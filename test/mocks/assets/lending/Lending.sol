pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "synthetix/DecimalMath.sol";
import "synthetix/SignedDecimalMath.sol";
import "src/interfaces/IAsset.sol";
import "./InterestRateModel.sol";
import "src/Account.sol";


contract Lending is IAsset, Owned {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;

  mapping(IManager => bool) riskModelAllowList;
  IERC20 token;
  Account account;
  InterestRateModel interestRateModel;

  uint reserveFactor; // fee taken by asset from interest

  uint totalBorrow;
  uint totalSupply;
  uint totalReserve;

  uint accrualBlockNumber; // block number of last update to indices
  uint borrowIndex; // used to apply interest accruals to individual borrow balances
  uint supplyIndex; // used to apply interest accruals to individual supply balances

  mapping(uint => uint) accountIndex; // could be borrow or supply index

  constructor(
    IERC20 token_, 
    Account account_, 
    InterestRateModel _interestRateModel    
  ) Owned() {
    token = token_;
    account = account_;

    accrualBlockNumber = block.number;
    _setInterestRateModelFresh(_interestRateModel);
    borrowIndex = DecimalMath.UNIT;
    supplyIndex = DecimalMath.UNIT;
  }

  ////////////////////
  // Accounts Hooks //
  ////////////////////

  function handleAdjustment(
    IAccount.AssetAdjustment memory adjustment, int preBal, IManager riskModel, address
  ) external override returns (int finalBal) {
    require(adjustment.subId == 0 && riskModelAllowList[riskModel]);
    accrueInterest();

    if (preBal == 0 && adjustment.amount == 0) {
      return 0; 
    }

    int freshBal = _getBalanceFresh(adjustment.acc, preBal);
    finalBal = freshBal + adjustment.amount;

    /* No need to SSTORE index if finalBal = 0 */
    if (finalBal < 0) {
      accountIndex[adjustment.acc] = borrowIndex;
    } else if (finalBal > 0) {
      accountIndex[adjustment.acc] = supplyIndex;
    } 
  }

  function handleManagerChange(uint, IManager, IManager) external pure override {}

  //////////////////
  // User Actions // 
  //////////////////

  function deposit(uint recipientAccount, uint amount) external {
    account.adjustBalance(
      IAccount.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      }),
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    account.adjustBalance(
      IAccount.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0, 
        amount: -int(amount),
        assetData: bytes32(0)
      }),
      ""
    );
    token.transfer(recipientAccount, amount);
  }

  //////////////
  // Interest // 
  //////////////

  function _getBalanceFresh(
    uint accountId, 
    int preBalance
  ) internal returns (int freshBalance) {
    /* expect interest to accrue before fresh balance is returned */
    if (accrualBlockNumber != block.number) {
      revert InterestAccrualStale(address(this), accrualBlockNumber, block.number);
    }

    uint currentMarketIndex;
    if (preBalance > 0) {
      currentMarketIndex = borrowIndex;
    } else if (preBalance < 0) {
      currentMarketIndex = supplyIndex;
    } else {
      return 0;
    }
    uint currentAccountIndex = accountIndex[accountId];

    return preBalance
      .multiplyDecimal(currentAccountIndex.toInt256())
      .divideDecimal(currentMarketIndex.toInt256());
  }


  /**
    * @notice Applies accrued interest to total borrows, supply and reserves
    * @dev Calculates interest accrued from the last checkpointed block
    *      up to the current block and writes new checkpoint to storage.
    */
  function accrueInterest() public {
    /* Short-circuit accumulating 0 interest */
    uint accrualBlockNumberPrior = accrualBlockNumber;
    if (accrualBlockNumberPrior == block.number) { return; }

    /* Read the previous values out of storage */
    uint borrowPrior = totalBorrow;
    uint reservePrior = totalReserve;
    uint supplyPrior = totalSupply;

    /* Calculate the current borrow interest rate */
    uint borrowRate = interestRateModel.getBorrowRate(getCash(), borrowPrior, reservePrior);

    /* Calculate the number of blocks elapsed since the last accrual */
    uint blockDelta = block.number - accrualBlockNumberPrior;

    /* Compound.Finance inspired non-compounding interest accrual  */
    uint interestAccumulated = borrowPrior.multiplyDecimal(blockDelta.multiplyDecimal(borrowRate));

    accrualBlockNumber = block.number;
    totalBorrow = interestAccumulated + borrowPrior;
    totalReserve = interestAccumulated.multiplyDecimal(reserveFactor) + reservePrior;
    totalSupply = interestAccumulated.multiplyDecimal(DecimalMath.UNIT - reserveFactor) + supplyPrior;

    borrowIndex = totalBorrow.divideDecimal(borrowPrior).multiplyDecimal(borrowIndex);
    supplyIndex = totalSupply.divideDecimal(supplyPrior).multiplyDecimal(supplyIndex);

    /* We emit an AccrueInterest event */
    emit AccrueInterest(getCash(), interestAccumulated, borrowIndex, totalBorrow);
  }

  ///////////
  // Views //
  ///////////

  /**
    * @notice Gets balance of this contract in terms of the underlying
    * @dev This excludes the value of the current message, if any
    * @return The quantity of underlying tokens owned by this contract
    */
  function getCash() internal view returns (uint) {
    return token.balanceOf(address(this));
  }


  ///////////
  // Admin //
  ///////////

  function setRiskModelAllowed(IManager riskModel, bool allowed) external onlyOwner {
    riskModelAllowList[riskModel] = allowed;
  }

  function setInterestRateModel(InterestRateModel newInterestRateModel) external onlyOwner {
    accrueInterest();
    return _setInterestRateModelFresh(newInterestRateModel);
  }

  /**
    * @notice admin function to update the interest rate model
    * @param newInterestRateModel the new interest rate model to use
    */
  function _setInterestRateModelFresh(InterestRateModel newInterestRateModel) internal {
    InterestRateModel oldInterestRateModel = interestRateModel;

    /* We fail gracefully unless market's block number equals current block number */
    if (accrualBlockNumber != block.number) {
      revert InterestAccrualStale(address(this), accrualBlockNumber, block.number);
    }

    /* newInterestRateModel.isInterestRateModel() must return true */
    require(newInterestRateModel.isInterestRateModel(), 
      "marker method returned false");

    /* Set the interest rate model to newInterestRateModel */
    interestRateModel = newInterestRateModel;
    emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel);
  }

  function reduceReserves(uint reduceAmount, address recipientAccount) external onlyOwner {
    accrueInterest();
    _reduceReservesFresh(reduceAmount, recipientAccount);
  }

  /**
    * @notice Reduces reserves by transferring to admin
    * @dev Requires fresh interest accrual
    * @param reduceAmount Amount of reduction to reserves
    * @param recipientAccount Address to send reduceAmount
    */
  function _reduceReservesFresh(uint reduceAmount, address recipientAccount) internal {
    /* Later on, this separation will allow for different underlying ERC20 types */

    // We fail gracefully unless market's block number equals current block number
    if (accrualBlockNumber != block.number) {
        revert InterestAccrualStale(address(this), accrualBlockNumber, block.number);
    }

    // Fail gracefully if protocol has insufficient underlying cash
    if (getCash() < reduceAmount) {
      revert NotEnoughCashForWithdrawal(address(this), getCash(), reduceAmount);
    }

    // Check reduceAmount ≤ reserves[n] (totalReserve)
    uint totalReservePrior = totalReserve;
    if (reduceAmount > totalReservePrior) {
      revert ReduceAmountGreaterThanReserve(address(this), totalReservePrior, reduceAmount);
    }

    totalReserve = totalReservePrior - reduceAmount;

    // TODO: implement token specific transfer for various types of stables
    // doTransferOut(admin, reduceAmount);
    token.transfer(recipientAccount, reduceAmount);

    emit ReservesReduced(msg.sender, reduceAmount, totalReserve);
  }



  /**
    * @notice Event emitted when interest is accrued
    */
  event AccrueInterest(
    uint cashPrior, 
    uint interestAccumulated, 
    uint borrowIndex, 
    uint totalBorrows
  );

  /**
    * @notice Event emitted when interestRateModel is changed
    */
  event NewMarketInterestRateModel(
    InterestRateModel oldInterestRateModel, 
    InterestRateModel newInterestRateModel
  );

  /**
    * @notice Event emitted when the reserves are reduced
    */
  event ReservesReduced(
    address owner, 
    uint reduceAmount, 
    uint newTotalReserves
  );

  ////////////
  // Errors //
  ////////////

  error InterestAccrualStale(address thrower, uint lastUpdatedBlock, uint currentBlock);
  error NotEnoughCashForWithdrawal(address thrower, uint currentCash, uint withdrawalAmount);
  error ReduceAmountGreaterThanReserve(address thrower, uint totalReserve, uint reduceAmount);

}
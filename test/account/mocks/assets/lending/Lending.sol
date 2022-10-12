// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "synthetix/DecimalMath.sol";
import "synthetix/SignedDecimalMath.sol";
import "src/interfaces/IAsset.sol";
import "./InterestRateModel.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";
import "forge-std/console2.sol";

contract Lending is IAsset, Owned {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  mapping(IManager => bool) riskModelAllowList;
  IERC20 token;
  IAccount account;
  InterestRateModel interestRateModel;

  uint public feeFactor; // fee taken by asset from interest

  uint public totalBorrow;
  uint public totalSupply;
  uint public accruedFees;

  uint public accrualTimestamp; // epoch time of last update to indices
  uint public borrowIndex; // used to apply interest accruals to individual borrow balances
  uint public supplyIndex; // used to apply interest accruals to individual supply balances

  mapping(uint => uint) public accountIndex; // could be borrow or supply index

  constructor(
    IERC20 token_, 
    IAccount account_, 
    InterestRateModel _interestRateModel    
  ) Owned() {
    token = token_;
    account = account_;

    accrualTimestamp = block.timestamp;
    _setInterestRateModelFresh(_interestRateModel);
    borrowIndex = DecimalMath.UNIT;
    supplyIndex = DecimalMath.UNIT;
  }

  ////////////////////
  // Accounts Hooks //
  ////////////////////

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment, int preBal, IManager riskModel, address
  ) external override returns (int finalBal, bool needAdjustment) {
    require(adjustment.subId == 0 && riskModelAllowList[riskModel]);

    /* Makes a continuous compounding interest calculation.
       (a) updates totalBorrow and totalSupply according to accrual */ 
    accrueInterest();

    if (preBal == 0 && adjustment.amount == 0) {
      return (0, false); 
    }

    needAdjustment = adjustment.amount < 0;

    int freshBal = _getBalanceFresh(adjustment.acc, preBal);
    finalBal = freshBal + adjustment.amount;

    /* No need to SSTORE index if finalBal = 0 */
    if (finalBal < 0) {
      accountIndex[adjustment.acc] = borrowIndex;
    } else if (finalBal > 0) {
      accountIndex[adjustment.acc] = supplyIndex;
    } 

    /* (b) updates totalBorrows and totalSupply according to adjustment */
    // TODO: need to clean up
    if (freshBal <= 0 && finalBal <= 0) {
      totalBorrow = (totalBorrow.toInt256() + (freshBal - finalBal)).toUint256();
    } else if (freshBal >= 0 && finalBal >= 0) {
      totalSupply = (totalSupply.toInt256() + (finalBal - freshBal)).toUint256();
    } else if (freshBal < 0 && finalBal > 0) {
      totalBorrow -= (-freshBal).toUint256();
      totalSupply += finalBal.toUint256();
    } else { // (freshBal > 0 && finalBal < 0)
      totalBorrow += (-finalBal).toUint256();
      totalSupply -= freshBal.toUint256();
    }
  }

  function handleManagerChange(uint, IManager) external pure override {}

  //////////////////
  // User Actions // 
  //////////////////

  /** @notice returns latest balance without updating accounts but will update market indices
    * @dev can be used by manager for risk assessments
    */
  function getBalance(uint accountId) external returns (int balance) {
    accrueInterest();
    return _getBalanceFresh(
      accountId, 
      account.getBalance(accountId, IAsset(address(this)), 0)
    );
  }


  function updateBalance(uint accountId) external returns (int balance) {
    /* This will eventually call asset.handleAdjustment() and accrue interest */
    balance = account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0,
        amount: 0,
        assetData: bytes32(0)
      }),
      true, // adjust balance with handleAdjustment so we apply interest
      ""
    );
  }

  function deposit(uint recipientAccount, uint amount) external {
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      }),
      true, // adjust balance with handleAdjustment so we apply interest
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0, 
        amount: -int(amount),
        assetData: bytes32(0)
      }),
      true, // adjust balance with handleAdjustment so we apply interest
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
  ) internal view returns (int freshBalance) {
    /* expect interest to accrue before fresh balance is returned */
    if (accrualTimestamp != block.timestamp) {
      revert InterestAccrualStale(address(this), accrualTimestamp, block.timestamp);
    }

    uint currentMarketIndex;
    if (preBalance > 0) {
      currentMarketIndex = supplyIndex;
    } else if (preBalance < 0) {
      currentMarketIndex = borrowIndex;
    } else {
      return 0;
    }
    uint currentAccountIndex = accountIndex[accountId];

    return preBalance
      .multiplyDecimal(currentMarketIndex.toInt256())
      .divideDecimal(currentAccountIndex.toInt256());
  }

  /**
    * @notice Applies accrued interest to total borrows, supply and reserves
    * @dev Calculates interest accrued from the last checkpointed block
    *      up to the current block and writes new checkpoint to storage.
    */
  function accrueInterest() public {
    /* Short-circuit accumulating 0 interest */
    uint accrualTimestampPrior = accrualTimestamp;
    if (accrualTimestampPrior == block.timestamp) { return; }

    /* Read the previous values out of storage */
    uint borrowPrior = totalBorrow;
    uint supplyPrior = totalSupply;

    /* Calculate the number of blocks elapsed since the last accrual */
    uint elapsedTime = block.timestamp - accrualTimestampPrior;

    /* Continuously compounding interest accrual  */
    uint interestFactor = interestRateModel.getBorrowInterestFactor(elapsedTime, getCash(), borrowPrior);
    uint interestAccumulated = borrowPrior.multiplyDecimal(interestFactor);
    
    /* SSTORE global variables */
    accrualTimestamp = block.timestamp;

    totalBorrow = interestAccumulated + borrowPrior;
    totalSupply = interestAccumulated.multiplyDecimal(DecimalMath.UNIT - feeFactor) + supplyPrior;
    accruedFees += interestAccumulated.multiplyDecimal(feeFactor);

    if (borrowPrior == 0) return;

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

  function socializeLoss(uint accountId, uint borrowAmountToSocialize) public {
    // TODO: this will need some onlyManager modifier

    uint supplyPrior = totalSupply;        
    uint newSupplyIndex = (supplyPrior - borrowAmountToSocialize) * supplyIndex / supplyPrior;

    supplyIndex = newSupplyIndex;

    // update the account's balance
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0, 
        amount: int(borrowAmountToSocialize),
        assetData: bytes32(0)
      }),
      false, // don't trigger the asset hook and accrue interest on this account
      ""
    );
  }

  function setManagerAllowed(IManager riskModel, bool allowed) external onlyOwner {
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
    if (accrualTimestamp != block.timestamp) {
      revert InterestAccrualStale(address(this), accrualTimestamp, block.timestamp);
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
    if (accrualTimestamp != block.timestamp) {
        revert InterestAccrualStale(address(this), accrualTimestamp, block.timestamp);
    }

    // Fail gracefully if protocol has insufficient underlying cash
    if (getCash() < reduceAmount) {
      revert NotEnoughCashForWithdrawal(address(this), getCash(), reduceAmount);
    }

    // Check reduceAmount ≤ reserves[n] (accruedFees)
    uint accruedFeesPrior = accruedFees;
    if (reduceAmount > accruedFeesPrior) {
      revert ReduceAmountGreaterThanAccrued(address(this), accruedFeesPrior, reduceAmount);
    }

    accruedFees = accruedFeesPrior - reduceAmount;

    // TODO: implement token specific transfer for various types of stables
    // doTransferOut(admin, reduceAmount);
    token.transfer(recipientAccount, reduceAmount);

    emit FeeClaimed(msg.sender, reduceAmount, accruedFees);
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
  event FeeClaimed(
    address owner, 
    uint reduceAmount, 
    uint newAccruedFees
  );

  ////////////
  // Errors //
  ////////////

  error InterestAccrualStale(address thrower, uint lastUpdatedAt, uint currentTimestamp);
  error NotEnoughCashForWithdrawal(address thrower, uint currentCash, uint withdrawalAmount);
  error ReduceAmountGreaterThanAccrued(address thrower, uint accruedFees, uint reduceAmount);

}
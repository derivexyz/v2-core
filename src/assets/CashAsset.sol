// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";
import "openzeppelin/access/Ownable2Step.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IManager} from "../interfaces/IManager.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";

import {ManagerWhitelist} from "./utils/ManagerWhitelist.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit a stable token and credit this cash asset into their subAccounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */
contract CashAsset is ICashAsset, Ownable2Step, ManagerWhitelist {
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  /// @dev The token address for stable coin
  IERC20Metadata public immutable wrappedAsset;

  /// @dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  //////////////////////////
  //      Variables       //
  //////////////////////////

  /// @dev InterestRateModel contract address
  IInterestRateModel public rateModel;

  /// @dev The address of liquidation module, which can trigger call of insolvency
  IDutchAuction public liquidationModule;

  /// @dev The security module accountId used for collecting a portion of fees
  uint public smId;

  /// @dev Total amount of positive balances
  uint public totalSupply;

  /// @dev Total amount of negative balances
  uint public totalBorrow;

  /// @dev Net amount of cash printed/burned due to settlement
  int public netSettledCash;

  /// @dev Total accrued fees for the security module
  uint public accruedSmFees;

  /// @dev Represents the growth of $1 of debt since deploy
  uint public borrowIndex = 1e18;

  /// @dev Represents the growth of $1 of positive balance since deploy
  uint public supplyIndex = 1e18;

  /// @dev Last timestamp that the interest was accrued
  uint public lastTimestamp;

  /// @dev The security module fee represented as a mantissa (0-1e18)
  uint public smFeePercentage;

  /// @dev The stored security module fee to return to after an insolvency event
  uint public previousSmFeePercentage;

  /// @dev True if the cash system is insolvent (stable balance < total cash asset)
  ///     In which case we turn on the withdraw fee to prevent bank-run
  bool public temporaryWithdrawFeeEnabled;

  /// @dev AccountId to previously stored borrow/supply index depending on a positive or debt position.
  mapping(uint => uint) public accountIdIndex;

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(ISubAccounts _subAccounts, IERC20Metadata _wrappedAsset, IInterestRateModel _rateModel)
    ManagerWhitelist(_subAccounts)
  {
    wrappedAsset = _wrappedAsset;
    stableDecimals = _wrappedAsset.decimals();

    lastTimestamp = block.timestamp;
    rateModel = _rateModel;
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice Allows owner to set InterestRateModel contract
   * @dev Accrues interest to make sure indexes are up to date before changing the model
   * @param _rateModel Interest rate model address
   */
  function setInterestRateModel(IInterestRateModel _rateModel) external onlyOwner {
    _accrueInterest();
    rateModel = _rateModel;

    emit InterestRateModelSet(rateModel);
  }

  /**
   * @notice Allows owner to set the security module fee cut
   * @param _smFee Interest rate model address
   */
  function setSmFee(uint _smFee) external onlyOwner {
    if (_smFee > DecimalMath.UNIT) revert CA_SmFeeInvalid(_smFee);
    smFeePercentage = _smFee;

    emit SmFeeSet(_smFee);
  }

  /**
   * @dev notice set the fee recipient
   */
  function setSmFeeRecipient(uint _smId) external onlyOwner {
    smId = _smId;

    emit SmFeeRecipientSet(_smId);
  }

  function setLiquidationModule(IDutchAuction _liquidationModule) external onlyOwner {
    liquidationModule = _liquidationModule;

    emit LiquidationModuleSet(address(_liquidationModule));
  }

  ////////////////////////////
  //  Deposit and Withdraw  //
  ////////////////////////////

  /**
   * @dev Deposit stable token and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param stableAmount amount of stable coins to deposit
   */
  function deposit(uint recipientAccount, uint stableAmount) external {
    _deposit(recipientAccount, stableAmount);
  }

  /**
   * @dev Deposit stable token and create a new account
   * @param recipient user for who the new account is created
   * @param stableAmount amount of stable coins to deposit
   * @param manager manager of the new account
   */
  function depositToNewAccount(address recipient, uint stableAmount, IManager manager)
    external
    returns (uint newAccountId)
  {
    newAccountId = subAccounts.createAccount(recipient, manager);
    _deposit(newAccountId, stableAmount);
  }

  /**
   * @dev Deposit stable token and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param stableAmount amount of stable coins to deposit
   */
  function _deposit(uint recipientAccount, uint stableAmount) internal {
    wrappedAsset.safeTransferFrom(msg.sender, address(this), stableAmount);
    uint amountInAccount = stableAmount.to18Decimals(stableDecimals);

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: amountInAccount.toInt256(),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );

    emit Deposit(recipientAccount, msg.sender, amountInAccount, stableAmount);
  }

  /**
   * @notice Withdraw stable token from a Lyra account
   * @param accountId account id to withdraw
   * @param stableAmount amount of stable asset in its native decimals
   * @param recipient stable token recipient
   */
  function withdraw(uint accountId, uint stableAmount, address recipient) external {
    if (msg.sender != subAccounts.ownerOf(accountId)) revert CA_OnlyAccountOwner();
    if (liquidationModule.getIsWithdrawBlocked()) revert CA_WithdrawBlockedByOngoingAuction();

    // if amount pass in is in higher decimals than 18, round up the trailing amount
    // to make sure users cannot withdraw dust amount, while keeping cashAmount == 0.
    uint cashAmount = stableAmount.to18DecimalsRoundUp(stableDecimals);
    _withdrawCashAmount(accountId, cashAmount, recipient);
  }

  /**
   * @dev Manager can trigger forge withdraw that burn cash and give out stable asset
   */
  function forceWithdraw(uint accountId) external {
    if (msg.sender != address(subAccounts.manager(accountId))) {
      revert CA_ForceWithdrawNotAuthorized();
    }
    if (liquidationModule.getIsWithdrawBlocked()) revert CA_WithdrawBlockedByOngoingAuction();
    address owner = subAccounts.ownerOf(accountId);
    int balance = subAccounts.getBalance(accountId, ICashAsset(address(this)), 0);
    if (balance < 0) {
      revert CA_ForceWithdrawNegativeBalance();
    }

    _withdrawCashAmount(accountId, balance.toUint256(), owner);
  }

  /**
   * @notice Withdraws cash from a given account and sends the converted stable amount to the recipient
   */
  function _withdrawCashAmount(uint accountId, uint cashAmount, address recipient) internal {
    uint stableAmount = cashAmount.from18Decimals(stableDecimals);

    // if the cash asset is insolvent,
    // each cash balance can only take out <100% amount of stable asset
    if (temporaryWithdrawFeeEnabled) {
      // if exchangeRate is 50% (0.5e18), we need to burn 2 cash asset for 1 stable to be withdrawn
      cashAmount = cashAmount.divideDecimal(_getExchangeRate());
    }

    // transfer the asset out after potentially needing to calculate exchange rate
    wrappedAsset.safeTransfer(recipient, stableAmount);

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountId,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: -(cashAmount.toInt256()),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );

    emit Withdraw(accountId, recipient, cashAmount, stableAmount);
  }

  //////////////////////////
  //  External functions  //
  //////////////////////////

  /**
   * @notice Disable withdraw fee when the cash asset is back to being solvent
   */
  function disableWithdrawFee() external {
    uint exchangeRate = _getExchangeRate();
    if (exchangeRate >= 1e18 && temporaryWithdrawFeeEnabled) {
      temporaryWithdrawFeeEnabled = false;
      smFeePercentage = previousSmFeePercentage;
    }

    emit WithdrawFeeDisabled(exchangeRate);
  }

  /// @notice External function for updating totalSupply and totalBorrow with the accrued interest since last timestamp.
  function accrueInterest() external {
    _accrueInterest();
  }

  /**
   * @notice Returns latest balance without updating accounts but will update indexes
   * @param accountId The accountId to check
   */
  function calculateBalanceWithInterest(uint accountId) external returns (int balance) {
    _accrueInterest();
    return _calculateBalanceWithInterest(subAccounts.getBalance(accountId, ICashAsset(address(this)), 0), accountId);
  }

  /**
   * @notice Allows anyone to transfer accrued SM fees to the SM
   */
  function transferSmFees() external {
    int amountToSend = accruedSmFees.toInt256();
    accruedSmFees = 0;

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: smId,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: amountToSend,
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );
  }

  /**
   * @notice Donate to the system during insolvency.
   * @dev This function makes sure no one accidentally burn more than needed to go back to solvency
   */
  function donateBalance(uint accountId, uint amount) external returns (uint burntAmount) {
    if (msg.sender != address(subAccounts.ownerOf(accountId))) {
      revert CA_DonateBalanceNotAuthorized();
    }

    uint totalCash = _getTotalCash();
    uint stableBalance = wrappedAsset.balanceOf(address(this)).to18Decimals(stableDecimals);

    // work out insolvent amount
    uint insolventAmount = totalCash - stableBalance;
    // burn up to that amount from given address
    burntAmount = Math.min(amount, insolventAmount);

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountId,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: -(burntAmount.toInt256()),
        assetData: bytes32(0)
      }),
      true, // trigger the hook to update total supply and balance
      ""
    );
  }

  /**
   * @dev Returns the exchange rate from cash asset to stable asset
   *      this should always be equal to 1, unless we have an insolvency
   */
  function getCashToStableExchangeRate() external view returns (uint) {
    return _getExchangeRate();
  }

  //////////////////////////
  //    Account Hooks     //
  //////////////////////////

  /**
   * @notice This function is called by the Account contract whenever a CashAsset balance is modified.
   * @dev    This function will apply any interest to the balance and return the final balance. final balance can be positive or negative.
   * @param adjustment Details about adjustment, containing account, subId, amount
   * @param preBalance Balance before adjustment
   * @param manager The manager contract that will verify the end state
   * @return finalBalance The final balance to be recorded in the account
   * @return needAllowance Return true if this adjustment should assume allowance in Account
   */
  function handleAdjustment(
    ISubAccounts.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    if (adjustment.subId != 0) revert CA_InvalidSubId();

    _checkManager(address(manager));
    // Accrue interest and update indexes
    _accrueInterest();

    // Apply interest to preBalance
    int preBalanceWithInterest = _calculateBalanceWithInterest(preBalance, adjustment.acc);
    finalBalance = preBalanceWithInterest + adjustment.amount;

    // Update borrow and supply indexes depending on if the accountId balance is net positive or negative
    if (finalBalance < 0) {
      accountIdIndex[adjustment.acc] = borrowIndex;
    } else if (finalBalance > 0) {
      accountIdIndex[adjustment.acc] = supplyIndex;
    } else {
      accountIdIndex[adjustment.acc] = 0;
    }

    _updateSupplyAndBorrow(preBalanceWithInterest, finalBalance);

    emit InterestAccruedOnAccount(
      adjustment.acc, preBalance, preBalanceWithInterest - preBalance, accountIdIndex[adjustment.acc]
    );

    // Need allowance only if trying to deduct balance
    return (finalBalance, adjustment.amount < 0);
  }

  ///////////////////////////
  //   Guarded Functions   //
  ///////////////////////////

  /**
   * @notice Liquidation module can report loss when there is insolvency.
   *         This function will "print" the amount of cash to the target account if the SM is empty
   *         and socialize the loss to everyone in the system
   *         this will result in turning on withdraw fee if the contract is indeed insolvent
   * @param lossAmountInCash Total amount of cash loss
   * @param accountToReceive Account to receive the new printed amount
   */
  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external onlyLiquidation {
    // accruedSmFees cover as much of the insolvency as possible
    // totalSupply/Borrow will be updated in the following adjustment
    if (lossAmountInCash <= accruedSmFees) {
      accruedSmFees -= lossAmountInCash;
    } else {
      accruedSmFees = 0;
    }

    // mint this amount in target account
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountToReceive,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: lossAmountInCash.toInt256(),
        assetData: bytes32(0)
      }),
      true, // trigger the hook to update total supply and balance
      ""
    );

    uint exchangeRate = _getExchangeRate();
    if (temporaryWithdrawFeeEnabled) {
      emit WithdrawFeeEnabled(exchangeRate);
      return;
    }

    // check if cash asset is insolvent
    if (exchangeRate < 1e18) {
      temporaryWithdrawFeeEnabled = true;
      previousSmFeePercentage = smFeePercentage;
      smFeePercentage = DecimalMath.UNIT;

      emit WithdrawFeeEnabled(exchangeRate);
    }
  }

  /**
   * @notice Allows whitelisted manager to adjust netSettledCash
   * @dev Required to track printed cash for asymmetric settlements
   * @param amountCash Amount of cash printed or burned
   */
  function updateSettledCash(int amountCash) external {
    _checkManager(address(msg.sender));
    netSettledCash += amountCash;

    emit SettledCashUpdated(amountCash, netSettledCash);
  }

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @notice Accrues interest onto the balance provided
   * @param preBalance the balance which the interest is going to be applied to
   * @param accountId the accountId which the balance belongs to
   */
  function _calculateBalanceWithInterest(int preBalance, uint accountId) internal view returns (int interestBalance) {
    uint accountIndex = accountIdIndex[accountId];
    // note: There shouldn't be a case where accountIndex == 0 and preBalance != 0
    if (accountIndex == 0 || preBalance == 0) return preBalance;

    uint indexChange = 0;
    if (preBalance < 0) {
      indexChange = borrowIndex.divideDecimal(accountIndex);
    } else {
      indexChange = supplyIndex.divideDecimal(accountIndex);
    }

    return indexChange.toInt256().multiplyDecimal(preBalance);
  }

  /**
   * @notice Updates totalSupply and totalBorrow with the accrued interest since last timestamp.
   * @dev Calculates interest accrued using the rate model and updates relevant state. A users balance
   * will be adjusted in the hook based off these new values.
   */
  function _accrueInterest() internal {
    if (lastTimestamp == block.timestamp) return;

    // Update timestamp even if there are no borrows
    uint elapsedTime = block.timestamp - lastTimestamp;
    lastTimestamp = block.timestamp;

    if (totalBorrow == 0) return;

    // Calculate interest since last timestamp using compounded interest rate
    uint realSupply = totalSupply; // include netSettledCash in the totalSupply

    // Only if we have "burned" supply from an asymmetric settlement, we add that amount to prevent
    // interest rate from spiking. Ignore "minted" supply since that only decreases interest rate.
    if (netSettledCash < 0) {
      realSupply += (-netSettledCash).toUint256(); // util = totalBorrow/(totalSupply + netBurned)
    }

    // Note: we ignore including netSettledCash in totalBorrow intentionally since all it would do is increase/spike
    // the interest rate temporarily (which causes unintentional side-effects with a large enough settlement amount)

    uint borrowRate = rateModel.getBorrowRate(realSupply, totalBorrow);
    uint borrowInterestFactor = rateModel.getBorrowInterestFactor(elapsedTime, borrowRate);
    uint interestAccrued = totalBorrow.multiplyDecimal(borrowInterestFactor);

    // Update totalBorrow with interestAccrued
    uint prevBorrow = totalBorrow;
    totalBorrow += interestAccrued;

    // Take security module fee cut from total interest accrued
    uint smFeeCut = interestAccrued.multiplyDecimal(smFeePercentage);
    accruedSmFees += smFeeCut;

    // Update total supply with interestAccrued - smFeeCut
    uint prevSupply = totalSupply;
    totalSupply += (interestAccrued - smFeeCut);

    // Update borrow/supply index by calculating the % change of total * current borrow/supply index
    borrowIndex = totalBorrow.divideDecimal(prevBorrow).multiplyDecimal(borrowIndex);
    supplyIndex = totalSupply.divideDecimal(prevSupply).multiplyDecimal(supplyIndex);

    emit InterestAccrued(interestAccrued, borrowIndex, supplyIndex, totalSupply, totalBorrow);
  }

  /**
   * @dev Get exchange rate from cash asset to stable coin amount
   * @dev This value should be 1 unless there's an insolvency
   */
  function _getExchangeRate() internal view returns (uint exchangeRate) {
    uint totalCash = _getTotalCash();
    uint stableBalance = wrappedAsset.balanceOf(address(this)).to18Decimals(stableDecimals);
    if (stableBalance >= totalCash) {
      return 1e18;
    }
    return stableBalance.divideDecimal(totalCash);
  }

  function _getTotalCash() internal view returns (uint) {
    return (totalSupply.toInt256() + accruedSmFees.toInt256() - totalBorrow.toInt256() - netSettledCash).toUint256();
  }

  /**
   * @dev Updates state of totalSupply and totalBorrow
   * @param preBalance The balance before the asset adjustment was made
   * @param finalBalance The balance after the asset adjustment was made
   */
  function _updateSupplyAndBorrow(int preBalance, int finalBalance) internal {
    uint newTotalSupply =
      (totalSupply.toInt256() + SignedMath.max(0, finalBalance) - SignedMath.max(0, preBalance)).toUint256();
    uint newTotalBorrow =
      (totalBorrow.toInt256() + SignedMath.min(0, preBalance) - SignedMath.min(0, finalBalance)).toUint256();
    totalSupply = newTotalSupply;
    totalBorrow = newTotalBorrow;
  }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  /// @dev revert if caller is not liquidation module
  modifier onlyLiquidation() {
    if (msg.sender != address(liquidationModule)) revert CA_NotLiquidationModule();
    _;
  }
}

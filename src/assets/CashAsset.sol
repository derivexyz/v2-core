// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "synthetix/SignedDecimalMath.sol";
import "synthetix/DecimalMath.sol";
import "../interfaces/IAccounts.sol";
import "../interfaces/ICashAsset.sol";
import "../interfaces/IInterestRateModel.sol";
import "../libraries/ConvertDecimals.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit USDC and credit this cash asset into their accounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */

contract CashAsset is ICashAsset, Owned {
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev The token address for stable coin
  IERC20Metadata public immutable stableAsset;

  ///@dev InterestRateModel contract address
  IInterestRateModel public rateModel;

  ///@dev The address of liqudation module, which can trigger call of insolvency
  address public immutable liquidationModule;

  ///@dev The security module accountId used for collecting a portion of fees
  uint public immutable smId;

  ///@dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  /////////////////////////
  //   State Variables   //
  /////////////////////////

  ///@dev Total amount of positive balances
  uint public totalSupply;

  ///@dev Total amount of negative balances
  uint public totalBorrow;

  ///@dev Total accrued fees for the security module
  uint public accruedSmFees;

  ///@dev Represents the growth of $1 of debt since deploy
  uint public borrowIndex = DecimalMath.UNIT;

  ///@dev Represents the growth of $1 of positive balance since deploy
  uint public supplyIndex = DecimalMath.UNIT;

  ///@dev Last timestamp that the interest was accrued
  uint public lastTimestamp;

  ///@dev The security module fee represented as a mantissa (0-1e18)
  uint public smFeePercentage;

  ///@dev The stored security module fee to return to after an insolvency event
  uint public previousSmFeePercentage;

  ///@dev True if the cash system is insolvent (USDC balance < total cash asset)
  ///     In which case we turn on the withdraw fee to prevent bankrun
  bool public temporaryWithdrawFeeEnabled;

  ///@dev Whitelisted managers. Only accounts controlled by whitelisted managers can trade this asset.
  mapping(address => bool) public whitelistedManager;

  ///@dev AccountId to previously stored borrow/supply index depending on a positive or debt position.
  mapping(uint => uint) public accountIdIndex;

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(
    IAccounts _accounts,
    IERC20Metadata _stableAsset,
    IInterestRateModel _rateModel,
    uint _smId,
    address _liquidationModule
  ) {
    stableAsset = _stableAsset;
    stableDecimals = _stableAsset.decimals();
    accounts = _accounts;
    smId = _smId;

    lastTimestamp = block.timestamp;
    rateModel = _rateModel;
    liquidationModule = _liquidationModule;
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice Whitelist or un-whitelist a manager
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;

    emit WhitelistManagerSet(_manager, _whitelisted);
  }

  /**
   * @notice Allows owner to set InterestRateModel contract
   * @dev Accures interest to make sure indexes are up to date before changing the model
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

  ////////////////////////////
  //   External Functions   //
  ////////////////////////////

  /**
   * @dev Deposit USDC and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param stableAmount amount of stable coins to deposit
   */
  function deposit(uint recipientAccount, uint stableAmount) external {
    stableAsset.safeTransferFrom(msg.sender, address(this), stableAmount);
    uint amountInAccount = stableAmount.to18Decimals(stableDecimals);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: recipientAccount,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: int(amountInAccount),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );

    // invoke handleAdjustment hook so the manager is checked, and interest is applied.

    emit Deposit(recipientAccount, msg.sender, amountInAccount, stableAmount);
  }

  /**
   * @notice Withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param stableAmount amount of stable asset in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint stableAmount, address recipient) external {
    if (msg.sender != accounts.ownerOf(accountId)) revert CA_OnlyAccountOwner();

    // if amount pass in is in higher decimals than 18, round up the trailing amount
    // to make sure users cannot withdraw dust amount, while keeping cashAmount == 0.
    uint cashAmount = stableAmount.to18DecimalsRoundUp(stableDecimals);

    // if the cash asset is insolvent,
    // each cash balance can only take out <100% amount of stable asset
    if (temporaryWithdrawFeeEnabled) {
      // if exchangeRate is 50% (0.5e18), we need to burn 2 cash asset for 1 stable to be withdrawn
      cashAmount = cashAmount.divideDecimal(_getExchangeRate());
    }

    // transfer the asset out after potentially needing to calculate exchange rate
    stableAsset.safeTransfer(recipient, stableAmount);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: -int(cashAmount),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );

    emit Withdraw(accountId, msg.sender, cashAmount, stableAmount);
  }

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
    return _calculateBalanceWithInterest(accounts.getBalance(accountId, ICashAsset(address(this)), 0), accountId);
  }

  /// @notice Allows anyone to transfer accrued SM fees to the SM
  function transferSmFees() external {
    int amountToSend = accruedSmFees.toInt256();
    accruedSmFees = 0;

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
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

  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external {
    // todo: only to comply with interface now: will accept incoming code from CashAsset
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
    AccountStructs.AssetAdjustment memory adjustment,
    int preBalance,
    IManager manager,
    address caller
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));
    if (preBalance == 0 && adjustment.amount == 0) {
      return (0, false);
    }

    // Accrue interest and update indexes
    _accrueInterest();

    // Apply interest to preBalance
    preBalance = _calculateBalanceWithInterest(preBalance, adjustment.acc);
    finalBalance = preBalance + adjustment.amount;

    // Update borrow and supply indexes depending on if the accountId balance is net positive or negative
    if (finalBalance < 0) {
      accountIdIndex[adjustment.acc] = borrowIndex;
    } else if (finalBalance > 0) {
      accountIdIndex[adjustment.acc] = supplyIndex;
    }

    // Need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;

    // Update totalSupply and totalBorrow amounts only if the call is not from manager
    // If the call is from manager, the call is triggered from managerAdjustment hook
    // from manager during settlement.
    if (caller != address(manager)) {
      _updateSupplyAndBorrow(preBalance, finalBalance);
    }
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
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
    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountToReceive,
        asset: ICashAsset(address(this)),
        subId: 0,
        amount: lossAmountInCash.toInt256(),
        assetData: bytes32(0)
      }),
      true, // trigger the hook to update total supply and balance
      ""
    );

    // check if cash asset is insolvent
    uint exchangeRate = _getExchangeRate();
    if (exchangeRate < 1e18) {
      temporaryWithdrawFeeEnabled = true;
      previousSmFeePercentage = smFeePercentage;
      smFeePercentage = DecimalMath.UNIT;

      emit WithdrawFeeEnabled(exchangeRate);
    }
  }

  /**
   * @dev Returns the exchange rate from cash asset to stable asset
   *      this should always be equal to 1, unless we have an insolvency
   */
  function getCashToStableExchangeRate() external view returns (uint) {
    return _getExchangeRate();
  }

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @dev Revert if manager address is not whitelisted by this contract
   * @param manager manager address
   */
  function _checkManager(address manager) internal view {
    if (!whitelistedManager[manager]) revert CA_UnknownManager();
  }

  /**
   * @notice Accrues interest onto the balance provided
   * @param preBalance the balance which the interest is going to be applied to
   * @param accountId the accountId which the balance belongs to
   */
  function _calculateBalanceWithInterest(int preBalance, uint accountId) internal view returns (int interestBalance) {
    uint accountIndex = accountIdIndex[accountId];
    if (accountIndex == 0) return preBalance;

    uint indexChange;
    if (preBalance < 0) {
      indexChange = borrowIndex.divideDecimal(accountIndex);
    } else if (preBalance > 0) {
      indexChange = supplyIndex.divideDecimal(accountIndex);
    }
    interestBalance = indexChange.toInt256().multiplyDecimal(preBalance);
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
    uint borrowRate = rateModel.getBorrowRate(totalSupply, totalBorrow);
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

    emit InterestAccrued(interestAccrued, borrowIndex, totalSupply, totalBorrow);
  }

  /**
   * @dev Get exchange rate from cash asset to stable coin amount
   * @dev This value should be 1 unless there's an insolvency
   */
  function _getExchangeRate() internal view returns (uint exchangeRate) {
    uint totalCash = totalSupply + accruedSmFees - totalBorrow;
    uint stableBalance = stableAsset.balanceOf(address(this)).to18Decimals(stableDecimals);
    exchangeRate = stableBalance.divideDecimal(totalCash);
  }

  /**
   * @dev Updates state of totalSupply and totalBorrow
   * @param preBalance The balance before the asset adjustment was made
   * @param finalBalance The balance after the asset adjustment was made
   */
  function _updateSupplyAndBorrow(int preBalance, int finalBalance) internal {
    if (preBalance <= 0 && finalBalance <= 0) {
      totalBorrow = (totalBorrow.toInt256() + (preBalance - finalBalance)).toUint256();
    } else if (preBalance >= 0 && finalBalance >= 0) {
      totalSupply = (totalSupply.toInt256() + (finalBalance - preBalance)).toUint256();
    } else if (preBalance < 0 && finalBalance > 0) {
      totalBorrow -= (-preBalance).toUint256();
      totalSupply += finalBalance.toUint256();
    } else {
      // (preBalance > 0 && finalBalance < 0)
      totalBorrow += (-finalBalance).toUint256();
      totalSupply -= preBalance.toUint256();
    }
  }

  /**
   * @dev get current account cash balance
   */
  // function _getStaleBalance(uint accountId) internal view returns (int balance) {
  //   balance = accounts.getBalance(accountId, ICashAsset(address(this)), 0);
  // }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyAccount() {
    if (msg.sender != address(accounts)) revert CA_NotAccount();
    _;
  }

  ///@dev revert if caller is not liquidation module
  modifier onlyLiquidation() {
    if (msg.sender != liquidationModule) revert CA_NotLiquidationModule();
    _;
  }
}

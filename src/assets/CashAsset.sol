// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "synthetix/SignedDecimalMath.sol";
import "synthetix/DecimalMath.sol";
import "../interfaces/IAsset.sol";
import "../interfaces/IAccounts.sol";
import "../interfaces/ICashAsset.sol";
import "../libraries/ConvertDecimals.sol";
import "./InterestRateModel.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit USDC and credit this cash asset into their accounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */

contract CashAsset is ICashAsset, Owned, IAsset {
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev The token address for stable coin
  IERC20Metadata public immutable stableAsset;

  ///@dev InterestRateModel contract address
  InterestRateModel public rateModel;

  ///@dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  /////////////////////////
  //   State Variables   //
  /////////////////////////

  ///@dev Total amount of positive balances
  uint public totalSupply;

  ///@dev Total amount of negative balances
  uint public totalBorrow;

  ///@dev Total accrued fees from interest
  uint public accruedFees;

  ///@dev Represents the growth of $1 of debt since deploy
  uint public borrowIndex;

  ///@dev Represents the growth of $1 of positive balance since deploy
  uint public supplyIndex;

  ///@dev Last timestamp that the interest was accrued
  uint public lastTimestamp;

  ///@dev Whitelisted managers. Only accounts controlled by whitelisted managers can trade this asset.
  mapping(address => bool) public whitelistedManager;

  ///@dev AccountId to previously stored borrow/supply index depending on a positive or debt position.
  mapping(uint => uint) public accountIdIndex;

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(IAccounts _accounts, IERC20Metadata _stableAsset, InterestRateModel _rateModel) {
    stableAsset = _stableAsset;
    stableDecimals = _stableAsset.decimals();
    accounts = _accounts;

    borrowIndex = ConvertDecimals.UNIT;
    supplyIndex = ConvertDecimals.UNIT;
    lastTimestamp = block.timestamp;
    _setInterestRateModel(_rateModel);
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
  }

  /**
   * @notice Allows owner to set InterestRateModel contract
   * @dev Accures interest to make sure indexes are up to date before changing the model
   * @param _rateModel Interest rate model address
   */
  function setInterestRateModel(InterestRateModel _rateModel) external onlyOwner {
    _accrueInterest();
    _setInterestRateModel(_rateModel);
  }

  ////////////////////////////
  //   External Functions   //
  ////////////////////////////

  /**
   * @dev Deposit USDC and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param amount amount of USDC to deposit
   */
  function deposit(uint recipientAccount, uint amount) external {
    stableAsset.safeTransferFrom(msg.sender, address(this), amount);
    uint amountInAccount = amount.to18Decimals(stableDecimals);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amountInAccount),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );

    // invoke handleAdjustment hook so the manager is checked, and interest is applied.
  }

  /**
   * @notice Withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param amount amount of stable asset in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint amount, address recipient) external {
    if (msg.sender != accounts.ownerOf(accountId)) revert CA_OnlyAccountOwner();

    stableAsset.safeTransfer(recipient, amount);

    // if amount pass in is in higher decimals than 18, round up the trailing amount
    // to make sure users cannot withdraw dust amount, while keeping cashAmount == 0.
    uint cashAmount = amount.to18DecimalsRoundUp(stableDecimals);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(cashAmount),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );
  }

  /// @notice External function for updating totalSupply and totalBorrow with the accrued interest since last timestamp.
  function accrueInterest() external {
    _accrueInterest();
  }

  /**
   * @notice Returns latest balance without updating accounts but will update indexes
   * @param accountId The account to check
   */
  function getBalance(uint accountId) external returns (int balance) {
    _accrueInterest();
    return _updateBalanceWithInterest(accounts.getBalance(accountId, IAsset(address(this)), 0), accountId);
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
    address /*caller*/
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));
    if (preBalance == 0 && adjustment.amount == 0) {
      return (0, false);
    }

    // Accrue interest and update indexes
    _accrueInterest();

    // Initialize accoundId index to 1
    if (accountIdIndex[adjustment.acc] == 0) {
      accountIdIndex[adjustment.acc] = DecimalMath.UNIT;
    }

    // Apply interest to preBalance
    preBalance = _updateBalanceWithInterest(preBalance, adjustment.acc);
    finalBalance = preBalance + adjustment.amount;

    // Update borrow and supply indexes depending on if the accountId balance is net positive or negative
    if (finalBalance < 0) {
      accountIdIndex[adjustment.acc] = borrowIndex;
    } else if (finalBalance > 0) {
      accountIdIndex[adjustment.acc] = supplyIndex;
    }

    // Need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;

    // Update totalSupply and totalBorrow amounts
    _updateSupplyAndBorrow(preBalance, finalBalance);
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
  }

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @dev revert if manager address is not whitelisted by this contract
   * @param manager manager address
   */
  function _checkManager(address manager) internal view {
    if (!whitelistedManager[manager]) revert CA_UnknownManager();
  }

  /**
   * @notice Sets the InterestRateModel contract used for interest rate calculations
   * @dev Can only change InterestRateModel if interest has been accrued for the current timestamp
   * @param _rateModel Interest rate model address
   */
  function _setInterestRateModel(InterestRateModel _rateModel) internal {
    rateModel = _rateModel;
  }

  /**
   * @notice Accrues interest onto the balance provided
   * @param preBalance the balance which the interest is going to be applied to
   * @param accountId the accountId which the balance belongs to
   */
  function _updateBalanceWithInterest(int preBalance, uint accountId) internal view returns (int interestBalance) {
    uint indexChange = borrowIndex.divideDecimal(accountIdIndex[accountId]);
    interestBalance = indexChange.toInt256().multiplyDecimal(preBalance);
  }

  /**
   * @notice Updates totalSupply and totalBorrow with the accrued interest since last timestamp.
   * @dev Calculates interest accrued using the rate model and updates relevant state. A users balance
   * will be adjusted in the hook based off these new values.
   */
  function _accrueInterest() internal {
    if (lastTimestamp == block.timestamp) return;

    // Update timestamp even if there are no borrows // todo is this logic sound?
    uint elapsedTime = block.timestamp - lastTimestamp;
    lastTimestamp = block.timestamp;
    if (totalBorrow == 0) return;

    // Calculate interest since last timestamp using compounded interest rate
    uint borrowRate = rateModel.getBorrowRate(totalSupply, totalBorrow);
    uint borrowInterestFactor = rateModel.getBorrowInterestFactor(elapsedTime, borrowRate);
    uint interestAccrued = totalBorrow.multiplyDecimal(borrowInterestFactor);

    // Update total supply and borrow
    uint prevBorrow = totalBorrow;
    uint prevSupply = totalSupply;
    totalSupply += interestAccrued;
    totalBorrow += interestAccrued;

    // Update borrow/supply index by calculating the % change of total * current borrow/supply index
    borrowIndex = totalBorrow.divideDecimal(prevBorrow).multiplyDecimal(borrowIndex);
    supplyIndex = totalSupply.divideDecimal(prevSupply).multiplyDecimal(supplyIndex);

    emit InterestAccrued(interestAccrued, borrowIndex, totalSupply, totalBorrow);
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
  //   balance = accounts.getBalance(accountId, IAsset(address(this)), 0);
  // }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyAccount() {
    if (msg.sender != address(accounts)) revert CA_NotAccount();
    _;
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "../interfaces/IAsset.sol";
import "../interfaces/IAccount.sol";
import "../libraries/DecimalMath.sol";

/**
 * @title cash asset with built-in lending feature.
 * @dev   user can deposit USDC and credit this cash asset into their account
 *        users can borrow cash by having a negative balance in their account (if allowed by manager)
 * @author Lyra
 */
contract Lending is Owned, IAsset {
  using SafeERC20 for IERC20;
  using DecimalMath for uint;

  ///@dev account contract address
  IAccount public immutable account;

  ///@dev usdc address
  address public immutable usdc;

  ///@dev store usdc decimals as immutable
  uint8 private immutable usdcDecimals;

  /////////////////////////
  //   State Variables   //
  /////////////////////////

  ///@dev borrow index
  uint public borrowIndex;

  ///@dev supply index
  uint public supplyIndex;

  ///@dev last timestamp that the interest is accrued
  uint public lastTimestamp;

  ///@dev whitelisted managers
  mapping(address => bool) public whitelistedManager;

  ///////////////////
  //   Modifiers   //
  ///////////////////
  modifier onlyAccount() {
    if (msg.sender != address(account)) revert LA_NotAccount();
    _;
  }

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(address _account, address _usdc) {
    usdc = _usdc;
    usdcDecimals = IERC20Metadata(_usdc).decimals();
    account = IAccount(_account);
  }

  //////////////////////////
  //    Account Hooks     //
  //////////////////////////

  /**
   * @notice triggered when an adjustment is triggered on the asset balance
   * @dev    we imply interest rate and modify the final balance. final balance can be positive or negative.
   * @param adjustment details about adjustment, containing account, subId, amount
   * @param preBalance balance before adjustment
   * @param manager the manager contract that will verify the end state
   * @return finalBalance the final balance to be recorded in the account
   * @return needAllowance if this adjustment should require allowance from non-ERC721 approved initiator
   */
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));

    // accrue interest rate
    _accrueInterest();

    // todo: accrue interest on prebalance

    // finalBalance can go positive or negative
    finalBalance = preBalance + adjustment.amount;

    // need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice whitelist or un-whitelist a manager
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;
  }

  ////////////////////////////
  //   External Functions   //
  ////////////////////////////

  /**
   * @dev deposit USDC and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param amount amount of USDC to deposit
   */
  function deposit(uint recipientAccount, uint amount) external {
    IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);

    uint amountInAccount = amount.convertDecimals(usdcDecimals, 18);

    account.assetAdjustment(
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

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @dev revert if manager address is not whitelisted by this contract
   * @param manager manager address
   */
  function _checkManager(address manager) internal view {
    if (!whitelistedManager[manager]) revert LA_UnknownManager();
  }

  /**
   * @dev update interest rate
   */
  function _accrueInterest() internal {
    //todo: actual interest updates

    lastTimestamp = block.timestamp;
  }
  
  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error LA_NotAccount();

  /// @dev revert when user trying to upgrade to a unknown manager
  error LA_UnknownManager();
}

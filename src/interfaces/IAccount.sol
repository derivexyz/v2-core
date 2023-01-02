// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC721/IERC721.sol";
import "./IAllowances.sol";
import "./IAsset.sol";
import "./IManager.sol";
import "./AccountStructs.sol";

// For full documentation refer to src/Account.sol";
interface IAccount is AccountStructs, IERC721 {
  ///////////////////
  // Account Admin //
  ///////////////////

  /**
   * @notice Creates account with new accountId
   * @param owner new account owner
   * @param _manager IManager of new account
   * @return newId ID of new account
   */
  function createAccount(address owner, IManager _manager) external returns (uint newId);

  /**
   * @notice Creates account and gives spender full allowance
   * @dev   @note: can be used to create and account for another user and simultaneously give allowance to oneself
   * @param owner new account owner
   * @param spender give address ERC721 approval
   * @param _manager IManager of new account
   * @return newId ID of new account
   */
  function createAccountWithApproval(address owner, address spender, IManager _manager) external returns (uint newId);

  /**
   * @notice Assigns new manager to account. No balances are adjusted.
   *         msg.sender must be ERC721 approved or owner
   * @param accountId ID of account
   * @param newManager new IManager
   * @param newManagerData data to be passed to manager._managerHook
   */
  function changeManager(uint accountId, IManager newManager, bytes memory newManagerData) external;

  ///////////////
  // Approvals //
  ///////////////

  /**
   * @notice Sets bidirectional allowances for all subIds of an asset.
   *         During a balance adjustment, if msg.sender not ERC721 approved or owner,
   *         asset allowance + subId allowance must be >= amount
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each asset
   */
  function setAssetAllowances(uint accountId, address delegate, AssetAllowance[] memory allowances)
    external;

  /**
   * @notice Sets bidirectional allowances for a specific subId.
   *         During a balance adjustment, the subId allowance is decremented first
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each (asset, subId)
   */
  function setSubIdAllowances(uint accountId, address delegate, SubIdAllowance[] memory allowances)
    external;

  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  /**
   * @notice Transfer an amount from one account to another for a specific (asset, subId)
   * @param assetTransfer (fromAcc, toAcc, asset, subId, amount)
   * @param managerData data passed to managers of both accounts
   */
  function submitTransfer(AssetTransfer memory assetTransfer, bytes memory managerData) external;

  /**
   * @notice Batch several transfers
   *         Gas efficient when modifying the same account several times,
   *         as _managerHook() is only performed once per account
   * @param assetTransfers array of (fromAcc, toAcc, asset, subId, amount)
   * @param managerData data passed to every manager involved in trade
   */
  function submitTransfers(AssetTransfer[] memory assetTransfers, bytes memory managerData) external;

  /**
   * @notice Asymmetric balance adjustment reserved for assets
   *         Must still pass both _managerHook()
   * @param adjustment asymmetric adjustment of amount for (asset, subId)
   * @param triggerAssetHook true if the adjustment need to be routed to Asset's custom hook
   * @param managerData data passed to manager of account
   */
  function assetAdjustment(
    AssetAdjustment memory adjustment,
    bool triggerAssetHook,
    bytes memory managerData
  ) external returns (int postBalance);

  /**
   * @notice Assymetric balance adjustment reserved for managers
   *         Must still pass both _assetHook()
   * @param adjustment assymetric adjustment of amount for (asset, subId)
   */
  function managerAdjustment(AssetAdjustment memory adjustment) external returns (int postBalance);

  //////////
  // View //
  //////////

  /**
   * @dev return the manager address of the account
   * @param accountId ID of account
   */
  function manager(uint accountId) external view returns (IManager);

  /**
   * @dev return amount of asset in the account, and the order (index) of the asset in the asset array
   * @param accountId ID of account
   * @param asset IAsset of balance
   * @param subId subId of balance
   */
  function balanceAndOrder(uint accountId, IAsset asset, uint subId)
    external
    view
    returns (int240 balance, uint16 order);

  /**
   * @notice Gets an account's balance for an (asset, subId)
   * @param accountId ID of account
   * @param asset IAsset of balance
   * @param subId subId of balance
   */
  function getBalance(uint accountId, IAsset asset, uint subId) external view returns (int balance);

  /**
   * @notice Gets a list of all asset balances of an account
   * @dev can use balanceAndOrder() to get the index of a specific balance
   * @param accountId ID of account
   */
  function getAccountBalances(uint accountId)
    external
    view
    returns (AssetBalance[] memory assetBalances);

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted account created or split
   */
  event AccountCreated(address indexed owner, uint indexed accountId, address indexed manager);

  /**
   * @dev Emitted account burned
   */
  event AccountBurned(address indexed owner, uint indexed accountId, address indexed manager);

  /**
   * @dev Emitted when account manager changed
   */
  event AccountManagerChanged(uint indexed accountId, address indexed oldManager, address indexed newManager);

  /**
   * @dev Emitted during any balance change event. This includes:
   *      1. single transfer
   *      2. batch transfer
   *      3. transferAll / merge / split
   *      4. manager or asset initiated adjustments
   *      PreBalance + amount not necessarily = postBalance
   */
  event BalanceAdjusted(
    uint indexed accountId,
    address indexed manager,
    HeldAsset indexed assetAndSubId,
    int amount,
    int preBalance,
    int postBalance
  );

  ////////////
  // Errors //
  ////////////

  error AC_OnlyManager();

  error AC_OnlyAsset();

  error AC_TooManyTransfers();

  error AC_NotOwnerOrERC721Approved(address spender, uint accountId, address owner, IManager manager, address approved);

  error AC_CannotTransferAssetToOneself(address caller, uint accountId);

  error AC_CannotChangeToSameManager(address caller, uint accountId);
}

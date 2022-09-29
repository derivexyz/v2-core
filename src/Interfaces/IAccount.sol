pragma solidity ^0.8.13;

import "./IAllowances.sol";
import "./IAsset.sol";
import "./IManager.sol";

// For full documentation refer to src/Account.sol";
interface IAccount is IAllowances {

  /////////////////////
  // Storage Structs //
  /////////////////////
  
  struct BalanceAndOrder {
    // balance of (asset, subId)
    int240 balance;
    // index in heldAssets() or getAccountBalances() 
    uint16 order; 
  }

  struct HeldAsset {
    IAsset asset;
    uint96 subId;
  }

  /////////////////////////
  // Memory-only Structs //
  /////////////////////////

  struct AssetBalance {
    IAsset asset;
    // adjustments will revert if > uint96
    uint subId;
    // base layer only stores up to int240
    int balance;
  }

  struct AssetTransfer {
    // credited by amount
    uint fromAcc;
    // debited by amount
    uint toAcc;
    IAsset asset;
    // adjustments will revert if >uint96
    uint subId;
    // reverts if transfer amount > uint240
    int amount;
    // data passed into asset.handleAdjustment()
    bytes32 assetData;
  }

  struct AssetAdjustment {
    uint acc;
    IAsset asset;
    // reverts for subIds > uint96
    uint subId;
    // reverts if transfer amount > uint240
    int amount;
    // data passed into asset.handleAdjustment()
    bytes32 assetData;
  }  


  ///////////////////
  // Account Admin //
  ///////////////////

  function createAccount(address owner, IManager _manager) external returns (uint newId);

  function createAccountWithApproval(
    address owner, address spender, IManager _manager
  ) external returns (uint newId);

  function changeManager(
    uint accountId, IManager newManager, bytes memory newManagerData
  ) external;

  ///////////////
  // Approvals //
  ///////////////

  function setAssetAllowances(
    uint accountId, 
    address delegate,
    AssetAllowance[] memory allowances
  ) external;

  function setSubIdAllowances(
    uint accountId, 
    address delegate,
    SubIdAllowance[] memory allowances
  ) external;

  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  function submitTransfer(
    AssetTransfer memory assetTransfer, bytes memory managerData
  ) external;

  function submitTransfers(
    AssetTransfer[] memory assetTransfers, bytes memory managerData
  ) external;

  /// @dev adjust balance by assets
  function assetAdjustment(
    AssetAdjustment memory adjustment, bool triggerSelf, bytes memory managerData
  ) external returns (int postBalance);

  /// @dev adjust balance by managers
  function managerAdjustment(
    AssetAdjustment memory adjustment
  ) external returns (int postBalance);

  //////////
  // View //
  //////////

  function manager(uint accountId) external view returns (IManager);

  function balanceAndOrder(
    uint accountId, IAsset asset, uint subId
  ) external view returns (int240 balance, uint16 order);

  function getBalance(
    uint accountId, IAsset asset, uint subId
  ) external view returns (int balance);

  function getAccountBalances(uint accountId) 
    external view returns (AssetBalance[] memory assetBalances);


  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted account created or split
   */
  event AccountCreated(
    address indexed owner, 
    uint indexed accountId, 
    address indexed manager
  );

  /**
   * @dev Emitted account burned
   */
  event AccountBurned(
    address indexed owner, 
    uint indexed accountId, 
    address indexed manager
  );

  /**
   * @dev Emitted when account manager changed
   */
  event AccountManagerChanged(
    uint indexed accountId, 
    address indexed oldManager, 
    address indexed newManager
  );

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

  error OnlyManager(address thrower, address caller, address manager);

  error OnlyAsset(address thrower, address caller, address asset);
  
  error NotOwnerOrERC721Approved(
    address thrower, address spender, uint accountId, address accountOwner, IManager manager, address approved);
  error CannotBurnAccountWithHeldAssets(address thrower, address caller, uint accountId, uint numOfAssets);
  error CannotTransferAssetToOneself(address thrower, address caller, uint accountId);
  error CannotChangeToSameManager(address thrower, address caller, uint accountId);
}

pragma solidity ^0.8.13;

import "./IAbstractAsset.sol";
import "./IAbstractManager.sol";

// For full documentation refer to src/Account.sol";
interface IAccount {

  /////////////
  // Structs //
  /////////////
  
  struct BalanceAndOrder {
    // balance of (asset, subId)
    int240 balance;
    // index in heldAssets() or getAccountBalances() 
    uint16 order; 
  }

  struct HeldAsset {
    IAbstractAsset asset;
    uint96 subId;
  }
  struct AssetBalance {
    IAbstractAsset asset;
    uint subId;
    int balance;
  }

  struct AssetTransfer {
    // credited by amount
    uint fromAcc;
    // debited by amount
    uint toAcc;
    IAbstractAsset asset;
    uint subId;
    int amount;
  }

  struct AssetAdjustment {
    uint acc;
    IAbstractAsset asset;
    uint subId;
    int amount;
  }  

  ///////////////////
  // Account Admin //
  ///////////////////

  function createAccount(address owner, IAbstractManager _manager) external returns (uint newId);

  function burnAccounts(uint[] memory accountIds) external;

  function changeManager(
    uint accountId, IAbstractManager newManager, bytes memory managerData, bytes memory assetData
  ) external;

  ///////////////
  // Approvals //
  ///////////////

  function setAssetAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    uint[] memory positiveAllowances,
    uint[] memory negativeAllowances
  ) external;

  function setSubIdAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    uint[] memory subIds,
    uint[] memory positiveAllowances,
    uint[] memory negativeAllowances
  ) external;

  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  function submitTransfer(
    AssetTransfer memory assetTransfer, bytes memory managerData, bytes memory assetData
  ) external;

  function submitTransfers(
    AssetTransfer[] memory assetTransfers, bytes memory managerData, bytes memory assetData
  ) external;

  function transferAll(
    uint fromAccountId, uint toAccountId, bytes memory managerData, bytes memory assetData
  ) external;

  function adjustBalance(
    AssetAdjustment memory adjustment, bytes memory managerData, bytes memory assetData
  ) external returns (int postBalance);

  //////////
  // View //
  //////////

  function manager(uint accountId) external view returns (IAbstractManager);

  function balanceAndOrder(
    uint accountId, IAbstractAsset asset, uint subId
  ) external view returns (int240 balance, uint16 order);

  function positiveSubIdAllowance(
    uint accountId, IAbstractAsset asset, uint subId, address spender
  ) external view returns (uint);
  
  function negativeSubIdAllowance(
    uint accountId, IAbstractAsset asset, uint subId, address spender
  ) external view returns (uint);

  function positiveAssetAllowance(
    uint accountId, IAbstractAsset asset, address spender
  ) external view returns (uint);

  function negativeAssetAllowance(
    uint accountId, IAbstractAsset asset, address spender
  ) external view returns (uint);

  function getBalance(
    uint accountId, IAbstractAsset asset, uint subId
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
   */
  event BalanceAdjusted(
    uint indexed accountId,
    address indexed manager,
    HeldAsset indexed assetAndSubId, 
    int preBalance, 
    int postBalance
  );

  ////////////
  // Errors //
  ////////////

  error OnlyManagerOrAssetAllowed(address thrower, address caller, address manager, address asset);
  error NotOwnerOrERC721Approved(address thrower, address caller, address accountOwner, uint accountId);
  error NotEnoughSubIdOrAssetAllowances(
    address thower, 
    address caller, 
    uint absAmount, 
    uint subIdAllowance, 
    uint assetAllowance
  );
  error CannotBurnAccountWithHeldAssets(address thrower, address caller, uint accountId, uint numOfAssets);
}

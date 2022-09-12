pragma solidity ^0.8.13;

import "./IAbstractAsset.sol";

interface IAccount {

  /////////////
  // Structs //
  /////////////
  
  // Balances
  struct BalanceAndOrder {
    int240 balance;
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

  // Adjustments
  struct AssetTransfer {
    uint fromAcc;
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

  struct Allowance {
    uint positive;
    uint negative;
  }


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

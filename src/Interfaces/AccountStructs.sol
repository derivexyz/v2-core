pragma solidity ^0.8.13;

import "./IAbstractAsset.sol";

contract AccountStructs {
  
  // Balances
  struct BalanceAndOrder {
    // significantly reduces cost of addHeldAsset (since order can be stored there?)
    int240 balance;
    uint16 order;
  }

  struct HeldAsset {
    IAbstractAsset asset;
    uint subId;
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

  // Allowances 

  struct Allowance {
    uint positive;
    uint negative;
  }
}

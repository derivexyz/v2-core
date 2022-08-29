pragma solidity ^0.8.13;

import "./IAbstractAsset.sol";

contract MarginStructs {
  
  // Balances

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

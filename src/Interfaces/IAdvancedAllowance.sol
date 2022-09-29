pragma solidity ^0.8.13;

import "./IAsset.sol";
import "./IManager.sol";

interface IAdvancedAllowance {
  struct AssetAllowance {
    IAsset asset;
    uint positive;
    uint negative;
  } 

  struct SubIdAllowance {
    IAsset asset;
    uint subId;
    uint positive;
    uint negative;
  } 

  function positiveSubIdAllowance(
    uint accountId, address owner, IAsset asset, uint subId, address spender
  ) external view returns (uint);
  
  function negativeSubIdAllowance(
    uint accountId, address owner, IAsset asset, uint subId, address spender
  ) external view returns (uint);

  function positiveAssetAllowance(
    uint accountId, address owner, IAsset asset, address spender
  ) external view returns (uint);

  function negativeAssetAllowance(
    uint accountId, address owner, IAsset asset, address spender
  ) external view returns (uint);

  error NotEnoughSubIdOrAssetAllowances(
    address thower,
    address caller,
    uint accountId,
    int amount, 
    uint subIdAllowance, 
    uint assetAllowance
  );
  
}

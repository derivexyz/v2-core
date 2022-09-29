pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IAccount.sol";

/**
 * @title Account
 * @author Lyra
 * @notice Base layer that manages:
 *         1. balances for each (account, asset, subId)
 *         2. routing of manager, asset, allowance hooks / checks 
 *            during any balance adjustment event
 *         3. account creation / manager assignment
 */

contract Allowances is IAllowances {
  // Variables

  /// @dev accountId => owner => asset => subId => delegate => allowance
  mapping(uint => mapping(address => mapping(IAsset => mapping(uint => mapping(address => uint))))) public positiveSubIdAllowance;
  mapping(uint => mapping(address => mapping(IAsset => mapping(uint => mapping(address => uint))))) public negativeSubIdAllowance;

  /// @dev accountId => owner => asset => delegate => allowance
  mapping(uint => mapping(address => mapping(IAsset => mapping(address => uint)))) public positiveAssetAllowance;
  mapping(uint => mapping(address => mapping(IAsset => mapping(address => uint)))) public negativeAssetAllowance;

  /////////////
  // Setting //
  /////////////

  /**
   * @notice Sets bidirectional allowances for all subIds of an asset.
   *         During a balance adjustment, if msg.sender not ERC721 approved or owner, 
   *         asset allowance + subId allowance must be >= amount 
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each asset
   */
  function _setAssetAllowances(
    uint accountId,
    address owner,
    address delegate,
    AssetAllowance[] memory allowances
  ) internal {
    uint allowancesLen = allowances.length;
    for (uint i; i < allowancesLen; i++) {
      positiveAssetAllowance[accountId][owner][allowances[i].asset][delegate] = allowances[i].positive;
      negativeAssetAllowance[accountId][owner][allowances[i].asset][delegate] = allowances[i].negative;
    }
  }

  /** 
   * @notice Sets bidirectional allowances for a specific subId. 
   *         During a balance adjustment, the subId allowance is decremented first 
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each (asset, subId)
   */
  function _setSubIdAllowances(
    uint accountId,
    address owner,
    address delegate,
    SubIdAllowance[] memory allowances
  ) internal {
    uint allowancesLen = allowances.length;
    for (uint i; i < allowancesLen; i++) {
      positiveSubIdAllowance[accountId][owner][allowances[i].asset][allowances[i].subId][delegate] = allowances[i].positive;
      negativeSubIdAllowance[accountId][owner][allowances[i].asset][allowances[i].subId][delegate] = allowances[i].negative;
    }
  }


  //////////////
  // Spending //
  //////////////

  /** 
   * @notice Checks allowances during transfers / merges / splits
   *         The subId allowance is decremented before the asset-wide allowance
   * @dev finalBalance adjustments tweaked by the asset not considered in allowances 
   * @param adjustment amount of balance adjustment for an (asset, subId)
   * @param delegate address of msg.sender initiating change
   */
  function _spendAllowance( // TODO: rename delegate to caller?
    IAccount.AssetAdjustment memory adjustment, address owner, address delegate
  ) internal {

    /* Early return if amount == 0 */
    if (adjustment.amount == 0) { return; }

    /* determine if positive vs negative allowance is needed */
    if (adjustment.amount > 0) {
      _spendAbsAllowance(
        adjustment.acc,
        positiveSubIdAllowance[adjustment.acc][owner][adjustment.asset][adjustment.subId],
        positiveAssetAllowance[adjustment.acc][owner][adjustment.asset],
        delegate,
        adjustment.amount
      );
    } else { // adjustment.amount < 0
      _spendAbsAllowance(
        adjustment.acc,
        negativeSubIdAllowance[adjustment.acc][owner][adjustment.asset][adjustment.subId],
        negativeAssetAllowance[adjustment.acc][owner][adjustment.asset],
        delegate,
        adjustment.amount
      );
    }
  }

  function _spendAbsAllowance(
    uint accountId,
    mapping(address => uint) storage allowancesForSubId,
    mapping(address => uint) storage allowancesForAsset,
    address delegate,
    int256 amount
  ) internal {
    uint subIdAllowance = allowancesForSubId[delegate];
    uint assetAllowance = allowancesForAsset[delegate];

    uint256 absAmount = _abs(amount);
    /* subId allowances are decremented before asset allowances */
    if (absAmount <= subIdAllowance) {
      allowancesForSubId[delegate] = subIdAllowance - absAmount;
    } else if (absAmount <= subIdAllowance + assetAllowance) { 
      allowancesForSubId[delegate] = 0;
      allowancesForAsset[delegate] = assetAllowance - (absAmount - subIdAllowance);
    } else {
      revert NotEnoughSubIdOrAssetAllowances(
        address(this), 
        msg.sender, 
        accountId, 
        amount,
        subIdAllowance, 
        assetAllowance);
    }
  }

  //////////
  // Util //
  //////////

  function _abs(int amount) internal pure returns (uint absAmount) {
    return amount >= 0 ? uint(amount) : uint(-amount);
  }


}

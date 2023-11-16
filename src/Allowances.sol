// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SignedMath.sol";

import {IAsset} from "./interfaces/IAsset.sol";
import {IAllowances} from "./interfaces/IAllowances.sol";
import {ISubAccounts} from "./interfaces/ISubAccounts.sol";

/**
 * @title Allowance
 * @author Lyra
 * @notice Allow more granular allowance setting, supposed to be used by Account
 */
contract Allowances is IAllowances {
  ///////////////
  // Variables //
  ///////////////

  /// @dev accountId => owner => asset => subId => delegate => allowance to add
  mapping(
    uint accountId
      => mapping(address owner => mapping(IAsset asset => mapping(uint subId => mapping(address delegate => uint))))
  ) public positiveSubIdAllowance;

  /// @dev accountId => owner => asset => subId => delegate => allowance to reduce
  mapping(
    uint accountId
      => mapping(address owner => mapping(IAsset asset => mapping(uint subId => mapping(address delegate => uint))))
  ) public negativeSubIdAllowance;

  /// @dev accountId => owner => asset => delegate => allowance
  mapping(uint accountId => mapping(address owner => mapping(IAsset asset => mapping(address delegate => uint)))) public
    positiveAssetAllowance;
  mapping(uint accountId => mapping(address owner => mapping(IAsset asset => mapping(address delegate => uint)))) public
    negativeAssetAllowance;

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
    IAllowances.AssetAllowance[] memory allowances
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
    IAllowances.SubIdAllowance[] memory allowances
  ) internal {
    uint allowancesLen = allowances.length;
    for (uint i; i < allowancesLen; i++) {
      positiveSubIdAllowance[accountId][owner][allowances[i].asset][allowances[i].subId][delegate] =
        allowances[i].positive;
      negativeSubIdAllowance[accountId][owner][allowances[i].asset][allowances[i].subId][delegate] =
        allowances[i].negative;
    }
  }

  //////////////
  // Spending //
  //////////////

  /**
   * @notice Consume delegate's allowance to update balance
   * @dev revert if delegate has insufficient allowance
   * @param adjustment amount of balance adjustment for an (asset, subId)
   * @param caller address of msg.sender initiating change
   */
  function _spendAllowance(ISubAccounts.AssetAdjustment memory adjustment, address owner, address caller) internal {
    /* Early return if amount == 0 */
    if (adjustment.amount == 0) {
      return;
    }

    /* determine if positive vs negative allowance is needed */
    if (adjustment.amount > 0) {
      _spendAbsAllowance(
        adjustment.acc,
        positiveSubIdAllowance[adjustment.acc][owner][adjustment.asset][adjustment.subId],
        positiveAssetAllowance[adjustment.acc][owner][adjustment.asset],
        caller,
        adjustment.amount
      );
    } else {
      // adjustment.amount < 0
      _spendAbsAllowance(
        adjustment.acc,
        negativeSubIdAllowance[adjustment.acc][owner][adjustment.asset][adjustment.subId],
        negativeAssetAllowance[adjustment.acc][owner][adjustment.asset],
        caller,
        adjustment.amount
      );
    }
  }

  /**
   * @dev reduce abs(amount) allowance and revert if allowance is not enough
   * @param accountId account id
   * @param allowancesForSubId storage pointer with maps account to subId allowance
   * @param allowancesForSubId storage pointer with maps account to asset allowance
   * @param spender address to spend the allowance
   * @param amount amount in raw transfer
   */
  function _spendAbsAllowance(
    uint accountId,
    mapping(address => uint) storage allowancesForSubId,
    mapping(address => uint) storage allowancesForAsset,
    address spender,
    int amount
  ) internal {
    uint subIdAllowance = allowancesForSubId[spender];
    uint assetAllowance = allowancesForAsset[spender];

    uint absAmount = SignedMath.abs(amount);
    /* subId allowances are decremented before asset allowances */
    if (absAmount <= subIdAllowance) {
      allowancesForSubId[spender] = subIdAllowance - absAmount;
    } else if (absAmount <= subIdAllowance + assetAllowance) {
      allowancesForSubId[spender] = 0;
      allowancesForAsset[spender] = assetAllowance - (absAmount - subIdAllowance);
    } else {
      revert NotEnoughSubIdOrAssetAllowances(msg.sender, accountId, amount, subIdAllowance, assetAllowance);
    }
  }
}

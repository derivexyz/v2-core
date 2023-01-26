// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAccounts.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/AccountStructs.sol";

abstract contract BaseManager is AccountStructs {
  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev Option asset address
  IOption public immutable option;

  ///@dev Cash asset address
  ICashAsset public immutable cashAsset;

  ///@dev OI fee rate in BPS. Charged based on contract traded * OIFee * spot
  uint OIFeeRateBPS = 10;

  constructor(IAccounts _accounts, IOption _option, ICashAsset _cashAsset) {
    accounts = _accounts;
    option = _option;
    cashAsset = _cashAsset;
  }

  function _chargeOIFee(uint accountId, uint feeRecipientAcc, uint tradeId, AssetDelta[] memory assetDeltas) internal {
    int fee;
    // iterate through all asset changes, if it's option asset, change if OI increased
    for (uint i; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == option) {
        (, uint oiBefore) = option.openInterestBeforeTrade(assetDeltas[i].subId, tradeId);
        uint oi = option.openInterest(assetDeltas[i].subId);

        // this trade increase OI, charge a fee
        if (oi > oiBefore) {}
      }
    }

    if (fee > 0) {
      // transfer cash to fee recipient account
      _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, fee);
    }
  }

  /**
   * @dev transfer asset from one account to another without invoking manager hook
   * @param from Account id of the from account. Must be controlled by this manager
   * @param to Account id of the to account. Must be controlled by this manager
   * @param asset Asset address to transfer
   * @param subId Asset subId to transfer
   * @param amount Amount of asset to transfer
   */
  function _symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) internal {
    // deduct amount in from account
    accounts.managerAdjustment(
      AccountStructs.AssetAdjustment({acc: from, asset: asset, subId: subId, amount: -amount, assetData: bytes32(0)})
    );

    // increase "to" account
    accounts.managerAdjustment(
      AccountStructs.AssetAdjustment({acc: to, asset: asset, subId: subId, amount: amount, assetData: bytes32(0)})
    );
  }
}

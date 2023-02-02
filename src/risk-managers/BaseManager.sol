// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAccounts.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "src/interfaces/ISpotFeeds.sol";

import "src/libraries/IntLib.sol";
import "src/libraries/DecimalMath.sol";

abstract contract BaseManager is AccountStructs {
  using IntLib for int;
  using DecimalMath for uint;

  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev Option asset address
  IOption public immutable option;

  ///@dev Cash asset address
  ICashAsset public immutable cashAsset;

  ///@dev Spot feed oracle to get spot price for each asset id
  ISpotFeeds public immutable spotFeeds;

  ///@dev OI fee rate in BPS. Charged fee = contract traded * OIFee * spot
  uint constant OIFeeRateBPS = 0.001e18; // 10 BPS

  constructor(IAccounts _accounts, ISpotFeeds spotFeeds_, ICashAsset _cashAsset, IOption _option) {
    accounts = _accounts;
    option = _option;
    cashAsset = _cashAsset;
    spotFeeds = spotFeeds_;
  }

  /**
   * @dev charge a fixed OI fee and send it in cash to feeRecipientAcc
   * @param accountId Account potentially to charge
   * @param feeRecipientAcc Account of feeRecipient
   * @param tradeId ID of the trade informed by Accounts
   * @param assetDeltas Array of asset changes made to this account
   */
  function _chargeOIFee(uint accountId, uint feeRecipientAcc, uint tradeId, AssetDelta[] calldata assetDeltas) internal {
    uint fee;
    // iterate through all asset changes, if it's option asset, change if OI increased
    for (uint i; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == option) {
        (, uint oiBefore) = option.openInterestBeforeTrade(assetDeltas[i].subId, tradeId);
        uint oi = option.openInterest(assetDeltas[i].subId);

        // this trade increase OI, charge a fee
        if (oi > oiBefore) {
          // todo [Anton]: get spot for specific asset base on subId
          uint spot = spotFeeds.getSpot(1);
          fee += assetDeltas[i].delta.abs().multiplyDecimal(spot).multiplyDecimal(OIFeeRateBPS);
        }
      }
    }

    if (fee > 0) {
      // transfer cash to fee recipient account
      _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, int(fee));
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

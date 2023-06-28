// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/risk-managers/BaseManager.sol";
import {ISpotFeed} from "../../../src/interfaces/ISpotFeed.sol";
import {ISettlementFeed} from "../../../src/interfaces/ISettlementFeed.sol";

contract BaseManagerTester is BaseManager {
  IOption public immutable option;
  IPerpAsset public immutable perp;
  IForwardFeed public immutable forwardFeed;
  ISpotFeed public immutable spotFeed;
  ISettlementFeed public immutable settlementFeed;

  constructor(
    ISubAccounts subAccounts_,
    IForwardFeed forwardFeed_,
    ISettlementFeed settlementFeed_,
    ISpotFeed spotFeed_,
    ICashAsset cash_,
    IOption option_,
    IPerpAsset perp_,
    IDutchAuction auction_,
    IBasePortfolioViewer viewer_
  ) BaseManager(subAccounts_, cash_, auction_, viewer_) {
    option = option_;
    perp = perp_;
    forwardFeed = forwardFeed_;
    settlementFeed = settlementFeed_;
    spotFeed = spotFeed_;
  }

  function mergeAccounts(uint mergeIntoId, uint[] memory mergeFromIds) external {
    _mergeAccounts(mergeIntoId, mergeFromIds);
  }

  function symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) external {
    _symmetricManagerAdjustment(from, to, asset, subId, amount);
  }

  function getOptionOIFee(IGlobalSubIdOITracking asset, int delta, uint subId, uint tradeId)
    external
    view
    returns (uint fee)
  {
    fee = _getOptionOIFee(asset, forwardFeed, delta, subId, tradeId);
  }

  function getPerpOIFee(IPerpAsset asset, int delta, uint tradeId) external view returns (uint fee) {
    fee = _getPerpOIFee(asset, delta, tradeId);
  }

  function settleOptions(uint accountId) external {
    _settleAccountOptions(option, accountId);
  }

  function handleAdjustment(
    uint, /*accountId*/
    uint, /*tradeId*/
    address,
    ISubAccounts.AssetDelta[] calldata, /*assetDeltas*/
    bytes memory
  ) public {}

  function getMargin(uint, bool) external view returns (int) {}

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int) {}

  function setBalances(uint accountId, ISubAccounts.AssetBalance[] memory assets) external {
    for (uint i = 0; i < assets.length; ++i) {
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment({
          acc: accountId,
          asset: assets[i].asset,
          subId: assets[i].subId,
          amount: assets[i].balance,
          assetData: bytes32(0)
        })
      );
    }
  }
}

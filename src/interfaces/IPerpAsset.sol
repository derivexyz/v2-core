// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

interface IPerpAsset is IAsset {
  struct PositionDetail {
    uint entryPrice;
    int funding;
    int lastAggregatedFundingRate;
    uint lastPositionUpdated; // timestamp of the last time position was updated
    uint lastFundingPaid; // timestamp of the last time funding was paid
  }

  //////////////////
  //   Events     //
  //////////////////

  event ImpactPricesSet(int askPrice, int bidPrice);

  event BotWhitelisted(address bot, bool isWhitelisted);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error PA_NotAccount();

  /// @dev caller is not the liquidation module
  error PA_NotLiquidationModule();

  /// @dev revert when user trying to upgrade to a unknown manager
  error PA_UnknownManager();

  /// @dev caller is not owner of the account
  error PA_OnlyAccountOwner();

  error PA_ImpactPriceMustBePositive();

  /// @dev ask price must be higher than bid price
  error PA_InvalidImpactPrices();

  /// @dev Caller is not a whitelisted bot
  error PA_OnlyBot();
}

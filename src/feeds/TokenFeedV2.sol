// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "src/interfaces/ITokenFeedV2.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ISpotFeeds.sol";

import "src/libraries/Owned.sol";
import "src/libraries/OptionEncoding.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/IntLib.sol";

/**
 * @title TokenFeedV2
 * @author Lyra
 * @notice feed used for v2.0 launch that support settlement price and future price
 */
contract TokenFeedV2 is ITokenFeedV2 {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  ///@dev Id used to query spot price from chainlink
  uint public immutable feedId;

  ISpotFeeds immutable chainlinkPriceFeed;

  ///@dev Expiry => Settlement price
  mapping(uint => uint) internal settlementPrices;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(ISpotFeeds _chainlinkSpotFeed, uint _feedId) {
    chainlinkPriceFeed = _chainlinkSpotFeed;
    feedId = _feedId;
  }

  ////////////////
  // Settlement //
  ////////////////

  /**
   * @notice Locks-in price which the option settles at for an expiry.
   * @dev Settlement handled by option to simplify multiple managers settling same option
   * @param expiry Timestamp of when the option expires
   */
  function setSettlementPrice(uint expiry) external {
    if (settlementPrices[expiry] != 0) revert SettlementPriceAlreadySet(expiry, settlementPrices[expiry]);
    if (expiry > block.timestamp) revert NotExpired(expiry, block.timestamp);

    settlementPrices[expiry] = chainlinkPriceFeed.getSpot(feedId);
    emit SettlementPriceSet(expiry, 0);
  }

  function getSettlementPrice(uint expiry) external view returns (uint) {
    return settlementPrices[expiry];
  }

  /**
   * @dev For now we just return spot price as future price
   */
  function getFuturePrice(uint /*expiry*/ ) external view returns (uint futurePrice) {
    return chainlinkPriceFeed.getSpot(feedId);
  }
}

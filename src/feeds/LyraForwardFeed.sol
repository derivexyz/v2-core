// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// Libraries
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/Math.sol";

// Inherited
import "src/feeds/BaseLyraFeed.sol";

// Interfaces
import {ILyraForwardFeed} from "../interfaces/ILyraForwardFeed.sol";
import {IForwardFeed} from "../interfaces/IForwardFeed.sol";
import {ISettlementFeed} from "../interfaces/ISettlementFeed.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

/**
 * @title LyraForwardFeed
 * @author Lyra
 * @notice Forward feed that takes off-chain updates, verify signature and update on-chain
 *  also includes a twap average as the expiry approaches 0. This is used to ensure option value is predictable as it
 *  approaches expiry. Will also use the aggregate (spot * time) values to determine the final settlement price of the
 *  options.
 *  Forward price is computed as a difference between the current spot price and the forward rate. This means only the
 *  spot feed needs to be updated more frequently.
 */
contract LyraForwardFeed is BaseLyraFeed, ILyraForwardFeed, IForwardFeed, ISettlementFeed {
  bytes32 public constant FORWARD_DATA_TYPEHASH = keccak256(
    "ForwardData(uint64 expiry,uint256 settlementStartAggregate,uint256 currentSpotAggregate,int96 fwdSpotDifference,uint64 confidence,uint64 timestamp,uint256 deadline,address signer,bytes signature)"
  );

  uint64 public constant SETTLEMENT_TWAP_DURATION = 30 minutes;

  ISpotFeed public spotFeed;

  /// @dev secondary heartbeat for when the forward price is close to expiry
  uint64 public settlementHeartbeat = 5 minutes;

  /// @dev forward price data
  mapping(uint64 => ForwardDetails) private forwardDetails;

  /// @dev settlement price data, as time approach expiry
  ///      the spot data stored here start contributing to forward price
  mapping(uint64 => SettlementDetails) private settlementDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(ISpotFeed _spotFeed) BaseLyraFeed("LyraForwardFeed", "1") {
    spotFeed = _spotFeed;
    emit SpotFeedUpdated(_spotFeed);
  }

  ///////////
  // Admin //
  ///////////

  /**
   * @dev in the last SETTLEMENT_TWAP_DURATION before expiry, we require constant update on settlement data
   * the call to get forward price will revert if last updated time is longer than settlementHeartbeat seconds ago
   */
  function setSettlementHeartbeat(uint64 _settlementHeartbeat) external onlyOwner {
    settlementHeartbeat = _settlementHeartbeat;
    emit SettlementHeartbeatUpdated(_settlementHeartbeat);
  }

  /**
   * @dev update the spot feed address
   */
  function setSpotFeed(ISpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;
    emit SpotFeedUpdated(_spotFeed);
  }

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets forward price for a given expiry
   * @dev as time approach expiry, the forward price will be a twap of the forward price & settlement price (twap of spot)
   */
  function getForwardPrice(uint64 expiry) external view returns (uint, uint) {
    (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence) = getForwardPricePortions(expiry);

    return (forwardFixedPortion + forwardVariablePortion, confidence);
  }

  /**
   * @notice Gets forward price for a given expiry
   * @return forwardFixedPortion The portion of the settlement price that is guaranteed to be included.
   *  Options have no further delta exposure to this portion.
   * @return forwardVariablePortion The part of the price that can still change until expiry
   * @return confidence The confidence value of the feed
   */
  function getForwardPricePortions(uint64 expiry)
    public
    view
    returns (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence)
  {
    (uint spotPrice, uint spotConfidence) = spotFeed.getSpot();

    ForwardDetails memory fwdDeets = forwardDetails[expiry];
    _verifyDetailTimestamp(expiry, fwdDeets.timestamp, expiry - SETTLEMENT_TWAP_DURATION);

    (forwardFixedPortion, forwardVariablePortion) =
      _getSettlementPricePortions(spotPrice, fwdDeets, settlementDetails[expiry], expiry);

    return (forwardFixedPortion, forwardVariablePortion, Math.min(fwdDeets.confidence, spotConfidence));
  }

  /**
   * @notice Gets settlement price for a given expiry
   * @dev Will revert if the provided data timestamp does not match the expiry
   */
  function getSettlementPrice(uint64 expiry) external view returns (bool settled, uint price) {
    // The data must have the exact same timestamp as the expiry to be considered valid for settlement
    if (forwardDetails[expiry].timestamp != expiry) {
      return (false, 0);
    }

    SettlementDetails memory settlementData = settlementDetails[expiry];

    return
      (true, (settlementData.currentSpotAggregate - settlementData.settlementStartAggregate) / SETTLEMENT_TWAP_DURATION);
  }

  ////////////////////////
  // Internal Functions //
  ////////////////////////

  /// @dev Checks the cached data timestamp against the heartbeat, and settlement heartbeat if applicable
  function _verifyDetailTimestamp(uint64 expiry, uint64 fwdDetailsTimestamp, uint64 settlementFeedStart) internal view {
    if (fwdDetailsTimestamp == 0) {
      revert LFF_MissingExpiryData();
    }

    // If price is settled, return early cause we will only rely on settlement data
    if (fwdDetailsTimestamp == expiry) {
      return;
    }

    // If price is not settled, check that the last updated forward data is not stale
    _checkNotStale(fwdDetailsTimestamp);

    // user should attach the latest settlement data to the forward data
    if (block.timestamp > settlementFeedStart && fwdDetailsTimestamp + settlementHeartbeat < block.timestamp) {
      revert LFF_SettlementDataTooOld();
    }
  }

  /**
   * @return fixedPortion The portion of the settlement price that is guaranteed to be included.
   *  Options have no further delta exposure to this portion.
   * @return variablePortion The part of the price that can still change until expiry (current forward price applied to
   *  the remaining time until expiry)
   */
  function _getSettlementPricePortions(
    uint spotPrice,
    ForwardDetails memory fwdDeets,
    SettlementDetails memory settlementData,
    uint64 expiry
  ) internal pure returns (uint fixedPortion, uint variablePortion) {
    // UNSCALED variable portion (must be scaled down if close to expiry)
    variablePortion = SafeCast.toUint256(SafeCast.toInt256(spotPrice) + int(fwdDeets.fwdSpotDifference));

    // It's possible at the start of the period these values are equal, so just ignore them
    if (expiry - fwdDeets.timestamp >= SETTLEMENT_TWAP_DURATION) {
      return (0, variablePortion);
    }

    // SCALED fixed portion (must be scaled down if not at expiry)
    uint aggregateDiff = settlementData.currentSpotAggregate - settlementData.settlementStartAggregate;
    fixedPortion = aggregateDiff / SETTLEMENT_TWAP_DURATION;

    // Now scale the variable portion down since we're past the settlement threshold
    // timestamp cannot exceed expiry, so this will be 0 if we're at expiry
    variablePortion = variablePortion * (expiry - fwdDeets.timestamp) / SETTLEMENT_TWAP_DURATION;

    return (fixedPortion, variablePortion);
  }

  function _verifySettlementDataValid(ForwardAndSettlementData memory forwardData) internal pure {
    if (
      forwardData.settlementStartAggregate == 0 //
        || forwardData.currentSpotAggregate == 0
        || forwardData.settlementStartAggregate >= forwardData.currentSpotAggregate
    ) {
      revert LFF_InvalidSettlementData();
    }
  }

  /////////////////////////
  // Parsing signed data //
  /////////////////////////

  function acceptData(bytes calldata data) external override {
    // parse data as ForwardData
    ForwardAndSettlementData memory forwardData = abi.decode(data, (ForwardAndSettlementData));
    // verify signature
    bytes32 structHash = hashForwardData(forwardData);
    _verifySignatureDetails(
      forwardData.signer, structHash, forwardData.signature, forwardData.deadline, forwardData.timestamp
    );

    // ignore if timestamp is lower or equal to current
    if (forwardData.timestamp <= forwardDetails[forwardData.expiry].timestamp) return;

    if (forwardData.confidence > 1e18) {
      revert LFF_InvalidConfidence();
    }

    if (forwardData.timestamp > forwardData.expiry) {
      revert LFF_InvalidFwdDataTimestamp();
    }

    SettlementDetails memory settlementData;
    if (forwardData.timestamp >= forwardData.expiry - SETTLEMENT_TWAP_DURATION) {
      // Settlement data, must include spot aggregate values
      _verifySettlementDataValid(forwardData);

      settlementData = SettlementDetails({
        settlementStartAggregate: forwardData.settlementStartAggregate,
        currentSpotAggregate: forwardData.currentSpotAggregate
      });

      settlementDetails[forwardData.expiry] = settlementData;
    }

    // always update forward
    ForwardDetails memory forwardDetail = ForwardDetails({
      fwdSpotDifference: forwardData.fwdSpotDifference,
      confidence: forwardData.confidence,
      timestamp: forwardData.timestamp
    });
    forwardDetails[forwardData.expiry] = forwardDetail;

    emit ForwardDataUpdated(forwardData.expiry, forwardData.signer, forwardDetail, settlementData);
  }

  /**
   * @dev return the hash of the spotData object
   */
  function hashForwardData(ForwardAndSettlementData memory forwardData) public pure returns (bytes32) {
    return keccak256(
      abi.encode(
        FORWARD_DATA_TYPEHASH,
        forwardData.fwdSpotDifference,
        forwardData.settlementStartAggregate,
        forwardData.currentSpotAggregate,
        forwardData.confidence,
        forwardData.timestamp
      )
    );
  }
}

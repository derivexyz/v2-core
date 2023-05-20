// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

import "openzeppelin/access/Ownable2Step.sol";
// interfaces
import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IDataReceiver.sol";
import "src/interfaces/ILyraSpotFeed.sol";
import "./BaseLyraFeed.sol";
import "../interfaces/ILyraForwardAndSettlementFeed.sol";
import "../interfaces/IForwardFeed.sol";
import "../interfaces/ISettlementFeed.sol";
import "../interfaces/ILyraForwardAndSettlementFeed.sol";

/**
 * @title LyraForwardFeed
 * @author Lyra
 * @notice Forward feed that takes off-chain updates, verify signature and update on-chain
 *  also includes a twap average as the expiry approaches 0. This is used to ensure option value is predictable as it
 *  approaches expiry. Will also use the aggregate (spot * time) values to determine the final settlement price of the
 *  options.
 */
contract LyraForwardFeed is BaseLyraFeed, ILyraForwardFeed, IForwardFeed, ISettlementFeed {
  bytes32 public constant FORWARD_DATA_TYPEHASH = keccak256(
    "SpotData(uint64 expiry,uint settlementStartAggregate,uint currentSpotAggregate,uint96 forwardPrice,uint64 confidence,uint64 timestamp,uint deadline,address signer,bytes signature)"
  );

  uint64 public constant SETTLEMENT_TWAP_DURATION = 30 minutes;

  // @dev secondary heartbeat for when the forward price is close to expiry
  uint64 settlementHeartbeat = 2 minutes;
  mapping(uint64 => ForwardDetails) private forwardDetails;
  mapping(uint64 => SettlementDetails) private settlementDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraForwardFeed", "1") {}

  ///////////
  // Admin //
  ///////////

  function setSettlementHeartbeat(uint64 _settlementHeartbeat) external onlyOwner {
    settlementHeartbeat = _settlementHeartbeat;
    emit SettlementHeartbeatUpdated(_settlementHeartbeat);
  }

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets forward price for a given expiry
   */
  function getForwardPrice(uint64 expiry) external view returns (uint, uint) {
    (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence) = getForwardPricePortions(expiry);

    return (forwardFixedPortion + forwardVariablePortion, confidence);
  }

  /**
   * @notice Gets forward price for a given expiry
   * @return forwardFixedPortion The part of the settlement price that wont change
   * @return forwardVariablePortion The part of the price that can still change until expiry
   * @return confidence The confidence value of the feed
   */
  function getForwardPricePortions(uint64 expiry)
    public
    view
    returns (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence)
  {
    ForwardDetails memory fwdDeets = forwardDetails[uint64(expiry)];

    _verifyDetailTimestamp(fwdDeets.timestamp, expiry - SETTLEMENT_TWAP_DURATION);

    (forwardFixedPortion, forwardVariablePortion) =
      _getSettlementPricePortions(fwdDeets, settlementDetails[expiry], expiry);

    return (forwardFixedPortion, forwardVariablePortion, fwdDeets.confidence);
  }

  /**
   * @notice Gets settlement price for a given expiry
   * @dev Will revert if the provided data timestamp does not match the expiry
   */
  function getSettlementPrice(uint64 expiry) external view returns (uint price) {
    // The data must have the exact same timestamp as the expiry to be considered valid for settlement
    if (forwardDetails[expiry].timestamp != expiry) {
      revert LFF_InvalidDataTimestampForSettlement();
    }

    SettlementDetails memory settlementData = settlementDetails[expiry];

    return (settlementData.currentSpotAggregate - settlementData.settlementStartAggregate) / SETTLEMENT_TWAP_DURATION;
  }

  function acceptData(bytes calldata data) external override {
    // parse data as SpotData
    ForwardData memory forwardData = abi.decode(data, (ForwardData));
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
      forwardPrice: forwardData.forwardPrice,
      confidence: forwardData.confidence,
      timestamp: forwardData.timestamp
    });
    forwardDetails[forwardData.expiry] = forwardDetail;

    emit ForwardDataUpdated(forwardData.expiry, forwardData.signer, forwardDetail, settlementData);
  }

  /**
   * @dev return the hash of the spotData object
   */
  function hashForwardData(ForwardData memory forwardData) public pure returns (bytes32) {
    return keccak256(
      abi.encode(
        FORWARD_DATA_TYPEHASH,
        forwardData.forwardPrice,
        forwardData.settlementStartAggregate,
        forwardData.currentSpotAggregate,
        forwardData.confidence,
        forwardData.timestamp
      )
    );
  }

  ////////////////////////
  // Internal Functions //
  ////////////////////////

  function _verifyDetailTimestamp(uint64 fwdDetailsTimestamp, uint64 settlementFeedStart) internal view {
    if (fwdDetailsTimestamp == 0) {
      revert LFF_MissingExpiryData();
    }

    _verifyTimestamp(fwdDetailsTimestamp);

    if (block.timestamp > settlementFeedStart && fwdDetailsTimestamp + settlementHeartbeat < block.timestamp) {
      revert LFF_SettlementDataTooOld();
    }
  }

  function _getSettlementPricePortions(
    ForwardDetails memory fwdDeets,
    SettlementDetails memory settlementData,
    uint64 expiry
  ) internal pure returns (uint fixedPortion, uint variablePortion) {
    // It's possible at the start of the period these values are equal, so just ignore them
    if (expiry - fwdDeets.timestamp >= SETTLEMENT_TWAP_DURATION) {
      return (0, fwdDeets.forwardPrice);
    }

    // fixedPortion is the part of settlement which cannot change from here on out
    uint aggregateDiff = settlementData.currentSpotAggregate - settlementData.settlementStartAggregate;
    fixedPortion = aggregateDiff / SETTLEMENT_TWAP_DURATION;

    variablePortion = fwdDeets.forwardPrice * (expiry - fwdDeets.timestamp) / SETTLEMENT_TWAP_DURATION;

    return (fixedPortion, variablePortion);
  }

  function _verifySettlementDataValid(ForwardData memory forwardData) internal pure {
    if (
      forwardData.settlementStartAggregate == 0 //
        || forwardData.currentSpotAggregate == 0
        || forwardData.settlementStartAggregate >= forwardData.currentSpotAggregate
    ) {
      revert LFF_InvalidSettlementData();
    }
  }
}

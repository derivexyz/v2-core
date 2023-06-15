// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";
import {ILyraSpotFeed} from "../interfaces/ILyraSpotFeed.sol";

/**
 * @title LyraSpotFeed
 * @author Lyra
 * @notice Spot feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraSpotFeed is BaseLyraFeed, ILyraSpotFeed, ISpotFeed {
  bytes32 public constant SPOT_DATA_TYPEHASH = keccak256(
    "SpotData(uint96 price,uint64 confidence,uint64 timestamp,uint256 deadline,address signer,bytes signature)"
  );

  // pack the following into 1 storage slot
  SpotDetail private spotDetail;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraSpotFeed", "1") {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets spot price
   * @return spotPrice Spot price with 18 decimals.
   */
  function getSpot() public view returns (uint, uint) {
    _checkNotStale(spotDetail.timestamp);

    return (spotDetail.price, spotDetail.confidence);
  }

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata data) external override {
    // parse data as SpotData
    SpotData memory spotData = abi.decode(data, (SpotData));
    // verify signature
    bytes32 structHash = hashSpotData(spotData);

    _verifySignatureDetails(spotData.signer, structHash, spotData.signature, spotData.deadline, spotData.timestamp);

    // ignore if timestamp is lower or equal to current
    if (spotData.timestamp <= spotDetail.timestamp) return;

    if (spotData.confidence > 1e18) {
      revert LSF_InvalidConfidence();
    }

    // update spot price
    spotDetail = SpotDetail(spotData.price, spotData.confidence, spotData.timestamp);

    emit SpotPriceUpdated(spotData.signer, spotData.price, spotData.confidence, spotData.timestamp);
  }

  /**
   * @dev return the hash of the spotData object
   */
  function hashSpotData(SpotData memory spotData) public pure returns (bytes32) {
    return keccak256(abi.encode(SPOT_DATA_TYPEHASH, spotData.price, spotData.confidence, spotData.timestamp));
  }
}

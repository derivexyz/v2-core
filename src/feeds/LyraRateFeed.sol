// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "src/feeds/BaseLyraFeed.sol";

// interfaces
import {ILyraRateFeed} from "../interfaces/ILyraRateFeed.sol";
import {IInterestRateFeed} from "../interfaces/IInterestRateFeed.sol";

/**
 * @title LyraRateFeed
 * @author Lyra
 * @notice Rate feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraRateFeed is BaseLyraFeed, ILyraRateFeed, IInterestRateFeed {
  bytes32 public constant RATE_DATA_TYPEHASH = keccak256(
    "RateData(uint64 expiry,int96 rate,uint64 confidence,uint64 timestamp,uint256 deadline,address signer,bytes signature)"
  );

  mapping(uint64 expiry => RateDetail) private rateDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraRateFeed", "1") {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets rate
   * @return ratePrice Rate with 18 decimals.
   */
  function getInterestRate(uint64 expiry) public view returns (int, uint) {
    RateDetail memory rateDetail = rateDetails[expiry];

    _checkNotStale(rateDetail.timestamp);

    return (rateDetail.rate, rateDetail.confidence);
  }

  /**
   * @notice Parse input data and update rate
   */
  function acceptData(bytes calldata data) external override {
    // parse data as RateData
    RateData memory rateData = abi.decode(data, (RateData));
    // verify signature
    bytes32 structHash = hashRateData(rateData);

    _verifySignatureDetails(rateData.signer, structHash, rateData.signature, rateData.deadline, rateData.timestamp);

    // ignore if timestamp is lower or equal to current
    if (rateData.timestamp <= rateDetails[rateData.expiry].timestamp) return;

    if (rateData.confidence > 1e18) {
      revert LRF_InvalidConfidence();
    }

    // update rate
    rateDetails[rateData.expiry] = RateDetail(rateData.rate, rateData.confidence, rateData.timestamp);

    emit RateUpdated(rateData.signer, rateData.expiry, rateData.rate, rateData.confidence, rateData.timestamp);
  }

  /**
   * @dev return the hash of the rateData object
   */
  function hashRateData(RateData memory rateData) public pure returns (bytes32) {
    return
      keccak256(abi.encode(RATE_DATA_TYPEHASH, rateData.expiry, rateData.rate, rateData.confidence, rateData.timestamp));
  }
}

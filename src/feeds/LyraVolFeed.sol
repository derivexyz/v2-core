// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {IVolFeed} from "../interfaces/IVolFeed.sol";
import {ILyraVolFeed} from "../interfaces/ILyraVolFeed.sol";

// libraries
import "lyra-utils/math/FixedPointMathLib.sol";
import "lyra-utils/math/SVI.sol";

/**
 * @title LyraVolFeed
 * @author Lyra
 * @notice Vol feed that takes off-chain updates, verify signature and update on-chain
 * @dev Uses SVI curve parameters to generate the full expiry of volatilities
 */
contract LyraVolFeed is BaseLyraFeed, ILyraVolFeed, IVolFeed {
  ////////////////////////
  //      Variable      //
  ////////////////////////

  mapping(uint expiry => VolDetails) private volDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraVolFeed", "1") {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets vol for a given strike and expiry
   * @return vol Vol of the given strike and expiry to 18dp.
   */
  function getVol(uint128 strike, uint64 expiry) public view returns (uint vol, uint confidence) {
    VolDetails memory volDetail = volDetails[expiry];

    // Revert if no data for given expiry
    if (volDetail.timestamp == 0) {
      revert LVF_MissingExpiryData();
    }

    _checkNotStale(volDetail.timestamp);

    // calculate the vol
    vol = SVI.getVol(
      strike,
      volDetail.SVI_a,
      volDetail.SVI_b,
      volDetail.SVI_rho,
      volDetail.SVI_m,
      volDetail.SVI_sigma,
      volDetail.SVI_fwd,
      volDetail.SVI_refTau
    );

    return (vol, volDetail.confidence);
  }

  function getExpiryMinConfidence(uint64 expiry) external view override returns (uint confidence) {
    VolDetails memory volDetail = volDetails[expiry];

    // Revert if no data for given expiry
    if (volDetail.timestamp == 0) {
      revert LVF_MissingExpiryData();
    }

    _checkNotStale(volDetail.timestamp);

    return volDetail.confidence;
  }

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata data) external override {
    FeedData memory feedData = _parseAndVerifyFeedData(data);

    (
      uint64 expiry,
      int SVI_a,
      uint SVI_b,
      int SVI_rho,
      int SVI_m,
      uint SVI_sigma,
      uint SVI_fwd,
      uint64 SVI_refTau,
      uint64 confidence
    ) = abi.decode(feedData.data, (uint64, int, uint, int, int, uint, uint, uint64, uint64));

    // ignore if timestamp is lower than current
    if (feedData.timestamp <= volDetails[expiry].timestamp) return;

    if (feedData.timestamp > expiry) revert LVF_InvalidVolDataTimestamp();

    if (confidence > 1e18) revert LVF_InvalidConfidence();

    // update spot price
    VolDetails memory newVolDetails = VolDetails({
      SVI_a: SVI_a,
      SVI_b: SVI_b,
      SVI_rho: SVI_rho,
      SVI_m: SVI_m,
      SVI_sigma: SVI_sigma,
      SVI_fwd: SVI_fwd,
      SVI_refTau: SVI_refTau,
      confidence: confidence,
      timestamp: feedData.timestamp
    });
    volDetails[expiry] = newVolDetails;

    emit VolDataUpdated(expiry, newVolDetails);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "lyra-utils/math/FixedPointMathLib.sol";

// interfaces
import "src/interfaces/IDataReceiver.sol";
import "src/interfaces/IVolFeed.sol";
import "./BaseLyraFeed.sol";

library SVI {
  // TODO: move to lyra-utils and CLEAN UP A LOT
  function getVol(uint strike, int SVI_a, uint SVI_b, int SVI_rho, int SVI_m, uint SVI_sigma, uint SVI_spot)
    internal
    pure
    returns (uint128)
  {
    int k = FixedPointMathLib.ln(int(strike * 1e18 / SVI_spot));

    // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05
    int k_sub_m = int(k) - SVI_m;
    int k_sub_m_sq = k_sub_m * k_sub_m / 1e18;
    int sigma_sq = int(SVI_sigma * SVI_sigma / 1e18);

    return uint128(
      FixedPointMathLib.sqrt(
        uint(
          SVI_a
            + (int(SVI_b) * ((SVI_rho * k_sub_m / 1e18) + int(FixedPointMathLib.sqrt(uint(k_sub_m_sq + sigma_sq)))))
              / 1e18
        )
      )
    );
  }
}

interface ILyraVolFeed {
  struct VolData {
    uint64 expiry;
    // price data
    int SVI_a;
    uint SVI_b;
    int SVI_rho;
    int SVI_m;
    uint SVI_sigma;
    uint SVI_spot;
    uint64 confidence;
    uint64 timestamp;
    // the latest timestamp you can use this data
    uint deadline;
    // signature v, r, s
    address signer;
    bytes signature;
  }

  /// @dev structure to store in contract storage
  struct VolDetails {
    int SVI_a;
    uint SVI_b;
    int SVI_rho;
    int SVI_m;
    uint SVI_sigma;
    uint SVI_spot;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LVF_MissingExpiryData();

  ////////////////////////
  //       Events       //
  ////////////////////////
  event VolDataUpdated(address indexed signer, uint64 indexed expiry, VolDetails volDetails);
}

/**
 * @title LyraVolFeed
 * @author Lyra
 * @notice Vol feed that takes off-chain updates, verify signature and update on-chain
 * @dev Uses SVI curve parameters to generate the full expiry of volatilities
 */
contract LyraVolFeed is BaseLyraFeed, ILyraVolFeed, IVolFeed {
  ////////////////////////
  //     Constants      //
  ////////////////////////
  bytes32 public constant VOL_DATA_TYPEHASH = keccak256(
    "VolData(int SVI_a,uint SVI_b,int SVI_rho,int SVI_m,uint SVI_sigma,uint SVI_spot,uint64 confidence,uint64 timestamp,uint deadline,address signer,bytes signature)"
  );

  ////////////////////////
  //      Variable      //
  ////////////////////////

  // expiry => vol details
  mapping(uint => VolDetails) private volDetails;

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
  function getVol(uint128 strike, uint64 expiry) public view returns (uint128 vol, uint64 confidence) {
    VolDetails memory volDetail = volDetails[expiry];

    if (volDetail.timestamp == 0) {
      // TODO: is this just caught by solidity?
      revert LVF_MissingExpiryData();
    }

    _verifyTimestamp(volDetail.timestamp);

    // calculate the vol
    vol = SVI.getVol(
      strike,
      volDetail.SVI_a,
      volDetail.SVI_b,
      volDetail.SVI_rho,
      volDetail.SVI_m,
      volDetail.SVI_sigma,
      volDetail.SVI_spot
    );

    return (vol, volDetail.confidence);
  }

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata data) external override {
    // parse data as SpotData
    VolData memory volData = abi.decode(data, (VolData));
    // verify signature
    bytes32 structHash = hashVolData(volData);

    _verifySignatureDetails(volData.signer, structHash, volData.signature, volData.deadline, volData.timestamp);

    // ignore if timestamp is lower than current
    if (volData.timestamp <= volDetails[volData.expiry].timestamp) return;

    // update spot price
    VolDetails memory newVolDetails = VolDetails({
      SVI_a: volData.SVI_a,
      SVI_b: volData.SVI_b,
      SVI_rho: volData.SVI_rho,
      SVI_m: volData.SVI_m,
      SVI_sigma: volData.SVI_sigma,
      SVI_spot: volData.SVI_spot,
      confidence: volData.confidence,
      timestamp: volData.timestamp
    });
    volDetails[volData.expiry] = newVolDetails;

    emit VolDataUpdated(volData.signer, volData.expiry, newVolDetails);
  }

  /**
   * @dev return the hash of the spotData object
   */
  function hashVolData(VolData memory volData) public pure returns (bytes32) {
    return keccak256(
      abi.encode(
        VOL_DATA_TYPEHASH,
        volData.SVI_a,
        volData.SVI_b,
        volData.SVI_rho,
        volData.SVI_m,
        volData.SVI_sigma,
        volData.SVI_spot,
        volData.confidence,
        volData.timestamp
      )
    );
  }
}

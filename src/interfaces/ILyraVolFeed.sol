// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraVolFeed {
  struct VolData {
    uint64 expiry;
    // price data
    int SVI_a;
    uint SVI_b;
    int SVI_rho;
    int SVI_m;
    uint SVI_sigma;
    uint SVI_fwd;
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
    uint SVI_fwd;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LVF_MissingExpiryData();
  error LVF_InvalidVolDataTimestamp();

  ////////////////////////
  //       Events       //
  ////////////////////////
  event VolDataUpdated(address indexed signer, uint64 indexed expiry, VolDetails volDetails);
}

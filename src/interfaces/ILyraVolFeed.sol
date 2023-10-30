// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IBaseLyraFeed} from "./IBaseLyraFeed.sol";

interface ILyraVolFeed is IBaseLyraFeed {
  /// @dev structure to store in contract storage
  struct VolDetails {
    int SVI_a;
    uint SVI_b;
    int SVI_rho;
    int SVI_m;
    uint SVI_sigma;
    uint SVI_fwd;
    uint64 SVI_refTau;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LVF_MissingExpiryData();
  error LVF_InvalidVolDataTimestamp();
  error LVF_InvalidConfidence();

  ////////////////////////
  //       Events       //
  ////////////////////////
  event VolDataUpdated(uint64 indexed expiry, VolDetails volDetails);
}

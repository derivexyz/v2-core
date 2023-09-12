// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";

// interfaces
import {IInterestRateFeed} from "../interfaces/IInterestRateFeed.sol";

/**
 * @title LyraRateFeedStatic
 * @author Lyra
 * @notice Static feed contract we use that set static interest rates for PMRM.
 */
contract LyraRateFeedStatic is Ownable2Step, IInterestRateFeed {
  event RateUpdated(int64 rate, uint64 confidence);

  error LRFS_StaticRateOutOfRange();

  ////////////////////////
  //     Variables      //
  ////////////////////////

  int64 public rate;
  uint64 public confidence;

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  function setRate(int64 _rate, uint64 _confidence) external onlyOwner {
    if (_rate > 1e18 || _rate < -1e18) revert LRFS_StaticRateOutOfRange();
    rate = _rate;
    confidence = _confidence;

    emit RateUpdated(_rate, _confidence);
  }

  /**
   * @notice Gets rate
   * @return ratePrice Rate with 18 decimals.
   */
  function getInterestRate(uint64 /*expiry*/ ) public view returns (int, uint) {
    return (rate, confidence);
  }
}

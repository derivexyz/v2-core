// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {IAllowList} from "../interfaces/IAllowList.sol";

/**
 * @title AllowList
 * @author Lyra
 * @notice Tracks users that are allowed to trade
 */
contract AllowList is BaseLyraFeed, IAllowList {
  // @dev If disabled, all users can trade
  bool public allowListEnabled;
  // user => allowed
  mapping(address => AllowListDetails) public allowListDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("AllowList", "1") {}

  ////////////////////////
  // Owner Only Actions //
  ////////////////////////

  /**
   * @notice Enable or disable allow list
   */
  function setAllowListEnabled(bool enabled) external onlyOwner {
    allowListEnabled = enabled;
    emit AllowListEnabled(enabled);
  }

  ////////////////////////
  //  Public Functions  //
  ////////////////////////
  /**
   * @notice Check if a user is allowed to trade
   */
  function canTrade(address user) external view returns (bool) {
    if (!allowListEnabled) {
      return true;
    }
    return allowListDetails[user].allowed;
  }

  /**
   * @notice Parse input data and update the allowlist
   */
  function acceptData(bytes calldata data) external override {
    FeedData memory feedData = _parseAndVerifyFeedData(data);

    (address user, bool allowed) = abi.decode(feedData.data, (address, bool));

    if (allowListDetails[user].timestamp >= feedData.timestamp) {
      return;
    }

    AllowListDetails memory details = AllowListDetails({timestamp: feedData.timestamp, allowed: allowed});
    allowListDetails[user] = details;

    emit AllowListUpdated(feedData.signer, user, details);
  }
}

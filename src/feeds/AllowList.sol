// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "src/feeds/BaseLyraFeed.sol";

// interfaces
import "src/interfaces/IAllowList.sol";

/**
 * @title AllowList
 * @author Lyra
 * @notice Tracks users that are allowed to trade
 */
contract AllowList is BaseLyraFeed, IAllowList {
  bytes32 public constant ALLOW_LIST_DATA_TYPEHASH = keccak256(
    "AllowListData(address user,bool allowed,uint64 timestamp,uint256 deadline,address signer,bytes signature)"
  );

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
    AllowListData memory allowListData = abi.decode(data, (AllowListData));

    bytes32 structHash = hashSpotData(allowListData);

    _verifySignatureDetails(allowListData.signer, structHash, allowListData.signature, allowListData.deadline, 0);

    if (allowListDetails[allowListData.user].timestamp >= allowListData.timestamp) {
      return;
    }

    AllowListDetails memory details =
      AllowListDetails({timestamp: allowListData.timestamp, allowed: allowListData.allowed});
    allowListDetails[allowListData.user] = details;

    emit AllowListUpdated(allowListData.signer, allowListData.user, details);
  }

  /**
   * @dev return the hash of the allowListData object
   */
  function hashSpotData(AllowListData memory allowListData) public pure returns (bytes32) {
    return keccak256(
      abi.encode(
        ALLOW_LIST_DATA_TYPEHASH,
        allowListData.signer,
        allowListData.user,
        allowListData.allowed,
        allowListData.timestamp
      )
    );
  }
}

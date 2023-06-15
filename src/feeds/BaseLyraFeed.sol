// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "lyra-utils/math/FixedPointMathLib.sol";

// interfaces
import {IDataReceiver} from "../interfaces/IDataReceiver.sol";
import {IVolFeed} from "../interfaces/IVolFeed.sol";
import {IBaseLyraFeed} from "../interfaces/IBaseLyraFeed.sol";

/**
 * @title BaseLyraFeed
 * @author Lyra
 * @dev Base contract for feeds that use multiple signers and signed messages to update their own data types.
 */
abstract contract BaseLyraFeed is EIP712, Ownable2Step, IDataReceiver, IBaseLyraFeed {
  bytes32 public constant FEED_DATA_TYPEHASH =
    keccak256("FeedData(bytes data,uint256 deadline,uint64 timestamp,address signer,bytes signature)");

  ////////////////////////
  //     Variables      //
  ////////////////////////

  mapping(address => bool) public isSigner;
  uint64 public heartbeat;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(string memory name, string memory version) EIP712("LyraVolFeed", "1") {}

  ////////////////////////
  //  Admin Functions   //
  ////////////////////////

  function addSigner(address signer, bool isWhitelisted) external onlyOwner {
    isSigner[signer] = isWhitelisted;
    emit SignerUpdated(signer, isWhitelisted);
  }

  function setHeartbeat(uint64 newHeartbeat) external onlyOwner {
    heartbeat = newHeartbeat;
  }

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @dev get domain separator for signing
   */
  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  ////////////////////////
  //  Helper Functions  //
  ////////////////////////
  function _checkNotStale(uint64 timestamp) internal view {
    if (timestamp + heartbeat < block.timestamp) {
      revert BLF_DataTooOld();
    }
  }

  function _verifyFeedData(FeedData memory feedData) internal view {
    bytes32 hashedData = hashFeedData(feedData);
    // check the signature is from the signer is valid
    if (!SignatureChecker.isValidSignatureNow(feedData.signer, _hashTypedDataV4(hashedData), feedData.signature)) {
      revert BLF_InvalidSignature();
    }

    // check that it is a valid signer
    if (!isSigner[feedData.signer]) {
      revert BLF_InvalidSigner();
    }

    // check the deadline
    if (feedData.deadline < block.timestamp) {
      revert BLF_DataExpired();
    }

    // cannot set price in the future
    if (feedData.timestamp > block.timestamp) {
      revert BLF_InvalidTimestamp();
    }
  }

  function _verifySignatureDetails(
    address signer,
    bytes32 dataHash,
    bytes memory signature,
    uint deadline,
    uint64 dataTimestamp
  ) internal view {
    // check the signature is from the signer is valid
    if (!SignatureChecker.isValidSignatureNow(signer, _hashTypedDataV4(dataHash), signature)) {
      revert BLF_InvalidSignature();
    }

    // check that it is a valid signer
    if (!isSigner[signer]) {
      revert BLF_InvalidSigner();
    }

    // check the deadline
    if (deadline < block.timestamp) {
      revert BLF_DataExpired();
    }

    // cannot set price in the future
    if (dataTimestamp > block.timestamp) {
      revert BLF_InvalidTimestamp();
    }
  }

  function hashFeedData(FeedData memory feedData) public pure returns (bytes32) {
    return
      keccak256(abi.encode(FEED_DATA_TYPEHASH, feedData.data, feedData.deadline, feedData.timestamp, feedData.signer));
  }
}

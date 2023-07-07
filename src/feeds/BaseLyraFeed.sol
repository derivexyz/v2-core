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

  ///@dev mapping of address to whether they are whitelisted signers
  mapping(address => bool) public isSigner;

  ///@dev number of signers required to submit data
  uint8 public requiredSigners = 1;

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

  function setRequiredSigners(uint8 newRequiredSigners) external onlyOwner {
    if (newRequiredSigners == 0) revert BLF_InvalidRequiredSigners();
    requiredSigners = newRequiredSigners;

    emit RequiredSignersUpdated(newRequiredSigners);
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

  /**
   * @dev parse data into FeedDa and verify signature, deadline and signed timestamp
   */
  function _parseAndVerifyFeedData(bytes memory data) internal view returns (FeedData memory feedData) {
    feedData = abi.decode(data, (FeedData));
    bytes32 hashedData = hashFeedData(feedData);
    // check the signature is from the signer is valid
    uint numOfSigners = feedData.signers.length;
    if (numOfSigners < requiredSigners) revert BLF_NotEnoughSigners();
    if (numOfSigners != feedData.signatures.length) revert BLF_SignatureSignersLengthMismatch();

    // verify all signatures

    // 256 bit that flip all the bits of address that have signed
    uint addressMask;
    for (uint i = 0; i < numOfSigners; i++) {
      // check that the signer has not signed before
      if (addressMask & uint160(feedData.signers[i]) == uint160(feedData.signers[i])) {
        revert BLF_DuplicatedSigner();
      }
      addressMask |= uint160(feedData.signers[i]);

      if (
        !SignatureChecker.isValidSignatureNow(feedData.signers[i], _hashTypedDataV4(hashedData), feedData.signatures[i])
      ) {
        revert BLF_InvalidSignature();
      }

      // check that it is a valid signer
      if (!isSigner[feedData.signers[i]]) {
        revert BLF_InvalidSigner();
      }
    }

    // check the deadline
    if (feedData.deadline < block.timestamp) {
      revert BLF_DataExpired();
    }

    // signed timestamp cannot be in the future
    if (feedData.timestamp > block.timestamp) {
      revert BLF_InvalidTimestamp();
    }
  }

  function hashFeedData(FeedData memory feedData) public pure returns (bytes32) {
    return keccak256(abi.encode(FEED_DATA_TYPEHASH, feedData.data, feedData.deadline, feedData.timestamp));
  }
}

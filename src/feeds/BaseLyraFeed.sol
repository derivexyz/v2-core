// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "lyra-utils/math/FixedPointMathLib.sol";

// interfaces
import "src/interfaces/IDataReceiver.sol";
import "src/interfaces/IVolFeed.sol";

interface IBaseLyraFeed {
  ////////////////////////
  //       Errors       //
  ////////////////////////

  /// @dev bad signature
  error BLF_InvalidSignature();

  /// @dev Invalid signer
  error BLF_InvalidSigner();

  /// @dev submission is expired
  error BLF_DataExpired();

  /// @dev invalid nonce
  error BLF_InvalidTimestamp();

  /// @dev Data has crossed heartbeat threshold
  error BLF_DataTooOld();

  /// @dev function has not been implemented by inheriting contract
  error BLF_NotImplementedError();

  ////////////////////////
  //       Events       //
  ////////////////////////

  event SignerUpdated(address indexed signer, bool isWhitelisted);
  event HeartbeatUpdated(address indexed signer, uint heartbeat);
}

/**
 * @title LyraVolFeed
 * @author Lyra
 * @notice Vol feed that takes off-chain updates, verify signature and update on-chain
 * @dev Uses SVI curve parameters to generate the full expiry of volatilities
 */
abstract contract BaseLyraFeed is EIP712, Ownable2Step, IDataReceiver, IBaseLyraFeed {
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

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata /* data */ ) external virtual override {
    revert BLF_NotImplementedError();
  }

  ////////////////////////
  //  Helper Functions  //
  ////////////////////////
  function _verifyTimestamp(uint64 timestamp) internal view {
    if (timestamp + heartbeat < block.timestamp) {
      revert BLF_DataTooOld();
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
}

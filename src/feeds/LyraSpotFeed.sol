// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

import "openzeppelin/access/Ownable2Step.sol";
// interfaces
import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IDataReceiver.sol";
import "src/interfaces/ILyraSpotFeed.sol";

/**
 * @title LyraSpotFeed
 * @author Lyra
 * @notice Spot feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraSpotFeed is EIP712, Ownable2Step, ILyraSpotFeed, ISpotFeed, IDataReceiver {
  // pack the following into 1 storage slot
  SpotDetail private spotDetail;

  mapping(address => bool) public isSigner;

  bytes32 public constant SPOT_DATA_TYPEHASH =
    keccak256("SpotData(uint96 price,uint64 confidence,uint64 timestamp,uint deadline,address signer,bytes signature)");

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() EIP712("LyraSpotFeed", "1") {}

  ////////////////////////
  //  Admin Functions   //
  ////////////////////////

  function addSigner(address signer, bool isWhitelisted) external onlyOwner {
    isSigner[signer] = isWhitelisted;
    emit SignerUpdated(signer, isWhitelisted);
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
   * @notice Gets spot price
   * @return spotPrice Spot price with 18 decimals.
   */
  function getSpot() public view returns (uint, uint) {
    SpotDetail memory spot = spotDetail;
    // todo: check last update timestamp, revert is stale

    // todo: update confidence based on timestamp?

    return (spot.price, spot.confidence);
  }

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata data) external {
    // parse data as SpotData
    SpotData memory spotData = abi.decode(data, (SpotData));
    // verify signature
    bytes32 structHash = hashSpotData(spotData);

    // check the signature is from signer specified in spotData
    if (!SignatureChecker.isValidSignatureNow(spotData.signer, _hashTypedDataV4(structHash), spotData.signature)) {
      revert LSF_InvalidSignature();
    }

    // check that it is a valid signer
    if (!isSigner[spotData.signer]) revert LSF_InvalidSigner();

    // check the deadline
    if (spotData.deadline < block.timestamp) revert LSF_DataExpired();

    // cannot set price in the future
    if (spotData.timestamp > block.timestamp) revert LSF_InvalidTimestamp();

    // ignore if timestamp is lower than current
    if (spotData.timestamp < spotDetail.timestamp) return;

    // update spot price
    spotDetail = SpotDetail(spotData.price, spotData.confidence, spotData.timestamp);

    emit SpotPriceUpdated(spotData.signer, spotData.price, spotData.confidence, spotData.timestamp);
  }

  /**
   * @dev return the hash of the spotData object
   */
  function hashSpotData(SpotData memory spotData) public pure returns (bytes32) {
    return keccak256(abi.encode(SPOT_DATA_TYPEHASH, spotData.price, spotData.confidence, spotData.timestamp));
  }
}

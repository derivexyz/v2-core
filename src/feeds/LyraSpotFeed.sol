// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

import "openzeppelin/access/Ownable2Step.sol";
// interfaces
import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IUpdatableOracle.sol";
import "src/interfaces/ILyraSpotFeed.sol";

/**
 * @title LyraSpotFeed
 * @author Lyra
 * @notice Spot feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraSpotFeed is EIP712, Ownable2Step, ILyraSpotFeed, ISpotFeed, IUpdatableOracle {
  uint128 public spotPrice;
  uint64 public nonce;
  uint64 public lastUpdateAt;

  mapping(address => bool) public isSigner;

  bytes32 public constant SPOT_DATA_TYPEHASH = keccak256("SpotData(uint256 spot,uint256 nonce,uint256 deadline)");

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() EIP712("LyraSpotFeed", "1") {}

  ////////////////////////
  //  Admin Functions   //
  ////////////////////////

  function addSigner(address signer, bool isWhitelisted) external {
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
    // todo: calculate confidence

    // todo: check last update timestamp, revert is stale
    return (spotPrice, 1e18);
  }

  /**
   * @notice Parse input data and update spot price
   */
  function updatePrice(bytes calldata data) external {
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

    // check nonce is higher than current
    if (spotData.nonce <= nonce) revert LSF_InvalidNonce();

    // update spot price
    nonce = spotData.nonce;
    spotPrice = spotData.price;
    lastUpdateAt = uint64(block.timestamp);

    emit SpotPriceUpdated(spotData.price, spotData.nonce);
  }

  /**
   * @dev return the hash of the spotData object
   */
  function hashSpotData(SpotData memory spotData) public pure returns (bytes32) {
    return keccak256(abi.encode(SPOT_DATA_TYPEHASH, spotData.price, spotData.nonce, spotData.deadline));
  }
}

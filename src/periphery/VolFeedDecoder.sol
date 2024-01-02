// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../interfaces/IDecoder.sol";
import "../libraries/BytesLib.sol";

/**
 * @dev VolFeedDecoder is for CompressedSubmitter to decode the compressed vol feed data, for LyraVolFeed
 */
contract VolFeedDecoder is IDecoder {
    /**
     * @dev Decode the compressed vol feed Data
     * @dev All SVI params are stored as uint80, which has max value of 1.2e+24, 
     *      With the scaler we can store value within range of
     *      [0, 1.2e+24] for uint and [-0.6e-24, 0.6e+24] for int 
     */
    function decode(bytes calldata data) external pure returns (bytes memory) {
      uint offset = 0;

      // expires can be fit in uint64
      uint64 expiry = uint64(BytesLib.bytesToUint(data[offset:offset + 8]));
      offset += 8;

      int SVI_a = int(BytesLib.bytesToUint(data[offset:offset + 10]));
      offset += 10;

      uint SVI_b = uint(BytesLib.bytesToUint(data[offset:offset + 10]));
      offset += 10;

      int SVI_rho = int(BytesLib.bytesToUint(data[offset:offset + 10]));
      offset += 10;

      int SVI_m = int(BytesLib.bytesToUint(data[offset:offset + 10]));
      offset += 10;

      uint SVI_sigma = uint(BytesLib.bytesToUint(data[offset:offset + 10]));
      offset += 10;

      // extra 2 bytes for forward price
      uint SVI_fwd = uint(BytesLib.bytesToUint(data[offset:offset + 12]));
      offset += 12;

      uint64 SVI_refTau = uint64(BytesLib.bytesToUint(data[offset:offset + 10]));
      offset += 10;

      // confidence is between [0, 1e18]
      uint64 confidence = uint64(BytesLib.bytesToUint(data[offset:offset + 8]));

      return abi.encode(
        expiry,
        SVI_a,
        SVI_b,
        SVI_rho,
        SVI_m,
        SVI_sigma,
        SVI_fwd,
        SVI_refTau,
        confidence
      );
    }
}


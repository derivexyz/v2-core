// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// inherited
import "openzeppelin/access/Ownable2Step.sol";

// interfaces
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

interface IStrandsSFP {
  function getSharePrice() external view returns (uint);
}

/**
 * @title StrandsSFPSpotFeed
 * @author Lyra
 * @notice Spot feed for StrandsSFP using StrandsSFP.getSharePrice
 */
contract SFPSpotFeed is ISpotFeed, Ownable2Step {
  IStrandsSFP public immutable strandsSFP;

  uint public minPrice = 0.98e18;
  uint public maxPrice = 1.2e18;

  constructor(IStrandsSFP _strandsSFP) Ownable(msg.sender) {
    strandsSFP = _strandsSFP;
  }

  /// @notice Set the price bounds
  function setPriceBounds(uint _minPrice, uint _maxPrice) external onlyOwner {
    if (_minPrice > _maxPrice) {
      revert LSSSF_InvalidPriceBounds();
    }
    minPrice = _minPrice;
    maxPrice = _maxPrice;
  }

  /// @notice Gets the price of the SFP tokens
  function getSpot() public view returns (uint, uint) {
    uint sharePrice = strandsSFP.getSharePrice();
    if (sharePrice < minPrice || sharePrice > maxPrice) {
      revert LSSSF_InvalidPrice();
    }

    return (sharePrice, 1e18);
  }

  error LSSSF_InvalidPrice();
  error LSSSF_InvalidPriceBounds();
}

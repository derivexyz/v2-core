pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/risk-managers/SpotJumpOracle.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";

contract UNIT_TestSpotJumpOracle is Test {
  Accounts account;
  ChainlinkSpotFeeds spotFeeds; 
  MockV3Aggregator aggregator;
  SpotJumpOracle oracle;
  
  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
  }

  ///////////
  // Admin //
  ///////////

  function testCreateContractAndSetEmptyJumps() public {
    SpotJumpOracle.JumpParams memory params = _defaultJumpParams(1000e18);
    uint32[16] memory initialJumps;
    oracle = new SpotJumpOracle(address(spotFeeds), 1, params, initialJumps);
  }

  function testRevertIfMaxJumpTooHigh() public {
    SpotJumpOracle.JumpParams memory params = _defaultJumpParams(1000e18);
    uint32[16] memory initialJumps;

    // make large so that width * 16 > type(uint32).max
    params.width = 300_000_000;
    vm.expectRevert(SpotJumpOracle.SJO_MaxJumpExceedsLimit.selector);
    oracle = new SpotJumpOracle(address(spotFeeds), 1, params, initialJumps);
  }

  ///////////////
  // Jump Math //
  ///////////////

  // todo [Josh]: finish testing

  /////////////
  // Helpers //
  /////////////

  function _defaultJumpParams(uint referencePrice) internal view returns (SpotJumpOracle.JumpParams memory params) {
    params = SpotJumpOracle.JumpParams({
      start: 100,
      width: 50,
      duration: uint32(10 days),
      secToJumpStale: uint32(30 minutes),
      jumpUpdatedAt: uint32(block.timestamp),
      referenceUpdatedAt: uint32(block.timestamp),
      secToReferenceStale: uint32(2 hours),
      referencePrice: referencePrice
    });
  }
}
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

contract SpotJumpOracleTester is SpotJumpOracle {
  constructor(address _spotFeeds, uint _feedId, JumpParams memory _params, uint32[16] memory _initialJumps)
    SpotJumpOracle(_spotFeeds, _feedId, _params, _initialJumps)
  {}

  function calcSpotJump(uint liveSpot, uint referencePrice) external pure returns (uint32 jump) {
    return _calcSpotJump(liveSpot, referencePrice);
  }

  function maybeStoreJump(uint32 start, uint32 width, uint32 jump, uint32 timestamp) external {
    return _maybeStoreJump(start, width, jump, timestamp);
  }

  function overrideJumps(uint32[16] memory _initialJumps) external {
    jumps = _initialJumps;
  }
}

contract UNIT_TestSpotJumpOracle is Test {
  Accounts account;
  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;
  SpotJumpOracleTester oracle;

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
    oracle = new SpotJumpOracleTester(address(spotFeeds), 1, params, initialJumps);
  }

  function testRevertIfMaxJumpTooHigh() public {
    SpotJumpOracle.JumpParams memory params = _defaultJumpParams(1000e18);
    uint32[16] memory initialJumps;

    // make large so that width * 16 > type(uint32).max
    params.width = 300_000_000;
    vm.expectRevert(SpotJumpOracle.SJO_MaxJumpExceedsLimit.selector);
    oracle = new SpotJumpOracleTester(address(spotFeeds), 1, params, initialJumps);
  }

  ///////////////
  // Jump Math //
  ///////////////

  function testCalcSpotJump() public {
    oracle = _setupDefaultOracle();

    // 0bp change
    uint32 jump = oracle.calcSpotJump(100, 100);
    assertEq(jump, 0);

    // up 10bp
    jump = oracle.calcSpotJump(1001e18, 1000e18);
    assertEq(jump, 10);

    // down 10bp
    jump = oracle.calcSpotJump(1000e18, 1001e18);
    assertEq(jump, 10);

    // up 500bp
    jump = oracle.calcSpotJump(15750e16, 15000e16);
    assertEq(jump, 500);

    // up 10x
    jump = oracle.calcSpotJump(1000e18, 100e18);
    assertEq(jump, 90_000);

    // down 10x
    jump = oracle.calcSpotJump(100e18, 1000e18);
    assertEq(jump, 90_000);

    // 10,000x increase floored
    jump = oracle.calcSpotJump(100_000_000_000e18, 1e18);
    assertEq(jump, type(uint32).max);
  }

  function testStoreJumpTimestamp() public {
    oracle = _setupDefaultOracle();

    uint32 timestamp = uint32(block.timestamp);
    oracle.maybeStoreJump(100, 200, 202, timestamp);
    assertEq(oracle.jumps(0), timestamp);
    assertEq(oracle.jumps(1), 0);
    assertEq(oracle.jumps(15), 0);
  }

  function testDoesNotStoreLowJump() public {
    oracle = _setupDefaultOracle();

    oracle.maybeStoreJump(100, 200, 99, uint32(block.timestamp));
    for (uint i; i < 16; i++) {
      assertEq(oracle.jumps(i), 0);
    }

    // stores if on the limit
    oracle.maybeStoreJump(50, 200, 50, 9876);
    assertEq(oracle.jumps(0), 9876);
  }

  function testRoundsDownJumpWhenStoring() public {
    oracle = _setupDefaultOracle();

    oracle.maybeStoreJump(50, 200, 251, 1234);
    assertEq(oracle.jumps(1), 1234);

    oracle.maybeStoreJump(50, 200, 51, 5678);
    assertEq(oracle.jumps(0), 5678);

    // overwrites existing entries
    oracle.maybeStoreJump(50, 200, 249, 9876);
    assertEq(oracle.jumps(0), 9876);

    // right on the limit of the last bin
    oracle.maybeStoreJump(50, 100, 1650, 1357);
    assertEq(oracle.jumps(15), 1357);

    oracle.maybeStoreJump(50, 100, 1550, 11234);
    assertEq(oracle.jumps(15), 11234);

    oracle.maybeStoreJump(50, 100, 100_000, 135);
    assertEq(oracle.jumps(15), 135);

    oracle.maybeStoreJump(50, 100, 467, 135);
    assertEq(oracle.jumps(4), 135);
  }

  //////////////////////////
  // Updating Jump Oracle //
  //////////////////////////

  function testUpdateJump() public {
    oracle = _setupDefaultOracle();

    // time 1
    uint32 time_1 = uint32(block.timestamp);
    int spotPrice = 1111e18;
    aggregator.updateRoundData(1, spotPrice, time_1, time_1, 1);

    oracle.updateJumps();
    assertEq(oracle.jumps(5), time_1);

    // time 2
    skip(10 minutes);
    uint32 time_2 = uint32(block.timestamp);
    spotPrice = 1120e18;
    aggregator.updateRoundData(2, spotPrice, time_2, time_2, 2);

    oracle.updateJumps();
    assertEq(oracle.jumps(5), time_2);
  }

  function testUpdateReferenceJump() public {
    oracle = _setupDefaultOracle();

    // time 1
    uint32 time_1 = uint32(block.timestamp);
    int spotPrice = 1111e18;
    aggregator.updateRoundData(1, spotPrice, time_1, time_1, 1);

    oracle.updateJumps();
    assertEq(oracle.jumps(5), time_1);

    // time 2
    skip(3 hours);
    uint32 time_2 = uint32(block.timestamp);
    spotPrice = 3000e18;
    aggregator.updateRoundData(2, spotPrice, time_2, time_2, 2);

    // still records jump based on last spot price
    oracle.updateJumps();
    assertEq(oracle.jumps(15), time_2);

    // updates reference
    (,, uint32 referenceUpdatedAt,, uint referencePrice) = oracle.params();
    assertEq(referenceUpdatedAt, time_2);
    assertEq(referencePrice, 3000e18);

    // uses new reference
    skip(1 hours);
    uint32 time_3 = uint32(block.timestamp);
    spotPrice = 3040e18;
    aggregator.updateRoundData(3, spotPrice, time_3, time_3, 3);

    oracle.updateJumps();
    assertEq(oracle.jumps(0), time_3);
  }

  //////////////////////
  // Getting Max Jump //
  //////////////////////

  function testGetMaxJump() public {
    skip(31 days);
    oracle = _setupDefaultOracle();
    uint32[16] memory initialJumps = _getDefaultJumps();
    oracle.overrideJumps(initialJumps);

    // finds 7th bucket
    aggregator.updateRoundData(2, 1000e18, block.timestamp, block.timestamp, 2);
    uint32 maxJump = oracle.updateAndGetMaxJump(uint32(10 days));
    assertEq(maxJump, 1700);

    // override 7th bucket, should find 5th bucket
    initialJumps[7] = uint32(block.timestamp) - 11 days;
    oracle.overrideJumps(initialJumps);

    maxJump = oracle.updateAndGetMaxJump(uint32(10 days));
    assertEq(maxJump, 1300);
  }

  function testGetsMaxJumpForDifferentSecToStale() public {
    skip(31 days);
    oracle = _setupDefaultOracle();
    uint32[16] memory initialJumps = _getDefaultJumps();
    oracle.overrideJumps(initialJumps);

    // ignores all entries if secToJumpStale = 30 minutes
    uint32 maxJump = oracle.updateAndGetMaxJump(uint32(30 minutes));
    assertEq(maxJump, 0);

    // finds the first jump that's < 2hours old
    maxJump = oracle.updateAndGetMaxJump(uint32(2 hours));
    assertEq(maxJump, 900);
  }

  /////////////
  // Helpers //
  /////////////

  function _setupDefaultOracle() internal returns (SpotJumpOracleTester) {
    SpotJumpOracle.JumpParams memory params = _defaultJumpParams(1000e18);
    uint32[16] memory initialJumps;
    return new SpotJumpOracleTester(address(spotFeeds), 1, params, initialJumps);
  }

  function _defaultJumpParams(uint referencePrice) internal view returns (SpotJumpOracle.JumpParams memory params) {
    params = SpotJumpOracle.JumpParams({
      start: 100,
      width: 200,
      referenceUpdatedAt: uint32(block.timestamp),
      secToReferenceStale: uint32(2 hours),
      referencePrice: uint128(referencePrice)
    });
  }

  function _getDefaultJumps() internal view returns (uint32[16] memory jumps) {
    // make sure to jump atleast 30 days ahead.
    uint32 currentTime = uint32(block.timestamp);
    jumps[0] = 0;
    jumps[1] = currentTime - 30 days;
    jumps[2] = 0;
    jumps[3] = currentTime - 1 hours;
    jumps[4] = 0;
    jumps[5] = currentTime - 3 hours;
    jumps[6] = 0;
    jumps[7] = currentTime - 5 hours;
    jumps[8] = 0;
    jumps[9] = currentTime - 11 days;
  }
}

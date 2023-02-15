pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeed.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/risk-managers/SpotJumpOracle.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

contract PCRMSpotJumpOracleGas is Script {
  Accounts account;
  ChainlinkSpotFeed spotFeeds;
  MockV3Aggregator aggregator;
  SpotJumpOracle oracle;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function run() external {
    vm.startBroadcast(alice);

    _setup();

    // gas tests
    _gasSingleUpdate();

    _updateAllJumps();

    _gasGetFirstJump();

    _gasGetLastJump();

    vm.stopBroadcast();
  }

  function _gasSingleUpdate() public {
    aggregator.updateRoundData(1, 1200e18, block.timestamp, block.timestamp, 1);

    // estimate tx cost of updating one field in jump buckets
    uint initGas = gasleft();

    oracle.updateJumps();

    console.log("gas:SingleUpdate:", initGas - gasleft());
  }

  function _gasGetFirstJump() public {
    // estimate tx cost when max jump is the first value to be read from the array
    uint initGas = gasleft();

    oracle.updateAndGetMaxJump(uint32(10 days));

    console.log("gas:updateAndGetFirstJump:", initGas - gasleft());
  }

  function _gasGetLastJump() public {
    // estimate tx cost when max jump is the last value to be read from the array

    // make jumps stale
    vm.warp(block.timestamp + 11 days);

    // record new jump as the very last bucket to be read
    aggregator.updateRoundData(10, 1030e18, block.timestamp, block.timestamp, 10);
    oracle.updateJumps();

    uint initGas = gasleft();

    oracle.updateAndGetMaxJump(uint32(10 days));

    console.log("gas:updateAndGetLastJump:", initGas - gasleft());
  }

  function _updateAllJumps() public {
    aggregator.updateRoundData(1, 1200e18, block.timestamp, block.timestamp, 1);
    oracle.updateJumps();

    aggregator.updateRoundData(2, 700e18, block.timestamp, block.timestamp, 2);
    oracle.updateJumps();

    aggregator.updateRoundData(3, 500e18, block.timestamp, block.timestamp, 3);
    oracle.updateJumps();

    aggregator.updateRoundData(4, 2400e18, block.timestamp, block.timestamp, 4);
    oracle.updateJumps();

    aggregator.updateRoundData(5, 1010e18, block.timestamp, block.timestamp, 4);
    oracle.updateJumps();

    aggregator.updateRoundData(6, 1030e18, block.timestamp, block.timestamp, 6);
    oracle.updateJumps();

    aggregator.updateRoundData(7, 1005e18, block.timestamp, block.timestamp, 7);
    oracle.updateJumps();
  }

  function _setup() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeed(aggregator, 1 hours);

    SpotJumpOracle.JumpParams memory params = SpotJumpOracle.JumpParams({
      start: 100,
      width: 200,
      referenceUpdatedAt: uint32(block.timestamp),
      secToReferenceStale: uint32(2 hours),
      referencePrice: uint128(1000e18)
    });

    uint32[16] memory initialJumps;
    oracle = new SpotJumpOracle(address(spotFeeds), params, initialJumps);
  }

  function test() public {}
}

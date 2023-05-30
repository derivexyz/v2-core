pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

import "test/shared/utils/JsonMechIO.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_TestCases is TestStandardManagerBase {
  using stdJson for string;

  JsonMechIO immutable jsonParser;

  constructor() {
    jsonParser = new JsonMechIO();
  }

  function testCase1() public {
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/StandardManager/test-cases.json");

    _setFeedsFromScenario(json, ".Test1");
  }

  function _setFeedsFromScenario(string memory json, string memory testId) internal {
    // set spot feed
    uint ethSpotPrice = json.readUint(string.concat(testId, ".Scenario.ETHSpotPrice"));
    uint btcSpotPrice = json.readUint(string.concat(testId, ".Scenario.BTCSpotPrice"));

    // get spot and perp confidence
    // todo: use 1e18 based number!
    uint[][] memory confs = readUintArray2D(json, string.concat(testId, ".Scenario.SpotPerpConfidences"));

    ethFeed.setSpot(ethSpotPrice, confs[0][0] * 1e18);
    btcFeed.setSpot(btcSpotPrice, confs[1][0] * 1e18);

    // set forward and vol feeds
    uint[] memory feedExpiries = json.readUintArray(string.concat(testId, ".Scenario.FeedExpiries"));
    uint[] memory forwardPrices = json.readUintArray(string.concat(testId, ".Scenario.Forwards"));
    uint[] memory forwardConfs = json.readUintArray(string.concat(testId, ".Scenario.ForwardConfidences"));
    // todo: add discounts
    uint[] memory discounts = json.readUintArray(string.concat(testId, ".Scenario.Discounts"));
    uint[] memory discountConfs = json.readUintArray(string.concat(testId, ".Scenario.DiscountConfidences"));

    for (uint i = 0; i < feedExpiries.length; i++) {
      ethFeed.setForwardPrice(block.timestamp + feedExpiries[i], forwardPrices[i], forwardConfs[i]);
      // todo: set discounts?
    }

    // set perp feed
    uint[] memory perpPrices = json.readUintArray(string.concat(testId, ".Scenario.PerpPrice"));
    ethPerpFeed.setSpot(perpPrices[0], confs[0][1] * 1e18);
    btcPerpFeed.setSpot(perpPrices[1], confs[1][1] * 1e18);

    // set stable feed
    uint usdcPrice = json.readUint(string.concat(testId, ".Scenario.USDCValue"));
    stableFeed.setSpot(usdcPrice, 1e18);
  }

  // helper
  function readUintArray2D(string memory json, string memory key) internal pure returns (uint[][] memory) {
    return abi.decode(vm.parseJson(json, key), (uint[][]));
  }
}

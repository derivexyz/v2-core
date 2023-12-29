// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/periphery/OracleDataSubmitter.sol";
import "../../../src/feeds/LyraSpotFeed.sol";
import "../unit-tests/LyraFeedTestUtils.sol";
import {IBaseManager} from "../../../src/interfaces/IBaseManager.sol";

contract OracleDataSubmitterTest is LyraFeedTestUtils {
  uint pk = 0xBEEF;

  OracleDataSubmitter submitter;
  LyraSpotFeed spotFeed1;
  LyraSpotFeed spotFeed2;

  function setUp() public {
    submitter = new OracleDataSubmitter();
    spotFeed1 = new LyraSpotFeed();
    spotFeed2 = new LyraSpotFeed();

    spotFeed1.addSigner(vm.addr(pk), true);
    spotFeed2.addSigner(vm.addr(pk), true);
  }

  function testSubmitBatchData() public {
    IBaseLyraFeed.FeedData memory spotData1 = _getDefaultSpotData();
    bytes memory data1 = _signFeedData(spotFeed1, pk, spotData1);

    IBaseLyraFeed.FeedData memory spotData2 = _getDefaultSpotData();
    bytes memory data2 = _signFeedData(spotFeed2, pk, spotData2);

    IBaseManager.ManagerData[] memory managerDatas = new IBaseManager.ManagerData[](2);
    managerDatas[0] = IBaseManager.ManagerData(address(spotFeed1), data1);
    managerDatas[1] = IBaseManager.ManagerData(address(spotFeed2), data2);
    bytes memory managerData = abi.encode(managerDatas);

    submitter.acceptData(managerData);

    (uint spot1, uint confidence1) = spotFeed1.getSpot();
    (uint spot2, uint confidence2) = spotFeed2.getSpot();

    assertEq(spot1, 1000e18);
    assertEq(confidence1, 1e18);

    assertEq(spot2, 1000e18);
    assertEq(confidence2, 1e18);
  }

  function _getDefaultSpotData() internal view returns (IBaseLyraFeed.FeedData memory) {
    uint96 price = 1000e18;
    uint64 confidence = 1e18;
    bytes memory spotData = abi.encode(price, confidence);
    return IBaseLyraFeed.FeedData({
      data: spotData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }
}

pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract TestPMRM_Admin is PMRMTestBase {
  function testSetNoScenarios() public {
    ////
    // Remove all scenarios
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](0);
    pmrm.setScenarios(scenarios);
    IPMRM.Scenario[] memory res = pmrm.getScenarios();
    assertEq(res.length, 0);

    /////
    // Add scenarios
    scenarios = new IPMRM.Scenario[](3);
    scenarios[0] = IPMRM.Scenario({spotShock: 0, volShock: IPMRM.VolShockDirection.None});
    scenarios[1] = IPMRM.Scenario({spotShock: 1, volShock: IPMRM.VolShockDirection.Up});
    scenarios[2] = IPMRM.Scenario({spotShock: 2, volShock: IPMRM.VolShockDirection.Down});

    pmrm.setScenarios(scenarios);

    res = pmrm.getScenarios();
    assertEq(res.length, 3);
    assertEq(res[0].spotShock, 0);
    assertEq(uint8(res[0].volShock), uint8(IPMRM.VolShockDirection.None));
    assertEq(res[1].spotShock, 1);
    assertEq(uint8(res[1].volShock), uint8(IPMRM.VolShockDirection.Up));
    assertEq(res[2].spotShock, 2);
    assertEq(uint8(res[2].volShock), uint8(IPMRM.VolShockDirection.Down));

    ////
    // Overwrite and add more scenarios
    scenarios = new IPMRM.Scenario[](4);
    scenarios[0] = IPMRM.Scenario({spotShock: 4, volShock: IPMRM.VolShockDirection.None});
    scenarios[1] = IPMRM.Scenario({spotShock: 3, volShock: IPMRM.VolShockDirection.Up});
    scenarios[2] = IPMRM.Scenario({spotShock: 2, volShock: IPMRM.VolShockDirection.Down});
    scenarios[3] = IPMRM.Scenario({spotShock: 1, volShock: IPMRM.VolShockDirection.Up});

    pmrm.setScenarios(scenarios);

    res = pmrm.getScenarios();
    assertEq(res.length, 4);
    assertEq(res[0].spotShock, 4);
    assertEq(uint8(res[0].volShock), uint8(IPMRM.VolShockDirection.None));
    assertEq(res[1].spotShock, 3);
    assertEq(uint8(res[1].volShock), uint8(IPMRM.VolShockDirection.Up));
    assertEq(res[2].spotShock, 2);
    assertEq(uint8(res[2].volShock), uint8(IPMRM.VolShockDirection.Down));
    assertEq(res[3].spotShock, 1);
    assertEq(uint8(res[3].volShock), uint8(IPMRM.VolShockDirection.Up));

    /////
    // Remove partial scenarios
    scenarios = new IPMRM.Scenario[](2);
    scenarios[0] = IPMRM.Scenario({spotShock: 3, volShock: IPMRM.VolShockDirection.Up});
    scenarios[1] = IPMRM.Scenario({spotShock: 2, volShock: IPMRM.VolShockDirection.Down});
    pmrm.setScenarios(scenarios);

    res = pmrm.getScenarios();
    assertEq(res.length, 2);
    assertEq(res[0].spotShock, 3);
    assertEq(uint8(res[0].volShock), uint8(IPMRM.VolShockDirection.Up));
    assertEq(res[1].spotShock, 2);
    assertEq(uint8(res[1].volShock), uint8(IPMRM.VolShockDirection.Down));

    /////
    // Update equal amount of scenarios
    scenarios = new IPMRM.Scenario[](2);
    scenarios[0] = IPMRM.Scenario({spotShock: 2, volShock: IPMRM.VolShockDirection.None});
    scenarios[1] = IPMRM.Scenario({spotShock: 3, volShock: IPMRM.VolShockDirection.None});
    pmrm.setScenarios(scenarios);

    res = pmrm.getScenarios();
    assertEq(res.length, 2);
    assertEq(res[0].spotShock, 2);
    assertEq(uint8(res[0].volShock), uint8(IPMRM.VolShockDirection.None));
    assertEq(res[1].spotShock, 3);
    assertEq(uint8(res[1].volShock), uint8(IPMRM.VolShockDirection.None));
  }

  function testSetFeeds() public {
    assertEq(address(pmrm.spotFeed()), address(feed));
    pmrm.setSpotFeed(ISpotFeed(address(0)));
    assertEq(address(pmrm.spotFeed()), address(0));

    assertEq(address(pmrm.stableFeed()), address(stableFeed));
    pmrm.setStableFeed(ISpotFeed(address(0)));
    assertEq(address(pmrm.stableFeed()), address(0));

    assertEq(address(pmrm.forwardFeed()), address(feed));
    pmrm.setForwardFeed(IForwardFeed(address(0)));
    assertEq(address(pmrm.forwardFeed()), address(0));

    assertEq(address(pmrm.interestRateFeed()), address(feed));
    pmrm.setInterestRateFeed(IInterestRateFeed(address(0)));
    assertEq(address(pmrm.interestRateFeed()), address(0));

    assertEq(address(pmrm.volFeed()), address(feed));
    pmrm.setVolFeed(IVolFeed(address(0)));
    assertEq(address(pmrm.volFeed()), address(0));

    assertEq(address(pmrm.settlementFeed()), address(feed));
    pmrm.setSettlementFeed(ISettlementFeed(address(0)));
    assertEq(address(pmrm.settlementFeed()), address(0));

    assertEq(address(pmrm.optionPricing()), address(optionPricing));
    pmrm.setOptionPricing(IOptionPricing(address(0)));
    assertEq(address(pmrm.optionPricing()), address(0));
  }

  function testSetParameters() public {
    //  struct VolShockParameters {
    //    uint volRangeUp;
    //    uint volRangeDown;
    //    uint shortTermPower;
    //    uint longTermPower;
    //    uint dteFloor;
    //  }
    //
    //  struct StaticDiscountParameters {
    //    uint rateMultiplicativeFactor;
    //    uint rateAdditiveFactor;
    //    uint baseStaticDiscount;
    //  }
    //
    //  struct ForwardContingencyParameters {
    //    uint spotShock1;
    //    uint spotShock2;
    //    uint additiveFactor;
    //    uint multiplicativeFactor;
    //  }
    //
    //  struct OtherContingencyParameters {
    //    uint pegLossThreshold;
    //    uint pegLossFactor;
    //    uint confidenceThreshold;
    //    uint confidenceFactor;
    //    uint basePercent;
    //    uint perpPercent;
    //    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio
    //    uint optionPercent;
    //  }
    //
    //  IPMRMLib.ForwardContingencyParameters fwdContParams;
    //  IPMRMLib.OtherContingencyParameters otherContParams;
    //  IPMRMLib.StaticDiscountParameters staticDiscountParams;
    //  IPMRMLib.VolShockParameters volShockParams;
    //
    IPMRMLib.ForwardContingencyParameters memory fwdContParams = IPMRMLib.ForwardContingencyParameters({
      spotShock1: 1,
      spotShock2: 1e18 + 1,
      additiveFactor: 3,
      multiplicativeFactor: 4
    });
    pmrm.setForwardContingencyParams(fwdContParams);
    IPMRMLib.ForwardContingencyParameters memory resFwdContParams = pmrm.getForwardContingencyParams();
    assertEq(resFwdContParams.spotShock1, 1);
    assertEq(resFwdContParams.spotShock2, 1e18 + 1);
    assertEq(resFwdContParams.additiveFactor, 3);
    assertEq(resFwdContParams.multiplicativeFactor, 4);

    IPMRMLib.OtherContingencyParameters memory otherContParams = IPMRMLib.OtherContingencyParameters({
      pegLossThreshold: 1,
      pegLossFactor: 2,
      confidenceThreshold: 3,
      confidenceFactor: 4,
      basePercent: 5,
      perpPercent: 6,
      optionPercent: 7
    });
    pmrm.setOtherContingencyParams(otherContParams);
    IPMRMLib.OtherContingencyParameters memory resOtherContParams = pmrm.getOtherContingencyParams();
    assertEq(resOtherContParams.pegLossThreshold, 1);
    assertEq(resOtherContParams.pegLossFactor, 2);
    assertEq(resOtherContParams.confidenceThreshold, 3);
    assertEq(resOtherContParams.confidenceFactor, 4);
    assertEq(resOtherContParams.basePercent, 5);
    assertEq(resOtherContParams.perpPercent, 6);
    assertEq(resOtherContParams.optionPercent, 7);

    IPMRMLib.StaticDiscountParameters memory staticDiscountParams =
      IPMRMLib.StaticDiscountParameters({rateMultiplicativeFactor: 1, rateAdditiveFactor: 2, baseStaticDiscount: 3});
    pmrm.setStaticDiscountParams(staticDiscountParams);
    IPMRMLib.StaticDiscountParameters memory resStaticDiscountParams = pmrm.getStaticDiscountParams();
    assertEq(resStaticDiscountParams.rateMultiplicativeFactor, 1);
    assertEq(resStaticDiscountParams.rateAdditiveFactor, 2);
    assertEq(resStaticDiscountParams.baseStaticDiscount, 3);

    IPMRMLib.VolShockParameters memory volShockParams =
      IPMRMLib.VolShockParameters({volRangeUp: 1, volRangeDown: 2, shortTermPower: 3, longTermPower: 4, dteFloor: 5});
    pmrm.setVolShockParams(volShockParams);
    IPMRMLib.VolShockParameters memory resVolShockParams = pmrm.getVolShockParams();
    assertEq(resVolShockParams.volRangeUp, 1);
    assertEq(resVolShockParams.volRangeDown, 2);
    assertEq(resVolShockParams.shortTermPower, 3);
    assertEq(resVolShockParams.longTermPower, 4);
    assertEq(resVolShockParams.dteFloor, 5);
  }
}

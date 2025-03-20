// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../risk-managers/unit-tests/PMRM_2_1/utils/PMRM_2_1TestBase.sol";
import "../../../../src/interfaces/IBaseManager.sol";

contract TestPMRM_2_1_Admin is PMRM_2_1TestBase {
  function testCannotSetNoScenarios() public {
    // Remove all scenarios
    IPMRM_2_1.Scenario[] memory scenarios = new IPMRM_2_1.Scenario[](0);
    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidScenarios.selector);
    pmrm_2_1.setScenarios(scenarios);

    scenarios = new IPMRM_2_1.Scenario[](41);
    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidScenarios.selector);
    pmrm_2_1.setScenarios(scenarios);
  }

  function testAddScenarios() public {
    // Add scenarios
    IPMRM_2_1.Scenario[] memory scenarios = new IPMRM_2_1.Scenario[](3);
    scenarios[0] = IPMRM_2_1.Scenario({spotShock: 0, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
    scenarios[1] = IPMRM_2_1.Scenario({spotShock: 1, volShock: IPMRM_2_1.VolShockDirection.Up, dampeningFactor: 1e18});
    scenarios[2] = IPMRM_2_1.Scenario({spotShock: 2, volShock: IPMRM_2_1.VolShockDirection.Down, dampeningFactor: 1e18});

    pmrm_2_1.setScenarios(scenarios);

    IPMRM_2_1.Scenario[] memory res = pmrm_2_1.getScenarios();
    assertEq(res.length, 3);
    assertEq(res[0].spotShock, 0);
    assertEq(uint8(res[0].volShock), uint8(IPMRM_2_1.VolShockDirection.None));
    assertEq(res[1].spotShock, 1);
    assertEq(uint8(res[1].volShock), uint8(IPMRM_2_1.VolShockDirection.Up));
    assertEq(res[2].spotShock, 2);
    assertEq(uint8(res[2].volShock), uint8(IPMRM_2_1.VolShockDirection.Down));

    ////
    // Overwrite and add more scenarios
    scenarios = new IPMRM_2_1.Scenario[](4);
    scenarios[0] = IPMRM_2_1.Scenario({spotShock: 4, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
    scenarios[1] = IPMRM_2_1.Scenario({spotShock: 3, volShock: IPMRM_2_1.VolShockDirection.Up, dampeningFactor: 1e18});
    scenarios[2] = IPMRM_2_1.Scenario({spotShock: 2, volShock: IPMRM_2_1.VolShockDirection.Down, dampeningFactor: 1e18});
    scenarios[3] = IPMRM_2_1.Scenario({spotShock: 1, volShock: IPMRM_2_1.VolShockDirection.Up, dampeningFactor: 1e18});

    pmrm_2_1.setScenarios(scenarios);

    res = pmrm_2_1.getScenarios();
    assertEq(res.length, 4);
    assertEq(res[0].spotShock, 4);
    assertEq(uint8(res[0].volShock), uint8(IPMRM_2_1.VolShockDirection.None));
    assertEq(res[1].spotShock, 3);
    assertEq(uint8(res[1].volShock), uint8(IPMRM_2_1.VolShockDirection.Up));
    assertEq(res[2].spotShock, 2);
    assertEq(uint8(res[2].volShock), uint8(IPMRM_2_1.VolShockDirection.Down));
    assertEq(res[3].spotShock, 1);
    assertEq(uint8(res[3].volShock), uint8(IPMRM_2_1.VolShockDirection.Up));

    /////
    // Remove partial scenarios
    scenarios = new IPMRM_2_1.Scenario[](2);
    scenarios[0] = IPMRM_2_1.Scenario({spotShock: 3, volShock: IPMRM_2_1.VolShockDirection.Up, dampeningFactor: 1e18});
    scenarios[1] = IPMRM_2_1.Scenario({spotShock: 2, volShock: IPMRM_2_1.VolShockDirection.Down, dampeningFactor: 1e18});
    pmrm_2_1.setScenarios(scenarios);

    res = pmrm_2_1.getScenarios();
    assertEq(res.length, 2);
    assertEq(res[0].spotShock, 3);
    assertEq(uint8(res[0].volShock), uint8(IPMRM_2_1.VolShockDirection.Up));
    assertEq(res[1].spotShock, 2);
    assertEq(uint8(res[1].volShock), uint8(IPMRM_2_1.VolShockDirection.Down));

    /////
    // Update equal amount of scenarios
    scenarios = new IPMRM_2_1.Scenario[](2);
    scenarios[0] = IPMRM_2_1.Scenario({spotShock: 2, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
    scenarios[1] = IPMRM_2_1.Scenario({spotShock: 3, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
    pmrm_2_1.setScenarios(scenarios);

    res = pmrm_2_1.getScenarios();
    assertEq(res.length, 2);
    assertEq(res[0].spotShock, 2);
    assertEq(uint8(res[0].volShock), uint8(IPMRM_2_1.VolShockDirection.None));
    assertEq(res[1].spotShock, 3);
    assertEq(uint8(res[1].volShock), uint8(IPMRM_2_1.VolShockDirection.None));
  }

  function testSetFeeds() public {
    assertEq(address(pmrm_2_1.spotFeed()), address(feed));
    pmrm_2_1.setSpotFeed(ISpotFeed(address(0)));
    assertEq(address(pmrm_2_1.spotFeed()), address(0));

    assertEq(address(pmrm_2_1.stableFeed()), address(stableFeed));
    pmrm_2_1.setStableFeed(ISpotFeed(address(0)));
    assertEq(address(pmrm_2_1.stableFeed()), address(0));

    assertEq(address(pmrm_2_1.forwardFeed()), address(feed));
    pmrm_2_1.setForwardFeed(IForwardFeed(address(0)));
    assertEq(address(pmrm_2_1.forwardFeed()), address(0));

    assertEq(address(pmrm_2_1.interestRateFeed()), address(feed));
    pmrm_2_1.setInterestRateFeed(IInterestRateFeed(address(0)));
    assertEq(address(pmrm_2_1.interestRateFeed()), address(0));

    assertEq(address(pmrm_2_1.volFeed()), address(feed));
    pmrm_2_1.setVolFeed(IVolFeed(address(0)));
    assertEq(address(pmrm_2_1.volFeed()), address(0));
  }

  function testSetPMRM_2_1ParametersBasisContingency() public {
    IPMRMLib_2_1.BasisContingencyParameters memory basisContParams = IPMRMLib_2_1.BasisContingencyParameters({
      scenarioSpotUp: 1e18 + 1,
      scenarioSpotDown: 2,
      basisContAddFactor: 3,
      basisContMultFactor: 4
    });
    lib.setBasisContingencyParams(basisContParams);
    IPMRMLib_2_1.BasisContingencyParameters memory resFwdContParams = lib.getBasisContingencyParams();
    assertEq(resFwdContParams.scenarioSpotUp, 1e18 + 1);
    assertEq(resFwdContParams.scenarioSpotDown, 2);
    assertEq(resFwdContParams.basisContAddFactor, 3);
    assertEq(resFwdContParams.basisContMultFactor, 4);

    basisContParams.scenarioSpotUp = 1e18;

    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.scenarioSpotUp = 1e18 + 1;

    basisContParams.scenarioSpotUp = 3e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.scenarioSpotUp = 1e18 + 1;

    basisContParams.scenarioSpotDown = 1e18;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.scenarioSpotDown = 2;

    basisContParams.basisContMultFactor = 5e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.basisContMultFactor = 4;

    basisContParams.basisContAddFactor = 5e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.basisContAddFactor = 4;
  }

  function testSetPMRM_2_1ParametersOtherContingency() public {
    IPMRMLib_2_1.OtherContingencyParameters memory otherContParams = IPMRMLib_2_1.OtherContingencyParameters({
      pegLossThreshold: 1,
      pegLossFactor: 2,
      confThreshold: 3,
      confMargin: 4,
      IMPerpPercent: 5,
      MMPerpPercent: 6,
      IMOptionPercent: 7,
      MMOptionPercent: 8
    });
    lib.setOtherContingencyParams(otherContParams);
    IPMRMLib_2_1.OtherContingencyParameters memory resOtherContParams = lib.getOtherContingencyParams();
    assertEq(resOtherContParams.pegLossThreshold, 1);
    assertEq(resOtherContParams.pegLossFactor, 2);
    assertEq(resOtherContParams.confThreshold, 3);
    assertEq(resOtherContParams.confMargin, 4);
    assertEq(resOtherContParams.IMPerpPercent, 5);
    assertEq(resOtherContParams.MMPerpPercent, 6);
    assertEq(resOtherContParams.IMOptionPercent, 7);
    assertEq(resOtherContParams.MMOptionPercent, 8);

    otherContParams.pegLossThreshold = 1e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.pegLossThreshold = 1;

    otherContParams.pegLossFactor = 20e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.pegLossFactor = 2;

    otherContParams.confThreshold = 1e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.confThreshold = 3;

    otherContParams.confMargin = 1.5e18 + 1;
    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.confMargin = 4;
    // TODO
    //    otherContParams.perpPercent = 1e18 + 1;
    //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidOtherContingencyParameters.selector);
    //    lib.setOtherContingencyParams(otherContParams);
    //    otherContParams.perpPercent = 6;
    //
    //    otherContParams.optionPercent = 1e18 + 1;
    //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidOtherContingencyParameters.selector);
    //    lib.setOtherContingencyParams(otherContParams);
    //    otherContParams.optionPercent = 7;
  }
  //
  //  function testSetPMRM_2_1ParametersMargin() public {
  //    // TODO
  //    IPMRMLib_2_1.MarginParameters memory marginParams = IPMRMLib_2_1.MarginParameters({
  //      imFactor: 1e18,
  //      rateMultScale: 1,
  //      rateAddScale: 2,
  //      baseStaticDiscount: 3
  //    });
  //    lib.setMarginParams(marginParams);
  //    IPMRMLib_2_1.MarginParameters memory resStaticDiscountParams = lib.getStaticDiscountParams();
  //    assertEq(resStaticDiscountParams.rateMultScale, 1);
  //    assertEq(resStaticDiscountParams.rateAddScale, 2);
  //    assertEq(resStaticDiscountParams.baseStaticDiscount, 3);
  //
  //    marginParams.imFactor = 1e18 - 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidMarginParameters.selector);
  //    lib.setMarginParams(marginParams);
  //    marginParams.imFactor = 1e18;
  //
  //    marginParams.imFactor = 4e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidMarginParameters.selector);
  //    lib.setMarginParams(marginParams);
  //    marginParams.imFactor = 1e18;
  //
  //    marginParams.rateMultScale = 5e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidMarginParameters.selector);
  //    lib.setMarginParams(marginParams);
  //    marginParams.rateMultScale = 1;
  //
  //    marginParams.rateAddScale = 5e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidMarginParameters.selector);
  //    lib.setMarginParams(marginParams);
  //    marginParams.rateAddScale = 2;
  //
  //    marginParams.baseStaticDiscount = 1e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidMarginParameters.selector);
  //    lib.setMarginParams(marginParams);
  //    marginParams.baseStaticDiscount = 3;
  //  }
  //
  //  function testSetPMRM_2_1ParametersVolShock() public {
  // TODO
  //    IPMRMLib_2_1.VolShockParameters memory volShockParams =
  //      IPMRMLib_2_1.VolShockParameters({volRangeUp: 1, volRangeDown: 2, shortTermPower: 3, longTermPower: 4, dteFloor: 864});
  //    lib.setVolShockParams(volShockParams);
  //    IPMRMLib_2_1.VolShockParameters memory resVolShockParams = lib.getVolShockParams();
  //    assertEq(resVolShockParams.volRangeUp, 1);
  //    assertEq(resVolShockParams.volRangeDown, 2);
  //    assertEq(resVolShockParams.shortTermPower, 3);
  //    assertEq(resVolShockParams.longTermPower, 4);
  //    assertEq(resVolShockParams.dteFloor, 864);
  //
  //    volShockParams.volRangeUp = 2e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidVolShockParameters.selector);
  //    lib.setVolShockParams(volShockParams);
  //    volShockParams.volRangeUp = 1;
  //
  //    volShockParams.volRangeDown = 2e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidVolShockParameters.selector);
  //    lib.setVolShockParams(volShockParams);
  //    volShockParams.volRangeDown = 2;
  //
  //    volShockParams.shortTermPower = 2e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidVolShockParameters.selector);
  //    lib.setVolShockParams(volShockParams);
  //    volShockParams.shortTermPower = 3;
  //
  //    volShockParams.longTermPower = 2e18 + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidVolShockParameters.selector);
  //    lib.setVolShockParams(volShockParams);
  //    volShockParams.longTermPower = 4;
  //
  //    volShockParams.dteFloor = 100 days + 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidVolShockParameters.selector);
  //    lib.setVolShockParams(volShockParams);
  //    volShockParams.dteFloor = 864;
  //
  //    volShockParams.dteFloor = 0.01 days - 1;
  //    vm.expectRevert(IPMRMLib_2_1.PMRM_2_1L_InvalidVolShockParameters.selector);
  //    lib.setVolShockParams(volShockParams);
  //    volShockParams.dteFloor = 864;
  //  }

  function testCannotSetInvalidMaxExpiries() public {
    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidMaxExpiries.selector);
    pmrm_2_1.setMaxExpiries(11);

    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidMaxExpiries.selector);
    pmrm_2_1.setMaxExpiries(31);

    pmrm_2_1.setMaxExpiries(15);
    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidMaxExpiries.selector);
    pmrm_2_1.setMaxExpiries(15);
  }

  function testCanSetMaxExpiries() public {
    pmrm_2_1.setMaxExpiries(12);

    assertEq(pmrm_2_1.maxExpiries(), 12);
  }

  function testCannotSetInvalidMaxSize() public {
    vm.expectRevert(IBaseManager.BM_InvalidMaxAccountSize.selector);
    pmrm_2_1.setMaxAccountSize(1);

    vm.expectRevert(IBaseManager.BM_InvalidMaxAccountSize.selector);
    pmrm_2_1.setMaxAccountSize(1000);
  }
}

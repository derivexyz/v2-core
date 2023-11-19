// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";
import "../../../../src/interfaces/IBaseManager.sol";

contract TestPMRM_Admin is PMRMTestBase {
  function testCannotSetNoScenarios() public {
    // Remove all scenarios
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](0);
    vm.expectRevert(IPMRM.PMRM_InvalidScenarios.selector);
    pmrm.setScenarios(scenarios);

    scenarios = new IPMRM.Scenario[](41);
    vm.expectRevert(IPMRM.PMRM_InvalidScenarios.selector);
    pmrm.setScenarios(scenarios);
  }

  function testAddScenarios() public {
    // Add scenarios
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](3);
    scenarios[0] = IPMRM.Scenario({spotShock: 0, volShock: IPMRM.VolShockDirection.None});
    scenarios[1] = IPMRM.Scenario({spotShock: 1, volShock: IPMRM.VolShockDirection.Up});
    scenarios[2] = IPMRM.Scenario({spotShock: 2, volShock: IPMRM.VolShockDirection.Down});

    pmrm.setScenarios(scenarios);

    IPMRM.Scenario[] memory res = pmrm.getScenarios();
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
  }

  function testSetPMRMParametersBasisContingency() public {
    IPMRMLib.BasisContingencyParameters memory basisContParams = IPMRMLib.BasisContingencyParameters({
      scenarioSpotUp: 1e18 + 1,
      scenarioSpotDown: 2,
      basisContAddFactor: 3,
      basisContMultFactor: 4
    });
    lib.setBasisContingencyParams(basisContParams);
    IPMRMLib.BasisContingencyParameters memory resFwdContParams = lib.getBasisContingencyParams();
    assertEq(resFwdContParams.scenarioSpotUp, 1e18 + 1);
    assertEq(resFwdContParams.scenarioSpotDown, 2);
    assertEq(resFwdContParams.basisContAddFactor, 3);
    assertEq(resFwdContParams.basisContMultFactor, 4);

    basisContParams.scenarioSpotUp = 1e18;

    vm.expectRevert(IPMRMLib.PMRML_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.scenarioSpotUp = 1e18 + 1;

    basisContParams.scenarioSpotUp = 3e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.scenarioSpotUp = 1e18 + 1;

    basisContParams.scenarioSpotDown = 1e18;
    vm.expectRevert(IPMRMLib.PMRML_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.scenarioSpotDown = 2;

    basisContParams.basisContMultFactor = 5e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.basisContMultFactor = 4;

    basisContParams.basisContAddFactor = 5e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidBasisContingencyParameters.selector);
    lib.setBasisContingencyParams(basisContParams);
    basisContParams.basisContAddFactor = 4;
  }

  function testSetPMRMParametersOtherContingency() public {
    IPMRMLib.OtherContingencyParameters memory otherContParams = IPMRMLib.OtherContingencyParameters({
      pegLossThreshold: 1,
      pegLossFactor: 2,
      confThreshold: 3,
      confMargin: 4,
      basePercent: 5,
      perpPercent: 6,
      optionPercent: 7
    });
    lib.setOtherContingencyParams(otherContParams);
    IPMRMLib.OtherContingencyParameters memory resOtherContParams = lib.getOtherContingencyParams();
    assertEq(resOtherContParams.pegLossThreshold, 1);
    assertEq(resOtherContParams.pegLossFactor, 2);
    assertEq(resOtherContParams.confThreshold, 3);
    assertEq(resOtherContParams.confMargin, 4);
    assertEq(resOtherContParams.basePercent, 5);
    assertEq(resOtherContParams.perpPercent, 6);
    assertEq(resOtherContParams.optionPercent, 7);

    otherContParams.pegLossThreshold = 1e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.pegLossThreshold = 1;

    otherContParams.pegLossFactor = 20e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.pegLossFactor = 2;

    otherContParams.confThreshold = 1e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.confThreshold = 3;

    otherContParams.confMargin = 1.5e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.confMargin = 4;

    otherContParams.basePercent = 1e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.basePercent = 5;

    otherContParams.perpPercent = 1e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.perpPercent = 6;

    otherContParams.optionPercent = 1e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidOtherContingencyParameters.selector);
    lib.setOtherContingencyParams(otherContParams);
    otherContParams.optionPercent = 7;
  }

  function testSetPMRMParametersMargin() public {
    IPMRMLib.MarginParameters memory marginParams =
      IPMRMLib.MarginParameters({imFactor: 1e18, rateMultScale: 1, rateAddScale: 2, baseStaticDiscount: 3});
    lib.setMarginParams(marginParams);
    IPMRMLib.MarginParameters memory resStaticDiscountParams = lib.getStaticDiscountParams();
    assertEq(resStaticDiscountParams.rateMultScale, 1);
    assertEq(resStaticDiscountParams.rateAddScale, 2);
    assertEq(resStaticDiscountParams.baseStaticDiscount, 3);

    marginParams.imFactor = 1e18 - 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidMarginParameters.selector);
    lib.setMarginParams(marginParams);
    marginParams.imFactor = 1e18;

    marginParams.imFactor = 4e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidMarginParameters.selector);
    lib.setMarginParams(marginParams);
    marginParams.imFactor = 1e18;

    marginParams.rateMultScale = 5e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidMarginParameters.selector);
    lib.setMarginParams(marginParams);
    marginParams.rateMultScale = 1;

    marginParams.rateAddScale = 5e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidMarginParameters.selector);
    lib.setMarginParams(marginParams);
    marginParams.rateAddScale = 2;

    marginParams.baseStaticDiscount = 1e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidMarginParameters.selector);
    lib.setMarginParams(marginParams);
    marginParams.baseStaticDiscount = 3;
  }

  function testSetPMRMParametersVolShock() public {
    IPMRMLib.VolShockParameters memory volShockParams =
      IPMRMLib.VolShockParameters({volRangeUp: 1, volRangeDown: 2, shortTermPower: 3, longTermPower: 4, dteFloor: 864});
    lib.setVolShockParams(volShockParams);
    IPMRMLib.VolShockParameters memory resVolShockParams = lib.getVolShockParams();
    assertEq(resVolShockParams.volRangeUp, 1);
    assertEq(resVolShockParams.volRangeDown, 2);
    assertEq(resVolShockParams.shortTermPower, 3);
    assertEq(resVolShockParams.longTermPower, 4);
    assertEq(resVolShockParams.dteFloor, 864);

    volShockParams.volRangeUp = 2e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidVolShockParameters.selector);
    lib.setVolShockParams(volShockParams);
    volShockParams.volRangeUp = 1;

    volShockParams.volRangeDown = 2e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidVolShockParameters.selector);
    lib.setVolShockParams(volShockParams);
    volShockParams.volRangeDown = 2;

    volShockParams.shortTermPower = 2e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidVolShockParameters.selector);
    lib.setVolShockParams(volShockParams);
    volShockParams.shortTermPower = 3;

    volShockParams.longTermPower = 2e18 + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidVolShockParameters.selector);
    lib.setVolShockParams(volShockParams);
    volShockParams.longTermPower = 4;

    volShockParams.dteFloor = 100 days + 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidVolShockParameters.selector);
    lib.setVolShockParams(volShockParams);
    volShockParams.dteFloor = 864;

    volShockParams.dteFloor = 0.01 days - 1;
    vm.expectRevert(IPMRMLib.PMRML_InvalidVolShockParameters.selector);
    lib.setVolShockParams(volShockParams);
    volShockParams.dteFloor = 864;
  }

  function testCannotSetInvalidMaxExpiries() public {
    vm.expectRevert(IPMRM.PMRM_InvalidMaxExpiries.selector);
    pmrm.setMaxExpiries(11);

    vm.expectRevert(IPMRM.PMRM_InvalidMaxExpiries.selector);
    pmrm.setMaxExpiries(31);

    pmrm.setMaxExpiries(15);
    vm.expectRevert(IPMRM.PMRM_InvalidMaxExpiries.selector);
    pmrm.setMaxExpiries(15);
  }

  function testCanSetMaxExpiries() public {
    pmrm.setMaxExpiries(12);

    assertEq(pmrm.maxExpiries(), 12);
  }

  function testCannotSetInvalidMaxSize() public {
    vm.expectRevert(IBaseManager.BM_InvalidMaxAccountSize.selector);
    pmrm.setMaxAccountSize(1);

    vm.expectRevert(IBaseManager.BM_InvalidMaxAccountSize.selector);
    pmrm.setMaxAccountSize(1000);
  }
}

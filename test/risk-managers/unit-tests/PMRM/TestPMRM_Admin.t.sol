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
    assertEq(address(pmrm.volFeed()), address(feed));
    pmrm.setVolFeed(IVolFeed(address(0)));
    assertEq(address(pmrm.volFeed()), address(0));
  }
}

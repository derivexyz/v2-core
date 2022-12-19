// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/interfaces/IDutchAuction.sol";
import {DutchAuctionBase} from "./DutchAuctionBase.sol";

contract DutchAuctionView is Test, DutchAuctionBase {

  IDutchAuction.DutchAuctionParameters public dutchAuctionParameters;
  
  function setUp() public {
    run();
    
    // // set params
    // IDutchAuction.DutchAuctionParameters memory dutchAuctionParameters = IDutchAuction.DutchAuctionParameters({
    //   stepInterval: 1,
    //   lengthOfAuction: 100,
    //   securityModule: address(0)
    // });

    // dutchAuction.setDutchAuctionParameters(dutchAuctionParameters);
  }

  function testGetParams() public {
    (uint stepInterval, uint lengthOfAuction, address securityModule) = dutchAuction.parameters();
    assertEq(stepInterval, dutchAuctionParameters.stepInterval);
    assertEq(lengthOfAuction, dutchAuctionParameters.lengthOfAuction);
    assertEq(securityModule, dutchAuctionParameters.securityModule);

    // change params
    dutchAuction.setDutchAuctionParameters(IDutchAuction.DutchAuctionParameters({
      stepInterval: 2,
      lengthOfAuction: 200,
      securityModule: address(1)
    }));

    // check if params changed
    (stepInterval, lengthOfAuction, securityModule) = dutchAuction.parameters();
    assertEq(stepInterval, 2);
    assertEq(lengthOfAuction, 200);
    assertEq(securityModule, address(1));
  }

}
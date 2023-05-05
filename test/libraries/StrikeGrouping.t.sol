// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ISingleExpiryPortfolio} from "src/interfaces/ISingleExpiryPortfolio.sol";

import "src/libraries/StrikeGrouping.sol";

contract StrikeGroupingTester {
  
  function findOrAddStrike(ISingleExpiryPortfolio.Strike[] memory strikes, uint newStrike, uint numStrikesHeld)
    external
    pure
    returns (uint, uint)
  {
    (uint strikeIndex, uint newArrayLen) = StrikeGrouping.findOrAddStrike(strikes, newStrike, numStrikesHeld);

    // had to inline error checks here since array modified via reference and getting stack overflow errors
    if (strikes[strikeIndex].strike != newStrike) {
      revert("invalid strike price");
    }

    if (newArrayLen > numStrikesHeld && strikeIndex != numStrikesHeld) {
      revert("invalid strike index");
    }

    return (strikeIndex, newArrayLen);
  }
}

contract StrikeGroupingTest is Test {
  StrikeGroupingTester tester;

  function setUp() public {
    tester = new StrikeGroupingTester();
  }

  //////////////////////////////
  // Unique Elements in Array //
  //////////////////////////////

  function testFindOrAddStrike() public {
    ISingleExpiryPortfolio.Portfolio memory portfolio = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(portfolio.strikes, 1250e18, 2);

    assertEq(strikeIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingStrike() public {
    ISingleExpiryPortfolio.Portfolio memory portfolio = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(portfolio.strikes, 10e18, 2);

    assertEq(strikeIndex, 0);
    assertEq(newArrayLen, 2);
  }

  //////////
  // Util //
  //////////
  function _getDefaultHoldings() public view returns (ISingleExpiryPortfolio.Portfolio memory) {
    // Hardcode max strike = 64
    uint MAX_STRIKE = 64;
    ISingleExpiryPortfolio.Strike[] memory strikes = new ISingleExpiryPortfolio.Strike[](MAX_STRIKE);
    // strike 1
    strikes[0] = ISingleExpiryPortfolio.Strike({strike: 10e18, calls: 10, puts: -10});

    // strike 2
    strikes[1] = ISingleExpiryPortfolio.Strike({strike: 15e18, calls: 0, puts: -10});

    // all expiries
    ISingleExpiryPortfolio.Portfolio memory portfolio = ISingleExpiryPortfolio.Portfolio({
      cash: 0,
      perp: 0,
      expiry: block.timestamp + 7 days,
      numStrikesHeld: 2,
      strikes: strikes
    });

    return portfolio;
  }
}

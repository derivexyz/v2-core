// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/Black76.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke internal library
 */
contract Black76Tester {
  using Black76 for Black76.Black76Inputs;

  function prices(Black76.Black76Inputs memory b76Input) external pure returns (uint call, uint put) {
    return b76Input.prices();
  }
}

contract Black76Test is Test {
  using Black76 for Black76.Black76Inputs;

  Black76Tester tester;

  function setUp() public {
    tester = new Black76Tester();
  }

  function testPrices() public {
    uint accuracy = uint(1e18 * 1e-12);

    Black76.Black76Inputs[] memory b76TestInputs = new Black76.Black76Inputs[](8);
    // just a normal ATM call/put
    b76TestInputs[0] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 7,
      volatility: 1e18,
      fwdPrice: 1500 * 1e18,
      strikePrice: 1500 * 1e18,
      discount: 1e18
    });
    // just a normal OTM/ITM call/put
    b76TestInputs[1] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 30,
      volatility: 0.25 * 1e18,
      fwdPrice: 1000 * 1e18,
      strikePrice: 1200 * 1e18,
      discount: 0.9991784198737006 * 1e18
    });
    // just a normal deep ITM/OTM call/put
    b76TestInputs[2] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 2,
      volatility: 0.75 * 1e18,
      fwdPrice: 1000 * 1e18,
      strikePrice: 700 * 1e18,
      discount: 0.9998904169635637 * 1e18
    });
    // total vol exceeds cap of 24.0 (expect call be F*discount, put be K*discount)
    b76TestInputs[3] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 365,
      volatility: 25 * 1e18,
      fwdPrice: 1000 * 1e18,
      strikePrice: 700 * 1e18,
      discount: 0.9801986733067553 * 1e18
    });
    // total vol is large but below cap (expect call/put be close to F*discount/K*discount)
    b76TestInputs[4] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 365,
      volatility: 5 * 1e18,
      fwdPrice: 1000 * 1e18,
      strikePrice: 700 * 1e18,
      discount: 0.9801986733067553 * 1e18
    });
    // strike is at uint128 max, fwd is at its min (expect call/put be 0/uint128 max)
    b76TestInputs[5] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 365,
      volatility: 4 * 1e18,
      fwdPrice: 1,
      strikePrice: type(uint128).max,
      discount: 1.0 * 1e18
    });
    // fwd is at uint128 max, strike is at its min (expect call/put be uint128 max/0)
    b76TestInputs[6] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 365,
      volatility: 4 * 1e18,
      fwdPrice: type(uint128).max,
      strikePrice: 1,
      discount: 1.0 * 1e18
    });
    // ZSC (expect call == discounted forward and put == 0 no matter the vol)
    b76TestInputs[7] = Black76.Black76Inputs({
      timeToExpirySec: 60 * 60 * 24 * 365,
      volatility: 4 * 1e18,
      fwdPrice: 1000 * 1e18,
      strikePrice: 0,
      discount: 0.99 * 1e18
    });

    // array of (call, put) benchmarks computed in python
    int[2][] memory benchmarkResults = new int[2][](b76TestInputs.length);
    benchmarkResults[0] = [int(82.805080668634559515 * 1e18), int(82.805080668634559515 * 1e18)];
    benchmarkResults[1] = [int(0.137082128426579297 * 1e18), int(199.972766103166719631 * 1e18)];
    benchmarkResults[2] = [int(299.967125089526177817 * 1e18), int(0.00000000045708468 * 1e18)];
    benchmarkResults[3] = [int(980.198673306755267731 * 1e18), int(686.139071314728653306 * 1e18)];
    benchmarkResults[4] = [int(970.034553583819047162 * 1e18), int(675.974951591792546424 * 1e18)];
    benchmarkResults[5] = [int(0), int(uint(type(uint128).max))];
    benchmarkResults[6] = [int(uint(type(uint128).max)), int(0)];
    benchmarkResults[7] = [int(990 * 1e18), int(0)];

    assert(b76TestInputs.length == benchmarkResults.length);

    for (uint i = 0; i < b76TestInputs.length; i++) {
      (uint call, uint put) = tester.prices(b76TestInputs[i]);
      assertApproxEqAbs(int(call), benchmarkResults[i][0], accuracy);
      assertApproxEqAbs(int(put), benchmarkResults[i][1], accuracy);
    }
  }
}

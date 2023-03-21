pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/assets/InterestRateModel.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";

contract MemoryArrayGasUsage is Test {
  struct PortfolioMarginCalcs {
    int cash; // plus unrealisedPnL from perps
    int delta1s; // perps and weth
    ExpiryMarginCalcs[] expiries;
  }

  struct ExpiryMarginCalcs {
    uint expiry;
    uint maxLossCalc;
    uint sumOfSomeSort;
    uint insertedCount;
    Strike[] strikes;
  }

  struct Strike {
    uint data1;
    uint data2;
    uint data3;
    uint data4;
  }

  struct Dummy {
    uint index;
    uint val;
  }

  uint amtOptions = 64;
  uint amtExpiries = 12;

  function testMemoryArrayGasUsage1() public view {
    Dummy[] memory dummyArray = new Dummy[](amtOptions);
    for (uint i = 0; i < amtOptions; i++) {
      dummyArray[i] = Dummy({index: i % amtExpiries, val: i});
    }

    PortfolioMarginCalcs memory portfolio =
      PortfolioMarginCalcs({cash: int(-1234), delta1s: int(100), expiries: new ExpiryMarginCalcs[](amtExpiries)});

    for (uint i = 0; i < amtExpiries; i++) {
      portfolio.expiries[i] = ExpiryMarginCalcs({
        expiry: i + 1,
        maxLossCalc: 1000,
        sumOfSomeSort: 1234,
        insertedCount: 0,
        strikes: new Strike[](amtOptions)
      });
    }

    for (uint i = 0; i < amtOptions; ++i) {
      Dummy memory item = dummyArray[i];
      uint expiryIndex = item.index;
      uint insertedCount = portfolio.expiries[expiryIndex].insertedCount++;
      portfolio.expiries[expiryIndex].strikes[insertedCount] =
        Strike({data1: item.val, data2: item.val, data3: item.val, data4: item.val});
    }
  }

  function testMemoryArrayGasUsage2() public view {
    Dummy[] memory dummyArray = new Dummy[](amtOptions);
    for (uint i = 0; i < amtOptions; i++) {
      dummyArray[i] = Dummy({index: i % amtExpiries, val: i});
    }

    PortfolioMarginCalcs memory portfolio =
      PortfolioMarginCalcs({cash: int(-1234), delta1s: int(100), expiries: new ExpiryMarginCalcs[](amtExpiries)});

    uint[] memory indexCounts = new uint[](amtExpiries);
    for (uint i = 0; i < dummyArray.length; i++) {
      indexCounts[dummyArray[i].index] += 1;
    }

    for (uint i = 0; i < amtExpiries; i++) {
      portfolio.expiries[i] = ExpiryMarginCalcs({
        expiry: i + 1,
        maxLossCalc: 1000,
        sumOfSomeSort: 1234,
        insertedCount: 0,
        strikes: new Strike[](indexCounts[i])
      });
    }

    for (uint i = 0; i < amtOptions; ++i) {
      Dummy memory item = dummyArray[i];
      uint expiryIndex = item.index;
      uint insertedCount = portfolio.expiries[expiryIndex].insertedCount++;
      portfolio.expiries[expiryIndex].strikes[insertedCount] =
        Strike({data1: item.val, data2: item.val, data3: item.val, data4: item.val});
    }
  }
}

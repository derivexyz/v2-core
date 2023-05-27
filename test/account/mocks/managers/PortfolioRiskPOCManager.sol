// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "forge-std/console2.sol";

import {IAsset} from "src/interfaces/IAsset.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";

import "./../assets/QuoteWrapper.sol";
import "./../assets/BaseWrapper.sol";
import "./../assets/OptionToken.sol";
import "./../assets/ISettleable.sol";
import "./../assets/lending/Lending.sol";

contract PortfolioRiskPOCManager is Ownable2Step, IManager {
  using DecimalMath for uint;
  using SafeCast for uint;
  using SignedDecimalMath for int;

  struct Scenario {
    uint spotShock;
    uint ivShock;
  }

  ISubAccounts subAccounts;

  ////
  // Allowed assets
  QuoteWrapper immutable quoteAsset;
  BaseWrapper immutable baseAsset;
  OptionToken immutable optionToken;
  Lending lending;

  ////
  // Data feeds
  PriceFeeds priceFeeds;

  ////
  // Vars
  Scenario[] scenarios;
  mapping(uint => bool) liquidationFlagged;

  address nextManager;

  constructor(
    ISubAccounts account_,
    PriceFeeds priceFeed_,
    QuoteWrapper quoteAsset_,
    BaseWrapper baseAsset_,
    OptionToken optionToken_,
    Lending lending_
  ) Ownable2Step() {
    subAccounts = account_;
    priceFeeds = priceFeed_;
    quoteAsset = quoteAsset_;
    baseAsset = baseAsset_;
    optionToken = optionToken_;
    lending = lending_;
  }

  ////
  // Admin

  function setScenarios(Scenario[] memory scenarios_) external onlyOwner {
    delete scenarios; // keeping simple bulk delete for now
    uint scenarioLen = scenarios_.length;
    for (uint i; i < scenarioLen; i++) {
      scenarios.push(scenarios_[i]);
    }
  }

  function setNextManager(address _manager) external onlyOwner {
    nextManager = _manager;
  }

  ////
  // Liquidations

  function flagLiquidation(uint accountId) external {
    ISubAccounts.AssetBalance[] memory assetBals = subAccounts.getAccountBalances(accountId);
    if (!liquidationFlagged[accountId] && _isAccountLiquidatable(accountId, assetBals)) {
      liquidationFlagged[accountId] = true;
    } else {
      revert("cannot be liquidated");
    }
    for (uint i; i < assetBals.length; i++) {
      if (assetBals[i].asset == IAsset(optionToken)) {
        // Have a counter for which subIds are involved in liquidations to pause settlement for them
        optionToken.incrementLiquidations(assetBals[i].subId);
      }
    }
  }

  // Note: this should be an auction
  function liquidateAccount(uint accountId, uint accountForCollateral, int extraCollateral) external {
    // TODO: SM and socialised losses, this require blocks that
    require(liquidationFlagged[accountId] && extraCollateral >= 0);

    require(msg.sender == subAccounts.ownerOf(accountForCollateral), "not auth");

    // TODO: check owner of accountForCollat
    subAccounts.managerAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountForCollateral,
        asset: quoteAsset,
        subId: 0,
        amount: -extraCollateral,
        assetData: bytes32(0)
      })
    );
    assessRisk(accountForCollateral, subAccounts.getAccountBalances(accountForCollateral));

    subAccounts.managerAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountId,
        asset: quoteAsset,
        subId: 0,
        amount: extraCollateral,
        assetData: bytes32(0)
      })
    );

    ISubAccounts.AssetBalance[] memory assetBals = subAccounts.getAccountBalances(accountId);
    for (uint i; i < assetBals.length; i++) {
      if (assetBals[i].asset == IAsset(optionToken)) {
        optionToken.decrementLiquidations(assetBals[i].subId);
      }
    }
    // reset flag
    liquidationFlagged[accountId] = false;
    assessRisk(accountId, subAccounts.getAccountBalances(accountId));

    // transfer account to liquidator
    subAccounts.transferFrom(subAccounts.ownerOf(accountId), msg.sender, accountId);
  }

  ////
  // Settlement

  function settleAssets(uint accountId, ISubAccounts.HeldAsset[] memory assetsToSettle) external {
    // iterate through all held assets and trigger settlement
    uint assetLen = assetsToSettle.length;
    for (uint i; i < assetLen; i++) {
      int balance = subAccounts.getBalance(accountId, assetsToSettle[i].asset, assetsToSettle[i].subId);

      (int pnl, bool settled) =
        ISettleable(address(assetsToSettle[i].asset)).calculateSettlement(assetsToSettle[i].subId, balance);

      if (settled) {
        // NOTE: RM A at risk of RM B not properly implementing settling
        subAccounts.managerAdjustment(
          ISubAccounts.AssetAdjustment({
            acc: accountId,
            asset: assetsToSettle[i].asset,
            subId: assetsToSettle[i].subId,
            amount: -balance, // set back to zero
            assetData: bytes32(0)
          })
        );

        // this could leave daiLending balance to negative value
        subAccounts.managerAdjustment(
          ISubAccounts.AssetAdjustment({acc: accountId, asset: lending, subId: 0, amount: pnl, assetData: bytes32(0)})
        );
      }
    }
  }

  function handleAdjustment(uint accountId, uint, /*tradeId*/ address, ISubAccounts.AssetDelta[] memory, bytes memory)
    public
    override
  {
    assessRisk(accountId, subAccounts.getAccountBalances(accountId));
  }

  function assessRisk(uint accountId, ISubAccounts.AssetBalance[] memory assets) public {
    if (liquidationFlagged[accountId]) {
      revert("Account flagged for liquidation");
    }
    if (_isAccountLiquidatable(accountId, assets)) {
      revert("Too much debt");
    }
  }

  function _isAccountLiquidatable(uint accountId, ISubAccounts.AssetBalance[] memory assets) internal returns (bool) {
    // Get fresh lending balance once in the beginning
    int freshLendingBalance = lending.getBalance(accountId);

    // begin each scenario
    uint assetLen = assets.length;
    uint scenarioLen = scenarios.length;

    // create spot and iv cache in memory;
    uint baseSpotPrice = priceFeeds.getSpotForAsset(IAsset(baseAsset));

    // assess each scenario
    for (uint j; j < scenarioLen; j++) {
      int scenarioValue = 0;
      uint shockedSpot = baseSpotPrice.multiplyDecimal(scenarios[j].spotShock);
      for (uint k; k < assetLen; k++) {
        ISubAccounts.AssetBalance memory assetBalance = assets[k];

        if (assetBalance.asset == IAsset(optionToken)) {
          scenarioValue +=
            optionToken.getValue(assetBalance.subId, assetBalance.balance, shockedSpot, scenarios[j].ivShock);
        } else if (assetBalance.asset == IAsset(baseAsset)) {
          scenarioValue += int(shockedSpot).multiplyDecimal(assetBalance.balance);
        } else if (assetBalance.asset == IAsset(quoteAsset)) {
          scenarioValue += assetBalance.balance;
        } else if (assetBalance.asset == IAsset(lending)) {
          // placeholder for lending asset
          scenarioValue += freshLendingBalance;
        } else {
          revert("Risk model does not support given asset");
        }
      }

      if (scenarioValue < 0) {
        return true;
      }
    }
    return false;
  }

  function handleManagerChange(uint, IManager _manager) external view {
    require(address(_manager) != nextManager && nextManager != address(0), "wrong manager");
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}

  function getMargin(uint accountId, bool isInitial) external view returns (int) {}
}

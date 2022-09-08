pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "synthetix/SignedDecimalMath.sol";
import "synthetix/DecimalMath.sol";
import "forge-std/console2.sol";

import "src/interfaces/IAbstractAsset.sol";
import "src/Account.sol";

import "./assets/QuoteWrapper.sol";
import "./assets/BaseWrapper.sol";
import "./assets/OptionToken.sol";
import "./assets/ISettleable.sol";

contract PortfolioRiskManager is Owned, IAbstractManager {
  using DecimalMath for uint;
  using SafeCast for uint;
  using SignedDecimalMath for int;

  struct Scenario {
    uint spotShock;
    uint ivShock;
  }

  Account account;

  ////
  // Allowed assets
  QuoteWrapper quoteAsset;
  uint quoteFeedId;
  BaseWrapper baseAsset;
  uint baseFeedId;
  OptionToken optionToken;

  ////
  // Data feeds
  PriceFeeds priceFeeds;

  ////
  // Vars
  Scenario[] scenarios;
  mapping(uint => bool) liquidationFlagged;

  constructor(
    Account account_,
    PriceFeeds priceFeed_,
    QuoteWrapper quoteAsset_,
    uint quoteFeedId_,
    BaseWrapper baseAsset_,
    uint baseFeedId_,
    OptionToken optionToken_
  ) Owned() {
    account = account_;
    priceFeeds = priceFeed_;
    quoteAsset = quoteAsset_;
    quoteFeedId = quoteFeedId_;
    baseAsset = baseAsset_;
    baseFeedId = baseFeedId_;
    optionToken = optionToken_;
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

  ////
  // Liquidations

  function flagLiquidation(uint accountId) external {
    AccountStructs.AssetBalance[] memory assetBals = account.getAccountBalances(accountId);
    if (!liquidationFlagged[accountId] && _isAccountLiquidatable(accountId, assetBals)) {
      liquidationFlagged[accountId] = true;
    } else {
      revert("cannot be liquidated");
    }
    for (uint i; i < assetBals.length; i++) {
      if (assetBals[i].asset == IAbstractAsset(optionToken)) {
        // Have a counter for which subIds are involved in liquidations to pause settlement for them
        optionToken.incrementLiquidations(assetBals[i].subId);
      }
    }
  }

  // Note: this should be an auction
  function liquidateAccount(uint accountId, int price, uint accountForCollateral, int extraCollateral) external {
    // TODO: SM and socialised losses, this require blocks that
    require(price >= 0 && liquidationFlagged[accountId] && extraCollateral >= 0);

    // TODO: check owner of accountForCollat
    account.adjustBalance(
      AccountStructs.AssetAdjustment({acc: accountForCollateral, asset: quoteAsset, subId: 0, amount: -extraCollateral})
    );
    assessRisk(accountForCollateral, account.getAccountBalances(accountForCollateral));

    account.adjustBalance(
      AccountStructs.AssetAdjustment({acc: accountForCollateral, asset: quoteAsset, subId: 0, amount: extraCollateral})
    );
    account.transferFrom(account.ownerOf(accountId), msg.sender, accountId);

    AccountStructs.AssetBalance[] memory assetBals = account.getAccountBalances(accountId);
    for (uint i; i < assetBals.length; i++) {
      if (assetBals[i].asset == IAbstractAsset(optionToken)) {
        optionToken.decrementLiquidations(assetBals[i].subId);
      }
    }
    assessRisk(accountId, assetBals);
  }

  ////
  // Settlement

  function settleAssets(uint accountId, AccountStructs.HeldAsset[] memory assetsToSettle) external {
    // iterate through all held assets and trigger settlement
    uint assetLen = assetsToSettle.length;
    for (uint i; i < assetLen; i++) {
      int balance = account.getAssetBalance(accountId, assetsToSettle[i].asset, assetsToSettle[i].subId);

      (int PnL, bool settled) = ISettleable(address(assetsToSettle[i].asset)).calculateSettlement(assetsToSettle[i].subId, balance);

      if (settled) {
        // NOTE: RM A at risk of RM B not properly implementing settling
        account.adjustBalance(
          AccountStructs.AssetAdjustment({
            acc: accountId,
            asset: assetsToSettle[i].asset,
            subId: assetsToSettle[i].subId,
            amount: -balance // set back to zero
          })
        );

        account.adjustBalance(AccountStructs.AssetAdjustment({acc: accountId, asset: quoteAsset, subId: 0, amount: PnL}));
      }
    }
  }

  ////
  // Views

  function handleAdjustment(uint accountId, AccountStructs.AssetBalance[] memory assets, address) public view override {
    assessRisk(accountId, assets);
  }

  function assessRisk(uint accountId, AccountStructs.AssetBalance[] memory assets) public view {
    if (liquidationFlagged[accountId]) {
      revert("Account flagged for liquidation");
    }
    if (_isAccountLiquidatable(accountId, assets)) {
      revert("Too much debt");
    }
  }

  function _isAccountLiquidatable(uint, AccountStructs.AssetBalance[] memory assets) internal view returns (bool) {
    uint assetLen = assets.length;
    uint scenarioLen = scenarios.length;

    // create spot and iv cache in memory;
    uint baseSpotPrice = priceFeeds.getSpotForAsset(IAbstractAsset(baseAsset));

    // assess each scenario
    for (uint j; j < scenarioLen; j++) {
      int scenarioValue = 0;
      uint shockedSpot = baseSpotPrice.multiplyDecimal(scenarios[j].spotShock);
      for (uint k; k < assetLen; k++) {
        AccountStructs.AssetBalance memory assetBalance = assets[k];

        if (assetBalance.asset == IAbstractAsset(optionToken)) {
          // swap out to remov BS price:
          scenarioValue += 0;

          // call external valuation contract assigned to subId
          // scenarioValue +=
          //   optionToken.getValue(assetBalance.subId, assetBalance.balance, shockedSpot, scenarios[j].ivShock);
        } else if (assetBalance.asset == IAbstractAsset(baseAsset)) {
          scenarioValue += int(shockedSpot).multiplyDecimal(assetBalance.balance);
        } else if (assetBalance.asset == IAbstractAsset(quoteAsset)) {
          scenarioValue += assetBalance.balance;
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

  function handleManagerChange(uint, IAbstractManager, IAbstractManager) external {}

}

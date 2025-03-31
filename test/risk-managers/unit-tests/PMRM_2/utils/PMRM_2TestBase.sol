// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import {IAsset} from "../../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../../src/interfaces/ISubAccounts.sol";
import {IManager} from "../../../../../src/interfaces/IManager.sol";
import {IDutchAuction} from "../../../../../src/interfaces/IDutchAuction.sol";
import {ISpotFeed} from "../../../../../src/interfaces/ISpotFeed.sol";
import {IForwardFeed} from "../../../../../src/interfaces/IForwardFeed.sol";
import {IInterestRateFeed} from "../../../../../src/interfaces/IInterestRateFeed.sol";
import {IVolFeed} from "../../../../../src/interfaces/IVolFeed.sol";
import {ISettlementFeed} from "../../../../../src/interfaces/ISettlementFeed.sol";
import {IPMRM_2} from "../../../../../src/interfaces/IPMRM_2.sol";

import {SubAccounts} from "../../../../../src/SubAccounts.sol";
import {CashAsset} from "../../../../../src/assets/CashAsset.sol";
import {WrappedERC20Asset} from "../../../../../src/assets/WrappedERC20Asset.sol";
import {PMRM_2} from "../../../../../src/risk-managers/PMRM_2.sol";
import {PMRMLib_2} from "../../../../../src/risk-managers/PMRMLib_2.sol";
import {BasePortfolioViewer} from "../../../../../src/risk-managers/BasePortfolioViewer.sol";
import {DutchAuction} from "../../../../../src/liquidation/DutchAuction.sol";

import {MockManager} from "../../../../shared/mocks/MockManager.sol";
import {MockERC20} from "../../../../shared/mocks/MockERC20.sol";
import {MockAsset} from "../../../../shared/mocks/MockAsset.sol";
import {MockOption} from "../../../../shared/mocks/MockOptionAsset.sol";
import {MockSM} from "../../../../shared/mocks/MockSM.sol";
import {MockFeeds} from "../../../../shared/mocks/MockFeeds.sol";
import {MockFeeds} from "../../../../shared/mocks/MockFeeds.sol";
import {MockPerp} from "../../../../shared/mocks/MockPerp.sol";
import {MockSpotDiffFeed} from "../../../../shared/mocks/MockSpotDiffFeed.sol";
import {MockCash} from "../../../../shared/mocks/MockCash.sol";
import {MockDutchAuction} from "../../../../risk-managers/mocks/MockDutchAuction.sol";
import {PMRM_2Public} from "../../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2Public.sol";

import {IPMRMLib_2} from "../../../../../src/interfaces/IPMRMLib_2.sol";

import "../../../../shared/utils/JsonMechIO.sol";
import {Config} from "../../../../config-test.sol";
import {
  TransparentUpgradeableProxy,
  ProxyAdmin,
  ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

library StringUtils {
  function uintToString(uint value) internal pure returns (string memory) {
    if (value == 0) {
      return "0";
    }
    uint temp = value;
    uint digits;
    while (temp != 0) {
      digits++;
      temp /= 10;
    }
    bytes memory buffer = new bytes(digits);
    while (value != 0) {
      digits -= 1;
      buffer[digits] = bytes1(uint8(48 + uint(value % 10)));
      value /= 10;
    }
    return string(buffer);
  }
}

contract PMRM_2TestBase is JsonMechIO {
  using StringUtils for uint;
  using stdJson for string;

  SubAccounts subAccounts;
  PMRM_2Public pmrm_2;
  MockCash cash;
  MockERC20 usdc;
  MockERC20 weth;
  WrappedERC20Asset baseAsset;

  MockOption option;
  DutchAuction auction;
  MockSM sm;
  MockFeeds feed;
  MockSpotDiffFeed perpFeed;
  MockFeeds stableFeed;
  uint feeRecipient;
  MockPerp mockPerp;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  BasePortfolioViewer viewer;
  PMRMLib_2 lib;
  ProxyAdmin proxyAdmin;

  mapping(address => string) assetLabel;

  function setUp() public virtual {
    vm.warp(1640995200); // 1st jan 2022

    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    feed = new MockFeeds();
    perpFeed = new MockSpotDiffFeed(feed);
    stableFeed = new MockFeeds();
    feed.setSpot(1500e18, 1e18);
    stableFeed.setSpot(1e18, 1e18);

    usdc = new MockERC20("USDC", "USDC");
    weth = new MockERC20("weth", "weth");
    cash = new MockCash(usdc, subAccounts);
    baseAsset = new WrappedERC20Asset(subAccounts, weth);
    mockPerp = new MockPerp(subAccounts);

    option = new MockOption(subAccounts);

    sm = new MockSM(subAccounts, cash);
    auction = new DutchAuction(subAccounts, sm, cash);

    viewer = new BasePortfolioViewer(subAccounts, cash);
    lib = new PMRMLib_2();

    PMRM_2Public imp = new PMRM_2Public();

    // record logs
    vm.recordLogs();

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(imp),
      address(this),
      abi.encodeWithSelector(
        PMRM_2.initialize.selector,
        subAccounts,
        cash,
        option,
        mockPerp,
        //      baseAsset, TODO: add as collateral asset seperately
        auction,
        IPMRM_2.Feeds({
          spotFeed: ISpotFeed(feed),
          stableFeed: ISpotFeed(stableFeed),
          forwardFeed: IForwardFeed(feed),
          interestRateFeed: IInterestRateFeed(feed),
          volFeed: IVolFeed(feed)
        }),
        viewer,
        lib,
        11
      )
    );

    Vm.Log[] memory logs = vm.getRecordedLogs();
    proxyAdmin;
    for (uint i = 0; i < logs.length; i++) {
      if (logs[i].topics[0] == keccak256("AdminChanged(address,address)")) {
        (address oldAdmin, address newAdmin) = abi.decode(logs[i].data, (address, address));
        proxyAdmin = ProxyAdmin(newAdmin);
        break;
      }
    }

    pmrm_2 = PMRM_2Public(address(proxy));

    setDefaultParameters();
    addScenarios();

    baseAsset.setWhitelistManager(address(pmrm_2), true);
    baseAsset.setTotalPositionCap(pmrm_2, 10000e18);

    pmrm_2.setCollateralSpotFeed(address(baseAsset), ISpotFeed(feed));
    lib.setCollateralParameters(
      address(baseAsset),
      IPMRMLib_2.CollateralParameters({isEnabled: true, isRiskCancelling: true, MMHaircut: 0.02e18, IMHaircut: 0.01e18})
    );

    _setupAliceAndBob();

    feeRecipient = subAccounts.createAccount(address(this), pmrm_2);
    pmrm_2.setFeeRecipient(feeRecipient);

    auction.setAuctionParams(_getDefaultAuctionParams());

    sm.createAccountForSM(pmrm_2);
  }

  function setDefaultParameters() internal {
    (
      IPMRMLib_2.BasisContingencyParameters memory basisContParams,
      IPMRMLib_2.OtherContingencyParameters memory otherContParams,
      IPMRMLib_2.MarginParameters memory marginParams,
      IPMRMLib_2.VolShockParameters memory volShockParams,
      IPMRMLib_2.SkewShockParameters memory skewShockParams
    ) = Config.getPMRM_2Params();

    lib.setBasisContingencyParams(basisContParams);
    lib.setOtherContingencyParams(otherContParams);
    lib.setMarginParams(marginParams);
    lib.setVolShockParams(volShockParams);
    lib.setSkewShockParameters(skewShockParams);

    auction.setWhitelistManager(address(pmrm_2), true);
  }

  function addScenarios() internal {
    // Scenario Number	Spot Shock (of max)	Vol Shock (of max)
    IPMRM_2.Scenario[] memory scenarios = Config.get_2_1DefaultScenarios();
    pmrm_2.setScenarios(scenarios);
  }

  function setBalances(uint acc, ISubAccounts.AssetBalance[] memory balances) internal {
    pmrm_2.setBalances(acc, balances);
  }

  function _setupAliceAndBob() internal {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    aliceAcc = subAccounts.createAccount(alice, IManager(address(pmrm_2)));
    bobAcc = subAccounts.createAccount(bob, IManager(address(pmrm_2)));

    // allow this contract to submit trades
    vm.prank(alice);
    subAccounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    subAccounts.setApprovalForAll(address(this), true);
  }

  function _depositCash(uint accId, uint amount) internal {
    usdc.mint(address(this), amount);
    usdc.approve(address(cash), amount);
    cash.deposit(accId, amount);
  }

  function _doBalanceTransfer(uint accA, uint accB, ISubAccounts.AssetBalance[] memory balances) internal {
    subAccounts.submitTransfers(_getTransferBatch(accA, accB, balances), "");
  }

  function _getTransferBatch(uint accA, uint accB, ISubAccounts.AssetBalance[] memory balances)
    internal
    pure
    returns (ISubAccounts.AssetTransfer[] memory)
  {
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](balances.length);

    for (uint i = 0; i < balances.length; i++) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
        fromAcc: accA,
        toAcc: accB,
        asset: balances[i].asset,
        subId: balances[i].subId,
        amount: balances[i].balance,
        assetData: bytes32(0)
      });
    }

    return transferBatch;
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }

  function _getDefaultAuctionParams() internal pure returns (IDutchAuction.AuctionParams memory) {
    return IDutchAuction.AuctionParams({
      startingMtMPercentage: 0.98e18,
      fastAuctionCutoffPercentage: 0.8e18,
      fastAuctionLength: 100,
      slowAuctionLength: 14400,
      insolventAuctionLength: 10 minutes,
      liquidatorFeeRate: 0.02e18,
      bufferMarginPercentage: 0.2e18
    });
  }

  function _logPortfolio(IPMRM_2.Portfolio memory portfolio, uint refTime) internal view {
    console.log();
    console.log("=== Portfolio ===");
    // Top level
    _logBN("- spotPrice", portfolio.spotPrice);
    _logBN("- perpPrice", portfolio.perpPrice);
    _logBN("- stablePrice", portfolio.stablePrice);
    _logBN("- cash", portfolio.cash);
    _logBN("- perpPosition", portfolio.perpPosition);
    _logBN("- totalMtM", portfolio.totalMtM);
    _logBN("- basisContingency", portfolio.basisContingency);
    _logBN("- MMContingency", portfolio.MMContingency);
    _logBN("- IMContingency", portfolio.IMContingency);
    _logBN("- minConfidence", portfolio.minConfidence);
    _logBN("- perpValue", portfolio.perpValue);

    // collaterals
    console2.log();
    console2.log("= Collaterals", uint(portfolio.collaterals.length));
    uint totalValue = 0;
    for (uint i = 0; i < portfolio.collaterals.length; i++) {
      address asset = portfolio.collaterals[i].asset;
      console2.log(string.concat("=== asset (", assetLabel[asset], "):"), portfolio.collaterals[i].asset);
      _logBN(unicode"  ├ value:", portfolio.collaterals[i].value);
      _logBN(unicode"  └ minConfidence:", portfolio.collaterals[i].minConfidence);
      totalValue += portfolio.collaterals[i].value;
    }
    _logBN(unicode"= Total Collateral Value:", totalValue);

    console2.log();
    console2.log("Expiries", uint(portfolio.expiries.length));
    for (uint i = 0; i < portfolio.expiries.length; i++) {
      IPMRM_2.ExpiryHoldings memory expiry = portfolio.expiries[i];
      if (refTime > 0) {
        console2.log("=== secToExpiry (ref):", expiry.secToExpiry + (block.timestamp - refTime));
      } else {
        console2.log("=== secToExpiry:", expiry.secToExpiry);
      }

      for (uint j = 0; j < expiry.options.length; j++) {
        console2.log(string.concat(unicode"  ├─┬ ", expiry.options[j].isCall ? "CALL" : "PUT"));
        _logBN(unicode"  │ ├ strike:", expiry.options[j].strike);
        _logBN(unicode"  │ ├ amount:", expiry.options[j].amount);
        _logBN(unicode"  │ └ vol:", expiry.options[j].vol);
      }
      _logBN(unicode"  ├ forwardFixedPortion", expiry.forwardFixedPortion);
      _logBN(unicode"  ├ forwardVariablePortion", expiry.forwardVariablePortion);
      _logBN(unicode"  ├ rate", expiry.rate);
      _logBN(unicode"  ├ discount", uint(expiry.discount));
      _logBN(unicode"  ├ minConfidence", expiry.minConfidence);
      _logBN(unicode"  ├ netOptions", expiry.netOptions);
      _logBN(unicode"  ├ mtm", expiry.mtm);
      _logBN(unicode"  ├ basisScenarioUpMtM", expiry.basisScenarioUpMtM);
      _logBN(unicode"  ├ basisScenarioDownMtM", expiry.basisScenarioDownMtM);
      _logBN(unicode"  ├ volShockUp", expiry.volShockUp);
      _logBN(unicode"  ├ volShockDown", expiry.volShockDown);
      _logBN(unicode"  ├ staticDiscountPos", expiry.staticDiscountPos);
      _logBN(unicode"  └ staticDiscountNeg", expiry.staticDiscountNeg);
    }
  }

  function _logBN(string memory key, int value) internal view {
    console.log(key, _fromBN(value));
  }

  function _logBN(string memory key, uint value) internal view {
    console.log(key, _fromBN(value));
  }

  function _fromBN(int value) internal pure returns (string memory) {
    return string.concat(value < 0 ? "-" : "", convert18DecimalUintToString(value < 0 ? uint(-value) : uint(value)));
  }

  function _fromBN(uint value) internal pure returns (string memory) {
    return convert18DecimalUintToString(value);
  }

  function convert18DecimalUintToString(uint value) internal pure returns (string memory) {
    string memory integerPart = (value / 1e18).uintToString();
    uint fractionalValue = value % 1e18;
    if (fractionalValue == 0) {
      return integerPart; // No decimals needed
    }
    string memory fractionalPart = fractionalValue.uintToString();

    // Ensure leading zeros in the fractional part
    while (bytes(fractionalPart).length < 18) {
      fractionalPart = string.concat("0", fractionalPart);
    }

    return string.concat(integerPart, ".", fractionalPart);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";

import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/SecurityModule.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/assets/Option.sol";
import "src/assets/InterestRateModel.sol";
import "src/liquidation/DutchAuction.sol";
import "src/Accounts.sol";
import "src/risk-managers/SpotJumpOracle.sol";

import "test/feeds/mocks/MockV3Aggregator.sol";

import "src/interfaces/IPCRM.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev real Accounts contract
 * @dev real CashAsset contract
 * @dev real SecurityModule contract
 */
contract IntegrationTestBase is Test {
  address public constant liquidation = address(0xdead);
  uint public constant DEFAULT_DEPOSIT = 5000e18;
  int public constant ETH_PRICE = 2000e8;

  Accounts accounts;
  CashAsset cash;
  MockERC20 usdc;
  Option option;
  PCRM pcrm;
  SpotJumpOracle spotJumpOracle;
  SecurityModule securityModule;
  InterestRateModel rateModel;
  ChainlinkSpotFeeds feed;
  DutchAuction auction;
  MockV3Aggregator aggregator;

  // feedId of the aggregator
  uint feedId = 1;

  // sm account id will be 1 after setup
  uint smAcc = 1;

  // updatable
  uint pcrmFeeAcc;

  function _setupIntegrationTestComplete() internal {
    // deployment
    _deployAllV2Contracts();

    // necessary shared setup
    _finishContractSetups();
  }

  function _deployAllV2Contracts() internal {
    // nonce: 1 => Deploy Accounts
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    // nonce: 2 => Deploy USDC
    usdc = new MockERC20("USDC", "USDC");

    address addr2 = _predictAddress(address(this), 2);
    assertEq(addr2, address(usdc));

    // function call: doesn't increase deployment nonce
    usdc.setDecimals(6);

    // nonce: 3  => Deploy Feed
    feed = new ChainlinkSpotFeeds();
    address addr3 = _predictAddress(address(this), 3);
    assertEq(addr3, address(feed));

    // nonce: 4 => Deploy RateModel
    // deploy rate model
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = _getDefaultRateModelParam();
    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce: 5 => Deploy CashAsset
    address auctionAddr = _predictAddress(address(this), 9);
    cash = new CashAsset(accounts, usdc, rateModel, smAcc, auctionAddr);

    // nonce: 6 => Deploy OptionAsset
    option = new Option(accounts, address(feed), feedId);

    // nonce: 7 => deploy SpotJumpOracle
    (ISpotJumpOracle.JumpParams memory params, uint32[16] memory initialJumps) =
      _getDefaultSpotJumpParams(SafeCast.toUint256(ETH_PRICE));
    spotJumpOracle = new SpotJumpOracle(feed, feedId, params, initialJumps);

    // nonce: 8 => Deploy Manager
    pcrm = new PCRM(accounts, feed, cash, option, auctionAddr, spotJumpOracle);

    // nonce: 9 => Deploy Auction
    // todo: remove IPCRM(address())
    address smAddr = _predictAddress(address(this), 10);
    auction = new DutchAuction(IPCRM(address(pcrm)), accounts, ISecurityModule(smAddr), cash);

    assertEq(address(auction), auctionAddr);

    // nonce: 10 => Deploy SM
    securityModule = new SecurityModule(accounts, cash, usdc, IManager(address(pcrm)));

    assertEq(securityModule.accountId(), smAcc);
  }

  function _finishContractSetups() internal {
    // whitelist setting in cash asset and option assert
    cash.setWhitelistManager(address(pcrm), true);
    option.setWhitelistManager(address(pcrm), true);

    // PCRM setups
    pcrmFeeAcc = accounts.createAccount(address(this), pcrm);
    pcrm.setFeeRecipient(pcrmFeeAcc);
    (PCRM.SpotShockParams memory spot, PCRM.VolShockParams memory vol, PCRM.PortfolioDiscountParams memory discount) =
      _getDefaultPCRMParams();
    pcrm.setParams(spot, vol, discount);

    // add aggregator to feed
    aggregator = new MockV3Aggregator(8, 2000e8);
    uint _feedId = feed.addFeed("ETH/USD", address(aggregator), 1 hours);
    assertEq(feedId, _feedId);

    // set parameter for auction
    auction.setDutchAuctionParameters(_getDefaultAuctionParam());

    // todo: option asset whitelist
  }

  /**
   * @dev helper to mint USDC and deposit cash for account (from user)
   */
  function _depositCash(address user, uint acc, uint amountCash) internal {
    uint amountUSDC = amountCash / 1e12;
    usdc.mint(user, amountUSDC);

    vm.startPrank(user);
    usdc.approve(address(cash), type(uint).max);
    cash.deposit(acc, amountUSDC);
    vm.stopPrank();
  }

  /**
   * @dev helper to withdraw (or borrow) cash for account (from user)
   */
  function _withdrawCash(address user, uint acc, uint amountCash) internal {
    uint amountUSDC = amountCash / 1e12;
    vm.startPrank(user);
    cash.withdraw(acc, amountUSDC, user);
    vm.stopPrank();
  }

  function _submitTrade(
    uint accA,
    IAsset assetA,
    uint96 subIdA,
    int amountA,
    uint accB,
    IAsset assetB,
    uint subIdB,
    int amountB
  ) internal {
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    // accA transfer asset A to accB
    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: accA,
      toAcc: accB,
      asset: assetA,
      subId: subIdA,
      amount: amountA,
      assetData: bytes32(0)
    });

    // accB transfer asset B to accA
    transferBatch[1] = AccountStructs.AssetTransfer({
      fromAcc: accB,
      toAcc: accA,
      asset: assetB,
      subId: subIdB,
      amount: amountB,
      assetData: bytes32(0)
    });

    accounts.submitTransfers(transferBatch, "");
  }

  /**
   * @dev set current price of aggregator
   * @param price price in 18 decimals
   */
  function _setSpotPriceE18(int price) internal {
    uint80 round = 1;
    int answerE8 = price / 1e10;
    aggregator.updateRoundData(round, answerE8, block.timestamp, block.timestamp, round);
  }

  /**
   * @dev set current price of aggregator, and report as settlement price at {expiry}
   * @param price price in 18 decimals
   */
  function _setSpotPriceAndSubmitForExpiry(int price, uint expiry) internal {
    _setSpotPriceE18(price);
    option.setSettlementPrice(expiry);
  }

  function _assertCashSolvent() internal {
    // exchange rate should be >= 1
    assertGe(cash.getCashToStableExchangeRate(), 1e18);
  }

  /**
   * @dev view function to help writing integration test
   */
  function getCashBalance(uint acc) public view returns (int) {
    return accounts.getBalance(acc, cash, 0);
  }

  /**
   * @dev view function to help writing integration test
   */
  function getOptionBalance(uint acc, uint96 subId) public view returns (int) {
    return accounts.getBalance(acc, option, subId);
  }

  function getAccInitMargin(uint acc) public returns (int) {
    PCRM.Portfolio memory portfolio = pcrm.getPortfolio(acc);
    return pcrm.getInitialMargin(portfolio);
  }

  function getAccMaintenanceMargin(uint acc) public returns (int) {
    PCRM.Portfolio memory portfolio = pcrm.getPortfolio(acc);
    return pcrm.getMaintenanceMargin(portfolio);
  }

  /**
   * @dev helper to update spot prices
   */
  function _updatePriceFeed(int spotPrice, uint80 roundId, uint80 answeredInRound) internal {
    aggregator.updateRoundData(roundId, spotPrice, block.timestamp, block.timestamp, answeredInRound);
  }

  /**
   * @dev default parameters for rate model
   */
  function _getDefaultRateModelParam()
    internal
    pure
    returns (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil)
  {
    minRate = 0.06 * 1e18;
    rateMultiplier = 0.2 * 1e18;
    highRateMultiplier = 0.4 * 1e18;
    optimalUtil = 0.6 * 1e18;
  }

  function _getDefaultPCRMParams()
    internal
    pure
    returns (
      PCRM.SpotShockParams memory spot,
      PCRM.VolShockParams memory vol,
      PCRM.PortfolioDiscountParams memory discount
    )
  {
    spot = PCRM.SpotShockParams({
      upInitial: 1.25e18,
      downInitial: 0.75e18,
      upMaintenance: 1.1e18,
      downMaintenance: 0.9e18,
      timeSlope: 1e18,
      spotJumpMultipleSlope: 5e18,
      spotJumpMultipleLookback: 1 days
    });

    vol = PCRM.VolShockParams({
      minVol: 1e18,
      maxVol: 3e18,
      timeA: 30 days,
      timeB: 90 days,
      spotJumpMultipleSlope: 5e18,
      spotJumpMultipleLookback: 1 days
    });

    discount = PCRM.PortfolioDiscountParams({
      maintenance: 0.9e18, // 90%
      initial: 0.8e18, // 80%
      riskFreeRate: 0.1e18 // 10%
    });
  }

  function _getDefaultSpotJumpParams(uint initialSpot)
    internal
    pure
    returns (ISpotJumpOracle.JumpParams memory params, uint32[16] memory initialJumps)
  {
    params = ISpotJumpOracle.JumpParams({
      start: 500,
      width: 250,
      referenceUpdatedAt: 0,
      secToReferenceStale: 1 days,
      referencePrice: SafeCast.toUint128(initialSpot)
    });

    return (params, initialJumps);
  }

  function _getDefaultAuctionParam() internal pure returns (DutchAuction.DutchAuctionParameters memory param) {
    param = DutchAuction.DutchAuctionParameters({
      stepInterval: 2,
      lengthOfAuction: 200,
      portfolioModifier: 1e18,
      inversePortfolioModifier: 1e18,
      secBetweenSteps: 1, // cool down
      liquidatorFeeRate: 0.05e18
    });
  }

  /**
   * @dev predict the address of the next contract being deployed
   */
  function _predictAddress(address _origin, uint _nonce) public pure returns (address) {
    if (_nonce == 0x00) {
      return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80))))));
    }
    if (_nonce <= 0x7f) {
      return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce))))));
    }
    if (_nonce <= 0xff) {
      return address(
        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)))))
      );
    }
    if (_nonce <= 0xffff) {
      return address(
        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)))))
      );
    }
    if (_nonce <= 0xffffff) {
      return address(
        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)))))
      );
    }
    return address(
      uint160(uint(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce)))))
    );
  }

  /**
   * for coverage to ignore
   */
  function test() public {}
}

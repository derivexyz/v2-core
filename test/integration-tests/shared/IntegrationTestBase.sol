//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.18;
//
//import "forge-std/Test.sol";
//
//import "../../shared/mocks/MockERC20.sol";
//
//import "src/SecurityModule.sol";
//import "src/assets/CashAsset.sol";
//import "src/assets/Option.sol";
//import "src/assets/InterestRateModel.sol";
//import "src/liquidation/DutchAuction.sol";
//import "src/Accounts.sol";
//
//import {IManager} from "src/interfaces/IManager.sol";
//import "../../../src/risk-managers/PMRM.sol";
//import "../../shared/mocks/MockFeeds.sol";
//
///**
// * @dev real Accounts contract
// * @dev real CashAsset contract
// * @dev real SecurityModule contract
// */
//contract IntegrationTestBase is Test {
//  address alice = address(0xace);
//  address bob = address(0xb0b);
//  uint aliceAcc;
//  uint bobAcc;
//
//  address public constant liquidation = address(0xdead);
//  uint public constant DEFAULT_DEPOSIT = 5000e18;
//  int public constant ETH_PRICE = 2000e18;
//
//  Accounts accounts;
//  CashAsset cash;
//  MockERC20 usdc;
//  Option option;
//  PMRM pmrm;
//  SecurityModule securityModule;
//  InterestRateModel rateModel;
//  DutchAuction auction;
//  MockFeeds feed;
//
//  // sm account id will be 1 after setup
//  uint smAcc = 1;
//
//  // updatable
//  uint pmrmFeeAcc;
//
//  function _setupIntegrationTestComplete() internal {
//    // deployment
//    _deployAllV2Contracts();
//
//    // necessary shared setup
//    _finishContractSetups();
//
//    _setupAliceAndBob();
//  }
//
//  function _setupAliceAndBob() internal {
//    vm.label(alice, "alice");
//    vm.label(bob, "bob");
//
//    aliceAcc = accounts.createAccount(alice, pmrm);
//    bobAcc = accounts.createAccount(bob, pmrm);
//
//    // allow this contract to submit trades
//    vm.prank(alice);
//    accounts.setApprovalForAll(address(this), true);
//    vm.prank(bob);
//    accounts.setApprovalForAll(address(this), true);
//  }
//
//  function _deployAllV2Contracts() internal {
//    // nonce: 1 => Deploy Accounts
//    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
//
//    // nonce: 2 => Deploy USDC
//    usdc = new MockERC20("USDC", "USDC");
//
//    address addr2 = _predictAddress(address(this), 2);
//    assertEq(addr2, address(usdc));
//
//    // function call: doesn't increase deployment nonce
//    usdc.setDecimals(6);
//
//    // nonce: 4 => Deploy Feed that will be used as future price and settlement price
//    feed = new MockFeeds();
//
//    // nonce: 5 => Deploy RateModel
//    // deploy rate model
//    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = _getDefaultRateModelParam();
//    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);
//
//    // nonce: 6 => Deploy CashAsset
//    address auctionAddr = _predictAddress(address(this), 10);
//    cash = new CashAsset(accounts, usdc, rateModel, smAcc, auctionAddr);
//
//    // nonce: 7 => Deploy OptionAsset
//    option = new Option(accounts, address(feed));
//
//
//
//    skip(7 days); // skip to make jumps stale
//
//    // nonce: 9 => Deploy Manager
//    pmrm = new PMRM(
//      accounts,
//      ICashAsset(address(cash)),
//      option,
//      IPerpAsset(address(mockPerp)),
//      IOptionPricing(optionPricing),
//      baseAsset,
//      IPMRM.Feeds({
//        spotFeed: ISpotFeed(feed),
//        stableFeed: ISpotFeed(stableFeed),
//        forwardFeed: IForwardFeed(feed),
//        interestRateFeed: IInterestRateFeed(feed),
//        volFeed: IVolFeed(feed),
//        settlementFeed: ISettlementFeed(feed)
//      })
//    );
//
//    // nonce: 10 => Deploy Auction
//    // todo: remove Ipmrm(address())
//    address smAddr = _predictAddress(address(this), 11);
//    auction = new DutchAuction(Ipmrm(address(pmrm)), accounts, ISecurityModule(smAddr), cash);
//
//    assertEq(address(auction), auctionAddr);
//
//    // nonce: 11 => Deploy SM
//    securityModule = new SecurityModule(accounts, cash, usdc, Ipmrm(address(pmrm)));
//
//    assertEq(securityModule.accountId(), smAcc);
//  }
//
//  function _finishContractSetups() internal {
//    // set aggregator again to update "updatedAt" in oracle, avoid stale reverts
//    _setSpotPriceE18(ETH_PRICE);
//
//    // whitelist setting in cash asset and option assert
//    cash.setWhitelistManager(address(pmrm), true);
//    option.setWhitelistManager(address(pmrm), true);
//
//    // pmrm setups
//    pmrmFeeAcc = accounts.createAccount(address(this), pmrm);
//    pmrm.setFeeRecipient(pmrmFeeAcc);
//
//    // set parameter for auction
//    auction.setDutchAuctionParameters(_getDefaultAuctionParam());
//
//    // allow liquidation to request payout from sm
//    securityModule.setWhitelistModule(address(auction), true);
//  }
//
//  /**
//   * @dev helper to mint USDC and deposit cash for account (from user)
//   */
//  function _depositCash(address user, uint acc, uint amountCash) internal {
//    uint amountUSDC = amountCash / 1e12;
//    usdc.mint(user, amountUSDC);
//
//    vm.startPrank(user);
//    usdc.approve(address(cash), type(uint).max);
//    cash.deposit(acc, amountUSDC);
//    vm.stopPrank();
//  }
//
//  /**
//   * @dev helper to withdraw (or borrow) cash for account (from user)
//   */
//  function _withdrawCash(address user, uint acc, uint amountCash) internal {
//    uint amountUSDC = amountCash / 1e12;
//    vm.startPrank(user);
//    cash.withdraw(acc, amountUSDC, user);
//    vm.stopPrank();
//  }
//
//  function _submitTrade(
//    uint accA,
//    IAsset assetA,
//    uint96 subIdA,
//    int amountA,
//    uint accB,
//    IAsset assetB,
//    uint subIdB,
//    int amountB
//  ) internal {
//    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](2);
//
//    // accA transfer asset A to accB
//    transferBatch[0] = IAccounts.AssetTransfer({
//      fromAcc: accA,
//      toAcc: accB,
//      asset: assetA,
//      subId: subIdA,
//      amount: amountA,
//      assetData: bytes32(0)
//    });
//
//    // accB transfer asset B to accA
//    transferBatch[1] = IAccounts.AssetTransfer({
//      fromAcc: accB,
//      toAcc: accA,
//      asset: assetB,
//      subId: subIdB,
//      amount: amountB,
//      assetData: bytes32(0)
//    });
//
//    accounts.submitTransfers(transferBatch, "");
//  }
//
//  function _depositSecurityModule(address user, uint amountCash) internal {
//    uint amountUSDC = amountCash / 1e12;
//    usdc.mint(user, amountUSDC);
//
//    vm.startPrank(user);
//    usdc.approve(address(securityModule), type(uint).max);
//    securityModule.deposit(amountUSDC);
//    vm.stopPrank();
//  }
//
//  /**
//   * @dev set current price of aggregator
//   * @param price price in 18 decimals
//   */
//  function _setSpotPriceE18(int price) internal {
//    uint80 round = 1;
//    // convert to chainlink decimals
//    int answerE8 = price / 1e10;
//    aggregator.updateRoundData(round, answerE8, block.timestamp, block.timestamp, round);
//  }
//
//  /**
//   * @dev set future price for feed
//   * @param price price in 18 decimals
//   */
//  function _setForwardPrice(uint, /*expiry*/ int price) internal {
//    // currently the same as set spot price
//    _setSpotPriceE18(price);
//  }
//
//  /**
//   * @dev set current price of aggregator, and report as settlement price at {expiry}
//   * @param price price in 18 decimals
//   */
//  function _setSpotPriceAndSubmitForExpiry(int price, uint expiry) internal {
//    _setSpotPriceE18(price);
//
//    feed.setSettlementPrice(expiry);
//  }
//
//  /**
//   * @dev trigger jump update
//   */
//  function _updateJumps() internal {
//    spotJumpOracle.updateJumps();
//  }
//
//  function _assertCashSolvent() internal {
//    // exchange rate should be >= 1
//    assertGe(cash.getCashToStableExchangeRate(), 1e18);
//  }
//
//  /**
//   * @dev view function to help writing integration test
//   */
//  function getCashBalance(uint acc) public view returns (int) {
//    return accounts.getBalance(acc, cash, 0);
//  }
//
//  /**
//   * @dev view function to help writing integration test
//   */
//  function getOptionBalance(uint acc, uint96 subId) public view returns (int) {
//    return accounts.getBalance(acc, option, subId);
//  }
//
//  function getAccInitMargin(uint acc) public view returns (int) {
//    return pmrm.getMargin(acc, true);
//  }
//
//  function getAccMaintenanceMargin(uint acc) public view returns (int) {
//    return pmrm.getMargin(acc, false);
//  }
//
//  /**
//   * @dev helper to update spot prices
//   */
//  function _updatePriceFeed(int spotPrice, uint80 roundId, uint80 answeredInRound) internal {
//    aggregator.updateRoundData(roundId, spotPrice, block.timestamp, block.timestamp, answeredInRound);
//  }
//
//  /**
//   * @dev default parameters for rate model
//   */
//  function _getDefaultRateModelParam()
//    internal
//    pure
//    returns (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil)
//  {
//    minRate = 0.06 * 1e18;
//    rateMultiplier = 0.2 * 1e18;
//    highRateMultiplier = 0.4 * 1e18;
//    optimalUtil = 0.6 * 1e18;
//  }
//
//  function _getDefaultAuctionParam() internal pure returns (DutchAuction.DutchAuctionParameters memory param) {
//    param = DutchAuction.DutchAuctionParameters({
//      stepInterval: 2,
//      lengthOfAuction: 200,
//      secBetweenSteps: 1, // cool down
//      liquidatorFeeRate: 0.05e18
//    });
//  }
//
//  /**
//   * @dev predict the address of the next contract being deployed
//   */
//  function _predictAddress(address _origin, uint _nonce) public pure returns (address) {
//    if (_nonce == 0x00) {
//      return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80))))));
//    }
//    if (_nonce <= 0x7f) {
//      return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce))))));
//    }
//    if (_nonce <= 0xff) {
//      return address(
//        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)))))
//      );
//    }
//    if (_nonce <= 0xffff) {
//      return address(
//        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)))))
//      );
//    }
//    if (_nonce <= 0xffffff) {
//      return address(
//        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)))))
//      );
//    }
//    return address(
//      uint160(uint(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce)))))
//    );
//  }
//
//  function _getForwardPrice(uint expiry) internal view returns (uint forwardPrice) {
//    (forwardPrice,) = feed.getForwardPrice(expiry);
//    return forwardPrice;
//  }
//
//  /**
//   * for coverage to ignore
//   */
//  function test() public {}
//}

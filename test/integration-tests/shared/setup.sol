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

  Accounts accounts;
  CashAsset cashAsset;
  MockERC20 usdc;
  Option option;
  PCRM pcrm;
  SecurityModule securityModule;
  InterestRateModel rateModel;
  ChainlinkSpotFeeds feed;
  DutchAuction auction;
  MockV3Aggregator aggregator;

  uint smAccId;
  uint accountId;

  // need to add feed
  uint feedId = 1;
  
  // sm need to be the first one create an account
  uint smAccountId = 1;
  

  function deployAllV2Contracts() public {
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
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = _getDefaultRateModuleParam();
    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce: 5 => Deploy CashAsset
    address auctionAddr = _predictAddress(address(this), 8);
    cashAsset = new CashAsset(accounts, usdc, rateModel, smAccountId, auctionAddr);
    
    // nonce: 6 => Deploy OptionAsset
    option = new Option(accounts, address(feed), feedId);

    // nonce: 7 => Deploy Manager
    pcrm = new PCRM(accounts, feed, cashAsset, option, auctionAddr);

    // nonce: 8 => Deploy Auction
    // todo: remove IPCRM(address())
    address smAddr = _predictAddress(address(this), 9); 
    auction = new DutchAuction(IPCRM(address(pcrm)), accounts, ISecurityModule(smAddr), cashAsset);

    assertEq(address(auction), auctionAddr);

    // nonce: 9 => Deploy SM
    securityModule = new SecurityModule(accounts, cashAsset, usdc, IManager(address(pcrm)));

    assertEq(securityModule.accountId(), smAccountId);

    // finish misc settings on permission ...etc
    _finishContractSetups();
  }

  function _finishContractSetups() internal {
    cashAsset.setWhitelistManager(address(pcrm), true);

    aggregator = new MockV3Aggregator(8, 2000e8);
    uint _feedId = feed.addFeed("ETH/USD", address(aggregator), 1 hours);
    assertEq(feedId, _feedId);
  }

  function _getDefaultRateModuleParam() internal returns (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) {
    minRate = 0.06 * 1e18;
    rateMultiplier = 0.2 * 1e18;
    highRateMultiplier = 0.4 * 1e18;
    optimalUtil = 0.6 * 1e18;
  }

  /**
   * predict the address of the next contract being deployed
   */
  function _predictAddress(address _origin, uint256 _nonce) public pure returns (address) {
      if (_nonce == 0x00) {
          return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80))))));
      }
      if (_nonce <= 0x7f) {
          return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce))))));
      }
      if (_nonce <= 0xff) {
          return address(
              uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)))))
          );
      }
      if (_nonce <= 0xffff) {
          return address(
              uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)))))
          );
      }
      if (_nonce <= 0xffffff) {
          return address(
              uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)))))
          );
      }
      return address(
          uint160(uint256(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce)))))
      );
  }

  function test() public {}
}

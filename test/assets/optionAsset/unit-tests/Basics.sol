// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/assets/Option.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";

import "test/shared/mocks/MockManager.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

contract UNIT_TestOptionBasics is Test {
  Accounts account;
  MockManager manager;

  Option option;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    option = new Option(account, address(0));
    manager = new MockManager(address(account));

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
    bobAcc = account.createAccount(bob, IManager(manager));
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();
  }

  //////////////
  // Transfer //
  //////////////

  function testWhitelistedManagerCheck() public {
    option.setWhitelistManager(address(manager), true);

    vm.startPrank(alice);
    IAccounts.AssetTransfer memory assetTransfer = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(assetTransfer, "");
    vm.stopPrank();
  }

  function testUnWhitelistedManagerCheck() public {
    vm.startPrank(alice);
    IAccounts.AssetTransfer memory assetTransfer = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });

    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);
    account.submitTransfer(assetTransfer, "");
    vm.stopPrank();
  }

  function testValidSubIdCheck() public {
    // todo: test out of bounds subId
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    /* ensure account holds asset before manager changed*/
    option.setWhitelistManager(address(manager), true);

    vm.startPrank(alice);
    IAccounts.AssetTransfer memory assetTransfer = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(assetTransfer, "");
    vm.stopPrank();

    MockManager newManager = new MockManager(address(account));

    // whitelist new manager
    option.setWhitelistManager(address(newManager), true);

    vm.startPrank(alice);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
  }

  function testInvalidManagerChange() public {
    /* ensure account holds asset before manager changed*/
    option.setWhitelistManager(address(manager), true);

    vm.startPrank(alice);
    IAccounts.AssetTransfer memory assetTransfer = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(assetTransfer, "");
    MockManager newManager = new MockManager(address(account));

    // new manager not whitelisted
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();
  }

  ///////////
  // Utils //
  ///////////

  function testDecodeSubId() public {
    uint expiry = block.timestamp + 3 days;
    uint strike = 1234e18;
    bool isCall = false;
    uint96 trueSubId = OptionEncoding.toSubId(expiry, strike, isCall);

    (uint rExpiry, uint rStrike, bool rIsCall) = option.getOptionDetails(trueSubId);
    assertEq(expiry, rExpiry);
    assertEq(strike, rStrike);
    assertEq(isCall, rIsCall);
  }

  function testEncodeSubId() public {
    // 1 mo, $10k strike, call
    uint expiry = block.timestamp + 30 days;
    uint strike = 10_000e18;
    bool isCall = true;
    uint96 trueSubId = OptionEncoding.toSubId(expiry, strike, isCall);
    uint96 returnedSubId = option.getSubId(expiry, strike, true);

    assertEq(trueSubId, returnedSubId);
  }
}

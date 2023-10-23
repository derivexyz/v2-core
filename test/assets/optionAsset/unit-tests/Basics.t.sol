// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../../../src/assets/OptionAsset.sol";
import "../../../../src/SubAccounts.sol";
import {IManager} from "../../../../src/interfaces/IManager.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";

import {IManagerWhitelist} from "../../../../src/interfaces/IManagerWhitelist.sol";
import {IAllowances} from "../../../../src/interfaces/IAllowances.sol";

import "test/shared/mocks/MockManager.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

contract UNIT_TestOptionBasics is Test {
  SubAccounts subAccounts;
  MockManager manager;

  OptionAsset option;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    option = new OptionAsset(subAccounts, address(0));
    manager = new MockManager(address(subAccounts));

    vm.startPrank(alice);
    aliceAcc = subAccounts.createAccount(alice, IManager(manager));
    bobAcc = subAccounts.createAccount(bob, IManager(manager));
    vm.stopPrank();

    vm.startPrank(bob);
    subAccounts.approve(alice, bobAcc);
    vm.stopPrank();
  }

  //////////////
  // Transfer //
  //////////////

  function testWhitelistedManagerCheck() public {
    option.setWhitelistManager(address(manager), true);

    vm.startPrank(alice);
    ISubAccounts.AssetTransfer memory assetTransfer = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    subAccounts.submitTransfer(assetTransfer, "");
    vm.stopPrank();
  }

  function testUnWhitelistedManagerCheck() public {
    vm.startPrank(alice);
    ISubAccounts.AssetTransfer memory assetTransfer = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });

    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);
    subAccounts.submitTransfer(assetTransfer, "");
    vm.stopPrank();
  }

  function testCannotTransferPositiveBalanceWithoutApproval() public {
    option.setWhitelistManager(address(manager), true);
    // bob cannot transfer to alice
    vm.prank(bob);
    ISubAccounts.AssetTransfer memory assetTransfer = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });

    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, bob, aliceAcc, 1e18, 0, 0)
    );
    subAccounts.submitTransfer(assetTransfer, "");
  }

  function testValidSubIdCheck() public {
    // todo: test out of bounds subId
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

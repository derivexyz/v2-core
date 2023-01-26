// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../../src/assets/Option.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev testing open interest before and after
 * asset transfers
 * single side adjustments
 */
contract UNIT_OptionAssetOITest is Test {
  Option option;
  MockManager manager;
  Accounts account;

  uint accountId;

  uint depositedAmount = 10000 ether;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    option = new Option();

    accountId = account.createAccount(address(this), manager);
  }

  /* --------------------- *
   |      Transfers        *
   * --------------------- */

  function testNormalTransfersBetweenPositiveAccountDoesntAffectOI() public {}
}

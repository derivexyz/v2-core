// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import {IPMRM} from "../../../../src/interfaces/IPMRM.sol";
import {MockManager} from "../../../shared/mocks/MockManager.sol";
import {MockOption} from "../../../shared/mocks/MockOptionAsset.sol";

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";

contract UNIT_TestPMRM_Misc is PMRMSimTest {
  function testCannotChangeFromBadManagerWithInvalidAsset() public {
    // create accounts with bad manager
    MockManager badManager = new MockManager(address(subAccounts));
    MockOption badAsset = new MockOption(subAccounts);
    uint badAcc = subAccounts.createAccount(address(this), badManager);
    uint badAcc2 = subAccounts.createAccount(address(this), badManager);

    // create bad positions
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: badAcc,
      toAcc: badAcc2,
      asset: badAsset,
      subId: 0,
      amount: 100e18,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");

    // alice migrate to a our pmrm
    vm.expectRevert(IPMRM.PMRM_UnsupportedAsset.selector);
    subAccounts.changeManager(badAcc, pmrm, "");
  }
}

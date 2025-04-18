// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/periphery/PerpSettlementHelper.sol";
import "../../../../src/periphery/OptionSettlementHelper.sol";

import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2TestBase.sol";

import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

contract TestPMRM_2_Settlement is PMRM_2TestBase {
  PerpSettlementHelper perpHelper;
  OptionSettlementHelper optionHelper;

  constructor() {
    perpHelper = new PerpSettlementHelper();
    optionHelper = new OptionSettlementHelper();
  }

  function setUp() public override {
    super.setUp();
    pmrm_2.setWhitelistedCallee(address(perpHelper), true);
    pmrm_2.setWhitelistedCallee(address(optionHelper), true);
  }

  function testCanSettlePerps() public {
    int cashBefore = _getCashBalance(aliceAcc);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    pmrm_2.settlePerpsWithIndex(aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 100e18);
  }

  function testCanSettleWithManagerData() public {
    int cashBefore = _getCashBalance(aliceAcc);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    bytes memory data = abi.encode(address(pmrm_2), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(perpHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    // only transfer 0 cash
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    subAccounts.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 100e18);
  }

  function testCanSettleOptions() public {
    _depositCash(aliceAcc, 2000e18);

    _tradeOptionAndMockSettlementValue(-500e18);

    int cashBefore = _getCashBalance(aliceAcc);

    pmrm_2.settleOptions(option, aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCanSettleOptionWithManagerData() public {
    _depositCash(aliceAcc, 2000e18);

    _tradeOptionAndMockSettlementValue(-500e18);

    int cashBefore = _getCashBalance(aliceAcc);

    // prepare manager data
    bytes memory data = abi.encode(address(pmrm_2), address(option), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(optionHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    subAccounts.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCannotCallUnWhitelistedContractInProcessManagerData() public {
    pmrm_2.setWhitelistedCallee(address(optionHelper), false);

    _depositCash(aliceAcc, 2000e18);

    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(optionHelper), data: ""});
    bytes memory managerData = abi.encode(allData);

    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});

    vm.expectRevert(IBaseManager.BM_UnauthorizedCall.selector);
    subAccounts.submitTransfer(transfer, managerData);
  }

  function testCanSettleOptionWithBadAddress() public {
    vm.expectRevert(IPMRM_2.PMRM_2_UnsupportedAsset.selector);
    pmrm_2.settleOptions(IOptionAsset(address(mockPerp)), aliceAcc);
  }

  function _tradeOptionAndMockSettlementValue(int netValue) internal {
    uint expiry = block.timestamp + 1 days;
    uint strike = 2000e18;

    _transferOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);

    uint subId = OptionEncoding.toSubId(expiry, strike, true);

    option.setMockedSubIdSettled(subId, true);
    option.setMockedTotalSettlementValue(subId, netValue);
  }

  function _transferOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }
}

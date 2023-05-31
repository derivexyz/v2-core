pragma solidity ^0.8.18;

import "src/periphery/PerpSettlementHelper.sol";
import "src/periphery/OptionSettlementHelper.sol";

import "test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

import "forge-std/console2.sol";

contract TestPMRM_Settlement is PMRMTestBase {
  PerpSettlementHelper perpHelper;
  OptionSettlementHelper optionHelper;

  constructor() {
    perpHelper = new PerpSettlementHelper();
    optionHelper = new OptionSettlementHelper();
  }

  function testCanSettlePerps() public {
    int cashBefore = _getCashBalance(aliceAcc);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    pmrm.settlePerpsWithIndex(mockPerp, aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 100e18);
  }

  function testCanSettleWithManagerData() public {
    int cashBefore = _getCashBalance(aliceAcc);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    bytes memory data = abi.encode(address(pmrm), address(mockPerp), aliceAcc);
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

  function testCanSettlePerpWithBadAddress() public {
    vm.expectRevert(IPMRM.PMRM_UnsupportedAsset.selector);
    pmrm.settlePerpsWithIndex(IPerpAsset(address(option)), aliceAcc);
  }

  function testCanSettleOptions() public {
    _depositCash(aliceAcc, 2000e18);

    _tradeOptionAndMockSettlementValue(-500e18);

    int cashBefore = _getCashBalance(aliceAcc);

    pmrm.settleOptions(option, aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCanSettleOptionWithManagerData() public {
    _depositCash(aliceAcc, 2000e18);

    _tradeOptionAndMockSettlementValue(-500e18);

    int cashBefore = _getCashBalance(aliceAcc);

    // prepare manager data
    bytes memory data = abi.encode(address(pmrm), address(option), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(optionHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    subAccounts.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCanSettleOptionWithBadAddress() public {
    vm.expectRevert(IPMRM.PMRM_UnsupportedAsset.selector);
    pmrm.settleOptions(IOption(address(mockPerp)), aliceAcc);
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

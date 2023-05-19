pragma solidity ^0.8.18;

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";
import "src/risk-managers/SettlementHelper.sol";

contract TestPMRM_SettlePerp is PMRMTestBase {
  SettlementHelper settlementHelper;

  constructor() {
    settlementHelper = new SettlementHelper();
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
    allData[0] = IBaseManager.ManagerData({receiver: address(settlementHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    // only transfer 0 cash
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    accounts.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 100e18);
  }
}

pragma solidity ^0.8.18;

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract TestPMRM_OIFee is PMRMTestBase {
  function testChargeOIFees() public {
    _depositCash(aliceAcc, 20000e18); // trade id = 1
    pmrm.setOIFeeRateBPS(0.001e18);

    uint expiry = block.timestamp + 1 days;
    uint strike = 3000e18;

    feed.setForwardPrice(expiry, 2000e18, 1e18);

    uint tradeId = 2;
    uint subId = OptionEncoding.toSubId(expiry, strike, true);
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 0);
    option.setMockedOI(subId, 10e18); // total oi increase 10!

    _transferOption(aliceAcc, bobAcc, 10e18, expiry, strike, true);

    // 2000 * 10 * 0.001 = 20
    int feePerPerson = 20e18;

    assertEq(_getCashBalance(feeRecipient), feePerPerson * 2);

    // oi fee is not considered as delta change, so bob is "risk reducing" only
    assertEq(_getCashBalance(bobAcc), -feePerPerson);
  }

  function _transferOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
    IAccounts.AssetTransfer memory transfer = IAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    accounts.submitTransfer(transfer, "");
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../shared/IntegrationTestBase.t.sol";
import {IManager} from "../../../../src/interfaces/IManager.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_MultiwayTradeTest is IntegrationTestBase {
  using DecimalMath for uint;

  address charlie = address(0xcc);
  uint charlieAcc;
  address dave = address(0xcc);
  uint daveAcc;

  int amountOfContracts = 1e18;

  IOption option;

  uint64 expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), srm);
    daveAcc = subAccounts.createAccountWithApproval(dave, address(this), srm);

    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
    _depositCash(address(charlie), charlieAcc, DEFAULT_DEPOSIT);
    _depositCash(address(dave), daveAcc, DEFAULT_DEPOSIT);

    option = markets["weth"].option;

    expiry = uint64(block.timestamp + 4 weeks);

    _setForwardPrice("weth", expiry, uint(ETH_PRICE), 1e18);
    _setDefaultSVIForExpiry("weth", expiry);
    _setInterestRate("weth", expiry, 0, 1e18);
  }

  function testThreeWayTradeNoOIFee() public {
    uint callStrike = 2000e18;
    uint callId = getSubId(expiry, callStrike, true);

    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](3);

    // Alice transfer to Bob
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Charlie transfer to Alice (closing the loop)
    transferBatch[2] = ISubAccounts.AssetTransfer({
      fromAcc: charlieAcc,
      toAcc: aliceAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // After all transfers no oi fee charged since option goes back to alice
    subAccounts.submitTransfers(transferBatch, "");
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();

    assertEq(uint(aliceBal), DEFAULT_DEPOSIT);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT);
  }

  function testThreeWayTradeITMCall() public {
    uint oiFee = (portfolioViewer.OIFeeRateBPS(address(option))).multiplyDecimal(_getSpot());

    // ATM Call
    uint callStrike = 2000e18;
    uint callId = getSubId(expiry, callStrike, true);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);

    // Alice transfer to Bob
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");

    vm.warp(expiry);
    int priceIncrease = 1000e18;

    _updateAllFeeds(uint(ETH_PRICE + priceIncrease));

    srm.settleOptions(option, aliceAcc);
    srm.settleOptions(option, bobAcc);
    srm.settleOptions(option, charlieAcc);

    // Alice's loss should be charlies gain
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT - uint(priceIncrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT + uint(priceIncrease) - oiFee);
  }

  function testThreeWayTradeITMPut() public {
    uint oiFee = (portfolioViewer.OIFeeRateBPS(address(option))).multiplyDecimal(_getSpot());

    uint putStrike = 2000e18;
    uint putId = getSubId(expiry, putStrike, false);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);

    // Alice transfer to Bob
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: putId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: putId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");

    vm.warp(expiry);

    int priceDecrease = 1000e18;
    _updateAllFeeds(uint(ETH_PRICE - priceDecrease));

    srm.settleOptions(option, aliceAcc);
    srm.settleOptions(option, bobAcc);
    srm.settleOptions(option, charlieAcc);

    // Alice's loss should be charlies gain
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();

    assertEq(uint(aliceBal), DEFAULT_DEPOSIT - uint(priceDecrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT + uint(priceDecrease) - oiFee);
  }

  function testThreeWayTradeOTMCall() public {
    uint oiFee = (portfolioViewer.OIFeeRateBPS(address(option))).multiplyDecimal(_getSpot());
    int premium = 1000e18;

    // ATM Call
    uint callStrike = 2000e18;
    uint callId = getSubId(expiry, callStrike, true);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal,) = _getAllCashBalances();

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](4);

    // Alice transfer option to Bob for premium
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: cash,
      subId: 0,
      amount: premium,
      assetData: bytes32(0)
    });

    // Bob transfers same option to Charlie for premium
    transferBatch[2] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    transferBatch[3] = ISubAccounts.AssetTransfer({
      fromAcc: charlieAcc,
      toAcc: bobAcc,
      asset: cash,
      subId: 0,
      amount: premium,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");
    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);

    // Settle OTM
    vm.warp(expiry);

    int priceDecrease = 1000e18;
    _updateAllFeeds(uint(ETH_PRICE - priceDecrease));

    srm.settleOptions(option, aliceAcc);
    srm.settleOptions(option, bobAcc);
    srm.settleOptions(option, charlieAcc);

    // Balances remain the same as options expire worthless
    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);
  }

  function testThreeWayTradeOTMPut() public {
    uint oiFee = (portfolioViewer.OIFeeRateBPS(address(option))).multiplyDecimal(_getSpot());
    int premium = 1000e18;

    // ATM Put
    uint putStrike = 2000e18;
    uint putId = getSubId(expiry, putStrike, false);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal,) = _getAllCashBalances();

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](4);

    // Alice transfer option to Bob for premium
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: putId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: cash,
      subId: 0,
      amount: premium,
      assetData: bytes32(0)
    });

    // Bob transfers same option to Charlie for premium
    transferBatch[2] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: putId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    transferBatch[3] = ISubAccounts.AssetTransfer({
      fromAcc: charlieAcc,
      toAcc: bobAcc,
      asset: cash,
      subId: 0,
      amount: premium,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");
    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);

    // Settle OTM
    vm.warp(expiry);

    int priceIncrease = 1000e18;
    _updateAllFeeds(uint(ETH_PRICE + priceIncrease));

    srm.settleOptions(option, aliceAcc);
    srm.settleOptions(option, bobAcc);
    srm.settleOptions(option, charlieAcc);

    // Balances remain the same as options expire worthless
    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);
  }

  function testFourWayTradeITMCall() public {
    uint oiFee = (portfolioViewer.OIFeeRateBPS(address(option))).multiplyDecimal(_getSpot());

    // ATM Call
    uint callStrike = 2000e18;
    uint callId = getSubId(expiry, callStrike, true);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](3);

    // Alice transfer to Bob
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Charlie transfers to Dave
    transferBatch[2] = ISubAccounts.AssetTransfer({
      fromAcc: charlieAcc,
      toAcc: daveAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");

    vm.warp(expiry);

    int priceIncrease = 1000e18;

    _updateAllFeeds(uint(ETH_PRICE + priceIncrease));
    srm.settleOptions(option, aliceAcc);
    srm.settleOptions(option, bobAcc);
    srm.settleOptions(option, charlieAcc);
    srm.settleOptions(option, daveAcc);

    // Alice's loss should be charlies gain
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT - uint(priceIncrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT);
    assertEq(uint(daveBal), DEFAULT_DEPOSIT + uint(priceIncrease) - oiFee);
  }

  function _getAllCashBalances() internal view returns (int aliceBal, int bobBal, int charlieBal, int daveBal) {
    aliceBal = getCashBalance(aliceAcc);
    bobBal = getCashBalance(bobAcc);
    charlieBal = getCashBalance(charlieAcc);
    daveBal = getCashBalance(daveAcc);
  }

  function _getSpot() internal view returns (uint) {
    (uint spot,) = markets["weth"].spotFeed.getSpot();
    return spot;
  }

  function _updateAllFeeds(uint price) internal {
    _setSpotPrice("weth", uint96(price), 1e18);

    _setSettlementPrice("weth", expiry, price);
  }
}

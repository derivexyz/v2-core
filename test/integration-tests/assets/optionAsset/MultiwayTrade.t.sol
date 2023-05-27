// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
//
//import "forge-std/console2.sol";
//import "../../shared/IntegrationTestBase.sol";
//import {IManager} from "src/interfaces/IManager.sol";
//
///**
// * @dev testing charge of OI fee in a real setting
// */
//contract INTEGRATION_MultiwayTradeTest is IntegrationTestBase {
//  using DecimalMath for uint;
//
//  address charlie = address(0xcc);
//  uint charlieAcc;
//  address dave = address(0xcc);
//  uint daveAcc;
//
//  int amountOfContracts = 1e18;
//
//  function setUp() public {
//    _setupIntegrationTestComplete();
//
//    charlieAcc =subAccounts.createAccount(charlie, pcrm);
//    daveAcc =subAccounts.createAccount(dave, pcrm);
//
//    // allow this contract to submit trades
//    vm.prank(charlie);
//   subAccounts.setApprovalForAll(address(this), true);
//    vm.prank(dave);
//   subAccounts.setApprovalForAll(address(this), true);
//
//    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(charlie), charlieAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(dave), daveAcc, DEFAULT_DEPOSIT);
//  }
//
//  function testThreeWayTradeNoOIFee() public {
//    uint callExpiry = block.timestamp + 4 weeks;
//    uint callStrike = 2000e18;
//    uint callId = option.getSubId(callExpiry, callStrike, true);
//
//    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();
//
//    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](3);
//
//    // Alice transfer to Bob
//    transferBatch[0] = ISubAccounts.AssetTransfer({
//      fromAcc: aliceAcc,
//      toAcc: bobAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // Bob transfers to Charlie
//    transferBatch[1] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: charlieAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // Charlie transfer to Alice (closing the loop)
//    transferBatch[2] = ISubAccounts.AssetTransfer({
//      fromAcc: charlieAcc,
//      toAcc: aliceAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // After all transfers no oi fee charged since option goes back to alice
//   subAccounts.submitTransfers(transferBatch, "");
//    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
//
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT);
//  }
//
//  function testThreeWayTradeITMCall() public {
//    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(_getSpot());
//
//    // ATM Call
//    uint callExpiry = block.timestamp + 4 weeks;
//    uint callStrike = 2000e18;
//    uint callId = option.getSubId(callExpiry, callStrike, true);
//
//    // Record pre balance
//    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();
//
//    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
//
//    // Alice transfer to Bob
//    transferBatch[0] = ISubAccounts.AssetTransfer({
//      fromAcc: aliceAcc,
//      toAcc: bobAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // Bob transfers to Charlie
//    transferBatch[1] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: charlieAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//   subAccounts.submitTransfers(transferBatch, "");
//
//    vm.warp(callExpiry);
//    int priceIncrease = 1000e18;
//    _setSpotPriceAndSubmitForExpiry(ETH_PRICE + priceIncrease, callExpiry);
//    pcrm.settleOptions(aliceAcc);
//    pcrm.settleOptions(bobAcc);
//    pcrm.settleOptions(charlieAcc);
//
//    // Alice's loss should be charlies gain
//    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT - uint(priceIncrease) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT + uint(priceIncrease) - oiFee);
//  }
//
//  function testThreeWayTradeITMPut() public {
//    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(_getSpot());
//
//    // ATM PUT
//    uint putExpiry = block.timestamp + 4 weeks;
//    uint putStrike = 2000e18;
//    uint putId = option.getSubId(putExpiry, putStrike, false);
//
//    // Record pre balance
//    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();
//
//    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
//
//    // Alice transfer to Bob
//    transferBatch[0] = ISubAccounts.AssetTransfer({
//      fromAcc: aliceAcc,
//      toAcc: bobAcc,
//      asset: option,
//      subId: putId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // Bob transfers to Charlie
//    transferBatch[1] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: charlieAcc,
//      asset: option,
//      subId: putId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//   subAccounts.submitTransfers(transferBatch, "");
//
//    vm.warp(putExpiry);
//    int priceDecrease = 1000e18;
//    _setSpotPriceAndSubmitForExpiry(ETH_PRICE - priceDecrease, putExpiry);
//    pcrm.settleOptions(aliceAcc);
//    pcrm.settleOptions(bobAcc);
//    pcrm.settleOptions(charlieAcc);
//
//    // Alice's loss should be charlies gain
//    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
//
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT - uint(priceDecrease) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT + uint(priceDecrease) - oiFee);
//  }
//
//  function testThreeWayTradeOTMCall() public {
//    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(_getSpot());
//    int premium = 1000e18;
//
//    // ATM Call
//    uint callExpiry = block.timestamp + 4 weeks;
//    uint callStrike = 2000e18;
//    uint callId = option.getSubId(callExpiry, callStrike, true);
//
//    // Record pre balance
//    (int aliceBal, int bobBal, int charlieBal,) = _getAllCashBalances();
//
//    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](4);
//
//    // Alice transfer option to Bob for premium
//    transferBatch[0] = ISubAccounts.AssetTransfer({
//      fromAcc: aliceAcc,
//      toAcc: bobAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    transferBatch[1] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: aliceAcc,
//      asset: cash,
//      subId: 0,
//      amount: premium,
//      assetData: bytes32(0)
//    });
//
//    // Bob transfers same option to Charlie for premium
//    transferBatch[2] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: charlieAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    transferBatch[3] = ISubAccounts.AssetTransfer({
//      fromAcc: charlieAcc,
//      toAcc: bobAcc,
//      asset: cash,
//      subId: 0,
//      amount: premium,
//      assetData: bytes32(0)
//    });
//
//   subAccounts.submitTransfers(transferBatch, "");
//    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);
//
//    // Settle OTM
//    vm.warp(callExpiry);
//    int priceDecrease = 1000e18;
//    _setSpotPriceAndSubmitForExpiry(ETH_PRICE - priceDecrease, callExpiry);
//    pcrm.settleOptions(aliceAcc);
//    pcrm.settleOptions(bobAcc);
//    pcrm.settleOptions(charlieAcc);
//
//    // Balances remain the same as options expire worthless
//    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);
//  }
//
//  function testThreeWayTradeOTMPut() public {
//    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(_getSpot());
//    int premium = 1000e18;
//
//    // ATM Put
//    uint putExpiry = block.timestamp + 4 weeks;
//    uint putStrike = 2000e18;
//    uint putId = option.getSubId(putExpiry, putStrike, false);
//
//    // Record pre balance
//    (int aliceBal, int bobBal, int charlieBal,) = _getAllCashBalances();
//
//    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](4);
//
//    // Alice transfer option to Bob for premium
//    transferBatch[0] = ISubAccounts.AssetTransfer({
//      fromAcc: aliceAcc,
//      toAcc: bobAcc,
//      asset: option,
//      subId: putId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    transferBatch[1] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: aliceAcc,
//      asset: cash,
//      subId: 0,
//      amount: premium,
//      assetData: bytes32(0)
//    });
//
//    // Bob transfers same option to Charlie for premium
//    transferBatch[2] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: charlieAcc,
//      asset: option,
//      subId: putId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    transferBatch[3] = ISubAccounts.AssetTransfer({
//      fromAcc: charlieAcc,
//      toAcc: bobAcc,
//      asset: cash,
//      subId: 0,
//      amount: premium,
//      assetData: bytes32(0)
//    });
//
//   subAccounts.submitTransfers(transferBatch, "");
//    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);
//
//    // Settle OTM
//    vm.warp(putExpiry);
//    int priceIncrease = 1000e18;
//    _setSpotPriceAndSubmitForExpiry(ETH_PRICE + priceIncrease, putExpiry);
//    pcrm.settleOptions(aliceAcc);
//    pcrm.settleOptions(bobAcc);
//    pcrm.settleOptions(charlieAcc);
//
//    // Balances remain the same as options expire worthless
//    (aliceBal, bobBal, charlieBal,) = _getAllCashBalances();
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT + uint(premium) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT - uint(premium) - oiFee);
//  }
//
//  function testFourWayTradeITMCall() public {
//    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(_getSpot());
//
//    // ATM Call
//    uint callExpiry = block.timestamp + 4 weeks;
//    uint callStrike = 2000e18;
//    uint callId = option.getSubId(callExpiry, callStrike, true);
//
//    // Record pre balance
//    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();
//
//    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](3);
//
//    // Alice transfer to Bob
//    transferBatch[0] = ISubAccounts.AssetTransfer({
//      fromAcc: aliceAcc,
//      toAcc: bobAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // Bob transfers to Charlie
//    transferBatch[1] = ISubAccounts.AssetTransfer({
//      fromAcc: bobAcc,
//      toAcc: charlieAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//    // Charlie transfers to Dave
//    transferBatch[2] = ISubAccounts.AssetTransfer({
//      fromAcc: charlieAcc,
//      toAcc: daveAcc,
//      asset: option,
//      subId: callId,
//      amount: amountOfContracts,
//      assetData: bytes32(0)
//    });
//
//   subAccounts.submitTransfers(transferBatch, "");
//
//    vm.warp(callExpiry);
//    int priceIncrease = 1000e18;
//    _setSpotPriceAndSubmitForExpiry(ETH_PRICE + priceIncrease, callExpiry);
//    pcrm.settleOptions(aliceAcc);
//    pcrm.settleOptions(bobAcc);
//    pcrm.settleOptions(charlieAcc);
//    pcrm.settleOptions(daveAcc);
//
//    // Alice's loss should be charlies gain
//    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
//    assertEq(uint(aliceBal), DEFAULT_DEPOSIT - uint(priceIncrease) - oiFee);
//    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
//    assertEq(uint(charlieBal), DEFAULT_DEPOSIT);
//    assertEq(uint(daveBal), DEFAULT_DEPOSIT + uint(priceIncrease) - oiFee);
//  }
//
//  function _getAllCashBalances() internal view returns (int aliceBal, int bobBal, int charlieBal, int daveBal) {
//    aliceBal = getCashBalance(aliceAcc);
//    bobBal = getCashBalance(bobAcc);
//    charlieBal = getCashBalance(charlieAcc);
//    daveBal = getCashBalance(daveAcc);
//  }
//
//  function _getSpot() internal view returns (uint) {
//    (uint spot,) = feed.getSpot();
//    return spot;
//  }
//}

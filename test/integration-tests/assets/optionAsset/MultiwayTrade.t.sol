// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "../../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

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

  function setUp() public {
    _setupIntegrationTestComplete();

    charlieAcc = accounts.createAccount(charlie, pcrm);
    daveAcc = accounts.createAccount(dave, pcrm);

    // allow this contract to submit trades
    vm.prank(charlie);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(dave);
    accounts.setApprovalForAll(address(this), true);

    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
    _depositCash(address(charlie), charlieAcc, DEFAULT_DEPOSIT);
    _depositCash(address(dave), daveAcc, DEFAULT_DEPOSIT);
  }

  function testThreeWayTradeToYourself() public {
    uint callExpiry = block.timestamp + 4 weeks;
    uint callStrike = 2000e18;
    uint callId = option.getSubId(callExpiry, callStrike, true);

    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();
    console2.log("aliceBal  ", aliceBal);
    console2.log("bobBal    ", bobBal);
    console2.log("charlieBal", charlieBal);
    console2.log("daveBal   ", daveBal);

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    // // Alice transfer to Bob
    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    //  // Charlie transfer to Alice (closing the loop)
    //  transferBatch[2] = AccountStructs.AssetTransfer({
    //   fromAcc: charlieAcc,
    //   toAcc: aliceAcc,
    //   asset: option,
    //   subId: callId,
    //   amount: amountOfContracts,
    //   assetData: bytes32(0)
    // });

    accounts.submitTransfers(transferBatch, "");
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
    console2.log("aliceBal  ", aliceBal);
    console2.log("bobBal    ", bobBal);
    console2.log("charlieBal", charlieBal);
    console2.log("daveBal   ", daveBal);

    assertEq(uint(aliceBal), DEFAULT_DEPOSIT-2e18);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT-2e18);
    assertEq(accounts.getBalance(aliceAcc, option, callId), -amountOfContracts);
    assertEq(accounts.getBalance(bobAcc, option, callId), 0);
    assertEq(accounts.getBalance(charlieAcc, option, callId), amountOfContracts);


    // Charlie transfer to Alice (closing the loop)
    AccountStructs.AssetTransfer memory finalTransfer = AccountStructs.AssetTransfer({
      fromAcc: charlieAcc,
      toAcc: aliceAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });
    accounts.submitTransfer(finalTransfer, "");

    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
    console2.log("aliceBal  ", aliceBal);
    console2.log("bobBal    ", bobBal);
    console2.log("charlieBal", charlieBal);
    console2.log("daveBal   ", daveBal);

    // todo 3 way batch vs 2 and 1 transfer results in different OI fees
    // assertEq(uint(aliceBal), DEFAULT_DEPOSIT);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    // assertEq(uint(charlieBal), DEFAULT_DEPOSIT);

    assertEq(accounts.getBalance(aliceAcc, option, callId), 0);
    assertEq(accounts.getBalance(bobAcc, option, callId), 0);
    assertEq(accounts.getBalance(charlieAcc, option, callId), 0);
  }

  function testThreeWayTradeITMCall() public {
    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(feed.getSpot());

    // ATM Call
    uint callExpiry = block.timestamp + 4 weeks;
    uint callStrike = 2000e18;
    uint callId = option.getSubId(callExpiry, callStrike, true);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    // Alice transfer to Bob
    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: callId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    accounts.submitTransfers(transferBatch, "");

    vm.warp(callExpiry);
    int priceIncrease = 1000e18;
    _setSpotPriceAndSubmitForExpiry(ETH_PRICE + priceIncrease, callExpiry);
    pcrm.settleAccount(aliceAcc);
    pcrm.settleAccount(bobAcc);
    pcrm.settleAccount(charlieAcc);

    // Alice's loss should be charlies gain
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();
    assertEq(uint(aliceBal), DEFAULT_DEPOSIT-uint(priceIncrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT+uint(priceIncrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
  }

  function testThreeWayTradeITMPut() public {
    uint oiFee = (pcrm.OIFeeRateBPS()).multiplyDecimal(feed.getSpot());

    // ATM PUT
    uint putExpiry = block.timestamp + 4 weeks;
    uint putStrike = 2000e18;
    uint putId = option.getSubId(putExpiry, putStrike, false);

    // Record pre balance
    (int aliceBal, int bobBal, int charlieBal, int daveBal) = _getAllCashBalances();

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    // Alice transfer to Bob
    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: putId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    // Bob transfers to Charlie
    transferBatch[1] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: charlieAcc,
      asset: option,
      subId: putId,
      amount: amountOfContracts,
      assetData: bytes32(0)
    });

    accounts.submitTransfers(transferBatch, "");

    vm.warp(putExpiry);
    int priceDecrease = 1000e18;
    // console2.log("SPOT", feed.getSpot());
    _setSpotPriceAndSubmitForExpiry(ETH_PRICE - priceDecrease, putExpiry);
    // console2.log("SPOT", feed.getSpot());
    pcrm.settleAccount(aliceAcc);
    pcrm.settleAccount(bobAcc);
    pcrm.settleAccount(charlieAcc);

    // Alice's loss should be charlies gain
    (aliceBal, bobBal, charlieBal, daveBal) = _getAllCashBalances();

    assertEq(uint(aliceBal), DEFAULT_DEPOSIT-uint(priceDecrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
    assertEq(uint(charlieBal), DEFAULT_DEPOSIT+uint(priceDecrease) - oiFee);
    assertEq(uint(bobBal), DEFAULT_DEPOSIT);
  }

  function testFourWayTradeITMCall() public {}

  function _getAllCashBalances() internal returns (int aliceBal, int bobBal, int charlieBal, int daveBal) {
    aliceBal = getCashBalance(aliceAcc);
    bobBal = getCashBalance(bobAcc);
    charlieBal = getCashBalance(charlieAcc);
    daveBal = getCashBalance(daveAcc);
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../../../src/assets/InterestRateModel.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "test/shared/utils/JsonMechIO.sol";

/**
 * @dev Simple testing for the InterestRateModel
 */
contract UNIT_InterestRateScenario is Test {
  struct Event {
    string name; // key1
    string accA; // key2
    string accB; // key3
    int amount; // key4
    uint timePassed; // key5
  }

  struct Inputs {
    Event[] actions;
    uint[] supplies;
    uint[] borrows;
    uint[] balances;
    int[] netPrints;
    uint[] utilizations;
    uint[] borrowRates;
    int[] smBalances;
  }

  using stdJson for string;

  uint public aliceAcc; // 1
  uint public bobAcc; // 2
  uint public charlieAcc; // 3
  uint public davidAcc; // 4
  uint public ericAcc; // 5
  uint public smAcc; // 6, sm account
  uint public owned; // temp account used for setting up

  JsonMechIO jsonParser;

  using ConvertDecimals for uint;
  using SafeCast for uint;
  using DecimalMath for uint;

  InterestRateModel rateModel;
  CashAsset cash;
  MockERC20 usdc;
  SubAccounts subAccounts;
  MockManager manager;

  function setUp() public {
    jsonParser = new JsonMechIO();

    uint minRate = 0.04 * 1e18;
    uint rateMultiplier = 0.4 * 1e18;
    uint highRateMultiplier = 2 * 1e18;
    uint optimalUtil = 0.6 * 1e18;

    subAccounts = new SubAccounts("Lyra MarginAccounts", "Lyra!");

    manager = new MockManager(address(subAccounts));

    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    usdc = new MockERC20("USDC", "USDC");

    cash = new CashAsset(subAccounts, usdc, rateModel);

    cash.setWhitelistManager(address(manager), true);
    cash.setSmFee(0.2e18);

    _setUpActors();

    cash.setSmFeeRecipient(smAcc);
  }

  function _setUpActors() public {
    aliceAcc = subAccounts.createAccount(address(this), manager);
    bobAcc = subAccounts.createAccount(address(this), manager);
    charlieAcc = subAccounts.createAccount(address(this), manager);
    davidAcc = subAccounts.createAccount(address(this), manager);
    ericAcc = subAccounts.createAccount(address(this), manager);
    smAcc = subAccounts.createAccount(address(this), manager);
    owned = subAccounts.createAccount(address(this), manager);
  }

  function testScenario() public {
    string memory json = jsonParser.jsonFromRelPath("/test/assets/cashAsset/unit-tests/json/sequence.json");

    _prepareStartingBalance(json);

    Inputs memory input = Inputs({
      actions: readEventArray(json, ".EventsVec"),
      supplies: json.readUintArray(".totalSupplys"),
      borrows: json.readUintArray(".totalBorrows"),
      balances: json.readUintArray(".balanceOfs"),
      netPrints: json.readIntArray(".netPrints"),
      utilizations: json.readUintArray(".utilizations"),
      borrowRates: json.readUintArray(".borrowRates"),
      smBalances: json.readIntArray(".SMBalances")
    });

    // verify initial states
    _verifyState(input, 0);

    for (uint i = 1; i < input.supplies.length - 1; i++) {
      _processAction(input, i);
      _verifyState(input, i);
    }
  }

  function _prepareStartingBalance(string memory json) public {
    usdc.mint(address(this), 1000_000e18);
    usdc.approve(address(cash), type(uint).max);
    cash.deposit(owned, 500_000e18);

    int[] memory balances = json.readIntArray(".StartingBalances");
    // the last one is the security module

    for (uint i = 0; i < balances.length; i++) {
      if (balances[i] > 0) {
        cash.deposit(i + 1, uint(balances[i]));
      } else {
        cash.withdraw(i + 1, uint(-balances[i]), address(this));
      }
    }

    // take out initial deposit to keep balance correct
    cash.withdraw(owned, 500_000e18, address(this));
  }

  function _verifyState(Inputs memory input, uint i) internal {
    assertApproxEqAbs(cash.totalSupply(), input.supplies[i], 1e5);
    assertApproxEqAbs(cash.totalBorrow(), input.borrows[i], 1e5);

    assertApproxEqAbs(cash.netSettledCash(), input.netPrints[i], 1e5);
    assertApproxEqAbs(usdc.balanceOf(address(cash)), input.balances[i], 1e5);

    // test util rate
    assertApproxEqAbs(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow()), input.utilizations[i], 0.000001e18);

    // test sm balance
    assertApproxEqAbs(subAccounts.getBalance(smAcc, cash, 0), input.smBalances[i], 1e5);

    console2.log("action verified", i);
  }

  function _processAction(Inputs memory input, uint i) internal {
    Event memory action = input.actions[i];

    vm.warp(action.timePassed / 1e18);

    if (equal(action.name, "TRADE")) {
      subAccounts.submitTransfer(
        ISubAccounts.AssetTransfer({
          fromAcc: accountToId(action.accA),
          toAcc: accountToId(action.accB),
          asset: cash,
          subId: 0,
          amount: action.amount,
          assetData: ""
        }),
        ""
      );
    }
  }

  function accountToId(string memory name) public returns (uint) {
    if (equal(name, "Alice")) {
      return aliceAcc;
    } else if (equal(name, "Bob")) {
      return bobAcc;
    } else if (equal(name, "Charlie")) {
      return charlieAcc;
    } else if (equal(name, "David")) {
      return davidAcc;
    } else if (equal(name, "Eric")) {
      return ericAcc;
    }
  }

  function equal(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }

  function readEventArray(string memory json, string memory key) internal pure returns (Event[] memory) {
    return abi.decode(vm.parseJson(json, key), (Event[]));
  }
}

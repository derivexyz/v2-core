// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";

import {IOptionAsset} from "../../../src/interfaces/IOptionAsset.sol";
import {MockPositionTracking} from "./MockPositionTracking.sol";
import {MockGlobalSubIdOITracking} from "./MockGlobalSubIdOITracking.sol";
import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";
import {IManager} from "../../../src/interfaces/IManager.sol";
import {IGlobalSubIdOITracking} from "../../../src/interfaces/IGlobalSubIdOITracking.sol";

contract MockOption is MockPositionTracking, MockGlobalSubIdOITracking, IOptionAsset {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  ISubAccounts immutable subAccounts;

  // mocked state to test # of calls
  bool recordMangerChangeCalls;
  uint public handleManagerCalled;

  // subId => settlement value
  mapping(uint => int) mockedTotalSettlementValue;

  // subId => settled or not
  mapping(uint => bool) mockedSubSettled;

  // expiry => price
  mapping(uint => uint) mockedExpiryPrice;

  // mocked state to test reverting calls from bad manager
  mapping(address => bool) revertFromManager;

  constructor(ISubAccounts account_) {
    subAccounts = account_;
  }

  function handleAdjustment(
    ISubAccounts.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBal,
    IManager _manager,
    address
  ) public view virtual returns (int finalBalance, bool needAllowance) {
    if (revertFromManager[address(_manager)]) revert();
    finalBalance = preBal + adjustment.amount;
    needAllowance = true;
  }

  function getSettlement(uint expiry) external view returns (bool isSettled, uint settlementPrice) {
    // not using the settlement Price right now. Returning 0 for now
    return (expiry > block.timestamp, 0);
  }

  function setRevertAdjustmentFromManager(address _manager, bool _revert) external {
    revertFromManager[_manager] = _revert;
  }

  function setRecordManagerChangeCalls(bool _record) external {
    recordMangerChangeCalls = _record;
  }

  function setSettlementPrice(uint /*expiry*/ ) external {
    // just to comply with interface
  }

  function setMockedTotalSettlementValue(uint subId, int value) external {
    mockedTotalSettlementValue[subId] = value;
  }

  function setMockedSubIdSettled(uint subId, bool settled) external {
    mockedSubSettled[subId] = settled;
  }

  function calcSettlementValue(uint subId, int /*balance*/ ) external view returns (int payout, bool priceSettled) {
    return (mockedTotalSettlementValue[subId], mockedSubSettled[subId]);
  }

  function setMockedExpiryPrice(uint expiry, uint price) external {
    mockedExpiryPrice[expiry] = price;
  }

  function settlementPrices(uint expiry) external view returns (uint price) {
    return mockedExpiryPrice[expiry];
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}

//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/IAccounts.sol";

contract MockOption is IOption {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  IAccounts immutable account;

  bool revertHandleManagerChange;

  // mocked state to test # of calls
  bool recordMangerChangeCalls;
  uint public handleManagerCalled;

  // subId => settlement value
  mapping(uint => int) mockedTotalSettlementValue;

  // subId => settled or not
  mapping(uint => bool) mockedSubSettled;

  // expiry => price
  mapping(uint => uint) mockedExpiryPrice;

  mapping(uint => uint) public openInterest;

  // mocked state to test reverting calls from bad manager
  mapping(address => bool) revertFromManager;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint => mapping(uint => OISnapshot)) public openInterestBeforeTrade;

  constructor(IAccounts account_) {
    account = account_;
  }

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBal,
    IManager _manager,
    address
  ) public view virtual returns (int finalBalance, bool needAllowance) {
    if (revertFromManager[address(_manager)]) revert();
    finalBalance = preBal + adjustment.amount;
    needAllowance = adjustment.amount < 0;
  }

  function handleManagerChange(uint, IManager) public virtual {
    if (revertHandleManagerChange) revert();
    if (recordMangerChangeCalls) handleManagerCalled += 1;
  }

  function setRevertAdjustmentFromManager(address _manager, bool _revert) external {
    revertFromManager[_manager] = _revert;
  }

  function setRevertHandleManagerChange(bool _revert) external {
    revertHandleManagerChange = _revert;
  }

  function setRecordManagerChangeCalls(bool _record) external {
    recordMangerChangeCalls = _record;
  }

  function setMockedOI(uint _subId, uint _oi) external {
    openInterest[_subId] = _oi;
  }

  function setMockedOISnapshotBeforeTrade(uint _subId, uint _tradeId, uint _oi) external {
    openInterestBeforeTrade[_subId][_tradeId] = OISnapshot(true, uint240(_oi));
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

  function getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    public
    pure
    returns (int)
  {
    int priceDiff = settlementPrice.toInt256() - strikePrice.toInt256();

    if (isCall && priceDiff > 0) {
      // ITM Call
      return priceDiff.multiplyDecimal(balance);
    } else if (!isCall && priceDiff < 0) {
      // ITM Put
      return -priceDiff.multiplyDecimal(balance);
    } else {
      // OTM
      return 0;
    }
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}

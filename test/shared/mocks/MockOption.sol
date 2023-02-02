//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/IAccounts.sol";
import "src/libraries/DecimalMath.sol";
/**
 */

contract MockOption is IOption {
  using DecimalMath for uint;

  IAccounts immutable account;

  bool revertHandleManagerChange;

  // mocked state to test # of calls
  bool recordMangerChangeCalls;
  uint public handleManagerCalled;

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

  function setMockedOISanpshotBeforeTrade(uint _subId, uint _tradeId, uint _oi) external {
    openInterestBeforeTrade[_subId][_tradeId] = OISnapshot(true, uint240(_oi));
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";

/**
 * @title DumbAsset is the easiest Asset wrapper that wraps ERC20 into account system.
 * @dev   deployer can set DumbAsset to not allow balance go negative. 
 *        if set to "allowNegative = false", token must be deposited before using
 */
contract DumbAsset is IAsset {
  IERC20 token;
  IAccount account;
  bool immutable allowNegative;

  bool revertHandleManagerChange;

  // mocked state to test # of calls
  bool recordMangerChangeCalls;
  uint public handleManagerCalled;

  // mocked state to test reverting calls from bad manager
  mapping(address => bool) revertFromManager;

  constructor(IERC20 token_, IAccount account_, bool allowNegative_){
    token = token_;
    account = account_;
    allowNegative = allowNegative_;
  }

  function deposit(uint recipientAccount, uint256 subId, uint amount) external {
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: subId,
        amount: int(amount),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0, 
        amount: -int(amount),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transfer(recipientAccount, amount);
  }

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment, int preBal, IManager _manager, address
  ) external view override returns (int finalBalance) {
    if (revertFromManager[address(_manager)]) revert();
    int result = preBal + adjustment.amount;
    if (result < 0 && !allowNegative) revert("negative balance");
    return result;
  }

  function handleManagerChange(uint, IManager) external override {
    if (revertHandleManagerChange) revert();
    if(recordMangerChangeCalls) handleManagerCalled += 1;
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

}

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";

/**
 * @title DumbAsset is design for us to wrap ERC20 into our account system. Only supports deposit and withdraw
 */
contract DumbAsset is IAsset {
  IERC20 token;
  IAccount account;

  constructor(IERC20 token_, IAccount account_){
    token = token_;
    account = account_;
  }

  function deposit(uint recipientAccount, uint amount) external {
    account.assetAdjustment(
      IAccount.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      }),
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  // Note: balances can go negative for quote but not base
  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    account.assetAdjustment(
      IAccount.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0, 
        amount: -int(amount),
        assetData: bytes32(0)
      }),
      ""
    );
    token.transfer(recipientAccount, amount);
  }

  function handleAdjustment(
    IAccount.AssetAdjustment memory adjustment, int preBal, IManager /*riskModel*/, address
  ) external pure override returns (int finalBalance) {
    return preBal + adjustment.amount;
  }

  function handleManagerChange(uint, IManager) external pure override {}
}

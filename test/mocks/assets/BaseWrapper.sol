pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "synthetix/Owned.sol";

import "src/interfaces/IAsset.sol";
import "src/Account.sol";
import "../feeds/PriceFeeds.sol";

// TODO: safecast to int
contract BaseWrapper is IAsset, Owned {
  IERC20 token;
  Account account;
  PriceFeeds priceFeeds;

  constructor(IERC20 token_, Account account_, PriceFeeds feeds_, uint feedId) Owned() {
    token = token_;
    account = account_;
    priceFeeds = feeds_;
    priceFeeds.assignFeedToAsset(IAsset(address(this)), feedId);
  }

  function deposit(uint recipientAccount, uint amount) external {
    account.adjustBalanceByAsset(
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

  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    int postBalance = account.adjustBalanceByAsset(
      IAccount.AssetAdjustment({
        acc: accountId, 
        asset: IAsset(address(this)), 
        subId: 0, 
        amount: -int(amount),
        assetData: bytes32(0)
      }),
      ""
    );
    require(postBalance >= 0);
    token.transfer(recipientAccount, amount);
  }

  function handleAdjustment(
    IAccount.AssetAdjustment memory adjustment, int preBal, IManager, address
  ) external pure override returns (int finalBalance) {
    require(adjustment.subId == 0 && preBal + adjustment.amount >= 0);
    return preBal + adjustment.amount;
  }

    function handleManagerChange(uint, IManager) external pure override {}

}

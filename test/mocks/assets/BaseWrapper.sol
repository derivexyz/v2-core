pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "synthetix/Owned.sol";

import "src/interfaces/IAbstractAsset.sol";
import "src/Account.sol";
import "../feeds/PriceFeeds.sol";

// TODO: safecast to int
contract BaseWrapper is IAbstractAsset, Owned {
  IERC20 token;
  Account account;
  PriceFeeds priceFeeds;

  constructor(IERC20 token_, Account account_, PriceFeeds feeds_, uint feedId) Owned() {
    token = token_;
    account = account_;
    priceFeeds = feeds_;
    priceFeeds.assignFeedToAsset(IAbstractAsset(address(this)), feedId);
  }

  function deposit(uint recipientAccount, uint amount) external {
    account.adjustBalance(
      IAccount.AssetAdjustment({
        acc: recipientAccount,
        asset: IAbstractAsset(address(this)),
        subId: 0,
        amount: int(amount)
      }),
      "",
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    int postBalance = account.adjustBalance(
      IAccount.AssetAdjustment({
        acc: accountId, asset: IAbstractAsset(address(this)), subId: 0, amount: -int(amount)
      }),
      "",
      ""
    );
    require(postBalance >= 0);
    token.transfer(recipientAccount, amount);
  }

  function handleAdjustment(uint, int, int postBal, uint subId, IAbstractManager, address, bytes memory) external pure override {
    require(subId == 0 && postBal >= 0);
  }

    function handleManagerChange(uint, IAbstractManager, IAbstractManager, bytes memory) external pure override {}

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable2Step.sol";

import {IAsset} from "src/interfaces/IAsset.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";
import {IManager} from "src/interfaces/IManager.sol";

import "../feeds/PriceFeeds.sol";

// TODO: safecast to int
contract BaseWrapper is IAsset, Ownable2Step {
  IERC20 token;
  ISubAccounts subAccounts;
  PriceFeeds priceFeeds;

  constructor(IERC20 token_, ISubAccounts account_, PriceFeeds feeds_, uint feedId) Ownable2Step() {
    token = token_;
    subAccounts = account_;
    priceFeeds = feeds_;
    priceFeeds.assignFeedToAsset(IAsset(address(this)), feedId);
  }

  function deposit(uint recipientAccount, uint amount) external {
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      }),
      false, // dont need to re-trigger handleAdjustment hook
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    int postBalance = subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(amount),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    require(postBalance >= 0);
    token.transfer(recipientAccount, amount);
  }

  function handleAdjustment(ISubAccounts.AssetAdjustment memory adjustment, uint, int preBal, IManager, address)
    external
    pure
    override
    returns (int finalBalance, bool needAllowance)
  {
    require(adjustment.subId == 0 && preBal + adjustment.amount >= 0);
    return (preBal + adjustment.amount, adjustment.amount < 0);
  }

  function handleManagerChange(uint, IManager) external pure override {}

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "src/interfaces/IAsset.sol";
import "src/Accounts.sol";

import "../feeds/PriceFeeds.sol";

// TODO: interest rates, not really needed for account system PoC
contract QuoteWrapper is IAsset, Ownable2Step {
  mapping(IManager => bool) riskModelAllowList;
  IERC20 token;
  Accounts account;
  PriceFeeds priceFeeds;

  constructor(IERC20 token_, Accounts account_, PriceFeeds feeds_, uint feedId) Ownable2Step() {
    token = token_;
    account = account_;
    priceFeeds = feeds_;
    priceFeeds.assignFeedToAsset(IAsset(address(this)), feedId);
  }

  // Need to limit the allowed risk models as someone could spin one up that allows for the generation of
  // -infinite quote and sends it to another account?
  function setManagerAllowed(IManager riskModel, bool allowed) external onlyOwner {
    riskModelAllowList[riskModel] = allowed;
  }

  function deposit(uint recipientAccount, uint amount) external {
    account.assetAdjustment(
      IAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  // Note: balances can go negative for quote but not base
  function withdraw(uint accountId, uint amount, address recipientAccount) external {
    account.assetAdjustment(
      IAccounts.AssetAdjustment({
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

  function handleAdjustment(IAccounts.AssetAdjustment memory adjustment, uint, int preBal, IManager riskModel, address)
    external
    view
    override
    returns (int finalBalance, bool needAllowance)
  {
    require(adjustment.subId == 0 && riskModelAllowList[riskModel]);
    return (preBal + adjustment.amount, adjustment.amount < 0);
  }

  function handleManagerChange(uint, IManager) external pure override {}

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}

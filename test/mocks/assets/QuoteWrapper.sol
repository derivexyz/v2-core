pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "synthetix/Owned.sol";
import "src/interfaces/IAsset.sol";
import "src/Account.sol";
import "../feeds/PriceFeeds.sol";

// TODO: interest rates, not really needed for account system PoC
contract QuoteWrapper is IAsset, Owned {
  mapping(IManager => bool) riskModelAllowList;
  IERC20 token;
  Account account;
  PriceFeeds priceFeeds;

  constructor(IERC20 token_, Account account_, PriceFeeds feeds_, uint feedId) Owned() {
    token = token_;
    account = account_;
    priceFeeds = feeds_;
    priceFeeds.assignFeedToAsset(IAsset(address(this)), feedId);
  }

  // Need to limit the allowed risk models as someone could spin one up that allows for the generation of
  // -infinite quote and sends it to another account?
  function setRiskModelAllowed(IManager riskModel, bool allowed) external onlyOwner {
    riskModelAllowList[riskModel] = allowed;
  }

  function deposit(uint recipientAccount, uint amount) external {
    account.adjustBalance(
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
    account.adjustBalance(
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
    uint, int preBal, int amount, uint96 subId, IManager riskModel, address, bytes32
  ) external view override returns (int finalBalance) {
    require(subId == 0 && riskModelAllowList[riskModel]);
    return preBal + amount;
  }

  function handleManagerChange(uint, IManager, IManager) external pure override {}
}

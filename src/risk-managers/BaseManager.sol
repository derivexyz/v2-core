// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";

import "src/interfaces/IAccounts.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "src/interfaces/IFutureFeed.sol";
import "src/interfaces/IBaseManager.sol";

import "src/libraries/IntLib.sol";
import "src/libraries/DecimalMath.sol";
import "src/libraries/OptionEncoding.sol";
import "src/libraries/StrikeGrouping.sol";

abstract contract BaseManager is AccountStructs, IBaseManager {
  using IntLib for int;
  using DecimalMath for uint;

  ///////////////
  // Variables //
  ///////////////

  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev Option asset address
  IOption public immutable option;

  ///@dev Cash asset address
  ICashAsset public immutable cashAsset;

  ///@dev Future feed oracle to get future price for an expiry
  IFutureFeed public immutable futureFeed;

  ///@dev Settlement feed oracle to get price fixed for settlement
  ISettlementFeed public immutable settlementFeed;

  ///@dev OI fee rate in BPS. Charged fee = contract traded * OIFee * spot
  uint public OIFeeRateBPS = 0.001e18; // 10 BPS

  constructor(
    IAccounts _accounts,
    IFutureFeed _futureFeed,
    ISettlementFeed _settlementFeed,
    ICashAsset _cashAsset,
    IOption _option
  ) {
    accounts = _accounts;
    option = _option;
    cashAsset = _cashAsset;
    futureFeed = _futureFeed;
    settlementFeed = _settlementFeed;
  }

  //////////////////////////
  //  External Functions  //
  //////////////////////////

  /**
   * @notice Settle expired option positions in an account.
   * @dev This function can be called by anyone
   */
  function settleAccount(uint accountId) external {
    _settleAccount(accountId);
  }

  /**
   * @notice Settle accounts in batch
   * @dev This function can be called by anyone
   */
  function batchSettleAccounts(uint[] calldata accountIds) external {
    for (uint i; i < accountIds.length; ++i) {
      _settleAccount(accountIds[i]);
    }
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  /**
   * @notice Adds option to portfolio holdings.
   * @dev This option arrangement is only additive, as portfolios are reconstructed for every trade
   * @param portfolio current portfolio of account
   * @param asset option asset to be added
   * @return addedStrikeIndex index of existing or added strike struct
   */
  function _addOption(Portfolio memory portfolio, AccountStructs.AssetBalance memory asset)
    internal
    pure
    returns (uint addedStrikeIndex)
  {
    // decode subId
    (uint expiry, uint strikePrice, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(asset.subId));

    // assume expiry = 0 means this is the first strike.
    if (portfolio.expiry == 0) {
      portfolio.expiry = expiry;
    }

    if (portfolio.expiry != expiry) {
      revert BM_OnlySingleExpiryPerAccount();
    }

    // add strike in-memory to portfolio
    (addedStrikeIndex, portfolio.numStrikesHeld) =
      StrikeGrouping.findOrAddStrike(portfolio.strikes, strikePrice, portfolio.numStrikesHeld);

    // add call or put balance
    if (isCall) {
      portfolio.strikes[addedStrikeIndex].calls += asset.balance;
    } else {
      portfolio.strikes[addedStrikeIndex].puts += asset.balance;
    }

    // return the index of the strike which was just modified
    return addedStrikeIndex;
  }

  /**
   * @dev charge a fixed OI fee and send it in cash to feeRecipientAcc
   * @param accountId Account potentially to charge
   * @param feeRecipientAcc Account of feeRecipient
   * @param tradeId ID of the trade informed by Accounts
   * @param assetDeltas Array of asset changes made to this account
   */
  function _chargeOIFee(uint accountId, uint feeRecipientAcc, uint tradeId, AssetDelta[] calldata assetDeltas) internal {
    uint fee;
    // iterate through all asset changes, if it's option asset, change if OI increased
    for (uint i; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset != option) continue;

      (, uint oiBefore) = option.openInterestBeforeTrade(assetDeltas[i].subId, tradeId);
      uint oi = option.openInterest(assetDeltas[i].subId);

      // if OI decreases, don't charge a fee
      if (oi <= oiBefore) continue;

      (uint expiry,,) = OptionEncoding.fromSubId(SafeCast.toUint96(assetDeltas[i].subId));
      uint futurePrice = futureFeed.getFuturePrice(expiry);
      fee += assetDeltas[i].delta.abs().multiplyDecimal(futurePrice).multiplyDecimal(OIFeeRateBPS);
    }

    if (fee > 0) {
      // transfer cash to fee recipient account
      _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, int(fee));
    }
  }

  /**
   * @dev settle an account by removing all expired option positions and adjust cash balance
   * @param accountId Account Id to settle
   */
  function _settleAccount(uint accountId) internal {
    AssetBalance[] memory balances = accounts.getAccountBalances(accountId);
    int cashDelta = 0;
    for (uint i; i < balances.length; i++) {
      // skip non option asset
      if (balances[i].asset != option) continue;

      (int value, bool isSettled) = option.calcSettlementValue(balances[i].subId, balances[i].balance);
      if (!isSettled) continue;

      cashDelta += value;

      // update user option balance
      accounts.managerAdjustment(
        AccountStructs.AssetAdjustment(accountId, option, balances[i].subId, -(balances[i].balance), bytes32(0))
      );
    }

    // update user cash amount
    accounts.managerAdjustment(AccountStructs.AssetAdjustment(accountId, cashAsset, 0, cashDelta, bytes32(0)));
    // report total print / burn to cash asset
    cashAsset.updateSettledCash(cashDelta);
  }

  /**
   * @dev transfer asset from one account to another without invoking manager hook
   * @param from Account id of the from account. Must be controlled by this manager
   * @param to Account id of the to account. Must be controlled by this manager
   * @param asset Asset address to transfer
   * @param subId Asset subId to transfer
   * @param amount Amount of asset to transfer
   */
  function _symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) internal {
    // deduct amount in from account
    accounts.managerAdjustment(
      AccountStructs.AssetAdjustment({acc: from, asset: asset, subId: subId, amount: -amount, assetData: bytes32(0)})
    );

    // increase "to" account
    accounts.managerAdjustment(
      AccountStructs.AssetAdjustment({acc: to, asset: asset, subId: subId, amount: amount, assetData: bytes32(0)})
    );
  }

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when OI fee rate is set
  event OIFeeRateSet(uint oiFeeRate);

  ////////////
  // Errors //
  ////////////

  error BM_OnlySingleExpiryPerAccount();
}

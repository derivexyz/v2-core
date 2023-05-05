// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import "lyra-utils/math/IntLib.sol";
import "openzeppelin/access/Ownable2Step.sol";

import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IOption} from "src/interfaces/IOption.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {ICashAsset} from "src/interfaces/ICashAsset.sol";
import {IFutureFeed} from "src/interfaces/IFutureFeed.sol";
import {IBaseManager} from "src/interfaces/IBaseManager.sol";

import {ISettlementFeed} from "src/interfaces/ISettlementFeed.sol";
import {IFutureFeed} from "src/interfaces/IFutureFeed.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

abstract contract BaseManager is IBaseManager, Ownable2Step {
  using IntLib for int;
  using DecimalMath for uint;

  ///////////////
  // Variables //
  ///////////////

  /// @dev Account contract address
  IAccounts public immutable accounts;

  /// @dev Option asset address
  IOption public immutable option;

  /// @dev Perp asset address
  IPerpAsset public immutable perp;

  /// @dev Cash asset address
  ICashAsset public immutable cashAsset;

  /// @dev Future feed oracle to get future price for an expiry
  IFutureFeed public immutable futureFeed;

  /// @dev Settlement feed oracle to get price fixed for settlement
  ISettlementFeed public immutable settlementFeed;

  /// @dev account id that receive OI fee
  uint public feeRecipientAcc;

  ///@dev OI fee rate in BPS. Charged fee = contract traded * OIFee * future price
  uint public OIFeeRateBPS = 0.001e18; // 10 BPS

  /// @dev Whitelisted managers. Account can only .changeManager() to whitelisted managers.
  mapping(address => bool) public whitelistedManager;

  /// @dev mapping of tradeId => accountId => fee charged
  mapping(uint => mapping(uint => uint)) public feeCharged;

  constructor(
    IAccounts _accounts,
    IFutureFeed _futureFeed,
    ISettlementFeed _settlementFeed,
    ICashAsset _cashAsset,
    IOption _option,
    IPerpAsset _perp
  ) Ownable2Step() {
    accounts = _accounts;
    option = _option;
    perp = _perp;
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
  function settleOptions(uint accountId) external {
    _settleAccountOptions(accountId);
  }

  /**
   * @notice Settle accounts in batch
   * @dev This function can be called by anyone
   */
  function batchSettleAccounts(uint[] calldata accountIds) external {
    for (uint i; i < accountIds.length; ++i) {
      _settleAccountOptions(accountIds[i]);
    }
  }

  //////////////////////////
  // Owner-only Functions //
  //////////////////////////

  /**
   * @dev Governance determined account to receive OI fee
   * @param _newAcc account id
   */
  function setFeeRecipient(uint _newAcc) external onlyOwner {
    // this line will revert if the owner tries to set an invalid account
    accounts.ownerOf(_newAcc);

    feeRecipientAcc = _newAcc;
  }

  /**
   * @notice Governance determined OI fee rate to be set
   * @dev Charged fee = contract traded * OIFee * spot
   * @param newFeeRate OI fee rate in BPS
   */
  function setOIFeeRateBPS(uint newFeeRate) external onlyOwner {
    OIFeeRateBPS = newFeeRate;

    emit OIFeeRateSet(OIFeeRateBPS);
  }

  /**
   * @notice Whitelist or un-whitelist a manager used in .changeManager()
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  /**
   * @dev charge a fixed OI fee and send it in cash to feeRecipientAcc
   * @param accountId Account potentially to charge
   * @param tradeId ID of the trade informed by Accounts
   * @param assetDeltas Array of asset changes made to this account
   */
  function _chargeOIFee(uint accountId, uint tradeId, IAccounts.AssetDelta[] calldata assetDeltas) internal {
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
      // keep track of OI Fee
      feeCharged[tradeId][accountId] = fee;

      // transfer cash to fee recipient account
      _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, int(fee));
    }
  }

  /**
   * @dev settle an account by removing all expired option positions and adjust cash balance
   * @param accountId Account Id to settle
   */
  function _settleAccountOptions(uint accountId) internal {
    IAccounts.AssetBalance[] memory balances = accounts.getAccountBalances(accountId);
    int cashDelta = 0;
    for (uint i; i < balances.length; i++) {
      // skip non option asset
      if (balances[i].asset != option) continue;

      (int value, bool isSettled) = option.calcSettlementValue(balances[i].subId, balances[i].balance);
      if (!isSettled) continue;

      cashDelta += value;

      // update user option balance
      accounts.managerAdjustment(
        IAccounts.AssetAdjustment(accountId, option, balances[i].subId, -(balances[i].balance), bytes32(0))
      );
    }

    // update user cash amount
    accounts.managerAdjustment(IAccounts.AssetAdjustment(accountId, cashAsset, 0, cashDelta, bytes32(0)));
    // report total print / burn to cash asset
    cashAsset.updateSettledCash(cashDelta);
  }

  /**
   * @notice to settle an account, clear PNL and funding in the perp contract and pay out cash
   */
  function _settleAccountPerps(uint accountId) internal {
    // settle perp: update latest funding rate and settle
    int netCash = perp.settleRealizedPNLAndFunding(accountId);

    cashAsset.updateSettledCash(netCash);

    // update user cash amount
    accounts.managerAdjustment(IAccounts.AssetAdjustment(accountId, cashAsset, 0, netCash, bytes32(0)));

    emit PerpSettled(accountId, netCash);
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
      IAccounts.AssetAdjustment({acc: from, asset: asset, subId: subId, amount: -amount, assetData: bytes32(0)})
    );

    // increase "to" account
    accounts.managerAdjustment(
      IAccounts.AssetAdjustment({acc: to, asset: asset, subId: subId, amount: amount, assetData: bytes32(0)})
    );
  }

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when OI fee rate is set
  event OIFeeRateSet(uint oiFeeRate);

  event PerpSettled(uint indexed accountId, int netCash);

  ////////////
  // Errors //
  ////////////

  error BM_ManagerNotWhitelisted(uint accountId, address newManager);
}

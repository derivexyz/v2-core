// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/Math.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IOptionAsset} from "../interfaces/IOptionAsset.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IForwardFeed} from "../interfaces/IForwardFeed.sol";
import {IBaseManager} from "../interfaces/IBaseManager.sol";

import {IGlobalSubIdOITracking} from "../interfaces/IGlobalSubIdOITracking.sol";
import {IDataReceiver} from "../interfaces/IDataReceiver.sol";

import {IForwardFeed} from "../interfaces/IForwardFeed.sol";
import {IAsset} from "../interfaces/IAsset.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IBasePortfolioViewer} from "../interfaces/IBasePortfolioViewer.sol";

/**
 * @title BaseManager
 * @notice Base contract for all managers. Handles OI fee, settling, liquidations and allowList. Also provides other
 *        utility functions.
 */
abstract contract BaseManager is IBaseManager, Ownable2Step {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using SafeCast for uint;

  /// @dev Account contract address
  ISubAccounts public immutable subAccounts;

  /// @dev Cash asset address
  ICashAsset public immutable cashAsset;

  /// @dev Dutch auction contract address, can trigger execute bid
  IDutchAuction public immutable liquidation;

  /////////////////
  //  Variables  //
  /////////////////

  /// @dev Portfolio viewer contract
  IBasePortfolioViewer public viewer;

  /// @dev the accountId controlled by this manager as intermediate to pay cash if needed
  uint public immutable accId;

  /// @dev Must be set to a value that the deployment environment can handle the gas cost of the given size.
  uint public maxAccountSize = 128;

  /// @dev within this buffer time, allow people to hold expired options in case the settlement price is not ready
  uint public optionSettlementBuffer = 5 minutes;

  /// @dev account id that receive OI fee
  uint public feeRecipientAcc;

  /// @dev minimum OI fee charged, given fee is > 0.
  uint public minOIFee = 0;

  /// @dev mapping of tradeId => accountId => fee charged
  mapping(uint => mapping(uint => uint)) public feeCharged;

  /// @dev keep track of the last tradeId that this manager updated before, to prevent double update
  uint internal lastOracleUpdateTradeId;

  /// @dev tx msg.sender to Accounts that can bypass OI fee on perp or options
  mapping(address sender => bool) public feeBypassedCaller;

  mapping(address callee => bool) internal whitelistedCallee;

  constructor(
    ISubAccounts _subAccounts,
    ICashAsset _cashAsset,
    IDutchAuction _liquidation,
    IBasePortfolioViewer _viewer
  ) Ownable2Step() {
    subAccounts = _subAccounts;
    cashAsset = _cashAsset;
    liquidation = _liquidation;
    viewer = _viewer;

    accId = subAccounts.createAccount(address(this), IManager(address(this)));
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
    subAccounts.ownerOf(_newAcc);

    feeRecipientAcc = _newAcc;
    emit FeeRecipientSet(_newAcc);
  }

  function setMinOIFee(uint newMinOIFee) external onlyOwner {
    if (newMinOIFee > 100e18) {
      revert BM_MinOIFeeTooHigh();
    }
    minOIFee = newMinOIFee;

    emit MinOIFeeSet(minOIFee);
  }

  /**
   * @notice Governance determined tx msg.sender to Accounts that can bypass OI fee on perp or options
   * @param caller msg.sender to Accounts, caller reported by handleAdjustment
   * @param bypassed true to bypass OI fee, false to charge OI fee
   */
  function setFeeBypassedCaller(address caller, bool bypassed) external onlyOwner {
    feeBypassedCaller[caller] = bypassed;

    emit FeeBypassedCallerSet(caller, bypassed);
  }

  /**
   * @notice Governance determined option settlement buffer
   */
  function setSettlementBuffer(uint newBuffer) external onlyOwner {
    if (newBuffer > 2 hours) revert BM_InvalidSettlementBuffer();

    optionSettlementBuffer = newBuffer;
    emit OptionSettlementBufferUpdated(newBuffer);
  }

  /**
   * @notice Governance determined whitelist that can be called during processManagerData
   */
  function setWhitelistedCallee(address callee, bool whitelisted) external onlyOwner {
    whitelistedCallee[callee] = whitelisted;

    emit CalleeWhitelisted(callee);
  }

  /**
   * @dev set max amount of assets in a single account
   */
  function setMaxAccountSize(uint _maxAccountSize) external onlyOwner {
    if (_maxAccountSize < 8 || _maxAccountSize > 500) {
      revert BM_InvalidMaxAccountSize();
    }
    maxAccountSize = _maxAccountSize;
    emit MaxAccountSizeUpdated(_maxAccountSize);
  }

  ///////////////////
  // Liquidations ///
  ///////////////////

  /**
   * @notice Transfers portion of account to the liquidator.
   *         Transfers cash to the liquidated account.
   * @dev Auction contract can decide to either:
   *      - revert / process bid
   *      - continue / complete auction
   * @param accountId ID of account which is being liquidated. assumed to be controlled by this manager
   * @param liquidatorId Liquidator account ID. assumed to be controlled by this manager
   * @param portion Portion of account that is requested to be liquidated.
   * @param bidAmount Cash amount liquidator is offering for portion of account.
   * @param reservedCash Cash amount to ignore in liquidated account's balance.
   */
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint bidAmount, uint reservedCash)
    external
    onlyLiquidations
  {
    if (portion > 1e18) revert BM_InvalidBidPortion();

    // check that liquidator only has cash and nothing else
    ISubAccounts.AssetBalance[] memory liquidatorAssets = subAccounts.getAccountBalances(liquidatorId);
    if (
      liquidatorAssets.length != 0
        && (liquidatorAssets.length != 1 || address(liquidatorAssets[0].asset) != address(cashAsset))
    ) {
      revert BM_LiquidatorCanOnlyHaveCash();
    }

    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);

    // transfer liquidated account's asset to liquidator
    for (uint i; i < assetBalances.length; i++) {
      int ignoreAmount = 0;
      if (assetBalances[i].asset == cashAsset) {
        ignoreAmount = int(reservedCash);
      }

      _symmetricManagerAdjustment(
        accountId,
        liquidatorId,
        assetBalances[i].asset,
        uint96(assetBalances[i].subId),
        (assetBalances[i].balance - ignoreAmount).multiplyDecimal(int(portion))
      );
    }

    if (bidAmount != 0) {
      // transfer cash (bid amount) to liquidated account
      _symmetricManagerAdjustment(liquidatorId, accountId, cashAsset, 0, int(bidAmount));
    }
  }

  /**
   * @dev the liquidation module can request manager to pay the liquidation fee from liquidated account at start of auction
   * @param accountId Account paying the fee (liquidated)
   * @param recipient Account receiving the fee, may NOT be controlled by this manager
   */
  function payLiquidationFee(uint accountId, uint recipient, uint cashAmount) external onlyLiquidations {
    _transferCash(accountId, recipient, cashAmount.toInt256());
  }

  /**
   * @dev settle pending interest on an account
   * @param accountId account id
   */
  function settleInterest(uint accountId) external {
    subAccounts.managerAdjustment(ISubAccounts.AssetAdjustment(accountId, cashAsset, 0, 0, bytes32(0)));
  }

  /**
   * @dev force a cash only account to leave the system if it's not on the allowlist
   * @param accountId Id of account to force withdraw
   */
  function forceWithdrawAccount(uint accountId) external {
    if (viewer.canTrade(accountId)) {
      revert BM_OnlyBlockedAccounts();
    }
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(accountId);
    if (balances.length != 1 || address(balances[0].asset) != address(cashAsset)) {
      revert BM_InvalidForceWithdrawAccountState();
    }

    cashAsset.forceWithdraw(accountId);
  }

  //////////////////////////
  //   Keeper Functions   //
  //////////////////////////

  /**
   * @dev keeper can call this function to force liquidate an account that has been removed from the allowlist
   * @param accountId Id of account to force liquidate
   * @param scenarioId Id of scenario used within liquidation module. Ignored for standard manager.
   */
  function forceLiquidateAccount(uint accountId, uint scenarioId) external {
    if (viewer.canTrade(accountId)) {
      revert BM_OnlyBlockedAccounts();
    }
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(accountId);
    if (balances.length == 1 && address(balances[0].asset) == address(cashAsset) && balances[0].balance > 0) {
      revert BM_InvalidForceLiquidateAccountState();
    }
    liquidation.startForcedAuction(accountId, scenarioId);
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  /**
   * @dev send custom data to oracles. Oracles should implement the verification logic on their own
   */
  function _processManagerData(uint tradeId, bytes calldata managerData) internal {
    if (managerData.length == 0 || lastOracleUpdateTradeId == tradeId) return;

    lastOracleUpdateTradeId = tradeId;

    // parse array of data and update each oracle or take action
    ManagerData[] memory managerDatas = abi.decode(managerData, (ManagerData[]));
    for (uint i; i < managerDatas.length; i++) {
      // invoke some actions if needed
      if (!whitelistedCallee[managerDatas[i].receiver]) revert BM_UnauthorizedCall();
      IDataReceiver(managerDatas[i].receiver).acceptData(managerDatas[i].data);
    }
  }

  ////////////////
  //   OI Fee   //
  ////////////////

  /**
   * @dev calculate the option OI fee for a specific option + subId combination
   * @dev if the OI after a batched trade is increased, all participants will be charged a fee if he trades this asset
   * @param asset Option contract
   * @param forwardFeed Forward feed contract
   * @param delta Change in this trade
   * @param subId SubId of the option
   */
  function _getOptionOIFee(IGlobalSubIdOITracking asset, IForwardFeed forwardFeed, int delta, uint subId, uint tradeId)
    internal
    view
    returns (uint fee)
  {
    (uint expiry,,) = OptionEncoding.fromSubId(SafeCast.toUint96(subId));
    (uint forwardPrice,) = forwardFeed.getForwardPrice(uint64(expiry));
    fee = viewer.getAssetOIFee(asset, subId, delta, tradeId, forwardPrice);
  }

  /**
   * @notice calculate the perpetual OI fee.
   * @dev if the OI after a batched trade is increased, all participants will be charged a fee if he trades this asset
   */
  function _getPerpOIFee(IPerpAsset perpAsset, int delta, uint tradeId) internal view returns (uint fee) {
    (uint perpPrice,) = perpAsset.getPerpPrice();
    fee = viewer.getAssetOIFee(perpAsset, 0, delta, tradeId, perpPrice);
  }

  /**
   * @dev Pay fee, carry up to minFee
   */
  function _payFee(uint accountId, uint fee) internal {
    // Only consider min fee if expected fee is > 0
    if (fee == 0 || feeRecipientAcc == 0) return;

    // transfer cash to fee recipient account
    _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, int(Math.max(fee, minOIFee)));
  }

  ////////////////
  // Settlement //
  ////////////////

  /**
   * @dev settle an account by removing all expired option positions and adjust cash balance
   * @dev this function will not revert even if settlement price is not updated
   * @param accountId Account Id to settle
   */
  function _settleAccountOptions(IOptionAsset option, uint accountId) internal {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(accountId);
    int cashDelta = 0;
    for (uint i; i < balances.length; i++) {
      // skip non option asset
      if (balances[i].asset != option) continue;

      (int value, bool isSettled) = option.calcSettlementValue(balances[i].subId, balances[i].balance);
      if (!isSettled) continue;

      cashDelta += value;

      // update user option balance
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment(accountId, option, balances[i].subId, -(balances[i].balance), bytes32(0))
      );

      emit OptionSettled(accountId, address(option), balances[i].subId, balances[i].balance, value);
    }

    // update user cash amount
    subAccounts.managerAdjustment(ISubAccounts.AssetAdjustment(accountId, cashAsset, 0, cashDelta, bytes32(0)));
    // report total print / burn to cash asset
    cashAsset.updateSettledCash(cashDelta);
  }

  /**
   * @notice to settle an account, clear PNL and funding in the perp contract and pay out cash
   * @dev this should only be called after a perp transfer happens on this account
   */
  function _settlePerpRealizedPNL(IPerpAsset perp, uint accountId) internal {
    // settle perp: update latest funding rate and settle
    (int pnl, int funding) = perp.settleRealizedPNLAndFunding(accountId);

    int netCash = pnl + funding;

    if (netCash == 0) return;

    cashAsset.updateSettledCash(netCash);

    // update user cash amount
    subAccounts.managerAdjustment(ISubAccounts.AssetAdjustment(accountId, cashAsset, 0, netCash, bytes32(0)));

    emit PerpSettled(accountId, address(perp), pnl, funding);
  }

  /**
   * @notice settle account's perp position with index price, and settle through cash
   * @dev calling function should make sure perp address is trusted
   */
  function _settlePerpUnrealizedPNL(IPerpAsset perp, uint accountId) internal {
    perp.realizePNLWithMark(accountId);

    _settlePerpRealizedPNL(perp, accountId);
  }

  /**
   * @dev merge bunch of accounts into one.
   * @dev reverts if the msg.sender is not the owner of all accounts
   */
  function _mergeAccounts(uint mergeIntoId, uint[] memory mergeFromIds) internal {
    address owner = subAccounts.ownerOf(mergeIntoId);
    if (owner != msg.sender) revert BM_OnlySubAccountOwner();

    for (uint i = 0; i < mergeFromIds.length; ++i) {
      // check owner of all accounts is the same - note this ignores
      if (owner != subAccounts.ownerOf(mergeFromIds[i])) {
        revert BM_MergeOwnerMismatch();
      }
      // Move all assets of the other
      ISubAccounts.AssetBalance[] memory assets = subAccounts.getAccountBalances(mergeFromIds[i]);
      for (uint j = 0; j < assets.length; ++j) {
        _symmetricManagerAdjustment(
          mergeFromIds[i], mergeIntoId, assets[j].asset, SafeCast.toUint96(assets[j].subId), assets[j].balance
        );
      }
    }
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
    subAccounts.managerAdjustment(
      ISubAccounts.AssetAdjustment({acc: from, asset: asset, subId: subId, amount: -amount, assetData: bytes32(0)})
    );

    // increase "to" account
    subAccounts.managerAdjustment(
      ISubAccounts.AssetAdjustment({acc: to, asset: asset, subId: subId, amount: amount, assetData: bytes32(0)})
    );
  }

  /**
   * @dev transfer asset from one account to another without invoking manager hook
   * @param from Account id of the from account. Must be controlled by this manager
   * @param to Account id of the to account. May not be controlled by this manager
   */
  function _transferCash(uint from, uint to, int amount) internal {
    // deduct amount in from account
    subAccounts.managerAdjustment(
      ISubAccounts.AssetAdjustment({acc: from, asset: cashAsset, subId: 0, amount: -amount, assetData: bytes32(0)})
    );

    // check if recipient under the same manager
    if (address(subAccounts.manager(to)) == address(this)) {
      // increase to account balance directly
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment({acc: to, asset: cashAsset, subId: 0, amount: amount, assetData: bytes32(0)})
      );
    } else {
      // mint cash to this account
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment({acc: accId, asset: cashAsset, subId: 0, amount: amount, assetData: bytes32(0)})
      );
      subAccounts.submitTransfer(
        ISubAccounts.AssetTransfer({
          fromAcc: accId,
          toAcc: to,
          asset: cashAsset,
          subId: 0,
          amount: amount,
          assetData: ""
        }),
        ""
      );
    }
  }

  ///////////////////
  // Account Hooks //
  ///////////////////

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint, IManager newManager) external view virtual override {}

  ////////////////////
  //    Modifier    //
  ////////////////////

  modifier onlyLiquidations() {
    if (msg.sender != address(liquidation)) revert BM_OnlyLiquidationModule();
    _;
  }

  modifier onlyAccounts() {
    if (msg.sender != address(subAccounts)) revert BM_OnlyAccounts();
    _;
  }
}

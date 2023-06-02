// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/Math.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";
import {IOption} from "src/interfaces/IOption.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {ICashAsset} from "src/interfaces/ICashAsset.sol";
import {IForwardFeed} from "src/interfaces/IForwardFeed.sol";
import {IBaseManager} from "src/interfaces/IBaseManager.sol";

import {IGlobalSubIdOITracking} from "src/interfaces/IGlobalSubIdOITracking.sol";
import {IPositionTracking} from "src/interfaces/IPositionTracking.sol";
import {IDataReceiver} from "src/interfaces/IDataReceiver.sol";

import {ISettlementFeed} from "src/interfaces/ISettlementFeed.sol";
import {IForwardFeed} from "src/interfaces/IForwardFeed.sol";
import {ISpotFeed} from "src/interfaces/ISpotFeed.sol";
import {IAsset} from "src/interfaces/IAsset.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAllowList} from "src/interfaces/IAllowList.sol";

import "forge-std/console2.sol";

/**
 * @title BaseManager
 * @notice Base contract for all managers. Handles OI fee, settling, liquidations and allowList. Also provides other
 *        utility functions.
 */
abstract contract BaseManager is IBaseManager, Ownable2Step {
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  ///////////////
  // Variables //
  ///////////////

  /// @dev Account contract address
  ISubAccounts public immutable subAccounts;

  /// @dev Cash asset address
  ICashAsset public immutable cashAsset;

  /// @dev Dutch auction contract address, can trigger execute bid
  IDutchAuction public immutable liquidation;

  /// @dev AllowList contract address
  IAllowList public allowList;

  /// @dev account id that receive OI fee
  uint public feeRecipientAcc;

  /// @dev minimum OI fee charged, given fee is > 0.
  uint public minOIFee = 0;

  /// @dev mapping of tradeId => accountId => fee charged
  mapping(uint => mapping(uint => uint)) public feeCharged;

  /// @dev keep track of the last tradeId that this manager updated before, to prevent double update
  uint public lastOracleUpdateTradeId;

  /// @dev tx msg.sender to Accounts that can bypass OI fee on perp or options
  mapping(address sender => bool) public feeBypassedCaller;

  /// @dev OI fee rate in BPS. Charged fee = contract traded * OIFee * future price
  mapping(address asset => uint) public OIFeeRateBPS;

  constructor(ISubAccounts _subAccounts, ICashAsset _cashAsset, IDutchAuction _liquidation) Ownable2Step() {
    subAccounts = _subAccounts;
    cashAsset = _cashAsset;
    liquidation = _liquidation;
  }

  //////////////////////////
  // Owner-only Functions //
  //////////////////////////

  /**
   * @notice Governance determined allowList
   * @param _allowList The allowList contract, can be empty which will bypass allowList checks
   */
  function setAllowList(IAllowList _allowList) external onlyOwner {
    allowList = _allowList;
    emit AllowListSet(_allowList);
  }

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

  /**
   * @notice Governance determined OI fee rate to be set
   * @dev Charged fee = contract traded * OIFee * spot
   * @param newFeeRate OI fee rate in BPS
   */
  function setOIFeeRateBPS(address asset, uint newFeeRate) external onlyOwner {
    if (newFeeRate > 0.2e18) {
      revert BM_OIFeeRateTooHigh();
    }

    OIFeeRateBPS[asset] = newFeeRate;

    emit OIFeeRateSet(asset, newFeeRate);
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

  ///////////////////
  // Liquidations ///
  ///////////////////

  /**
   * @notice Transfers portion of account to the liquidator.
   *         Transfers cash to the liquidated account.
   * @dev Auction contract can decide to either:
   *      - revert / process bid
   *      - continue / complete auction
   * @param accountId ID of account which is being liquidated.
   * @param liquidatorId Liquidator account ID.
   * @param portion Portion of account that is requested to be liquidated.
   * @param cashAmount Cash amount liquidator is offering for portion of account.
   */
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount) external onlyLiquidations {
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
      _symmetricManagerAdjustment(
        accountId,
        liquidatorId,
        assetBalances[i].asset,
        uint96(assetBalances[i].subId),
        assetBalances[i].balance.multiplyDecimal(int(portion))
      );
    }

    // transfer cash (bid amount) to liquidated account
    _symmetricManagerAdjustment(liquidatorId, accountId, cashAsset, 0, int(cashAmount));
  }

  /**
   * @dev the liquidation module can request manager to pay the liquidation fee from liquidated account at start of auction
   */
  function payLiquidationFee(uint accountId, uint recipient, uint cashAmount) external onlyLiquidations {
    _symmetricManagerAdjustment(accountId, recipient, cashAsset, 0, int(cashAmount));
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
    if (_canTrade(accountId)) {
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
    if (_canTrade(accountId)) {
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
    bool oiIncreased = _getOIIncreased(asset, subId, tradeId);
    if (!oiIncreased) return 0;

    (uint expiry,,) = OptionEncoding.fromSubId(SafeCast.toUint96(subId));
    (uint forwardPrice,) = forwardFeed.getForwardPrice(uint64(expiry));
    fee = SignedMath.abs(delta).multiplyDecimal(forwardPrice).multiplyDecimal(OIFeeRateBPS[address(asset)]);
  }

  /**
   * @notice calculate the perpetual OI fee.
   * @dev if the OI after a batched trade is increased, all participants will be charged a fee if he trades this asset
   */
  function _getPerpOIFee(IGlobalSubIdOITracking asset, ISpotFeed perpFeed, int delta, uint tradeId)
    internal
    view
    returns (uint fee)
  {
    bool oiIncreased = _getOIIncreased(asset, 0, tradeId);
    if (!oiIncreased) return 0;

    (uint perpPrice,) = perpFeed.getSpot();
    fee = SignedMath.abs(delta).multiplyDecimal(perpPrice).multiplyDecimal(OIFeeRateBPS[address(asset)]);
  }

  /**
   * @dev check if OI increased for a given asset and subId in a trade
   */
  function _getOIIncreased(IGlobalSubIdOITracking asset, uint subId, uint tradeId) internal view returns (bool) {
    (, uint oiBefore) = asset.openInterestBeforeTrade(subId, tradeId);
    uint oi = asset.openInterest(subId);
    return oi > oiBefore;
  }

  /**
   * @dev pay fee, carry up to minFee
   */
  function _payFee(uint accountId, uint fee) internal {
    // Only consider min fee if expected fee is > 0
    if (fee == 0 || feeRecipientAcc == 0) return;

    // transfer cash to fee recipient account
    _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, int(Math.max(fee, minOIFee)));
  }

  ////////////
  // OI Cap //
  ////////////

  /**
   * @notice check that all assets in an account is below the cap
   * @dev this function assume all assets are compliant to IPositionTracking interface
   */
  function _checkAllAssetCaps(uint accountId, uint tradeId) internal view {
    address[] memory assets = subAccounts.getUniqueAssets(accountId);
    for (uint i; i < assets.length; i++) {
      if (assets[i] == address(cashAsset)) continue;

      _checkAssetCap(IPositionTracking(assets[i]), tradeId);
    }
  }

  /**
   * @dev check that an asset is not over the total position cap for this manager
   */
  function _checkAssetCap(IPositionTracking asset, uint tradeId) internal view {
    uint totalPosCap = asset.totalPositionCap(IManager(address(this)));
    (, uint preTradePos) = asset.totalPositionBeforeTrade(IManager(address(this)), tradeId);
    uint postTradePos = asset.totalPosition(IManager(address(this)));

    // If the trade increased OI and we are past the cap, revert.
    if (preTradePos < postTradePos && postTradePos > totalPosCap) revert BM_AssetCapExceeded();
  }

  ////////////////
  // Settlement //
  ////////////////

  /**
   * @dev settle an account by removing all expired option positions and adjust cash balance
   * @param accountId Account Id to settle
   */
  function _settleAccountOptions(IOption option, uint accountId) internal {
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

    emit PerpSettled(accountId, netCash);
  }

  /**
   * @notice settle account's perp position with index price, and settle through cash
   * @dev calling function should make sure perp address is trusted
   */
  function _settlePerpUnrealizedPNL(IPerpAsset perp, uint accountId) internal {
    perp.realizePNLWithIndex(accountId);

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
   * @dev get the original balances state before a trade is executed
   */
  function _undoAssetDeltas(uint accountId, ISubAccounts.AssetDelta[] memory assetDeltas)
    internal
    view
    returns (ISubAccounts.AssetBalance[] memory newAssetBalances)
  {
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);

    // keep track of how many new elements to add to the result. Can be negative (remove balances that end at 0)
    uint removedBalances = 0;
    uint newBalances = 0;
    ISubAccounts.AssetBalance[] memory preBalances = new ISubAccounts.AssetBalance[](assetDeltas.length);

    for (uint i = 0; i < assetDeltas.length; ++i) {
      ISubAccounts.AssetDelta memory delta = assetDeltas[i];
      if (delta.delta == 0) {
        continue;
      }
      bool found = false;
      for (uint j = 0; j < assetBalances.length; ++j) {
        ISubAccounts.AssetBalance memory balance = assetBalances[j];
        if (balance.asset == delta.asset && balance.subId == delta.subId) {
          found = true;
          assetBalances[j].balance = balance.balance - delta.delta;
          if (assetBalances[j].balance == 0) {
            removedBalances++;
          }
          break;
        }
      }
      if (!found) {
        preBalances[newBalances++] =
          ISubAccounts.AssetBalance({asset: delta.asset, subId: delta.subId, balance: -delta.delta});
      }
    }

    newAssetBalances = new ISubAccounts.AssetBalance[](assetBalances.length + newBalances - removedBalances);

    uint newBalancesIndex = 0;
    for (uint i = 0; i < assetBalances.length; ++i) {
      ISubAccounts.AssetBalance memory balance = assetBalances[i];
      if (balance.balance != 0) {
        newAssetBalances[newBalancesIndex++] = balance;
      }
    }
    for (uint i = 0; i < newBalances; ++i) {
      newAssetBalances[newBalancesIndex++] = preBalances[i];
    }

    return newAssetBalances;
  }

  /**
   * @dev revert if the accountID is not on the allow list
   */
  function _verifyCanTrade(uint accountId) internal view {
    if (!_canTrade(accountId)) {
      revert BM_CannotTrade();
    }
  }

  /**
   * @dev return true if the owner of an account ID is on the allow list
   */
  function _canTrade(uint accountId) internal view returns (bool) {
    if (allowList == IAllowList(address(0))) {
      return true;
    }
    address user = subAccounts.ownerOf(accountId);
    return allowList.canTrade(user);
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

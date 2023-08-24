// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/security/ReentrancyGuard.sol";
import {ISubAccounts} from "./interfaces/ISubAccounts.sol";
import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import {IAsset} from "./interfaces/IAsset.sol";
import {IManager} from "./interfaces/IManager.sol";
import {Allowances} from "./Allowances.sol";
import {AssetDeltaLib} from "./libraries/AssetDeltaLib.sol";
import {PermitAllowanceLib} from "./libraries/PermitAllowanceLib.sol";

/**
 * @title SubAccounts
 * @author Lyra
 * @notice Base layer that manages:
 *         1. balances for each (subAccounts, asset, subId)
 *         2. routing of manager, asset, allowance hooks / checks during any balance adjustment event
 *         3. account creation / manager assignment
 */
contract SubAccounts is Allowances, ERC721, EIP712, ReentrancyGuard, ISubAccounts {
  using SafeCast for int;
  using SafeCast for uint;
  using AssetDeltaLib for AssetDeltaArrayCache;

  ///////////////
  // Variables //
  ///////////////

  /// @dev last account id (ERC721 id) created
  uint public lastAccountId = 0;

  /// @dev last trade id that was attached with manager hook and asset hook
  uint public lastTradeId = 0;

  /// @dev accountId to manager
  mapping(uint => IManager) public manager;

  /// @dev accountId => asset => subId => BalanceAndOrder struct
  mapping(uint => mapping(IAsset => mapping(uint => BalanceAndOrder))) public balanceAndOrder;

  /// @dev accountId to non-zero assets array
  mapping(uint => HeldAsset[]) public heldAssets;

  /// @dev user nonce for permit. User => wordPosition => nonce bit map
  mapping(address => mapping(uint => uint)) public nonceBitmap;

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyOwnerOrManagerOrERC721Approved(address sender, uint accountId) {
    if (!_isApprovedOrOwner(sender, accountId)) {
      revert AC_NotOwnerOrERC721Approved(
        sender, accountId, ownerOf(accountId), manager[accountId], getApproved(accountId)
      );
    }
    _;
  }

  modifier onlyManager(uint accountId) {
    address accountManager = address(manager[accountId]);
    if (msg.sender != accountManager) revert AC_OnlyManager();
    _;
  }

  modifier onlyAsset(IAsset asset) {
    if (msg.sender != address(asset)) revert AC_OnlyAsset();
    _;
  }

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) EIP712("Lyra", "1") {}

  ////////////////////////
  // Account Management //
  ////////////////////////

  /**
   * @notice Creates account with new accountId
   * @param owner new account owner
   * @param _manager IManager of new account
   * @return newId ID of new account
   */
  function createAccount(address owner, IManager _manager) external returns (uint newId) {
    return _createAccount(owner, _manager);
  }

  /**
   * @notice Creates account and gives spender full allowance
   * @dev   @note: can be used to create and account for another user and simultaneously give allowance to oneself
   * @param owner new account owner
   * @param spender give address ERC721 approval
   * @param _manager IManager of new account
   * @return newId ID of new account
   */
  function createAccountWithApproval(address owner, address spender, IManager _manager) external returns (uint newId) {
    newId = _createAccount(owner, _manager);
    _approve(spender, newId);
  }

  /**
   * @dev create an account for a user, assign manager and emit event
   * @param owner new account owner
   * @param _manager IManager of new account
   * @return newId ID of new account
   */
  function _createAccount(address owner, IManager _manager) internal returns (uint newId) {
    newId = ++lastAccountId;
    manager[newId] = _manager;
    _mint(owner, newId);
    emit AccountCreated(owner, newId, address(_manager));
  }

  /**
   * @notice Assigns new manager to account. No balances are adjusted.
   *         msg.sender must be ERC721 approved or owner
   * @param accountId ID of account
   * @param newManager new IManager
   * @param newManagerData data to be passed to manager._managerHook
   */
  function changeManager(uint accountId, IManager newManager, bytes memory newManagerData)
    external
    onlyOwnerOrManagerOrERC721Approved(msg.sender, accountId)
  {
    IManager oldManager = manager[accountId];
    if (oldManager == newManager) {
      revert AC_CannotChangeToSameManager(msg.sender, accountId);
    }
    oldManager.handleManagerChange(accountId, newManager);

    /* get unique assets to only call to asset once */
    (address[] memory uniqueAssets, uint uniqueLength) = _getUniqueAssets(heldAssets[accountId]);
    for (uint i; i < uniqueLength; ++i) {
      IAsset(uniqueAssets[i]).handleManagerChange(accountId, newManager);
    }

    // construct asset delta array from existing balances
    uint assetsLength = heldAssets[accountId].length;
    AssetDelta[] memory deltas = new AssetDelta[](assetsLength);
    for (uint i; i < assetsLength; i++) {
      HeldAsset memory heldAsset = heldAssets[accountId][i];
      deltas[i] = AssetDelta({
        asset: heldAsset.asset,
        subId: heldAsset.subId,
        delta: balanceAndOrder[accountId][heldAsset.asset][heldAsset.subId].balance
      });
    }
    // update the manager after all checks (external calls) are done. expected reentry pattern
    manager[accountId] = newManager;

    uint tradeId = ++lastTradeId;

    // trigger the manager hook on the new manager. Same as post-transfer checks
    _managerHook(accountId, tradeId, msg.sender, deltas, newManagerData);

    emit AccountManagerChanged(accountId, address(oldManager), address(newManager));
  }

  ////////////////
  // Allowances //
  ////////////////

  /**
   * @notice Sets bidirectional allowances for all subIds of an asset.
   *         During a balance adjustment, if msg.sender not ERC721 approved or owner,
   *         asset allowance + subId allowance must be >= amount
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each asset
   */
  function setAssetAllowances(uint accountId, address delegate, AssetAllowance[] memory allowances)
    external
    onlyOwnerOrManagerOrERC721Approved(msg.sender, accountId)
  {
    _setAssetAllowances(accountId, ownerOf(accountId), delegate, allowances);
  }

  /**
   * @notice Sets bidirectional allowances for a specific subId.
   *         During a balance adjustment, the subId allowance is decremented first
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each (asset, subId)
   */
  function setSubIdAllowances(uint accountId, address delegate, SubIdAllowance[] memory allowances)
    external
    onlyOwnerOrManagerOrERC721Approved(msg.sender, accountId)
  {
    address owner = ownerOf(accountId);
    _setSubIdAllowances(accountId, owner, delegate, allowances);
  }

  /**
   * @dev adjust allowance by owner signature
   * @param allowancePermit struct specifying accountId, delegator and allowance detail
   * @param signature ECDSA signature or EIP 1271 contract signature
   */
  function permit(PermitAllowance calldata allowancePermit, bytes calldata signature) external {
    _permit(allowancePermit, signature);
  }

  /**
   * @notice Invalidates the bits specified in mask for the bitmap at the word position
   * @dev Copied from Uniswap's Permit2 nonce system
   *      https://github.com/Uniswap/permit2/blob/ca6b6ff2b47afc2942f3c67b0d929ca4f0b32631/src/SignatureTransfer.sol#L130
   * @dev The wordPos is maxed at type(uint248).max
   * @param wordPos A number to index the nonceBitmap at
   * @param mask A bitmap masked against msg.sender's current bitmap at the word position
   */
  function invalidateUnorderedNonces(uint wordPos, uint mask) external {
    nonceBitmap[msg.sender][wordPos] |= mask;

    emit UnorderedNonceInvalidated(msg.sender, wordPos, mask);
  }

  /**
   * @dev verify signature and update allowance mapping
   * @param allowancePermit struct specifying accountId, delegator and allowance detail
   * @param signature ECDSA signature or EIP 1271 contract signature
   */
  function _permit(PermitAllowance calldata allowancePermit, bytes calldata signature) internal {
    if (allowancePermit.deadline < block.timestamp) revert AC_SignatureExpired();

    // owner of the account, who should be the signer
    address owner = ownerOf(allowancePermit.accountId);

    bytes32 structHash = PermitAllowanceLib.hash(allowancePermit);

    // check the signature is from the current owner
    if (!SignatureChecker.isValidSignatureNow(owner, _hashTypedDataV4(structHash), signature)) {
      revert AC_InvalidPermitSignature();
    }

    // consume nonce
    _useUnorderedNonce(owner, allowancePermit.nonce);

    // update asset allowance
    _setAssetAllowances(allowancePermit.accountId, owner, allowancePermit.delegate, allowancePermit.assetAllowances);

    // update subId allowance
    _setSubIdAllowances(allowancePermit.accountId, owner, allowancePermit.delegate, allowancePermit.subIdAllowances);
  }

  /**
   * @notice Checks whether a nonce is taken and sets the bit at the bit position in the bitmap at the word position
   * @dev Copied from Uniswap's Permit2 nonce system
   *      https://github.com/Uniswap/permit2/blob/ca6b6ff2b47afc2942f3c67b0d929ca4f0b32631/src/SignatureTransfer.sol#L150
   * @param from The address to use the nonce at
   * @param nonce The nonce to spend
   */
  function _useUnorderedNonce(address from, uint nonce) internal {
    (uint wordPos, uint bitPos) = _bitmapPositions(nonce);
    uint bit = 1 << bitPos;
    uint flipped = nonceBitmap[from][wordPos] ^= bit;

    // if no bit flipped: the nonce is already marked as used before ^=
    if (flipped & bit == 0) revert AC_InvalidNonce();
  }

  /**
   * @notice Returns the index of the bitmap and the bit position within the bitmap. Used for unordered nonces
   * @dev Copied from Uniswap's Permit2 nonce system
   *      https://github.com/Uniswap/permit2/blob/ca6b6ff2b47afc2942f3c67b0d929ca4f0b32631/src/SignatureTransfer.sol#L142
   * @dev The first 248 bits of the nonce value is the index of the desired bitmap
   * @dev The last 8 bits of the nonce value is the position of the bit in the bitmap
   *
   * @param nonce The nonce to get the associated word and bit positions
   * @return wordPos The word position or index into the nonceBitmap
   * @return bitPos The bit position
   *
   */
  function _bitmapPositions(uint nonce) private pure returns (uint wordPos, uint bitPos) {
    wordPos = uint248(nonce >> 8);
    bitPos = uint8(nonce);
  }

  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  /**
   * @notice Transfer an amount from one account to another for a specific (asset, subId)
   * @param assetTransfer (fromAcc, toAcc, asset, subId, amount)
   * @param managerData data passed to managers of both accounts
   */
  function submitTransfer(AssetTransfer calldata assetTransfer, bytes calldata managerData)
    external
    nonReentrant
    returns (uint tradeId)
  {
    return _submitTransfer(assetTransfer, managerData);
  }

  /**
   * @notice Batch several transfers
   *         Gas efficient when modifying the same account several times,
   *         as _managerHook() is only performed once per account
   * @param assetTransfers array of (fromAcc, toAcc, asset, subId, amount)
   * @param managerData data passed to every manager involved in trade
   */
  function submitTransfers(AssetTransfer[] calldata assetTransfers, bytes calldata managerData)
    external
    nonReentrant
    returns (uint tradeId)
  {
    return _submitTransfers(assetTransfers, managerData);
  }

  /**
   * @notice Permit and transfer in a single transaction
   * @param assetTransfer Detailed struct on transfer (fromAcc, toAcc, asset, subId, amount)
   * @param managerData Data passed to managers of both accounts
   * @param allowancePermit Detailed struct for permit (accountId, delegator allowance detail)
   * @param signature ECDSA signature or EIP 1271 contract signature
   */
  function permitAndSubmitTransfer(
    AssetTransfer calldata assetTransfer,
    bytes calldata managerData,
    PermitAllowance calldata allowancePermit,
    bytes calldata signature
  ) external nonReentrant returns (uint tradeId) {
    _permit(allowancePermit, signature);
    return _submitTransfer(assetTransfer, managerData);
  }

  /**
   * @notice Batch multiple permits and transfers
   * @param assetTransfers Array of transfers to perform
   * @param managerData Data passed to managers of both accounts
   * @param allowancePermits Array of permit struct (accountId, delegator allowance detail)
   * @param signatures Array of permit signatures
   */
  function permitAndSubmitTransfers(
    AssetTransfer[] calldata assetTransfers,
    bytes calldata managerData,
    PermitAllowance[] calldata allowancePermits,
    bytes[] calldata signatures
  ) external nonReentrant returns (uint tradeId) {
    for (uint i; i < allowancePermits.length; ++i) {
      _permit(allowancePermits[i], signatures[i]);
    }
    return _submitTransfers(assetTransfers, managerData);
  }

  /**
   * @notice Transfer an amount from one account to another for a specific (asset, subId)
   * @param assetTransfer Detail struct (fromAcc, toAcc, asset, subId, amount)
   * @param managerData Data passed to managers of both accounts
   */
  function _submitTransfer(AssetTransfer calldata assetTransfer, bytes calldata managerData)
    internal
    returns (uint tradeId)
  {
    tradeId = ++lastTradeId;
    (int fromDelta, int toDelta) = _transferAsset(assetTransfer, tradeId);
    _managerHook(
      assetTransfer.fromAcc,
      tradeId,
      msg.sender,
      AssetDeltaLib.getDeltasFromSingleAdjustment(assetTransfer.asset, assetTransfer.subId, fromDelta),
      managerData
    );
    _managerHook(
      assetTransfer.toAcc,
      tradeId,
      msg.sender,
      AssetDeltaLib.getDeltasFromSingleAdjustment(assetTransfer.asset, assetTransfer.subId, toDelta),
      managerData
    );
  }

  /**
   * @notice Batch several transfers
   *         Gas efficient when modifying the same account several times,
   *         as _managerHook() is only performed once per account
   * @param assetTransfers Array of (fromAcc, toAcc, asset, subId, amount)
   * @param managerData Data passed to every manager involved in trade
   */
  function _submitTransfers(AssetTransfer[] calldata assetTransfers, bytes calldata managerData)
    internal
    returns (uint tradeId)
  {
    // keep track of seen accounts to assess risk once per account
    uint[] memory seenAccounts = new uint[](assetTransfers.length * 2);

    // keep track of the array of "asset delta" for each account
    // assetDeltas[i] stores asset delta array for seenAccounts[i]
    AssetDeltaArrayCache[] memory assetDeltas = new AssetDeltaArrayCache[](assetTransfers.length * 2);

    uint nextSeenId = 0;
    tradeId = ++lastTradeId;

    for (uint i; i < assetTransfers.length; ++i) {
      if (assetTransfers[i].fromAcc == 0 && assetTransfers[i].toAcc == 0) continue;
      // if from or to account is not seen before, add to seenAccounts in memory
      (uint fromIndex, uint toIndex) = (0, 0);
      (nextSeenId, fromIndex) =
        UnorderedMemoryArray.addUniqueToArray(seenAccounts, assetTransfers[i].fromAcc, nextSeenId);
      (nextSeenId, toIndex) = UnorderedMemoryArray.addUniqueToArray(seenAccounts, assetTransfers[i].toAcc, nextSeenId);

      (int fromDelta, int toDelta) = _transferAsset(assetTransfers[i], tradeId);

      // update assetDeltas[from] directly.
      assetDeltas[fromIndex].addToAssetDeltaArray(
        AssetDelta({asset: assetTransfers[i].asset, subId: uint96(assetTransfers[i].subId), delta: fromDelta})
      );

      // update assetDeltas[to] directly.
      assetDeltas[toIndex].addToAssetDeltaArray(
        AssetDelta({asset: assetTransfers[i].asset, subId: uint96(assetTransfers[i].subId), delta: toDelta})
      );
    }

    for (uint i; i < nextSeenId; i++) {
      AssetDelta[] memory nonEmptyDeltas = AssetDeltaLib.getDeltasFromArrayCache(assetDeltas[i]);
      _managerHook(seenAccounts[i], tradeId, msg.sender, nonEmptyDeltas, managerData);
    }
  }

  /**
   * @notice Transfer an amount from one account to another for a specific (asset, subId)
   * @dev    update the allowance and balanceAndOrder storage
   * @param assetTransfer (fromAcc, toAcc, asset, subId, amount)
   * @param tradeId a shared id for both asset and manager hooks within a same call
   */
  function _transferAsset(AssetTransfer calldata assetTransfer, uint tradeId)
    internal
    returns (int fromDelta, int toDelta)
  {
    if (assetTransfer.fromAcc == assetTransfer.toAcc) {
      revert AC_CannotTransferAssetToOneself(msg.sender, assetTransfer.toAcc);
    }

    AssetAdjustment memory fromAccAdjustment = AssetAdjustment({
      acc: assetTransfer.fromAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: -assetTransfer.amount,
      assetData: assetTransfer.assetData
    });

    AssetAdjustment memory toAccAdjustment = AssetAdjustment({
      acc: assetTransfer.toAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: assetTransfer.amount,
      assetData: assetTransfer.assetData
    });

    // balance is adjusted based on asset hook
    (, int fromDelta_, bool fromAdjustmentNeedAllowance) = _adjustBalance(fromAccAdjustment, tradeId, true);
    (, int toDelta_, bool toAdjustmentNeedAllowance) = _adjustBalance(toAccAdjustment, tradeId, true);

    // if it's not ERC721 approved: spend allowances
    if (fromAdjustmentNeedAllowance && !_isApprovedOrOwner(msg.sender, fromAccAdjustment.acc)) {
      _spendAllowance(fromAccAdjustment, ownerOf(fromAccAdjustment.acc), msg.sender);
    }
    if (toAdjustmentNeedAllowance && !_isApprovedOrOwner(msg.sender, toAccAdjustment.acc)) {
      _spendAllowance(toAccAdjustment, ownerOf(toAccAdjustment.acc), msg.sender);
    }

    emit AssetTransferred(
      assetTransfer.fromAcc,
      assetTransfer.toAcc,
      assetTransfer.asset,
      assetTransfer.subId,
      assetTransfer.amount,
      assetTransfer.assetData,
      tradeId
    );

    return (fromDelta_, toDelta_);
  }

  /**
   * @notice Assymetric balance adjustment reserved for managers
   *         Must still pass both _assetHook()
   * @param adjustment assymetric adjustment of amount for (asset, subId)
   */
  function managerAdjustment(AssetAdjustment memory adjustment)
    external
    onlyManager(adjustment.acc)
    returns (int postAdjustmentBalance)
  {
    uint tradeId = ++lastTradeId;
    // balance is adjusted based on asset hook
    (postAdjustmentBalance,,) = _adjustBalance(adjustment, tradeId, true);
  }

  /**
   * @notice Asymmetric balance adjustment reserved for assets
   *         Must still pass both _managerHook()
   * @param adjustment asymmetric adjustment of amount for (asset, subId)
   * @param triggerAssetHook true if the adjustment need to be routed to Asset's custom hook
   * @param managerData data passed to manager of account
   */
  function assetAdjustment(AssetAdjustment memory adjustment, bool triggerAssetHook, bytes memory managerData)
    external
    onlyAsset(adjustment.asset)
    returns (int postAdjustmentBalance)
  {
    uint tradeId = ++lastTradeId;
    // balance adjustment is routed through asset if triggerAssetHook == true
    int delta;
    (postAdjustmentBalance, delta,) = _adjustBalance(adjustment, tradeId, triggerAssetHook);
    _managerHook(
      adjustment.acc,
      tradeId,
      msg.sender,
      AssetDeltaLib.getDeltasFromSingleAdjustment(adjustment.asset, adjustment.subId, delta),
      managerData
    );
  }

  /**
   * @dev the order field is never set back to 0 to save on gas
   *      ensure balance != 0 when using the BalandAnceOrder.order field
   * @param tradeId a shared id for both asset and manager hooks within a same call
   * @param triggerHook whether this call should trigger asset hook
   * @return postBalance the final balance after adjustment
   * @return delta exact amount updated during the adjustment
   * @return needAllowance whether this adjustment needs allowance
   */
  function _adjustBalance(AssetAdjustment memory adjustment, uint tradeId, bool triggerHook)
    internal
    returns (int postBalance, int delta, bool needAllowance)
  {
    BalanceAndOrder storage userBalanceAndOrder = balanceAndOrder[adjustment.acc][adjustment.asset][adjustment.subId];
    int preBalance = int(userBalanceAndOrder.balance);

    // allow asset to modify final balance in special cases
    if (triggerHook) {
      (postBalance, needAllowance) = _assetHook(adjustment, tradeId, preBalance, msg.sender);
      delta = postBalance - preBalance;
    } else {
      postBalance = preBalance + adjustment.amount;
      delta = adjustment.amount;
      // needAllowance id default to: only need allowance if subtracting from account
      needAllowance = adjustment.amount < 0;
    }

    userBalanceAndOrder.balance = postBalance.toInt240();
    if (preBalance != 0 && postBalance == 0) {
      _removeHeldAsset(adjustment.acc, userBalanceAndOrder.order);
    } else if (preBalance == 0 && postBalance != 0) {
      userBalanceAndOrder.order = _addHeldAsset(adjustment.acc, adjustment.asset, adjustment.subId);
    }

    emit BalanceAdjusted(
      adjustment.acc,
      address(manager[adjustment.acc]),
      HeldAsset({asset: adjustment.asset, subId: uint96(adjustment.subId)}),
      delta,
      preBalance,
      postBalance,
      tradeId
    );
  }

  ////////////////////////////
  // Checks and Permissions //
  ////////////////////////////

  /**
   * @notice Hook that calls the manager once per account during:
   *         1. Transfers
   *         2. Assymetric balance adjustments from Assets
   *
   * @param accountId ID of account being checked
   * @param tradeId a shared id for both asset and manager hooks within a same call
   * @param caller address of msg.sender initiating balance adjustment
   * @param managerData open ended data passed to manager
   */
  function _managerHook(
    uint accountId,
    uint tradeId,
    address caller,
    AssetDelta[] memory deltas,
    bytes memory managerData
  ) internal {
    manager[accountId].handleAdjustment(accountId, tradeId, caller, deltas, managerData);
  }

  /**
   * @notice Hook that calls the asset during:
   *         1. Transfers
   *         2. Assymetric balance adjustments from Managers or Asset
   * @dev as hook is called for every asset transfer (unlike _managerHook())
   *      care must be given to reduce gas usage
   * @param tradeId a shared id for both asset and manager hooks within a same call.
   * @param adjustment all details related to balance adjustment
   * @param preBalance balance before adjustment
   * @param caller address of msg.sender initiating balance adjustment
   * @return finalBalance the amount should be written as final balance
   * @return needAllowance true if this adjustment needs to consume adjustment
   */
  function _assetHook(AssetAdjustment memory adjustment, uint tradeId, int preBalance, address caller)
    internal
    returns (int finalBalance, bool needAllowance)
  {
    return adjustment.asset.handleAdjustment(adjustment, tradeId, preBalance, manager[adjustment.acc], caller);
  }

  //////////
  // Util //
  //////////

  /**
   * @notice Called when the account does not already hold the (asset, subId)
   * @dev Useful for managers to check the risk of the whole account
   * @param accountId account id
   * @param asset asset contract
   * @param subId subId of asset
   * @return newOrder order that can be used to access this entry in heldAsset array
   */
  function _addHeldAsset(uint accountId, IAsset asset, uint subId) internal returns (uint16 newOrder) {
    heldAssets[accountId].push(HeldAsset({asset: asset, subId: subId.toUint96()}));
    newOrder = (heldAssets[accountId].length - 1).toUint16();
  }

  /**
   * @notice Called when the balance of a (asset, subId) returns to zero
   * @dev order used to gas efficiently remove assets from large accounts
   *      1. removes ~200k gas overhead for a 100 position portfolio
   *      2. for expiration with strikes, reduces gas overheada by ~150k
   *      for gas efficiency, order field is not reset when an asset is removed
   */
  function _removeHeldAsset(uint accountId, uint16 order) internal {
    // swap order value if middle asset removed
    uint heldAssetLen = heldAssets[accountId].length;

    // if the entry is not the last one: move the last asset to index #order
    if (order != heldAssetLen - 1) {
      HeldAsset memory assetToMove = heldAssets[accountId][heldAssetLen - 1];
      heldAssets[accountId][order] = assetToMove;

      // update the "order" field of the moved asset for an account
      balanceAndOrder[accountId][assetToMove.asset][uint(assetToMove.subId)].order = order;
    }

    heldAssets[accountId].pop(); // 200 gas
  }

  /**
   * @dev get unique assets from heldAssets.
   *      heldAssets can hold multiple entries with same asset but different subId
   * @return uniqueAssets list of address
   */
  function _getUniqueAssets(HeldAsset[] memory assets)
    internal
    pure
    returns (address[] memory uniqueAssets, uint length)
  {
    uniqueAssets = new address[](assets.length);

    for (uint i; i < assets.length; ++i) {
      length = UnorderedMemoryArray.addUniqueToArray(uniqueAssets, address(assets[i].asset), length);
    }

    UnorderedMemoryArray.trimArray(uniqueAssets, length);
  }

  //////////
  // View //
  //////////

  /**
   * @notice Gets an account's balance for an (asset, subId)
   * @param accountId ID of account
   * @param asset IAsset of balance
   * @param subId subId of balance
   */
  function getBalance(uint accountId, IAsset asset, uint subId) external view returns (int balance) {
    BalanceAndOrder memory userBalanceAndOrder = balanceAndOrder[accountId][asset][subId];
    return int(userBalanceAndOrder.balance);
  }

  /**
   * @notice Gets a list of all asset balances of an account
   * @dev can use balanceAndOrder() to get the index of a specific balance
   * @param accountId ID of account
   */
  function getAccountBalances(uint accountId) external view returns (AssetBalance[] memory assetBalances) {
    uint allAssetBalancesLen = heldAssets[accountId].length;
    assetBalances = new AssetBalance[](allAssetBalancesLen);
    for (uint i; i < allAssetBalancesLen; i++) {
      HeldAsset memory heldAsset = heldAssets[accountId][i];
      BalanceAndOrder memory userBalanceAndOrder = balanceAndOrder[accountId][heldAsset.asset][uint(heldAsset.subId)];

      assetBalances[i] =
        AssetBalance({asset: heldAsset.asset, subId: uint(heldAsset.subId), balance: int(userBalanceAndOrder.balance)});
    }
    return assetBalances;
  }

  /**
   * @dev get unique assets from heldAssets.
   *      heldAssets can hold multiple entries with same asset but different subId
   * @return uniqueAssets list of address
   */
  function getUniqueAssets(uint accountId) external view returns (address[] memory uniqueAssets) {
    (uniqueAssets,) = _getUniqueAssets(heldAssets[accountId]);
  }

  /**
   * @dev get domain separator for signing
   */
  function domainSeparator() external view returns (bytes32) {
    return _domainSeparatorV4();
  }

  ////////////
  // Access //
  ////////////

  /**
   * @dev giving managers exclusive rights to transfer account ownerships
   * @dev this function overrides ERC721._isApprovedOrOwner(spender, tokenId);
   *
   */
  function _isApprovedOrOwner(address spender, uint accountId) internal view override returns (bool) {
    if (super._isApprovedOrOwner(spender, accountId)) return true;

    // check if caller is manager
    return address(manager[accountId]) == msg.sender;
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/cryptography/EIP712.sol";
import "openzeppelin/utils/cryptography/SignatureChecker.sol";

import "./interfaces/IAsset.sol";
import "./interfaces/IManager.sol";
import "./Allowances.sol";
import "./libraries/ArrayLib.sol";
import "./libraries/AssetDeltaLib.sol";
import "./libraries/PermitAllowanceLib.sol";

/**
 * todo: update memory to calldata
 * todo: permit
 * @title Account
 * @author Lyra
 * @notice Base layer that manages:
 *         1. balances for each (account, asset, subId)
 *         2. routing of manager, asset, allowance hooks / checks during any balance adjustment event
 *         3. account creation / manager assignment
 */
contract Account is Allowances, ERC721, EIP712, AccountStructs {
  using SafeCast for int;
  using SafeCast for uint;
  using AssetDeltaLib for AssetDeltaArrayCache;

  ///////////////
  // Variables //
  ///////////////

  /// @dev account id (ERC721 id) for the next account being created
  uint public nextId = 0;

  /// @dev accountId to manager
  mapping(uint => IManager) public manager;

  /// @dev accountId => asset => subId => BalanceAndOrder struct
  mapping(uint => mapping(IAsset => mapping(uint => BalanceAndOrder))) public balanceAndOrder;

  /// @dev accountId to non-zero assets array
  mapping(uint => HeldAsset[]) public heldAssets;

  ////////////
  // Events //
  ////////////

  /// @dev Emitted account created or split
  event AccountCreated(address indexed owner, uint indexed accountId, address indexed manager);

  /// @dev Emitted when account manager is updated
  event AccountManagerChanged(uint indexed accountId, address indexed oldManager, address indexed newManager);

  /// @dev Emitted during any balance change event.
  event BalanceAdjusted(
    uint indexed accountId,
    address indexed manager,
    HeldAsset indexed assetAndSubId,
    int delta,
    int preBalance,
    int postBalance
  );

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
    newId = ++nextId;
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

    // update the manager after all checks (external calls) are done. expected reentry pattern
    manager[accountId] = newManager;

    // trigger the manager hook on the new manager. Same as post-transfer checks
    AssetDelta[] memory deltas = new AssetDelta[](0);
    _managerHook(accountId, msg.sender, deltas, newManagerData);

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
   * todo: update natspec
   * @dev adjust allowance by signature
   * @param allowancePermit struct specifying accountId, delegator
   * @param signature signature {V, R, S}
   */
  function permit(PermitAllowance calldata allowancePermit, bytes calldata signature) external {
    _permit(allowancePermit, signature);
  }

  function _permit(PermitAllowance calldata allowancePermit, bytes calldata signature) internal {
    if (allowancePermit.deadline < block.timestamp) revert AC_SignatureExpired();

    // owner of the account, who should be the signer
    address owner = ownerOf(allowancePermit.accountId);

    bytes32 structHash = PermitAllowanceLib.hash(allowancePermit);

    // check the signature is from the current owner
    if (!SignatureChecker.isValidSignatureNow(owner, _hashTypedDataV4(structHash), signature)) {
      revert AC_InvalidPermitSignature();
    }

    // todo: consume nonce

    // update asset allowance
    _setAssetAllowances(allowancePermit.accountId, owner, allowancePermit.delegate, allowancePermit.assetAllowances);

    // update subId allowance
    _setSubIdAllowances(allowancePermit.accountId, owner, allowancePermit.delegate, allowancePermit.subIdAllowances);
  }

  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  /**
   * @notice Transfer an amount from one account to another for a specific (asset, subId)
   * @param assetTransfer (fromAcc, toAcc, asset, subId, amount)
   * @param managerData data passed to managers of both accounts
   */
  function submitTransfer(AssetTransfer memory assetTransfer, bytes memory managerData) external {
    (int fromDelta, int toDelta) = _transferAsset(assetTransfer);
    _managerHook(
      assetTransfer.fromAcc,
      msg.sender,
      AssetDeltaLib.getDeltasFromSingleAdjustment(assetTransfer.asset, assetTransfer.subId, fromDelta),
      managerData
    );
    _managerHook(
      assetTransfer.toAcc,
      msg.sender,
      AssetDeltaLib.getDeltasFromSingleAdjustment(assetTransfer.asset, assetTransfer.subId, toDelta),
      managerData
    );
  }

  /**
   * @notice Batch several transfers
   *         Gas efficient when modifying the same account several times,
   *         as _managerHook() is only performed once per account
   * @param assetTransfers array of (fromAcc, toAcc, asset, subId, amount)
   * @param managerData data passed to every manager involved in trade
   */
  function submitTransfers(AssetTransfer[] memory assetTransfers, bytes memory managerData) external {
    uint transfersLen = assetTransfers.length;

    /* Keep track of seen accounts to assess risk once per account */
    uint[] memory seenAccounts = new uint[](transfersLen * 2);

    // seen index => delta[]
    AssetDeltaArrayCache[] memory assetDeltas = new AssetDeltaArrayCache[](transfersLen * 2);

    uint nextSeenId = 0;

    for (uint i; i < transfersLen; ++i) {
      // if from or to account is not seens before, add to seenAccounts in memory
      (uint fromIndex, uint toIndex) = (0, 0);
      (nextSeenId, fromIndex) = ArrayLib.addUniqueToArray(seenAccounts, assetTransfers[i].fromAcc, nextSeenId);
      (nextSeenId, toIndex) = ArrayLib.addUniqueToArray(seenAccounts, assetTransfers[i].toAcc, nextSeenId);

      (int fromDelta, int toDelta) = _transferAsset(assetTransfers[i]);

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
      AccountStructs.AssetDelta[] memory nonEmptyDeltas = AssetDeltaLib.getDeltasFromArrayCache(assetDeltas[i]);
      _managerHook(seenAccounts[i], msg.sender, nonEmptyDeltas, managerData);
    }
  }

  /**
   * @notice Transfer an amount from one account to another for a specific (asset, subId)
   * @dev    update the allowance and balanceAndOrder storage
   * @param assetTransfer (fromAcc, toAcc, asset, subId, amount)
   */
  function _transferAsset(AssetTransfer memory assetTransfer) internal returns (int fromDelta, int toDelta) {
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
    (, int fromDelta_, bool fromAdjustmentNeedAllowance) = _adjustBalance(fromAccAdjustment, true);
    (, int toDelta_, bool toAdjustmentNeedAllowance) = _adjustBalance(toAccAdjustment, true);

    // if it's not ERC721 approved: spend allowances
    if (fromAdjustmentNeedAllowance && !_isApprovedOrOwner(msg.sender, fromAccAdjustment.acc)) {
      _spendAllowance(fromAccAdjustment, ownerOf(fromAccAdjustment.acc), msg.sender);
    }
    if (toAdjustmentNeedAllowance && !_isApprovedOrOwner(msg.sender, toAccAdjustment.acc)) {
      _spendAllowance(toAccAdjustment, ownerOf(toAccAdjustment.acc), msg.sender);
    }

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
    // balance is adjusted based on asset hook
    (postAdjustmentBalance,,) = _adjustBalance(adjustment, true);
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
    // balance adjustment is routed through asset if triggerAssetHook == true
    int delta;
    (postAdjustmentBalance, delta,) = _adjustBalance(adjustment, triggerAssetHook);
    _managerHook(
      adjustment.acc,
      msg.sender,
      AssetDeltaLib.getDeltasFromSingleAdjustment(adjustment.asset, adjustment.subId, delta),
      managerData
    );
  }

  /**
   * @dev the order field is never set back to 0 to safe on gas
   *      ensure balance != 0 when using the BalandAnceOrder.order field
   * @return postBalance the final balance after adjustment
   * @return delta exact amount updated during the adjustment
   * @return needAllowance whether this adjustment needs allowance
   */
  function _adjustBalance(AssetAdjustment memory adjustment, bool triggerHook)
    internal
    returns (int postBalance, int delta, bool needAllowance)
  {
    BalanceAndOrder storage userBalanceAndOrder = balanceAndOrder[adjustment.acc][adjustment.asset][adjustment.subId];
    int preBalance = int(userBalanceAndOrder.balance);

    // allow asset to modify final balance in special cases
    if (triggerHook) {
      (postBalance, needAllowance) = _assetHook(adjustment, preBalance, msg.sender);
      delta = postBalance - preBalance;
    } else {
      postBalance = preBalance + adjustment.amount;
      delta = adjustment.amount;
      // needAllowance id default to: only need allowance if substracting from account
      needAllowance = adjustment.amount < 0;
    }

    /* for gas efficiency, order unchanged when asset removed */
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
      postBalance
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
   * @param caller address of msg.sender initiating balance adjustment
   * @param managerData open ended data passed to manager
   */
  function _managerHook(uint accountId, address caller, AssetDelta[] memory deltas, bytes memory managerData) internal {
    manager[accountId].handleAdjustment(accountId, caller, deltas, managerData);
  }

  /**
   * @notice Hook that calls the asset during:
   *         1. Transfers
   *         2. Assymetric balance adjustments from Managers or Asset
   * @dev as hook is called for every asset transfer (unlike _managerHook())
   *      care must be given to reduce gas usage
   * @param adjustment all details related to balance adjustment
   * @param preBalance balance before adjustment
   * @param caller address of msg.sender initiating balance adjustment
   * @return finalBalance the amount should be written as final balance
   * @return needAllowance true if this adjustment needs to consume adjustment
   */
  function _assetHook(AssetAdjustment memory adjustment, int preBalance, address caller)
    internal
    returns (int finalBalance, bool needAllowance)
  {
    return adjustment.asset.handleAdjustment(adjustment, preBalance, manager[adjustment.acc], caller);
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
   */
  function _removeHeldAsset(uint accountId, uint16 order) internal {
    /* swap order value if middle asset removed */
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
   * @return length max index of returned address that is non-zero
   */
  function _getUniqueAssets(HeldAsset[] memory assets)
    internal
    pure
    returns (address[] memory uniqueAssets, uint length)
  {
    uniqueAssets = new address[](assets.length);

    for (uint i; i < assets.length; ++i) {
      length = ArrayLib.addUniqueToArray(uniqueAssets, address(assets[i].asset), length);
    }
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

  ////////////
  // Errors //
  ////////////

  error AC_OnlyManager();

  error AC_OnlyAsset();

  error AC_TooManyTransfers();

  error AC_InvalidPermitSignature();

  error AC_SignatureExpired();

  error AC_NotOwnerOrERC721Approved(address spender, uint accountId, address owner, IManager manager, address approved);

  error AC_CannotTransferAssetToOneself(address caller, uint accountId);

  error AC_CannotChangeToSameManager(address caller, uint accountId);
}

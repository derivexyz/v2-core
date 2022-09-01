pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "./interfaces/IAbstractAsset.sol";
import "./interfaces/IAbstractManager.sol";
import "./interfaces/AccountStructs.sol";

import "forge-std/console2.sol";

contract Account is ERC721, Owned {

  ///////////////
  // Variables //
  ///////////////

  IERC20 public feeToken;
  address public feeRecipient;
  uint public creationFee;

  uint nextId = 1;
  mapping(uint => IAbstractManager) manager;
  mapping(bytes32 => int) public balances;
  mapping(bytes32 => mapping(address => AccountStructs.Allowance)) public delegateSubIdAllowances;
  mapping(bytes32 => mapping(address => AccountStructs.Allowance)) public delegateAssetAllowances;

  mapping(uint => AccountStructs.HeldAsset[]) heldAssets;
  mapping(bytes32 => uint) heldOrder; // starts at 1

  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Owned() {}

  ////////////////////
  // Protocol Admin //
  ////////////////////

  function setCreationFee(address _feeToken,  address _feeRecipient, uint _creationFee) onlyOwner() external {
    require(
      _feeToken != address(0) && _feeRecipient != address(0), 
      "fee token & recipient cannot be zero address"
    );

    creationFee = _creationFee;
    feeToken = IERC20(_feeToken);
    feeRecipient = _feeRecipient;
  }

  ///////////////////
  // Account Admin //
  ///////////////////

  function createAccount(IAbstractManager _manager, address owner) public returns (uint newId) {
    // charge a flat fee to prevent spam
    if (creationFee > 0) {
      feeToken.transferFrom(msg.sender, feeRecipient, creationFee);
    }

    newId = nextId++;
    manager[newId] = _manager;
    _mint(owner, newId);
    return newId;
  }

  /// @dev blanket allowance over transfers, merges, splits, account transfers 
  ///      only one blanket delegate allowed
  function setFullDelegate(
    uint accountId,
    address delegate
  ) external {
    _approve(delegate, accountId);
  }

  /// @dev the sum of asset allowances + subId allowances is used during _delegateCheck()
  ///      subId allowances are decremented before asset allowances
  ///      cannot merge with this type of allowance
  function setAssetDelegateAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    AccountStructs.Allowance[] memory allowances  
  ) external {
    _updateDelegateAllowances(accountId, delegate, assets, new uint[](0), allowances);
  }

  function setSubIdDelegateAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    uint[] memory subIds,
    AccountStructs.Allowance[] memory allowances
  ) external {
    _updateDelegateAllowances(accountId, delegate, assets, subIds, allowances);
  }

  function _updateDelegateAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    uint[] memory subIds,
    AccountStructs.Allowance[] memory allowances
  ) internal {
    require(msg.sender == ownerOf(accountId), "only owner");

    uint assetsLen = assets.length;
    for (uint i; i < assetsLen; i++) {
      AccountStructs.Allowance memory allowance = AccountStructs.Allowance({
        positive: allowances[i].positive,
        negative: allowances[i].negative
      });

      if (subIds.length > 0) {
        delegateSubIdAllowances[
          _getEntryKey(accountId, assets[i], subIds[i])][delegate] = allowance;
      } else {     // uses 0 when encoding key for delegateAssetAllowances key
        delegateAssetAllowances[
          _getEntryKey(accountId, assets[i], 0)][delegate] = allowance;
      }
    }
  }

  /// @dev Merges all accounts into first account and leaves remaining empty but not burned
  ///      This ensures accounts can be reused after being merged
  function merge(uint targetAccount, uint[] memory accountsToMerge) external {
    // does not use _delegateCheck() for gas efficiency
    require(_isApprovedOrOwner(msg.sender, targetAccount), "must be ERC721 approved to merge");

    uint mergingAccLen = accountsToMerge.length;
    for (uint i = 0; i < mergingAccLen; i++) {
      require(_isApprovedOrOwner(msg.sender, accountsToMerge[i]), "must be ERC721 approved to merge");
      require(manager[targetAccount] == manager[accountsToMerge[i]], "accounts use different risk models");

      uint heldAssetLen = heldAssets[accountsToMerge[i]].length;
      for (uint j; j < heldAssetLen; j++) {
        AccountStructs.HeldAsset memory heldAsset = heldAssets[accountsToMerge[i]][j];
        bytes32 targetKey = _getEntryKey(targetAccount, heldAsset.asset, heldAsset.subId);
        bytes32 mergeAccountKey = _getEntryKey(accountsToMerge[i], heldAsset.asset, heldAsset.subId);

        // TODO: test max number of assets this can support

        int preBalance = balances[targetKey];
        int balanceToAdd = balances[mergeAccountKey];
        if (preBalance == 0) { // add asset if not present 
          _addHeldAsset(targetAccount, heldAsset.asset, heldAsset.subId);
        } else if (preBalance + balanceToAdd == 0) { // remove if balance = 0
          // TODO: gas will depend on both size of target
          _removeHeldAsset(targetAccount, heldAsset.asset, heldAsset.subId);
        }

        // increment target account balance and set merging account to 0
        balances[targetKey] = preBalance + balanceToAdd;
        balances[mergeAccountKey] = 0;
      }

      _clearHeldAssets(accountsToMerge[i]);
    }
  }

  /// @dev same as (1) create account (2) submit transfers [the `AssetTranfser.toAcc` field is overwritten]
  ///      msg.sender must be delegate approved to split
  function split(uint accountToSplitId, AccountStructs.AssetTransfer[] memory assetTransfers, address splitAccountOwner) external {
    uint newAccountId = createAccount(manager[accountToSplitId], msg.sender);

    uint transfersLen = assetTransfers.length;
    for (uint i; i < transfersLen; ++i) {
      assetTransfers[i].toAcc = newAccountId;
    }

    submitTransfers(assetTransfers);

    if (splitAccountOwner != msg.sender) {
      transferFrom(msg.sender, splitAccountOwner, newAccountId);
    }
  }

  /// @dev giving managers exclusive rights to transfer account ownerships
  function _isApprovedOrOwner(address spender, uint256 tokenId) internal view override returns (bool) {
    address owner = ERC721.ownerOf(tokenId);
    bool isManager = ownerOf(tokenId) == msg.sender;
    return (
      spender == owner || 
      isApprovedForAll(owner, spender) || 
      getApproved(tokenId) == spender || 
      isManager
    );
  }

  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  function submitTransfers(AccountStructs.AssetTransfer[] memory assetTransfers) public {
    // Do the transfers
    uint transfersLen = assetTransfers.length;

    // Keep track of seen accounts to assess risk later
    uint[] memory seenAccounts = new uint[](transfersLen * 2);
    uint nextSeenId = 0;

    for (uint i; i < transfersLen; ++i) {
      _transferAsset(assetTransfers[i]);

      uint fromAcc = assetTransfers[i].fromAcc;
      if (!_findInArray(seenAccounts, fromAcc)) {
        seenAccounts[nextSeenId++] = fromAcc;
      }
      uint toAcc = assetTransfers[i].toAcc;
      if (!_findInArray(seenAccounts, toAcc)) {
        seenAccounts[nextSeenId++] = toAcc;
      }
    }

    // Assess the risk for all modified balances
    for (uint i; i < nextSeenId; i++) {
      _managerCheck(seenAccounts[i], msg.sender);
    }
  }


  function _transferAsset(AccountStructs.AssetTransfer memory assetTransfer) internal {
    AccountStructs.AssetAdjustment memory fromAccAdjustment = AccountStructs.AssetAdjustment({
      acc: assetTransfer.fromAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: -assetTransfer.amount
    });

    AccountStructs.AssetAdjustment memory toAccAdjustment = AccountStructs.AssetAdjustment({
      acc: assetTransfer.toAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: assetTransfer.amount
    });

    _delegateCheck(fromAccAdjustment, msg.sender);
    _delegateCheck(toAccAdjustment, msg.sender);

    _adjustBalance(fromAccAdjustment);
    _adjustBalance(toAccAdjustment);

  }

  /// @dev privileged function that only the asset can call to do things like minting and burning
  function adjustBalance(
    AccountStructs.AssetAdjustment memory adjustment
  ) onlyManagerOrAsset(adjustment.acc, adjustment.asset) external returns (int postAdjustmentBalance) {
    require(msg.sender == address(manager[adjustment.acc]) || msg.sender == address(adjustment.asset),
      "only managers and assets can make assymmetric adjustments");
    
    _adjustBalance(adjustment);
    _managerCheck(adjustment.acc, msg.sender); // since caller is passed, manager can internally decide to ignore check
    
    return balances[_getEntryKey(adjustment.acc, adjustment.asset, adjustment.subId)];
  }

  function _adjustBalance(AccountStructs.AssetAdjustment memory adjustment) internal {
    bytes32 balanceKey = _getEntryKey(adjustment.acc, adjustment.asset, adjustment.subId);

    int preBalance = balances[balanceKey];
    balances[balanceKey] += adjustment.amount;
    int postBalance = balances[balanceKey];

    _assetCheck(adjustment.asset, adjustment.subId, adjustment.acc, preBalance, postBalance, msg.sender);

    if (preBalance != 0 && postBalance == 0) {
      _removeHeldAsset(adjustment.acc, adjustment.asset, adjustment.subId);
    } else if (preBalance == 0 && postBalance != 0) {
      _addHeldAsset(adjustment.acc, adjustment.asset, adjustment.subId);
    }
  }

  ////////////////////////////
  // Checks and Permissions //
  ////////////////////////////

  function _managerCheck(
    uint accountId, 
    address caller
  ) internal {
    manager[accountId].handleAdjustment(accountId, _getAccountBalances(accountId), caller);
  }

  function _assetCheck(
    IAbstractAsset asset, 
    uint subId, 
    uint accountId,
    int preBalance, 
    int postBalance, 
    address caller
  ) internal {
    asset.handleAdjustment(
      accountId, preBalance, postBalance, subId, manager[accountId], caller
    );
  }

  function _delegateCheck(
    AccountStructs.AssetAdjustment memory adjustment, address delegate
  ) internal {
    // ERC721 approved or owner get blanket allowance
    if (_isApprovedOrOwner(msg.sender, adjustment.acc)) { return; }

    AccountStructs.Allowance storage subIdAllowance = 
      delegateSubIdAllowances[_getEntryKey(adjustment.acc, adjustment.asset, adjustment.subId)][delegate];
    AccountStructs.Allowance storage assetAllowance = 
      delegateAssetAllowances[_getEntryKey(adjustment.acc, adjustment.asset, 0)][delegate];

    uint absAmount = _abs(adjustment.amount);

    bool isPositiveAdjustment = adjustment.amount > 0;
    bool isAllowanceEnough = (isPositiveAdjustment)
      ? absAmount <= subIdAllowance.positive + assetAllowance.positive
      : absAmount <= subIdAllowance.negative + assetAllowance.negative;

    require(isAllowanceEnough, "delegate does not have enough allowance");

    if (isAllowanceEnough && isPositiveAdjustment) {
      if (absAmount <= subIdAllowance.positive) {
        subIdAllowance.positive -= absAmount;
      } else { // subId allowances are decremented first
        subIdAllowance.positive = 0;
        assetAllowance.positive -= absAmount - subIdAllowance.positive;
      }
    } else {
      if (absAmount <= subIdAllowance.negative) {
        subIdAllowance.negative -= absAmount;
      } else {
        subIdAllowance.negative = 0;
        assetAllowance.negative -= absAmount - subIdAllowance.negative;
      }
    } 
  }

  //////////
  // View //
  //////////

  function getAccountBalances(uint accountId) external view returns (AccountStructs.AssetBalance[] memory assetBalances) {
    return _getAccountBalances(accountId);
  }

  function _getAccountBalances(uint accountId)
    internal
    view
    returns (AccountStructs.AssetBalance[] memory assetBalances)
  {
    uint allAssetBalancesLen = heldAssets[accountId].length;
    assetBalances = new AccountStructs.AssetBalance[](allAssetBalancesLen);
    for (uint i; i < allAssetBalancesLen; i++) {
      AccountStructs.HeldAsset memory heldAsset = heldAssets[accountId][i];
      assetBalances[i] = AccountStructs.AssetBalance({
        asset: heldAsset.asset,
        subId: heldAsset.subId,
        balance: balances[_getEntryKey(accountId, heldAsset.asset, heldAsset.subId)]
      });
    }
    return assetBalances;
  }


  //////////
  // Util //
  //////////

  /// @dev keep mappings succinct and gas efficient
  function _getEntryKey(
    uint accountId, IAbstractAsset asset, uint subId
  ) internal pure returns (bytes32 balanceKey) {
    return keccak256(abi.encodePacked(accountId, address(asset), subId));
  } 

  /// @dev this should never be called if the account already holds the asset
  function _addHeldAsset(uint accountId, IAbstractAsset asset, uint subId) internal {
    heldAssets[accountId].push(AccountStructs.HeldAsset({asset: asset, subId: subId}));
    // extra 20k gas, but improvement over 2k * 100 positions during 1x removeHeldAsset
    heldOrder[_getEntryKey(accountId, asset, subId)] = heldAssets[accountId].length;
  }
  

  /// @dev uses heldOrder mapping to make removals gas efficient 
  ///      moves static 20k per added asset overhead
  ///      (1) removes $200k bottleneck from removeHeldAsset
  ///      (2) reduces overall gas spent during large splits
  ///      (3) low overhead for everyday traders with 1-3 transfers 
  function _removeHeldAsset(uint accountId, IAbstractAsset asset, uint subId) internal {
    uint currentAssetOrder = heldOrder[_getEntryKey(accountId, asset, subId)];
    require(currentAssetOrder != 0, "asset not present");

    // remove asset from heldOrder
    heldOrder[_getEntryKey(accountId, asset, subId)] = 0; // 5k refund

    // swap orders if middle asset removed
    uint heldAssetLen = heldAssets[accountId].length;
    if (currentAssetOrder != heldAssetLen) { 
      heldAssets[accountId][currentAssetOrder - 1] = heldAssets[accountId][heldAssetLen - 1];
      heldOrder[_getEntryKey(accountId, asset, subId)] = currentAssetOrder; // 3k gas 
    }

    // remove asset from heldAsset
    heldAssets[accountId].pop();
  }

  /// @dev used when blanket deleting all assets
  function _clearHeldAssets(uint accountId) internal {
    AccountStructs.HeldAsset[] memory assets = heldAssets[accountId];
    uint heldAssetLen = assets.length;
    for (uint i; i < heldAssetLen; i++) {
      heldOrder[_getEntryKey(accountId, assets[i].asset, assets[i].subId)] = 0;
    }
    delete heldAssets[accountId];
  }

  function _abs(int amount) internal pure returns (uint absAmount) {
    return (amount >= 0) ? uint256(amount) : SafeCast.toUint256(-amount);
  }

  function _findInArray(uint[] memory array, uint toFind) internal pure returns (bool found) {
    /// TODO: Binary search? :cringeGrin: We do have the array max length
    uint arrayLen = array.length;
    for (uint i; i < arrayLen; ++i) {
      if (array[i] == 0) {
        return false;
      }
      if (array[i] == toFind) {
        return true;
      }
    }
    return false;
  }

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyManagerOrAsset(uint accountId, IAbstractAsset asset) {
    require(msg.sender == ownerOf(accountId) || 
      msg.sender == address(asset), 
    "only manager or asset");
    _;
  }


}
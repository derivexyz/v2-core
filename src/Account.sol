pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "./interfaces/IAbstractAsset.sol";
import "./interfaces/IAbstractManager.sol";
import "./interfaces/MarginStructs.sol";

import "forge-std/console2.sol";

contract Account is ERC721 {

  ///////////////
  // Variables //
  ///////////////

  uint nextId = 1;
  mapping(uint => IAbstractManager) manager;
  mapping(bytes32 => int) public balances;
  mapping(bytes32 => mapping(address => MarginStructs.Allowance)) public delegateAllowances;
  mapping(uint => MarginStructs.HeldAsset[]) heldAssets;
  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

  ///////////////////
  // Account Admin //
  ///////////////////

  function createAccount(IAbstractManager _manager) external returns (uint newId) {
    newId = nextId++;
    manager[newId] = _manager;
    _mint(msg.sender, newId);
    return newId;
  }

  function setDelegateAllowances(
    uint accountId, address delegate, MarginStructs.AssetAllowance[] memory allowances
  ) external {
    require(msg.sender == ownerOf(accountId));

    uint allowancesLen = allowances.length;
    for (uint i; i < allowancesLen; i++) {
      delegateAllowances[
        _getBalanceKey(accountId, allowances[i].asset, allowances[i].subId)
      ][delegate] = MarginStructs.Allowance({
        positive: allowances[i].positive,
        negative: allowances[i].negative
      });
    }
  }

  function merge(uint[] memory accounts) external {}

  function changeOwner(uint accountId, address newOwner) external {}


  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  function submitTransfers(MarginStructs.AssetTransfer[] memory assetTransfers) external {
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


  function _transferAsset(MarginStructs.AssetTransfer memory assetTransfer) internal {
    MarginStructs.AssetAdjustment memory fromAccAdjustment = MarginStructs.AssetAdjustment({
      acc: assetTransfer.fromAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: -assetTransfer.amount
    });

    MarginStructs.AssetAdjustment memory toAccAdjustment = MarginStructs.AssetAdjustment({
      acc: assetTransfer.toAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: assetTransfer.amount
    });

    require(_delegateCheck(fromAccAdjustment, msg.sender), "delegate not approved by from-account");
    require(_delegateCheck(toAccAdjustment, msg.sender), "delegate not approved by to-account");

    _adjustBalance(fromAccAdjustment);
    _adjustBalance(toAccAdjustment);

  }

  /// @dev privileged function that only the asset can call to do things like minting and burning
  function adjustBalance(MarginStructs.AssetAdjustment memory adjustment) external returns (int postAdjustmentBalance) {
    uint accountId = adjustment.acc;
    _adjustBalance(adjustment);

    if (msg.sender == address(adjustment.asset)) {
      _managerCheck(accountId, msg.sender);
    } else {
      require(msg.sender == address(manager[accountId]));
    }
    
    return balances[_getBalanceKey(adjustment.acc, adjustment.asset, adjustment.subId)];
  }

  function _adjustBalance(MarginStructs.AssetAdjustment memory adjustment) internal {
    bytes32 balanceKey = _getBalanceKey(adjustment.acc, adjustment.asset, adjustment.subId);

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

  function _delegateCheck(
    MarginStructs.AssetAdjustment memory adjustment, address delegate
  ) internal returns (bool isApproved) {
    // owner is by default delegate approved
    if (delegate == ownerOf(adjustment.acc)) { return true; }

    MarginStructs.Allowance storage allowance = 
      delegateAllowances[_getBalanceKey(adjustment.acc, adjustment.asset, adjustment.subId)][delegate];

    bool isPositiveApproved = adjustment.amount >= 0 && 
      SafeCast.toUint256(adjustment.amount) <= allowance.positive;
    bool isNegativeApproved = adjustment.amount < 0 && 
      SafeCast.toUint256(-adjustment.amount) <= allowance.negative;

    if (isPositiveApproved) {
      // positive transfer and delegate / counterparty approved
      allowance.positive -= SafeCast.toUint256(adjustment.amount);
      return true;
    } else if (isNegativeApproved) {
      // negative transfer and delegate / counterparty approved
      allowance.negative -= SafeCast.toUint256(-adjustment.amount);
      return true;
    } else {
      // unapproved delegate / counterparty
      return false;
    }
  }

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

  //////////
  // View //
  //////////

  function getAccountBalances(uint accountId) external view returns (MarginStructs.AssetBalance[] memory assetBalances) {
    return _getAccountBalances(accountId);
  }

  function _getAccountBalances(uint accountId)
    internal
    view
    returns (MarginStructs.AssetBalance[] memory assetBalances)
  {
    uint allAssetBalancesLen = heldAssets[accountId].length;
    assetBalances = new MarginStructs.AssetBalance[](allAssetBalancesLen);
    for (uint i; i < allAssetBalancesLen; i++) {
      MarginStructs.HeldAsset memory heldAsset = heldAssets[accountId][i];
      assetBalances[i] = MarginStructs.AssetBalance({
        asset: heldAsset.asset,
        subId: heldAsset.subId,
        balance: balances[_getBalanceKey(accountId, heldAsset.asset, heldAsset.subId)]
      });
    }
    return assetBalances;
  }


  //////////
  // Util //
  //////////

  /// @dev keep mappings succinct and gas efficient
  function _getBalanceKey(
    uint accountId, IAbstractAsset asset, uint subId
  ) internal pure returns (bytes32 balanceKey) {
    return keccak256(abi.encodePacked(accountId, address(asset), subId));
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

  /// @dev this should never be called if the account already holds the asset
  function _addHeldAsset(uint accountId, IAbstractAsset asset, uint subId) internal {
    heldAssets[accountId].push(MarginStructs.HeldAsset({asset: asset, subId: subId}));
  }

  function _removeHeldAsset(uint accountId, IAbstractAsset asset, uint subId) internal {
    uint heldAssetLen = heldAssets[accountId].length;
    for (uint i; i < heldAssetLen; i++) {
      MarginStructs.HeldAsset memory heldAsset = heldAssets[accountId][i];
      if (heldAsset.asset == asset && heldAsset.subId == subId) {
        if (i != heldAssetLen - 1) {
          heldAssets[accountId][i] = heldAssets[accountId][heldAssetLen - 1];
        }
        heldAssets[accountId].pop();
        return;
      }
    }
    revert("Invalid state");
  }
}
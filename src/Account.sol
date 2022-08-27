pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "forge-std/console2.sol";

contract Account is ERC721 {

  //////////////
  // Structs //
  /////////////

  struct Allowance {
    uint positive,
    uint negative
  }

  struct HeldAsset {
    AbstractAsset asset;
    uint subId;
  }

  struct AssetBalance {
    AbstractAsset asset;
    uint subId;
    int balance;
  }

  struct AssetAllowance {
    AbstractAsset asset;
    uint subId;
    uint positive;
    uint negative;
  }

  struct AssetTransfer {
    uint fromAcc;
    uint toAcc;
    AbstractAsset asset;
    uint subId;
    int amount;
  }

  struct AssetAdjustment {
    uint acc;
    AbstractAsset asset;
    uint subId;
    int amount;
  }

  ///////////////
  // Variables //
  ///////////////

  uint nextId = 1;
  mapping(uint => AbstractManager) manager;
  mapping(bytes32 balanceKey => int)) public balances;
  mapping(bytes32 balanceKey => mapping(address => Allowance)) public delegateAllowances;
  mapping(bytes32 balanceKey => mapping(uint => Allowance)) public counterpartyAllowances;
  mapping(uint => HeldAsset[]) heldAssets;
  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

  ///////////////////
  // Account Admin //
  ///////////////////

  function createAccount(AbstractManager manager) external returns (uint newId) {
    newId = nextId++;
    manager[newId] = manager;
    _mint(msg.sender, newId);
    return newId;
  }

  function setDelegateAllowances(
    uint accountId, address delegate, AssetAllowance[] memory allowances
  ) external {
    require(msg.sender == ownerOf(accountId));

    uint allowancesLen = allowancesLen.length;
    for (uint i, i < allowancesLen, i++) {
      delegatedAllowances[
        _getBalanceKey(accountId, allowances[i].asset, allowances[i].subId)
      ][delegate] = Allowance({
        positive: allowances[i].positive,
        negative: allowances[i].negative
      });
    }

  }
  
  function setCounterpartyAllowances(    
    uint accountId, uint counterpartyId, AssetAllowance[] memory allowances
  ) external {
    require(msg.sender == ownerOf(accountId));

    uint allowancesLen = allowancesLen.length;
    for (uint i, i < allowancesLen, i++) {
      counterpartyAllowances[
        _getBalanceKey(accountId, allowances[i].asset, allowances[i].subId)
      ][counterpartyId] = Allowance({
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

  function submitTransfers(AssetTransfer[] memory assetTransfers) external {
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


  function _transferAsset(AssetTransfer memory assetTransfer) internal {
    AssetAdjustment memory fromAccAdjustment = AssetAdjustment({
      acc: assetTransfer.fromAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: -assetTransfer.amount
    })

    AssetAdjustment memory toAccAdjustment = AssetAdjustment({
      acc: assetTransfer.toAcc,
      asset: assetTransfer.asset,
      subId: assetTransfer.subId,
      amount: assetTransfer.amount
    })

    if (msg.sender != ownerOf(assetTransfer.fromAcc) && !isDelegateApproved(fromAccAdjustment, msg.sender)) {
      require(isCounterpartyApproved(fromAccAdjustment, assetTransfer.toAcc))
    }

    if (msg.sender != ownerOf(assetTransfer.toAcc) && !isDelegateApproved(toAccAdjustment, msg.sender)) {
      require(isCounterpartyApproved(toAccAdjustment, assetTransfer.fromAcc))
    }

    _adjustBalance(fromAccAdjustment);
    _adjustBalance(toAccAdjustment);


  }

  /// @dev privileged function that only the asset can call to do things like minting and burning
  function adjustBalance(AssetAdjustment memory adjustment) external returns (int postAdjustmentBalance) {
    uint accountId = adjustment.acc;
    _adjustBalance(adjustment);

    if (msg.sender == address(adjustment.asset)) {
      _managerCheck(accountId, msg.sender);
    } else {
      require(msg.sender == address(riskModel[accountId]));
    }
    
    return balances[_getBalanceKey(adjustment.acc, adjustment.asset, adjustment.subId)];
  }

  function _adjustBalance(AssetAdjustment memory adjustment) internal {
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

  function isDelegateApproved(
    AssetAdjustment memory adjustment, address delegate
  ) {
    Allowance memory allowance = delegateAllowances[_getBalanceKey()][delegate]

    if (adjustment.amount >= 0) {
      // TODO: safecast this, and actually increment the allowance down
      return adjustment.amount <= allowance.positive;
    } else {
      // TODO: safecast this, and actually increment the allowance down
      return -adjustment.amount <= allowance.negative;
    }
  }

  function isCounterpartyApproved(
    AssetAdjustment memory adjustment, uint counterpartyId
  ) {}

  function _managerCheck(
    uint accountId, 
    address caller
  ) internal {
    riskModel[accountId].handleAdjustment(accountId, _getAccountBalances(accountId), caller);
  }

  function _assetCheck(
    AbstractAsset asset, 
    uint subId, 
    uint accountId,
    int preBalance, 
    int postBalance, 
    address caller
  ) internal {
    asset.handleAdjustment(
      accountId, preBalance, postBalance, subId, riskModel[accountId], caller
    );
  }

  //////////
  // View //
  //////////

  function getAccountBalances(uint accountId) external view returns (AssetBalance[] memory assetBalances) {
    return _getAccountBalances(accountId);
  }

  function _getAccountBalances(uint accountId)
    internal
    view
    returns (AssetBalance[] memory assetBalances)
  {
    uint allAssetBalancesLen = heldAssets[accountId].length;
    assetBalances = new AssetBalance[](allAssetBalancesLen);
    for (uint i; i < allAssetBalancesLen; i++) {
      HeldAsset memory heldAsset = heldAssets[accountId][i];
      assetBalances[i] = AssetBalance({
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
    uint accountId, AbstractAsset asset, uint subId
  ) internal pure returns (bytes32 balanceKey) {
    return keccak256(abi.encodePacked(account, address(asset), subId));
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
  function _addHeldAsset(uint accountId, AbstractAsset asset, uint subId) internal {
    heldAssets[accountId].push(HeldAsset({asset: asset, subId: subId}));
  }

  function _removeHeldAsset(uint accountId, AbstractAsset asset, uint subId) internal {
    uint heldAssetLen = heldAssets[accountId].length;
    for (uint i; i < heldAssetLen; i++) {
      HeldAsset memory heldAsset = heldAssets[accountId][i];
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

  function getAccountBalances(uint accountId) external view returns (AssetBalance[] memory assetBalances) {
    return _getAccountBalances(accountId);
  }

  function _getAccountBalances(uint accountId)
    internal
    view
    returns (AssetBalance[] memory assetBalances)
  {
    uint allAssetBalancesLen = heldAssets[accountId].length;
    assetBalances = new AssetBalance[](allAssetBalancesLen);
    for (uint i; i < allAssetBalancesLen; i++) {
      HeldAsset memory heldAsset = heldAssets[accountId][i];
      assetBalances[i] = AssetBalance({
        asset: heldAsset.asset,
        subId: heldAsset.subId,
        balance: balances[accountId][heldAsset.asset][heldAsset.subId]
      });
    }
    return assetBalances;
  }

}
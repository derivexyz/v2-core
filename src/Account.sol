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

  /// @dev simple wrapper of ERC721.transferFrom()
  function changeOwner(uint accountId, address newOwner) external {
    transferFrom(ownerOf(accountId), newOwner, accountId);
  }

  function createAccount(IAbstractManager _manager) external returns (uint newId) {
    // charge a flat fee to prevent spam
    if (creationFee > 0) {
      feeToken.transferFrom(msg.sender, feeRecipient, creationFee);
    }

    // create account
    newId = nextId++;
    manager[newId] = _manager;
    _mint(msg.sender, newId);
    return newId;
  }

  /// @dev set positive / negative allowances per subId
  ///      the sum of asset allowances + subId allowances is used during _delegateCheck()
  ///      subId allowances are decremented before asset allowances
  function setDelegateSubIdAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    uint[] memory subIds,
    AccountStructs.Allowance[] memory allowances
  ) external {
    _updateDelegateAllowances(accountId, delegate, assets, subIds, allowances);
  }

  function setDelegateAssetAllowances(
    uint accountId, 
    address delegate, 
    IAbstractAsset[] memory assets,
    AccountStructs.Allowance[] memory allowances  
  ) external {
    _updateDelegateAllowances(accountId, delegate, assets, new uint[](0), allowances);
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
          _getBalanceKey(accountId, assets[i], subIds[i])][delegate] = allowance;
      } else {     // uses 0 when encoding key for delegateAssetAllowances key
        delegateAssetAllowances[
          _getBalanceKey(accountId, assets[i], 0)][delegate] = allowance;
      }
    }
  }

  function merge(uint[] memory accounts) external {}


  /////////////////////////
  // Balance Adjustments //
  /////////////////////////

  function submitTransfers(AccountStructs.AssetTransfer[] memory assetTransfers) external {
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
  function adjustBalance(AccountStructs.AssetAdjustment memory adjustment) external returns (int postAdjustmentBalance) {
    require(msg.sender == address(manager[accountId]) || msg.sender == address(adjustment.asset),
      "only managers and assets can make assymmetric adjustments");
    
    _adjustBalance(adjustment);
    _managerCheck(adjustment.acc, msg.sender); // since caller is passed, manager can internally decide to ignore check
    
    return balances[_getBalanceKey(adjustment.acc, adjustment.asset, adjustment.subId)];
  }

  function _adjustBalance(AccountStructs.AssetAdjustment memory adjustment) internal {
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
    AccountStructs.AssetAdjustment memory adjustment, address delegate
  ) internal {
    // owner is by default delegate approved
    if (delegate == ownerOf(adjustment.acc)) { return; }

    AccountStructs.Allowance storage subIdAllowance = 
      delegateSubIdAllowances[_getBalanceKey(adjustment.acc, adjustment.asset, adjustment.subId)][delegate];

    AccountStructs.Allowance storage assetAllowance = 
      delegateAssetAllowances[_getBalanceKey(adjustment.acc, adjustment.asset, 0)][delegate];

    uint absAmount = _abs(adjustment.amount);

    // TODO: a bit repetitive, can probably clean up a bit
    if (adjustment.amount > 0) {
      require(absAmount <= subIdAllowance.positive + assetAllowance.positive, 
        "positive adjustment not approved");
      if (absAmount <= subIdAllowance.positive) {
        subIdAllowance.positive -= absAmount;
      } else {
        // subId allowances are decremented first
        subIdAllowance.positive = 0;
        assetAllowance.positive -= absAmount - subIdAllowance.positive;
      }

    } else {
      require(absAmount <= subIdAllowance.negative + assetAllowance.negative, 
        "negative adjustment not approved");
      if (absAmount <= subIdAllowance.negative) {
        subIdAllowance.negative -= absAmount;
      } else {
        // subId allowances are decremented first
        subIdAllowance.negative = 0;
        assetAllowance.negative -= absAmount - subIdAllowance.negative;
      }
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

  /// @dev this should never be called if the account already holds the asset
  function _addHeldAsset(uint accountId, IAbstractAsset asset, uint subId) internal {
    heldAssets[accountId].push(AccountStructs.HeldAsset({asset: asset, subId: subId}));
  }

  function _removeHeldAsset(uint accountId, IAbstractAsset asset, uint subId) internal {
    uint heldAssetLen = heldAssets[accountId].length;
    for (uint i; i < heldAssetLen; i++) {
      AccountStructs.HeldAsset memory heldAsset = heldAssets[accountId][i];
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
}
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IManager.sol";
import "./interfaces/IAccount.sol";
import "forge-std/console2.sol";

/**
 * @title Account
 * @author Lyra
 * @notice Base layer that manages:
 *         1. balances for each (account, asset, subId)
 *         2. routing of manager, asset, allowance hooks / checks 
 *            during any balance adjustment event
 *         3. account creation / manager assignment
 */

abstract contract AbstractAllowance is IAccount, ERC721 {
  /// @dev accountId => owner => asset => subId => delegate => allowance
  mapping(uint => mapping(address => mapping(IAsset => mapping(uint => mapping(address => uint))))) public positiveSubIdAllowance;
  mapping(uint => mapping(address => mapping(IAsset => mapping(uint => mapping(address => uint))))) public negativeSubIdAllowance;

  /// @dev accountId => owner => asset => delegate => allowance
  mapping(uint => mapping(address => mapping(IAsset => mapping(address => uint)))) public positiveAssetAllowance;
  mapping(uint => mapping(address => mapping(IAsset => mapping(address => uint)))) public negativeAssetAllowance;

  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}


  ////////////
  // Public //
  ////////////

  /// @dev for use in setting manager ERC721 preapproval
  function getManager(uint accountId) virtual override public view returns (IManager);

  /** 
   * @notice Sets bidirectional allowances for all subIds of an asset. 
   *         During a balance adjustment, if msg.sender not ERC721 approved or owner, 
   *         asset allowance + subId allowance must be >= amount 
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each asset
   */
  function setAssetAllowances(
    uint accountId, 
    address delegate,
    AssetAllowance[] memory allowances
  ) external onlyOwnerOrManagerOrERC721Approved(msg.sender, accountId) {
    address owner = ownerOf(accountId);
    uint allowancesLen = allowances.length;
    for (uint i; i < allowancesLen; i++) {
      positiveAssetAllowance[accountId][owner][allowances[i].asset][delegate] = allowances[i].positive;
      negativeAssetAllowance[accountId][owner][allowances[i].asset][delegate] = allowances[i].negative;
    }
  }

  /** 
   * @notice Sets bidirectional allowances for a specific subId. 
   *         During a balance adjustment, the subId allowance is decremented first 
   * @param accountId ID of account
   * @param delegate address to assign allowance to
   * @param allowances positive and negative amounts for each (asset, subId)
   */
  function setSubIdAllowances(
    uint accountId, 
    address delegate,
    SubIdAllowance[] memory allowances
  ) external onlyOwnerOrManagerOrERC721Approved(msg.sender, accountId) {
    address owner = ownerOf(accountId);
    uint allowancesLen = allowances.length;
    for (uint i; i < allowancesLen; i++) {
      positiveSubIdAllowance[accountId][owner][allowances[i].asset][allowances[i].subId][delegate] = allowances[i].positive;
      negativeSubIdAllowance[accountId][owner][allowances[i].asset][allowances[i].subId][delegate] = allowances[i].negative;
    }
  }

  //////////////
  // Internal //
  //////////////

  /** 
   * @notice Checks allowances during transfers / merges / splits
   *         Not checked during adjustBalance()
   *         1. If delegate ERC721 approved or owner, blanket allowance given
   *         2. Otherwise, sum of subId and asset bidirectional allowances used
   *         The subId allowance is decremented before the asset-wide allowance
   * @dev finalBalance adjustments tweaked by the asset not considered in allowances 
   * @param adjustment amount of balance adjustment for an (asset, subId)
   * @param delegate address of msg.sender initiating change
   */
  function _spendAllowance(
    AssetAdjustment memory adjustment, address delegate
  ) internal {
    /* ERC721 approved, manager or owner get blanket allowance */
    if (_isApprovedOrOwner(delegate, adjustment.acc)) { return; }

    /* Early return if amount == 0 */
    if (adjustment.amount == 0) { return; }

    /* determine if positive vs negative allowance is needed */
    address owner = ownerOf(adjustment.acc);
    if (adjustment.amount > 0) {
      _spendAbsAllowance(
        adjustment.acc,
        positiveSubIdAllowance[adjustment.acc][owner][adjustment.asset][adjustment.subId],
        positiveAssetAllowance[adjustment.acc][owner][adjustment.asset],
        delegate,
        adjustment.amount
      );
    } else { // adjustment.amount < 0
      _spendAbsAllowance(
        adjustment.acc,
        negativeSubIdAllowance[adjustment.acc][owner][adjustment.asset][adjustment.subId],
        negativeAssetAllowance[adjustment.acc][owner][adjustment.asset],
        delegate,
        adjustment.amount
      );
    }
  }

  function _spendAbsAllowance(
    uint accountId,
    mapping(address => uint) storage allowancesForSubId,
    mapping(address => uint) storage allowancesForAsset,
    address delegate,
    int256 amount
  ) internal {
    uint subIdAllowance = allowancesForSubId[delegate];
    uint assetAllowance = allowancesForAsset[delegate];

    uint256 absAmount = _abs(amount);
    /* subId allowances are decremented before asset allowances */
    if (absAmount <= subIdAllowance) {
      allowancesForSubId[delegate] = subIdAllowance - absAmount;
    } else if (absAmount <= subIdAllowance + assetAllowance) { 
      allowancesForSubId[delegate] = 0;
      allowancesForAsset[delegate] = assetAllowance - (absAmount - subIdAllowance);
    } else {
      revert NotEnoughSubIdOrAssetAllowances(
        address(this), 
        msg.sender, 
        accountId, 
        amount,
        subIdAllowance, 
        assetAllowance);
    }
  }


  /// @dev giving managers exclusive rights to transfer account ownerships
  /// @dev this function overrides ERC721._isApprovedOrOwner(spender, tokenId);
  function _isApprovedOrOwner(
    address spender, uint tokenId
  ) internal view override returns (bool) {
    address owner = ERC721.ownerOf(tokenId);
    
    // return early if msg.sender is owner
    if (
      spender == owner || 
      isApprovedForAll(owner, spender) || 
      getApproved(tokenId) == spender
    ) return true;

    // check if caller is manager
    return address(getManager(tokenId)) == msg.sender;
  }

  //////////
  // Util //
  //////////

  function _abs(int amount) internal pure returns (uint absAmount) {
    return amount >= 0 ? uint(amount) : uint(-amount);
  }

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyOwnerOrManagerOrERC721Approved(address sender, uint accountId) {
    if (!_isApprovedOrOwner(sender, accountId)) {
      revert NotOwnerOrERC721Approved(
        address(this), 
        sender, 
        accountId, 
        ownerOf(accountId), 
        getManager(accountId), 
        getApproved(accountId)
      );
    }
    _;
  }

}

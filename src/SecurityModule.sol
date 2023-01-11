// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "synthetix/Owned.sol";

import "./interfaces/IAsset.sol";
import "./interfaces/IAccounts.sol";
import "./interfaces/ICashAsset.sol";
import "./interfaces/ISecurityModule.sol";

import "./libraries/ConvertDecimals.sol";

/**
 * @title SecurityModule
 * @author Lyra
 * @notice Module used to store fund to bail out insolvent accounts
 */
contract SecurityModule is Owned, ERC20, ISecurityModule {
  using ConvertDecimals for uint;
  using SafeERC20 for IERC20Metadata;

  ///@dev Cash Asset contract address
  ICashAsset public immutable cashAsset;

  ///@dev The token address for stable coin
  IERC20Metadata public immutable stableAsset;

  ///@dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  ///@dev Mapping of (address => isWhitelistedModule)
  mapping(address => bool) isWhitelisted;

  constructor(ICashAsset _cashAsset, IERC20Metadata _stableAsset) ERC20("Lyra USDC Security Module Share", "lsUSD") {
    stableAsset = _stableAsset;
    cashAsset = _cashAsset;
    stableDecimals = _stableAsset.decimals();
  }

  /**
   * @dev Deposit stable asset into the module
   */
  function deposit(uint stableAmount) external {
    // todo[Anton]: exchange rate when USDC is paid out and stable amount is no longer 1:1
    _mint(msg.sender, stableAmount);

    stableAsset.safeTransferFrom(msg.sender, address(this), stableAmount);
  }

  /**
   * @dev Withdraw stable asset from the module
   */
  function withdraw(uint shareAmount) external {
    // todo[Anton]: exchange rate when USDC is paid out and stable amount is no longer 1:1
    _burn(msg.sender, shareAmount);

    stableAsset.safeTransferFrom(msg.sender, address(this), shareAmount);
  }

  ////////////////////////////
  //  Onwer-only Functions  //
  ////////////////////////////

  /**
   * @notice set which address can request funds from security module
   */
  function setWhitelistModule(address module, bool whitelisted) external onlyOwner {
    isWhitelisted[module] = whitelisted;

    emit ModuleWhitelisted(module, whitelisted);
  }

  /////////////////////////////
  //  Whitelisted Functions  //
  /////////////////////////////

  /**
   * @notice request a payout from the security module
   * @param accountId Account ID requested to pay to
   * @param amountCashNeeded Amount of Lyra cash to pay. In 18 decimals
   * @return amountCashUncovered amount of cash not covered by this request. If this number > 0
   *         it means the security module is out of money
   */
  function requestPayout(uint accountId, uint amountCashNeeded)
    external
    onlyWhitelistedModule
    returns (uint amountCashUncovered)
  {
    // amount denominated in USDC or stable token decimals
    uint stableAssetAmount = amountCashNeeded.from18Decimals(stableDecimals);

    // check if the security module has enough fund
    uint stableBalance = stableAsset.balanceOf(address(this));
    if (stableBalance < stableAssetAmount) {
      unchecked {
        amountCashUncovered = (stableAssetAmount - stableBalance).to18Decimals(stableDecimals);
      }

      // cap the amount to deposit for target account at "balance"
      stableAssetAmount = stableBalance;
    }

    // deposit the amount into the target Lyra account
    // todo[Anton]: change to deposit cashAmount directly once we have that deposit option
    cashAsset.deposit(accountId, stableAssetAmount);

    emit SecurityModulePaidOut(accountId, stableAssetAmount);
  }

  /////////////////
  //  Modifiers  //
  /////////////////

  modifier onlyWhitelistedModule() {
    if (!isWhitelisted[msg.sender]) revert SM_NotWhitelisted();

    _;
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "synthetix/Owned.sol";

import "./interfaces/IAsset.sol";
import "./interfaces/IAccounts.sol";
import "./interfaces/ICashAsset.sol";
import "./interfaces/ISecurityModule.sol";
import "./interfaces/AccountStructs.sol";

import "./libraries/ConvertDecimals.sol";

/**
 * @title SecurityModule
 * @author Lyra
 * @notice Module used to store fund to bail out insolvent accounts
 */
contract SecurityModule is Owned, ERC20, ISecurityModule {
  using SafeCast for int;
  using ConvertDecimals for uint;
  using SafeERC20 for IERC20Metadata;

  ///@dev Cash Asset contract address
  IAccounts public immutable accounts;

  ///@dev Cash Asset contract address
  ICashAsset public immutable cashAsset;

  ///@dev The token address for stable coin
  IERC20Metadata public immutable stableAsset;

  ///@dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  ///@dev The account id security module is holding
  uint public immutable accountId;

  ///@dev Mapping of (address => isWhitelistedModule)
  mapping(address => bool) isWhitelisted;

  constructor(IAccounts _accounts, ICashAsset _cashAsset, IERC20Metadata _stableAsset, IManager _manager)
    ERC20("Lyra USDC Security Module Share", "lsUSD")
  {
    accounts = _accounts;
    stableAsset = _stableAsset;
    cashAsset = _cashAsset;
    stableDecimals = _stableAsset.decimals();

    accountId = IAccounts(_accounts).createAccount(address(this), _manager);
  }

  /**
   * @dev Deposit stable asset into the module
   */
  function deposit(uint stableAmount) external {
    // todo[Anton]: update share calculation when share to stable is no longer 1:1
    uint shareAmount = stableAmount;
    _mint(msg.sender, shareAmount);

    stableAsset.safeTransferFrom(msg.sender, address(this), stableAmount);

    cashAsset.deposit(accountId, stableAmount);
  }

  /**
   * @dev Withdraw stable asset from the module
   */
  function withdraw(uint shareAmount, address recipient) external {
    _burn(msg.sender, shareAmount);

    // todo[Anton]: exchange rate when USDC is paid out and stable amount is no longer 1:1
    uint stableAmount = shareAmount;

    cashAsset.withdraw(accountId, stableAmount, recipient);
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
   * @param targetAccount Account ID requested to pay to
   * @param cashAmountNeeded Amount of Lyra cash to pay. In 18 decimals
   * @return cashAmountPaid amount of cash covered by this request
   */
  function requestPayout(uint targetAccount, uint cashAmountNeeded)
    external
    onlyWhitelistedModule
    returns (uint cashAmountPaid)
  {
    // check if the security module has enough fund. Cap the payout at min(balance, cashAmount)
    uint cashBalance = accounts.getBalance(accountId, IAsset(address(cashAsset)), 0).toUint256();
    if (cashBalance < cashAmountNeeded) {
      cashAmountPaid = cashBalance;
    } else {
      cashAmountPaid = cashAmountNeeded;
    }

    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: accountId,
      toAcc: targetAccount,
      asset: IAsset(address(cashAsset)),
      subId: 0,
      amount: int(cashAmountPaid),
      assetData: ""
    });

    accounts.submitTransfer(transfer, "");

    emit SecurityModulePaidOut(accountId, cashAmountNeeded, cashAmountPaid);
  }

  /////////////////
  //  Modifiers  //
  /////////////////

  modifier onlyWhitelistedModule() {
    if (!isWhitelisted[msg.sender]) revert SM_NotWhitelisted();

    _;
  }
}

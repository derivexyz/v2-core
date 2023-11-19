// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";
import "openzeppelin/access/Ownable2Step.sol";

import {IAsset} from "./interfaces/IAsset.sol";
import {IAllowances} from "./interfaces/IAllowances.sol";
import {ISubAccounts} from "./interfaces/ISubAccounts.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ICashAsset} from "./interfaces/ICashAsset.sol";
import {ISecurityModule} from "./interfaces/ISecurityModule.sol";

/**
 * @title SecurityModule
 * @author Lyra
 * @notice Module used to store fund to bail out insolvent accounts
 */
contract SecurityModule is Ownable2Step, ISecurityModule {
  using SafeCast for int;
  using ConvertDecimals for uint;
  using SafeERC20 for IERC20Metadata;
  using DecimalMath for uint;

  /// @dev Cash Asset contract address
  ISubAccounts public immutable subAccounts;

  /// @dev Cash Asset contract address
  ICashAsset public immutable cashAsset;

  /// @dev The token address for stable coin
  IERC20Metadata public immutable stableAsset;

  /// @dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  /// @dev The account id security module is holding
  uint public immutable accountId;

  /// @dev Mapping of (address => isWhitelistedModule)
  mapping(address => bool) public isWhitelisted;

  constructor(ISubAccounts _subAccounts, ICashAsset _cashAsset, IManager accountManager) {
    subAccounts = _subAccounts;
    cashAsset = _cashAsset;
    stableAsset = cashAsset.wrappedAsset();
    stableDecimals = stableAsset.decimals();

    accountId = ISubAccounts(_subAccounts).createAccount(address(this), accountManager);
    stableAsset.safeApprove(address(_cashAsset), type(uint).max);
  }

  /////////////////////////////
  //        Owner-Only       //
  /////////////////////////////

  /**
   * @notice set which address can request funds from security module
   */
  function setWhitelistModule(address module, bool whitelisted) external onlyOwner {
    isWhitelisted[module] = whitelisted;

    emit ModuleWhitelisted(module, whitelisted);
  }

  /**
   * @dev Withdraw stable asset from the module
   */
  function withdraw(uint stableAmount, address recipient) external onlyOwner {
    cashAsset.withdraw(accountId, stableAmount, recipient);
  }

  /**
   * @dev Recover ERC20 token from the module
   */
  function recoverERC20(address tokenAddress, address recipient, uint tokenAmount) external onlyOwner {
    IERC20Metadata(tokenAddress).safeTransfer(recipient, tokenAmount);
  }

  /////////////////////////////
  //     Public Functions    //
  /////////////////////////////

  /**
   * @dev Deposit stable asset into the security module
   */
  function donate(uint stableAmount) external {
    stableAsset.safeTransferFrom(msg.sender, address(this), stableAmount);
    cashAsset.deposit(accountId, stableAmount);
  }

  /**
   * @dev Use the cash balance in the security module to pay for insolvency
   */
  function payCashInsolvency() external {
    // Donate full balance as the function will cap amount burnt to the size of the insolvency
    cashAsset.donateBalance(accountId, subAccounts.getBalance(accountId, IAsset(address(cashAsset)), 0).toUint256());
  }

  /////////////////////////////
  //    Guarded Functions    //
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
    uint usableCash = subAccounts.getBalance(accountId, IAsset(address(cashAsset)), 0).toUint256();

    // payout up to useable cash
    if (usableCash < cashAmountNeeded) {
      cashAmountPaid = usableCash;
    } else {
      cashAmountPaid = cashAmountNeeded;
    }

    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: accountId,
      toAcc: targetAccount,
      asset: IAsset(address(cashAsset)),
      subId: 0,
      amount: int(cashAmountPaid),
      assetData: ""
    });

    subAccounts.submitTransfer(transfer, "");

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

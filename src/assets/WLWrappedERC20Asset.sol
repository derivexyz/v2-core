// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IAsset} from "../interfaces/IAsset.sol";
import {WrappedERC20Asset} from "./WrappedERC20Asset.sol";

/**
 * @title Whitelisted Wrapped ERC20 Asset
 * @dev   Select users (subaccounts) can deposit the given ERC20, and can only have positive balances.
 * @dev   Fee-on-transfer and rebasing tokens are not supported
 * @author Lyra
 */
contract WLWrappedERC20Asset is WrappedERC20Asset {
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for int;

  /// @dev Subaccounts which have been whitelisted to be able to deposit
  mapping(uint accountId => bool) public wlAccounts;
  bool public wlEnabled = true;

  constructor(ISubAccounts _subAccounts, IERC20Metadata _wrappedAsset) WrappedERC20Asset(_subAccounts, _wrappedAsset) {}

  ///////////
  // Admin //
  ///////////

  /**
   * @dev Whitelist a subaccount to be able to deposit the ERC20
   * @param accountId The subaccount to whitelist
   */
  function setSubAccountWL(uint accountId, bool isWhitelisted) external onlyOwner {
    wlAccounts[accountId] = isWhitelisted;
    emit SubAccountWhitelisted(accountId, isWhitelisted);
  }

  function setWhitelistEnabled(bool enabled) external onlyOwner {
    wlEnabled = enabled;
  }

  ////////////////////////////
  //   External Functions   //
  ////////////////////////////

  /**
   * @dev Deposit ERC20 asset and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param assetAmount amount of the wrapped asset to deposit
   */
  function deposit(uint recipientAccount, uint assetAmount) external override {
    if (wlEnabled && !wlAccounts[recipientAccount]) {
      revert WLWERC_NotWhitelisted();
    }

    wrappedAsset.safeTransferFrom(msg.sender, address(this), assetAmount);
    uint adjustmentAmount = assetAmount.to18Decimals(assetDecimals);

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(adjustmentAmount),
        assetData: bytes32(0)
      }),
      true,
      ""
    );

    emit Deposit(recipientAccount, msg.sender, adjustmentAmount, assetAmount);
  }

  ///////////////////
  // Events/Errors //
  ///////////////////
  event SubAccountWhitelisted(uint indexed subaccount, bool isWhitelisted);

  error WLWERC_NotWhitelisted();
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IAsset} from "./IAsset.sol";

interface IERC20BasedAsset is IAsset {
  function wrappedAsset() external view returns (IERC20Metadata);
  function deposit(uint recipientAccount, uint assetAmount) external;
  function withdraw(uint accountId, uint assetAmount, address recipient) external;

  /// @dev emitted when a user deposits to an account
  event Deposit(uint indexed accountId, address indexed depositor, uint amountAssetMinted, uint wrappedAssetDeposited);

  /// @dev emitted when a user withdraws from an account
  event Withdraw(uint indexed accountId, address indexed recipient, uint amountCashBurn, uint wrappedAssetWithdrawn);
}

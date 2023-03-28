// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import "lyra-utils/ownership/Owned.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IPerpAsset.sol";
import "src/interfaces/ISettlementFeed.sol";
import "src/interfaces/IPerpManager.sol";

import "forge-std/console2.sol";

/**
 * @title PerpManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract PerpManager is IPerpManager, Owned {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;

  ///////////////
  // Variables //
  ///////////////

  /// @dev Account contract address
  IAccounts public immutable accounts;

  /// @dev Perp asset address
  IPerpAsset public immutable perp;

  /// @dev Cash asset address
  ICashAsset public immutable cashAsset;

  /// @dev Future feed oracle to get future price for an expiry
  ISettlementFeed public immutable feed;

  /// @dev Whitelisted managers. Account can only .changeManager() to whitelisted managers.
  mapping(address => bool) public whitelistedManager;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ICashAsset cashAsset_, IPerpAsset perp_, ISettlementFeed feed_) {
    accounts = accounts_;
    cashAsset = cashAsset_;
    perp = perp_;
    feed = feed_;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Whitelist or un-whitelist a manager used in .changeManager()
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;
  }

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint tradeId, address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
    override
  {
    // check the call is from Accounts



    // check assets are only cash and perp
  }

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint /*accountId*/, IManager newManager) external view {
    if (!whitelistedManager[address(newManager)]) {
      revert PM_NotWhitelistManager();
    }
  }

  /**
   * @notice to settle an account, clear PNL and funding in the perp contract and pay out cash
   */
  function settleAccount(uint accountId) external {

    perp.updateFundingRate();
    perp.applyFundingOnAccount(accountId);
    int netCash = perp.settleRealizedPNLAndFunding(accountId);

    cashAsset.updateSettledCash(netCash);

    // update user cash amount
    accounts.managerAdjustment(AccountStructs.AssetAdjustment(accountId, cashAsset, 0, netCash, bytes32(0)));

    emit AccountSettled(accountId, netCash);
  }

  //////////
  // View //
  //////////
}

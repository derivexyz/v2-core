// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/periphery/OptionSettlementHelper.sol";
import "../../../../src/periphery/PerpSettlementHelper.sol";

import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2TestBase.sol";

import "./utils/PMRM_2Public.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";

contract PMRM_2Upgrade is PMRM_2Public {
  function initialize(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IOptionAsset option_,
    IPerpAsset perp_,
    IDutchAuction liquidation_,
    Feeds memory feeds_,
    IBasePortfolioViewer viewer_,
    IPMRMLib_2 lib_,
    uint maxExpiries_
  ) external override reinitializer(2) {
    __ReentrancyGuard_init();

    __BaseManagerUpgradeable_init(subAccounts_, cashAsset_, liquidation_, viewer_, 128);

    spotFeed = feeds_.spotFeed;
    stableFeed = feeds_.stableFeed;
    forwardFeed = feeds_.forwardFeed;
    interestRateFeed = feeds_.interestRateFeed;
    volFeed = feeds_.volFeed;
    lib = lib_;

    option = option_;
    perp = perp_;

    require(maxExpiries_ <= 30 && maxExpiries_ > 0, PMRM_2_InvalidMaxExpiries());
    maxExpiries = maxExpiries_;
    emit MaxExpiriesUpdated(maxExpiries_);
  }
}

contract TestPMRM_2_Upgrade is PMRM_2TestBase {
  function setUp() public override {
    super.setUp();
  }

  function testCanUpgradeContract() public {
    PMRM_2Upgrade newImp = new PMRM_2Upgrade();

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(pmrm_2)),
      address(newImp),
      abi.encodeWithSelector(
        PMRM_2.initialize.selector,
        subAccounts,
        cash,
        option,
        mockPerp,
        auction,
        IPMRM_2.Feeds({
          spotFeed: ISpotFeed(feed),
          stableFeed: ISpotFeed(stableFeed),
          forwardFeed: IForwardFeed(feed),
          interestRateFeed: IInterestRateFeed(feed),
          volFeed: IVolFeed(feed)
        }),
        viewer,
        lib,
        11
      )
    );
  }
}

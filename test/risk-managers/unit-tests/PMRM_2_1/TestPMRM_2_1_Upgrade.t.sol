// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/periphery/OptionSettlementHelper.sol";
import "../../../../src/periphery/PerpSettlementHelper.sol";

import "../../../risk-managers/unit-tests/PMRM_2_1/utils/PMRM_2_1TestBase.sol";

import "./utils/PMRM_2_1Public.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";

contract PMRM_2_1Upgrade is PMRM_2_1Public {
  function initialize(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IOptionAsset option_,
    IPerpAsset perp_,
    IDutchAuction liquidation_,
    Feeds memory feeds_,
    IBasePortfolioViewer viewer_,
    IPMRMLib_2_1 lib_,
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

    require(maxExpiries_ <= 30 && maxExpiries_ > 0, PMRM_2_1_InvalidMaxExpiries());
    maxExpiries = maxExpiries_;
    emit MaxExpiriesUpdated(maxExpiries_);
  }
}

contract TestPMRM_2_1_Upgrade is PMRM_2_1TestBase {
  function setUp() public override {
    super.setUp();
  }

  function testCanUpgradeContract() public {
    PMRM_2_1Upgrade newImp = new PMRM_2_1Upgrade();

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(pmrm_2_1)),
      address(newImp),
      abi.encodeWithSelector(
        PMRM_2_1.initialize.selector,
        subAccounts,
        cash,
        option,
        mockPerp,
        auction,
        IPMRM_2_1.Feeds({
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

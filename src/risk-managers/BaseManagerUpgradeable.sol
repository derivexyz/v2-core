import "./BaseManager.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

abstract contract BaseManagerUpgradeable is BaseManager {
  constructor() {
    _disableInitializers();
  }

  function __BaseManagerUpgradeable_init(
    ISubAccounts _subAccounts,
    ICashAsset _cashAsset,
    IDutchAuction _liquidation,
    IBasePortfolioViewer _viewer,
    uint _maxAccountSize
  ) internal initializer {
    __Ownable_init(msg.sender);

    subAccounts = _subAccounts;
    cashAsset = _cashAsset;
    liquidation = _liquidation;
    viewer = _viewer;

    maxAccountSize = _maxAccountSize;

    accId = subAccounts.createAccount(address(this), IManager(address(this)));
  }
}

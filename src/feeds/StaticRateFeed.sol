import "lyra-utils/ownership/Owned.sol";
import "src/interfaces/IDiscountFactorFeed.sol";

contract StaticDiscountFactorFeed is Owned, IDiscountFactorFeed {
  uint64 public discountFactor;

  function setDiscountFactor(uint64 newDiscountFactor) external onlyOwner {
    discountFactor = newDiscountFactor;
    emit DiscountFactorSet(discountFactor, 1e18);
  }

  function getDiscountFactor(uint /* expiry */ ) external view override returns (uint64, uint64) {
    return (discountFactor, 1e18);
  }
}

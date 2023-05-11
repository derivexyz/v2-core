import "lyra-utils/ownership/Owned.sol";
import "src/interfaces/IInterestRateFeed.sol";

contract StaticInterestRateFeed is Owned, IInterestRateFeed {
  uint64 public interestRate;

  function setInterestRate(uint64 newInterestRate) external onlyOwner {
    interestRate = newInterestRate;
    emit InterestRateSet(interestRate, 1e18);
  }

  function getInterestRate(uint /* expiry */ ) external view override returns (uint64, uint64) {
    return (interestRate, 1e18);
  }
}

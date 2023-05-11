import "lyra-utils/ownership/Owned.sol";
import "src/interfaces/IInterestRateFeed.sol";

contract StaticInterestRateFeed is Owned, IInterestRateFeed {
  int64 public interestRate;

  function setInterestRate(int64 newInterestRate) external onlyOwner {
    interestRate = newInterestRate;
    emit InterestRateSet(interestRate, 1e18);
  }

  function getInterestRate(uint /* expiry */ ) external view override returns (int64, uint64) {
    return (interestRate, 1e18);
  }
}

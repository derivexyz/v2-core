import "src/interfaces/IInterestRateFeed.sol";
import "openzeppelin/access/Ownable2Step.sol";

contract StaticInterestRateFeed is Ownable2Step, IInterestRateFeed {
  int64 public interestRate;

  function setInterestRate(int64 newInterestRate) external onlyOwner {
    interestRate = newInterestRate;
    emit InterestRateSet(interestRate, 1e18);
  }

  function getInterestRate(uint /* expiry */ ) external view override returns (int64, uint64) {
    return (interestRate, 1e18);
  }
}

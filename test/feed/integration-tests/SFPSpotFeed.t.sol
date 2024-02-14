import "forge-std/Test.sol";
import "src/feeds/SFPSpotFeed.sol";
import "./sfp-contracts/StrandsAPI.sol";
import "./sfp-contracts/StrandsSFP.sol";


contract SFPTest is Test {
  address deployer;
  address alice;

  StrandsAPI strandsAPI;
  StrandsSFP strandsSFP;
  SFPSpotFeed sfpSpotFeed;

  function setUp() public {
    deployer = address(this);
    alice = address(0xa);

    strandsAPI = new StrandsAPI(deployer, deployer);
    strandsSFP = new StrandsSFP(strandsAPI);
    sfpSpotFeed = new SFPSpotFeed(IStrandsSFP(address(strandsSFP)));
  }


  function test_sfp() public {
    strandsAPI.mint(alice, 100e18);
    vm.prank(alice);
    strandsAPI.approve(address(strandsSFP), 100e18);
    vm.prank(alice);
    strandsSFP.deposit(100e18, alice);

    assertEq(strandsSFP.balanceOf(alice), 100e18);
    assertEq(strandsSFP.totalSupply(), 100e18);
    (uint spot, uint confidence) = sfpSpotFeed.getSpot();
    assertEq(spot, 1e18);
    assertEq(confidence, 1e18);

    strandsAPI.mint(address(strandsSFP), 1e18);

    (spot, confidence) = sfpSpotFeed.getSpot();
    assertApproxEqAbs(spot, 1.01e18, 0.00001e18);
    assertEq(confidence, 1e18);

  }
}
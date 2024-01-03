// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/access/Ownable2Step.sol";

/**
 * @title LyraERC20
 * @author Lyra
 * @notice ERC20 token on Lyra Chain
 */
contract LyraERC20 is Ownable2Step, ERC20 { 

    uint8 internal _decimals;

    mapping(address => bool) public minters;

    error OnlyMinter();

    modifier onlyMinter() {
        if(!minters[msg.sender]) revert OnlyMinter();
        _;
    }

    event MinterConfigured(address indexed minter, bool enabled);
    
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function configureMinter(address minter, bool enabled) public onlyOwner {
        minters[minter] = enabled;

        emit MinterConfigured(minter, enabled);
    }

    function mint(address to, uint256 amount) public onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyMinter {
        _burn(from, amount);
    }
}

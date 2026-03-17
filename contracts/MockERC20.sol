// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    address owner;
    uint8 private _decimals;

    constructor(uint8 decimals_) ERC20("USD Coin", "USDC"){
        owner = msg.sender;
        _mint(msg.sender, 1000);
        _setupDecimals(decimals_);
    }

    function mint(address to, uint256 amount) public onlyOwner{
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyOwner {
        _burn(to, amount);
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    modifier onlyOwner{
        require(msg.sender == owner, "only owner");
        _;
    }
}
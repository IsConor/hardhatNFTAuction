// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    address owner;

    constructor() ERC20("USD Coin", "USDC"){
        owner = msg.sender;
        _mint(msg.sender, 1000);
    }

    function mint(address to, uint256 amount) public onlyOwner{
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyOwner {
        _burn(to, amount);
    }

    modifier onlyOwner{
        require(msg.sender == owner, "only owner");
        _;
    }
}
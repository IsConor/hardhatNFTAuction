// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract MetaNFT is ERC721 {
    address private _owner;
    // tokenId 初始值为1
    uint256 tokenId;

    constructor() ERC721("MetaNFT", "MFT") {
        _owner = msg.sender;
        tokenId = 0;
        _safeMint(msg.sender, tokenId);
    }

    function mint(address to) external onlyOwner{
        tokenId += 1;
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId_) external onlyOwner {
        _burn(tokenId_);
    }

    modifier onlyOwner {
        require(msg.sender == _owner, "not owner");
        _;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {MetaNFT} from "./MetaNFT.sol";

contract MetaNFTTest is Test {
    MetaNFT metaNft;
    address private owner = address(1);
    address private user = address(2); 

    function setUp() public {
        vm.prank(owner);
        metaNft = new MetaNFT();
    }

    // 测试铸造
    function test_mint() public {
        vm.prank(owner);
        metaNft.mint(user);

        // 验证tokenId为0的Nft所有者是 owner
        assertEq(metaNft.ownerOf(0), owner);
        // 验证user拥有1个NFT
        assertEq(metaNft.balanceOf(user), 1); // USER 余额为 1
    }

    function test_burn() public {
        vm.startPrank(owner);
        // 给user铸造一个NFT
        metaNft.mint(user);
        // 验证user的NFT数量为1
        assertEq(metaNft.balanceOf(user), 1);
        // 销毁nftId为1的NFT（user账户的）
        metaNft.burn(1);
        vm.stopPrank();

        // 验证user持有的NFT数量变成0
        assertEq(metaNft.balanceOf(user), 0);
    }
}
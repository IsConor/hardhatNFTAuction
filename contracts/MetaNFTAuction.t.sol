// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {MetaNFT} from "./MetaNFT.sol";
import {MetaNFTAuction} from "./MetaNFTAuction.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockPriceFeed} from "./MockPriceFeed.sol";
import {MockERC20} from "./MockERC20.sol";

contract MetaNFTTest is Test {
    MetaNFTAuction private auction;
    MetaNFT private nft;
    MockPriceFeed private mockEthPriceFeed; // ETH Mock预言机
    MockPriceFeed private mockUsdcPriceFeed; // USDC Mock预言机

    address private admin = address(0xA11CE);
    address private proxyAdmin = address(0xBEEF);
    address private owner = address(1);
    address private usdc_owner = address(2);
    MockERC20 private USDC_SEPOLIA;
    // address private constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    

    function setUp() public {
        vm.deal(admin, 100 ether);
        vm.startPrank(admin);

        // 1. 部署Mock预言机（ETH=7美元，USDC=1美元，带8位小数）
        mockEthPriceFeed = new MockPriceFeed(7 * 10**8); 
        mockUsdcPriceFeed = new MockPriceFeed(1 * 10**8);

        

        MetaNFTAuction impl = new MetaNFTAuction();
        bytes memory initData = abi.encodeCall(
            MetaNFTAuction.initialize, 
            (admin, true, address(mockEthPriceFeed), address(mockUsdcPriceFeed))
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdmin, initData);

        auction = MetaNFTAuction(address(proxy));

        vm.stopPrank();

        // 部署NFT合约
        vm.startPrank(owner);
        // 新建MetaNFT的NFT
        nft = new MetaNFT();
        vm.stopPrank();

        // 部署ERC20合约
        vm.prank(usdc_owner);
        USDC_SEPOLIA = new MockERC20();
     
    }

    // 测试只能由管理员发起拍卖
    function test_startOnlyAdmin() public {
        address seller = address(0xB0B);
        MockERC20 usdc = USDC_SEPOLIA;

        // 切换到非admin地址
        vm.startPrank(seller);
        vm.expectRevert("Not Admin!");
        // 创建拍卖 revert
        auction.startBid(seller, address(nft),1, 3600, address(usdc),100);
    }

    // 测试预言机
    function test_getPriceInDollar() public view {

        uint256 ethPrice = auction.getPriceInDollar(1);
        uint256 usdcPrice = auction.getPriceInDollar(2);

        console2.log("ETH/USD price", ethPrice);
        console2.log("USDC/USD price", usdcPrice);

        // 验证Mock返回值（7*10^8=700000000，1*10^8=100000000）
        assertEq(ethPrice, 7 * 10**8, "ETH Mock price error");
        assertEq(usdcPrice, 1 * 10**8, "USDC Mock price error");
    }

    // 验证拍卖号auctionId会随着拍卖的创建自增
    function test_startIncrementsAuctionId() public {
        // 卖家
        address seller = address(0xB0B);
        MockERC20 usdc = USDC_SEPOLIA;

        vm.startPrank(owner);    // 切换到owner地址
        nft.mint(seller);   // 给卖家铸造NFT tokenId为1
        nft.mint(seller);   // 给卖家铸造NFT tokenId为2
        vm.stopPrank();

        vm.startPrank(seller);  // 切换到卖家地址
        nft.approve(address(auction), 1); // 卖家授权当前拍卖合约 tokenId 为1 的NFT
        nft.approve(address(auction), 2); // 卖家授权当前拍卖合约 tokenId 为2 的NFT
        vm.stopPrank();

        // 创建拍卖
        vm.startPrank(admin);
        auction.startBid(seller, address(nft), 1, 3600, address(usdc),10);
        // 验证拍卖Id为1
        assertEq(auction.auctionId(), 1);

        // 再次创建拍卖
        auction.startBid(seller, address(nft), 2, 3600, address(usdc),10);
        // 验证拍卖Id为2
        assertEq(auction.auctionId(), 2);
    }

    // 测试超过了拍卖时间
    function test_startAuctionGtDuration() public {
        // 卖家地址
        address seller = address(0xB0B);
        address bidder = address(0xB0C);
        MockERC20 usdc = USDC_SEPOLIA;

        // NFT合约的owner 给 卖家 铸造 NFT tokenId=1
        vm.prank(owner);
        nft.mint(seller);
        // 卖家授权拍卖合约 tokenId为1 的NFT 
        vm.prank(seller);
        nft.approve(address(auction), 1);

        // admin 创建拍卖
        vm.prank(admin);
        auction.startBid(seller, address(nft), 1, 30, address(usdc), 10);
        // 当前创建的拍卖 auctionId
        uint256 currentAuctionId = auction.auctionId() - 1;

        // 获取当前拍卖的开始时间和持续时间
        (,,,,uint256 startTime, uint256 duration, ,,,,) = auction.auctions(currentAuctionId);
        // 模拟时间 自然截止
        vm.warp(block.timestamp + 50);
        console2.log("current time", block.timestamp);
        console2.log("startTime", startTime);
        console2.log("duration", duration);

        vm.deal(bidder, 1 ether);
        vm.expectRevert("auction is end!");
        vm.prank(bidder);
        auction.bid{value: 1 ether}(currentAuctionId, 0);
    }

    // 测试起拍价太少
    function test_lowStartingPrice() public {
        MockERC20 usdc = USDC_SEPOLIA;
        address seller = address(0xB0B);
        address bidder = address(0xB0C);

        vm.prank(owner);
        nft.mint(seller);
        vm.prank(seller);
        nft.approve(address(auction), 1);
        // 设置起拍价为8美元
        uint256 startingPriceInDollar = 8;


        // admin创建拍卖，起拍价8美元
        vm.startPrank(admin);
        // uint256 ethPrice = auction.getPriceInDollar(1) / 10 ** 8;
        auction.startBid(seller, address(nft), 1, 30, address(usdc), startingPriceInDollar);
        vm.stopPrank();
        // 当前创建的拍卖 auctionId
        uint256 currentAuctionId = auction.auctionId() - 1;
        
        vm.deal(bidder,2 ether);

        vm.expectRevert("invalid startingPrice");
        // bidder竞拍的价格为 1 ether = 7美元 比起拍价要低
        vm.prank(bidder);
        auction.bid{value:1 ether}(currentAuctionId, 0);
    }
 
    // 测试修改支付方式
    function test_changeBidMethod() public {
        MockERC20 usdc = USDC_SEPOLIA;
        address seller = address(0xB0B);
        address bidder = address(0xB0C);

        vm.prank(owner);
        nft.mint(seller);
        vm.prank(seller);
        nft.approve(address(auction), 1);
        // 设置起拍价为8美元
        uint256 startingPriceInDollar = 8;


        // admin 创建拍卖
        vm.startPrank(admin);
        // uint256 ethPrice = auction.getPriceInDollar(1) / 10 ** 8;
        auction.startBid(seller, address(nft), 1, 30, address(usdc), startingPriceInDollar);
        vm.stopPrank();
        // 当前创建的拍卖 auctionId
        uint256 currentAuctionId = auction.auctionId() - 1;

        // 切换到MockERC20代币的管理员地址
        vm.prank(usdc_owner);
        // 给竞拍者bidder铸造100个token
        usdc.mint(bidder, 100);

        // 切换到竞拍者bidder地址
        vm.startPrank(bidder);
        // 授权竞拍合约100个token
        usdc.approve(address(auction), 100);

        // 竞拍者bidder储值2 ether
        vm.deal(bidder, 2 ether);
        // bidder 开始竞拍 出 2 ether
        auction.bid{value: 2 ether}(currentAuctionId, 0);
        // 验证revert
        vm.expectRevert("invalid method");
        // bidder 再次竞拍 出 20 个 ERC20代币
        auction.bid(currentAuctionId, 20);

    }
}
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
        USDC_SEPOLIA = new MockERC20(6);
     
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
        // ERC20 的合约地址
        MockERC20 usdc = USDC_SEPOLIA;
        // 卖家地址
        address seller = address(0xB0B);
        // 竞拍者地址
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

    // 测试低于上一次最高价
    function test_bidLowerThanHighestBid() public {
        // ERC20 的合约地址
        MockERC20 usdc = USDC_SEPOLIA;
        // 卖家地址
        address seller = address(0xB0B);
        // 竞拍者地址
        address bidder1 = address(0xB0C);
        address bidder2 = address(0xB0D);

        // 竞拍者储蓄10 ether
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);

        // NFT合约owner 给卖家铸造NFT
        vm.prank(owner);
        nft.mint(seller);
        // 卖家授权拍卖合约使用tokenId为1的NFT
        vm.prank(seller);
        nft.approve(address(auction), 1);
        // 设置起拍价为8美元
        uint256 startingPriceInDollar = 8;


        // admin 创建拍卖
        vm.startPrank(admin);
        auction.startBid(seller, address(nft), 1, 30, address(usdc), startingPriceInDollar);
        vm.stopPrank();

        // 当前创建的拍卖 auctionId
        uint256 currentAuctionId = auction.auctionId() - 1;

        // 竞拍开始
        // bidder1 出价 3ETH
        vm.prank(bidder1);
        auction.bid{value:3 ether}(currentAuctionId, 0);

        // 断言revert信息为：
        vm.expectRevert("Your bid must be higher than the current highest bid");

        // bidder2 出价 2ETH
        vm.prank(bidder2);
        auction.bid{value:2 ether}(currentAuctionId, 0);
    }

    // 测试拍卖结果正确
    function test_bidResult() public {
        // ERC20 的合约地址
        MockERC20 usdc = USDC_SEPOLIA;
        // 卖家地址
        address seller = address(0xB0B);
        // 竞拍者地址
        address bidder1 = address(0xB0C);
        address bidder2 = address(0xB0D);

        // 竞拍者储蓄10 ether
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);

        // NFT合约owner 给卖家铸造NFT
        vm.prank(owner);
        nft.mint(seller);
        // 卖家授权拍卖合约使用tokenId为1的NFT
        vm.prank(seller);
        nft.approve(address(auction), 1);
        // 设置起拍价为8美元
        uint256 startingPriceInDollar = 8;


        // admin 创建拍卖
        vm.startPrank(admin);
        auction.startBid(seller, address(nft), 1, 30, address(usdc), startingPriceInDollar);
        vm.stopPrank();
        // 当前创建的拍卖 auctionId
        uint256 currentAuctionId = auction.auctionId() - 1;

        vm.prank(bidder1);
        auction.bid{value: 2 ether}(currentAuctionId, 0);

        vm.prank(bidder2);
        auction.bid{value: 3 ether}(currentAuctionId, 0);

        vm.prank(bidder1);
        auction.bid{value: 4 ether}(currentAuctionId, 0);

        (,,,,,,address highestBidder, uint256 highestBid,,,) = auction.auctions(currentAuctionId);

        assertEq(highestBidder, bidder1);
        assertEq(highestBid, 4 ether);
        // 验证 bidder1 锁定在拍卖合约的ETH一共为6枚（一共出价两次：2ETH + 4ETH）
        assertEq(bidder1.balance, 4 ether);

        // 使拍卖自然截止
        vm.warp(block.timestamp + 50);
    
        // admin调用拍卖成功函数结算
        vm.prank(admin);
        auction.bidFinally(currentAuctionId);

        // 验证赢家bidder1 除了成交额4ETH 以外 锁定在合约中的2ETH是否退还
        assertEq(bidder1.balance, 6 ether);
        // 验证成交额 4ETH 是否转移给卖家 seller
        assertEq(seller.balance, 4 ether);

        // 验证赢家bidder1 是否 获得NFT
        assertEq(nft.ownerOf(1), bidder1);
        assertEq(nft.balanceOf(bidder1), 1);
    }

    // 竞价失败者测试提款正确
    function test_withdraw() public {
        MockERC20 usdc = USDC_SEPOLIA;
        address seller = address(0xB0B);
        address bidder1 = address(0xB0C);
        address bidder2 = address(0xB0D);

        // bidder1 竞拍者 存入 20枚 ETH
        vm.deal(bidder1, 20 ether);
        // usdc_owner 给 bidder2 竞拍者 铸造 1000 token

        vm.prank(usdc_owner);
        usdc.mint(bidder2, 1000 * 10**6);

        // 授权给拍卖合约1000枚token
        vm.prank(bidder2);
        usdc.approve(address(auction), 1000 * 10**6);

        // owner 给卖家 seller 铸造 NFT
        vm.prank(owner);
        nft.mint(seller);

        // 卖家seller授权给拍卖合约 tokenId为1 的NFT
        vm.prank(seller);
        nft.approve(address(auction), 1);

        // 设置起拍价为8美元
        uint256 startingPriceInDollar = 8;

        // admin 创建拍卖
        vm.prank(admin);
        auction.startBid(seller, address(nft), 1, 30, address(usdc), startingPriceInDollar);
        uint256 currentAuctionId = auction.auctionId() - 1;


        // 开始竞拍
        // bidder1 出价2枚ETH锁定在拍卖合约
        vm.prank(bidder1);
        auction.bid{value: 2 ether}(currentAuctionId, 0);

        // bidder2 出价15枚USDC锁定在拍卖合约
        vm.prank(bidder2);
        auction.bid(currentAuctionId, 15 * 10**6);

        // bidder1 再次出价3枚ETH锁定在拍卖合约
        vm.prank(bidder1);
        auction.bid{value: 3 ether}(currentAuctionId, 0);

        // bidder2 不屑 再次出价25枚USDC锁定在拍卖合约
        vm.prank(bidder2);
        auction.bid(currentAuctionId, 25 * 10**6);

        // bidder1 撇了撇嘴 豪掷4枚ETH锁定在拍卖合约并赢得NFT
        vm.prank(bidder1);
        auction.bid{value: 4 ether}(currentAuctionId, 0);

        // 使拍卖超过持续时间 自然结束
        vm.warp(block.timestamp + 50);

        // admin调用拍卖结算方法，结算卖家和买家资产
        vm.prank(admin);
        auction.bidFinally(currentAuctionId);

        // 验证卖家seller获得4枚ETH
        assertEq(seller.balance, 4 ether);

        // 验证竞拍成功者 bidder1获得了NFT
        assertEq(nft.ownerOf(1), bidder1);

        // bidder2调用提款方法，取走竞拍过程中锁定的资产
        vm.prank(bidder2);
        auction.withdraw(currentAuctionId);

        // 验证bidder2的余额回到了竞拍之前的初始值
        assertEq(usdc.balanceOf(address(bidder2)), 1000 * 10**6);
        // 验证赢家bidder1的余额为 20 - 4 = 16
        assertEq(bidder1.balance, 16 ether);
    }
}
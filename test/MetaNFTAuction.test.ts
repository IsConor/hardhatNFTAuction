import { expect } from "chai";
import { network } from "hardhat";
// import { MetaNFTAuction } from "../types/ethers-contracts/MetaNFTAuction.js";

const { ethers, networkHelpers } = await network.connect();

// 定义全局常量
const ADMIN_INITIAL_ETH = ethers.parseEther("100");
const ETH_PRICE = 7n * 10n ** 8n; // 7美元，8位小数
const USDC_PRICE = 1n * 10n ** 8n; // 1美元，8位小数
const USDC_DECIMALS = 6;

// 定义Fixture函数
async function loadMetaNFTFixture() {
    const [admin, proxyAdmin, owner, usdcOwner, seller, bidder1, bidder2] = 
    await ethers.getSigners();

    // 1. 部署Mock预言机（ETH=7美元，USDC=1美元，带8位小数）
    const mockEthPriceFeed = await ethers.deployContract("MockPriceFeed",[7 * 10**8]);
    const mockUsdcPriceFeed = await ethers.deployContract("MockPriceFeed",[1 * 10**8]);

    const metaNFTAuctionImpl = await ethers.deployContract("MetaNFTAuction");
    const initData = metaNFTAuctionImpl.interface.encodeFunctionData(
        "initialize",
        [
            admin.address,true,
            await mockEthPriceFeed.getAddress(),
            await mockUsdcPriceFeed.getAddress()
        ]
    );
    // 部署透明升级代理
    const transparentProxy = await ethers.deployContract(
        "TransparentUpgradeableProxy",
        [
            await metaNFTAuctionImpl.getAddress(),
            proxyAdmin.address,
            initData,
        ]
    );

    // 将代理合约包装为MetaNFTAuction接口
    const auction = await ethers.getContractAt(
        "MetaNFTAuction",
        await transparentProxy.getAddress()
    ) as MetaNFTAuction;

    // 部署MetaNFT合约
    const nft = await ethers.deployContract("MetaNFT", [], owner); // 由owner部署

    // 部署Mock USDC合约
    const usdc = await ethers.deployContract("MockERC20", [USDC_DECIMALS], usdcOwner);
   
    return { 
        // 合约实例
        auction, 
        nft, 
        mockEthPriceFeed, 
        mockUsdcPriceFeed, 
        usdc, 
        // 测试账户
        admin, 
        seller, 
        bidder1, 
        bidder2
    };
}

describe("MetaNFTAuction", function () {

    // 仅管理员可以发起拍卖
    it("Should revert when non-admin starts auction", async function (){
        const {auction, seller, nft, usdc} = await networkHelpers.loadFixture(loadMetaNFTFixture);
        await expect(
            auction.connect(seller).startBid(
                seller.address,
                await nft.getAddress(),
                1,
                3600,
                await usdc.getAddress(),
                100
            )
        ).to.be.revertedWith("Not Admin!");
    })
});

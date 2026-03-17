import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const MockPriceFeedModule = buildModule("MockPriceFeedModule", (m) => {
    // 1. 部署Mock预言机（ETH=7美元，USDC=1美元，带8位小数）
    // ETH=7美元，USDC=1美元，带8位小数）7 * 10**8/1 * 10**8
    const MockPriceFeed = m.contract("MockPriceFeed",[7 * 10 ** 8]);

    return {MockPriceFeed};
})

export default MockPriceFeedModule;

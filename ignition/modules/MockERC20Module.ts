import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const MockERC20Module = buildModule("MockERC20Module", (m) => {
    // 例如USDC小数位数是 6
    const MockERC20 = m.contract("MockERC20", [6]);

    return {MockERC20};
})

export default MockERC20Module;

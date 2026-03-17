import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const MetaNFTModule = buildModule("MetaNFTModule", (m) => {
    const metaNft = m.contract("MetaNFT");

    return {metaNft};
})

export default MetaNFTModule;

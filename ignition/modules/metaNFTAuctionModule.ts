import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// 定义并创建部署模块
const metaNFTAuctionModule = buildModule("MetaNFTAuction", (m)=>{
  // 声明要部署的 metaNFTAuction 合约
    const metaNFTAuction = m.contract("MetaNFTAuction");
    return {metaNFTAuction};
})

// 导出整个部署模块,Hardhat ignition运行部署命令时，会识别这个导出的模块，并执行其中的合约部署逻辑
export default metaNFTAuctionModule;
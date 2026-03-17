import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.connect();

// 定义Fixture函数
async function loadMetaNFTFixture() {
    const [owner, user1] = await ethers.getSigners();
    const metaNft = await ethers.deployContract("MetaNFT");
    return { metaNft, owner, user1 };
}

describe("MetaNft", function () {
    // 测试铸造功能
    it("Should test ownerOf address when mint", async function () {
        const { metaNft, owner, user1 } = await networkHelpers.loadFixture(loadMetaNFTFixture);
        // 先给user1铸造一枚NFT，tokenId为1
        await metaNft.connect(owner).mint(user1);
        // 验证非合约部署者owner铸造会revert：not owner
        await expect(metaNft.connect(user1).mint(user1)).to.be.revertedWith("not owner");

        // 验证tokenId为0的NFT 持有者为owner
        expect(await metaNft.ownerOf(0)).to.equal(owner);
        // 验证tokenId为1的NFT 持有者为user1
        expect(await metaNft.ownerOf(1)).to.equal(user1);
    });

    it("Should test ownerof address when burn", async function () {
        const { metaNft, owner, user1 } = await networkHelpers.loadFixture(loadMetaNFTFixture);
        // 先给user1铸造一枚NFT，tokenId为1
        await metaNft.mint(user1);


        // 验证tokenId为1的NFT 持有者为user1
        expect(await metaNft.ownerOf(1)).to.equal(user1);
        // 验证user1持有的NFT数量为1
        expect(await metaNft.balanceOf(user1)).to.equal(1);


        // 销毁tokenId为1的代币
        await metaNft.burn(1);
        // 验证非合约部署者use1销毁NFT会revert：not owner
        await expect(metaNft.connect(user1).burn(1)).to.be.revertedWith("not owner");
        // 验证user1持有的代币数量为0
        expect(await metaNft.balanceOf(user1)).to.equal(0);
    })
});

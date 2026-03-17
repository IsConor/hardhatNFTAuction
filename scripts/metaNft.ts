import { network } from "hardhat";

const { ethers } = await network.connect({
  network: "hardhatOp",
  chainType: "op",
});

console.log("Sending transaction using the OP chain type");

const [seller] = await ethers.getSigners();

// const metaNft = ethers.deployContract("MetaNft");


console.log("Sending 1 wei from", seller.address, "to itself");

console.log("Sending L2 transaction");
const tx = await seller.sendTransaction({
  to: seller.address,
  value: 1n,
});

await tx.wait();

console.log("Transaction sent successfully");

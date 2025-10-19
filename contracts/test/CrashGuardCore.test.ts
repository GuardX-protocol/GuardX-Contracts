import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { describe, it } from "node:test";

describe("CrashGuardCore", function () {
  async function deployCrashGuardCoreFixture() {
    const [owner, user1, user2, emergencyExecutor] = await ethers.getSigners();

    // Deploy CrashGuardCore
    const CrashGuardCore = await ethers.getContractFactory("CrashGuardCore");
    const crashGuardCore = await CrashGuardCore.deploy();

    // Deploy mock ERC20 token for testing
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockERC20.deploy("Mock Token", "MOCK", 18);

    return {
      crashGuardCore,
      mockToken,
      owner,
      user1,
      user2,
      emergencyExecutor
    };
  }

  describe("Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      const { crashGuardCore, owner } = await loadFixture(deployCrashGuardCoreFixture);

      expect(await crashGuardCore.owner()).to.equal(owner.address);
      expect(await crashGuardCore.supportedTokens(ethers.ZeroAddress)).to.be.true; // ETH is supported by default
    });
  });

  describe("Asset Management", function () {
    it("Should allow ETH deposits", async function () {
      const { crashGuardCore, user1 } = await loadFixture(deployCrashGuardCoreFixture);

      const depositAmount = ethers.parseEther("1.0");
      
      await expect(
        crashGuardCore.connect(user1).depositAsset(ethers.ZeroAddress, depositAmount, { value: depositAmount })
      ).to.emit(crashGuardCore, "AssetDeposited")
        .withArgs(user1.address, ethers.ZeroAddress, depositAmount);

      expect(await crashGuardCore.getUserBalance(user1.address, ethers.ZeroAddress)).to.equal(depositAmount);
    });

    it("Should allow ERC20 deposits", async function () {
      const { crashGuardCore, mockToken, user1, owner } = await loadFixture(deployCrashGuardCoreFixture);

      // Add token as supported
      await crashGuardCore.connect(owner).addSupportedToken(await mockToken.getAddress());

      // Mint tokens to user1
      const depositAmount = ethers.parseEther("100");
      await mockToken.mint(user1.address, depositAmount);
      await mockToken.connect(user1).approve(await crashGuardCore.getAddress(), depositAmount);

      await expect(
        crashGuardCore.connect(user1).depositAsset(await mockToken.getAddress(), depositAmount)
      ).to.emit(crashGuardCore, "AssetDeposited")
        .withArgs(user1.address, await mockToken.getAddress(), depositAmount);

      expect(await crashGuardCore.getUserBalance(user1.address, await mockToken.getAddress())).to.equal(depositAmount);
    });

    it("Should allow withdrawals", async function () {
      const { crashGuardCore, user1 } = await loadFixture(deployCrashGuardCoreFixture);

      const depositAmount = ethers.parseEther("1.0");
      const withdrawAmount = ethers.parseEther("0.5");

      // Deposit first
      await crashGuardCore.connect(user1).depositAsset(ethers.ZeroAddress, depositAmount, { value: depositAmount });

      // Withdraw
      await expect(
        crashGuardCore.connect(user1).withdrawAsset(ethers.ZeroAddress, withdrawAmount)
      ).to.emit(crashGuardCore, "AssetWithdrawn")
        .withArgs(user1.address, ethers.ZeroAddress, withdrawAmount);

      expect(await crashGuardCore.getUserBalance(user1.address, ethers.ZeroAddress)).to.equal(depositAmount - withdrawAmount);
    });

    it("Should reject deposits below minimum", async function () {
      const { crashGuardCore, user1 } = await loadFixture(deployCrashGuardCoreFixture);

      const tooSmallAmount = ethers.parseEther("0.0001"); // Below 0.001 ETH minimum

      await expect(
        crashGuardCore.connect(user1).depositAsset(ethers.ZeroAddress, tooSmallAmount, { value: tooSmallAmount })
      ).to.be.revertedWith("Amount below minimum");
    });
  });

  describe("Protection Policy", function () {
    it("Should allow setting protection policy", async function () {
      const { crashGuardCore, mockToken, user1, owner } = await loadFixture(deployCrashGuardCoreFixture);

      // Add token as supported
      await crashGuardCore.connect(owner).addSupportedToken(await mockToken.getAddress());

      const policy = {
        crashThreshold: 2000, // 20%
        maxSlippage: 1000, // 10%
        emergencyActions: [],
        stablecoinPreference: await mockToken.getAddress(),
        gasLimit: 500000
      };

      await expect(
        crashGuardCore.connect(user1).setProtectionPolicy(policy)
      ).to.emit(crashGuardCore, "PolicyUpdated")
        .withArgs(user1.address, [policy.crashThreshold, policy.maxSlippage, policy.emergencyActions, policy.stablecoinPreference, policy.gasLimit]);

      const retrievedPolicy = await crashGuardCore.getProtectionPolicy(user1.address);
      expect(retrievedPolicy.crashThreshold).to.equal(policy.crashThreshold);
      expect(retrievedPolicy.maxSlippage).to.equal(policy.maxSlippage);
      expect(retrievedPolicy.stablecoinPreference).to.equal(policy.stablecoinPreference);
    });

    it("Should reject invalid protection policy", async function () {
      const { crashGuardCore, user1 } = await loadFixture(deployCrashGuardCoreFixture);

      const invalidPolicy = {
        crashThreshold: 15000, // > 100%
        maxSlippage: 1000,
        emergencyActions: [],
        stablecoinPreference: ethers.ZeroAddress,
        gasLimit: 500000
      };

      await expect(
        crashGuardCore.connect(user1).setProtectionPolicy(invalidPolicy)
      ).to.be.revertedWith("Invalid crash threshold");
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow emergency executor to withdraw", async function () {
      const { crashGuardCore, user1, emergencyExecutor, owner } = await loadFixture(deployCrashGuardCoreFixture);

      // Set emergency executor
      await crashGuardCore.connect(owner).setEmergencyExecutor(emergencyExecutor.address);

      const depositAmount = ethers.parseEther("1.0");
      const withdrawAmount = ethers.parseEther("0.5");

      // User deposits
      await crashGuardCore.connect(user1).depositAsset(ethers.ZeroAddress, depositAmount, { value: depositAmount });

      // Emergency executor withdraws
      await expect(
        crashGuardCore.connect(emergencyExecutor).emergencyWithdraw(user1.address, ethers.ZeroAddress, withdrawAmount)
      ).to.emit(crashGuardCore, "EmergencyProtectionTriggered")
        .withArgs(user1.address, await ethers.provider.getBlock('latest').then(b => b!.timestamp + 1));

      expect(await crashGuardCore.getUserBalance(user1.address, ethers.ZeroAddress)).to.equal(depositAmount - withdrawAmount);
    });

    it("Should reject emergency withdrawal from unauthorized address", async function () {
      const { crashGuardCore, user1, user2 } = await loadFixture(deployCrashGuardCoreFixture);

      const depositAmount = ethers.parseEther("1.0");
      await crashGuardCore.connect(user1).depositAsset(ethers.ZeroAddress, depositAmount, { value: depositAmount });

      await expect(
        crashGuardCore.connect(user2).emergencyWithdraw(user1.address, ethers.ZeroAddress, depositAmount)
      ).to.be.revertedWith("Only emergency executor");
    });
  });

  describe("Access Control", function () {
    it("Should allow owner to add supported tokens", async function () {
      const { crashGuardCore, mockToken, owner } = await loadFixture(deployCrashGuardCoreFixture);

      await crashGuardCore.connect(owner).addSupportedToken(await mockToken.getAddress());
      expect(await crashGuardCore.supportedTokens(await mockToken.getAddress())).to.be.true;
    });

    it("Should reject non-owner adding supported tokens", async function () {
      const { crashGuardCore, mockToken, user1 } = await loadFixture(deployCrashGuardCoreFixture);

      await expect(
        crashGuardCore.connect(user1).addSupportedToken(await mockToken.getAddress())
      ).to.be.revertedWithCustomError(crashGuardCore, "OwnableUnauthorizedAccount");
    });
  });
});
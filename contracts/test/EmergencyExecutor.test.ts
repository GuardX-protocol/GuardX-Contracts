import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { describe, it } from "node:test";

describe("EmergencyExecutor", function () {
  async function deployEmergencyExecutorFixture() {
    const [owner, user1, user2, controller] = await ethers.getSigners();

    // Deploy CrashGuardCore
    const CrashGuardCore = await ethers.getContractFactory("CrashGuardCore");
    const crashGuardCore = await CrashGuardCore.deploy();

    // Deploy DEXAggregator
    const DEXAggregator = await ethers.getContractFactory("DEXAggregator");
    const dexAggregator = await DEXAggregator.deploy();

    // Deploy EmergencyExecutor
    const EmergencyExecutor = await ethers.getContractFactory("EmergencyExecutor");
    const emergencyExecutor = await EmergencyExecutor.deploy(
      await crashGuardCore.getAddress(),
      await dexAggregator.getAddress()
    );

    // Deploy mock ERC20 tokens
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockERC20.deploy("Mock Token", "MOCK", 18);
    const stablecoin = await MockERC20.deploy("Mock USDC", "USDC", 6);

    // Set up emergency executor in CrashGuardCore
    await crashGuardCore.setEmergencyExecutor(await emergencyExecutor.getAddress());

    return {
      crashGuardCore,
      dexAggregator,
      emergencyExecutor,
      mockToken,
      stablecoin,
      owner,
      user1,
      user2,
      controller
    };
  }

  describe("Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      const { emergencyExecutor, crashGuardCore, dexAggregator, owner } = await loadFixture(deployEmergencyExecutorFixture);

      expect(await emergencyExecutor.owner()).to.equal(owner.address);
      expect(await emergencyExecutor.crashGuardCore()).to.equal(await crashGuardCore.getAddress());
      expect(await emergencyExecutor.dexAggregator()).to.equal(await dexAggregator.getAddress());
      expect(await emergencyExecutor.emergencyPaused()).to.be.false;
    });
  });

  describe("Access Control", function () {
    it("Should allow owner to set access control", async function () {
      const { emergencyExecutor, controller, owner } = await loadFixture(deployEmergencyExecutorFixture);

      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);
      expect(await emergencyExecutor.authorizedControllers(controller.address)).to.be.true;
    });

    it("Should reject non-owner setting access control", async function () {
      const { emergencyExecutor, controller, user1 } = await loadFixture(deployEmergencyExecutorFixture);

      await expect(
        emergencyExecutor.connect(user1).setAccessControl(controller.address, true)
      ).to.be.revertedWithCustomError(emergencyExecutor, "OwnableUnauthorizedAccount");
    });
  });

  describe("Emergency Protection", function () {
    it("Should execute emergency protection for authorized controller", async function () {
      const { 
        emergencyExecutor, 
        crashGuardCore, 
        mockToken, 
        stablecoin, 
        controller, 
        user1, 
        owner 
      } = await loadFixture(deployEmergencyExecutorFixture);

      // Set up authorized controller
      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);

      // Add tokens as supported
      await crashGuardCore.connect(owner).addSupportedToken(await mockToken.getAddress());
      await crashGuardCore.connect(owner).addSupportedToken(await stablecoin.getAddress());

      // Set up user portfolio with assets
      const depositAmount = ethers.parseEther("100");
      await mockToken.mint(user1.address, depositAmount);
      await mockToken.connect(user1).approve(await crashGuardCore.getAddress(), depositAmount);
      await crashGuardCore.connect(user1).depositAsset(await mockToken.getAddress(), depositAmount);

      // Set protection policy
      const policy = {
        crashThreshold: 2000, // 20%
        maxSlippage: 1000, // 10%
        emergencyActions: [],
        stablecoinPreference: await stablecoin.getAddress(),
        gasLimit: 500000
      };
      await crashGuardCore.connect(user1).setProtectionPolicy(policy);

      // Mock portfolio with high risk assets
      await crashGuardCore.connect(owner).updateAssetValue(
        user1.address,
        await mockToken.getAddress(),
        ethers.parseEther("100"), // $100 value
        5 // High risk level
      );

      // Execute emergency protection
      await expect(
        emergencyExecutor.connect(controller).executeEmergencyProtection(user1.address)
      ).to.emit(emergencyExecutor, "EmergencyExecutionStarted")
        .withArgs(user1.address, await ethers.provider.getBlock('latest').then(b => b!.timestamp + 1));
    });

    it("Should reject emergency protection from unauthorized address", async function () {
      const { emergencyExecutor, user1, user2 } = await loadFixture(deployEmergencyExecutorFixture);

      await expect(
        emergencyExecutor.connect(user2).executeEmergencyProtection(user1.address)
      ).to.be.revertedWith("Not authorized");
    });

    it("Should reject emergency protection when paused", async function () {
      const { emergencyExecutor, controller, user1, owner } = await loadFixture(deployEmergencyExecutorFixture);

      // Set up authorized controller
      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);

      // Pause emergency operations
      await emergencyExecutor.connect(owner).setEmergencyPause(true);

      await expect(
        emergencyExecutor.connect(controller).executeEmergencyProtection(user1.address)
      ).to.be.revertedWith("Emergency paused");
    });
  });

  describe("Asset Conversion", function () {
    it("Should convert assets to stablecoin", async function () {
      const { 
        emergencyExecutor, 
        crashGuardCore,
        dexAggregator,
        mockToken, 
        stablecoin, 
        controller, 
        owner 
      } = await loadFixture(deployEmergencyExecutorFixture);

      // Set up authorized controller
      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);

      // Add tokens as supported
      await crashGuardCore.connect(owner).addSupportedToken(await mockToken.getAddress());
      await crashGuardCore.connect(owner).addSupportedToken(await stablecoin.getAddress());

      // Provide liquidity to DEX aggregator for swaps
      const liquidityAmount = ethers.parseEther("1000");
      await stablecoin.mint(await dexAggregator.getAddress(), liquidityAmount);

      const assets = [await mockToken.getAddress()];
      const maxSlippage = 1000; // 10%

      await expect(
        emergencyExecutor.connect(controller).emergencyConvertToStable(
          assets,
          await stablecoin.getAddress(),
          maxSlippage
        )
      ).to.not.be.reverted;
    });

    it("Should reject conversion with excessive slippage", async function () {
      const { emergencyExecutor, mockToken, stablecoin, controller, owner } = await loadFixture(deployEmergencyExecutorFixture);

      // Set up authorized controller
      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);

      const assets = [await mockToken.getAddress()];
      const excessiveSlippage = 6000; // 60% - above MAX_SLIPPAGE

      await expect(
        emergencyExecutor.connect(controller).emergencyConvertToStable(
          assets,
          await stablecoin.getAddress(),
          excessiveSlippage
        )
      ).to.be.revertedWith("Slippage too high");
    });
  });

  describe("Batch Operations", function () {
    it("Should execute batch emergency actions", async function () {
      const { 
        emergencyExecutor, 
        crashGuardCore,
        mockToken, 
        stablecoin, 
        controller, 
        user1,
        user2,
        owner 
      } = await loadFixture(deployEmergencyExecutorFixture);

      // Set up authorized controller
      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);

      // Add tokens as supported
      await crashGuardCore.connect(owner).addSupportedToken(await mockToken.getAddress());
      await crashGuardCore.connect(owner).addSupportedToken(await stablecoin.getAddress());

      const actions = [
        {
          user: user1.address,
          assetsToConvert: [await mockToken.getAddress()],
          targetStablecoin: await stablecoin.getAddress(),
          maxSlippage: 1000,
          deadline: Math.floor(Date.now() / 1000) + 3600
        },
        {
          user: user2.address,
          assetsToConvert: [await mockToken.getAddress()],
          targetStablecoin: await stablecoin.getAddress(),
          maxSlippage: 1000,
          deadline: Math.floor(Date.now() / 1000) + 3600
        }
      ];

      await expect(
        emergencyExecutor.connect(controller).batchEmergencyActions(actions)
      ).to.emit(emergencyExecutor, "BatchExecutionCompleted");
    });

    it("Should reject batch with too many actions", async function () {
      const { emergencyExecutor, mockToken, stablecoin, controller, owner } = await loadFixture(deployEmergencyExecutorFixture);

      // Set up authorized controller
      await emergencyExecutor.connect(owner).setAccessControl(controller.address, true);

      // Create batch with more than MAX_BATCH_SIZE actions
      const actions = Array(51).fill({
        user: ethers.ZeroAddress,
        assetsToConvert: [await mockToken.getAddress()],
        targetStablecoin: await stablecoin.getAddress(),
        maxSlippage: 1000,
        deadline: Math.floor(Date.now() / 1000) + 3600
      });

      await expect(
        emergencyExecutor.connect(controller).batchEmergencyActions(actions)
      ).to.be.revertedWith("Batch too large");
    });
  });

  describe("Statistics and Monitoring", function () {
    it("Should track execution statistics", async function () {
      const { emergencyExecutor } = await loadFixture(deployEmergencyExecutorFixture);

      const stats = await emergencyExecutor.getExecutionStats();
      expect(stats.total).to.equal(0);
      expect(stats.successful).to.equal(0);
      expect(stats.successRate).to.equal(0);
    });

    it("Should check if user can execute emergency", async function () {
      const { emergencyExecutor, user1 } = await loadFixture(deployEmergencyExecutorFixture);

      const [canExecute, reason] = await emergencyExecutor.canExecuteEmergency(user1.address);
      expect(canExecute).to.be.false;
      expect(reason).to.equal("No assets to protect");
    });
  });
});
import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { describe, it } from "node:test";

describe("Lit Protocol Integration", function () {
  async function deployLitProtocolFixture() {
    const [owner, user1, user2, relayer, pkpAddress] = await ethers.getSigners();

    // Deploy LitRelayContract
    const LitRelayContract = await ethers.getContractFactory("LitRelayContract");
    const litRelayContract = await LitRelayContract.deploy();

    // Deploy LitProtocolIntegration
    const LitProtocolIntegration = await ethers.getContractFactory("LitProtocolIntegration");
    const litProtocolIntegration = await LitProtocolIntegration.deploy(
      await litRelayContract.getAddress()
    );

    // Deploy CrossChainManager
    const CrossChainManager = await ethers.getContractFactory("CrossChainManager");
    const crossChainManager = await CrossChainManager.deploy(
      await litRelayContract.getAddress(),
      await litProtocolIntegration.getAddress()
    );

    return {
      litRelayContract,
      litProtocolIntegration,
      crossChainManager,
      owner,
      user1,
      user2,
      relayer,
      pkpAddress
    };
  }

  describe("LitRelayContract", function () {
    describe("Deployment", function () {
      it("Should deploy with correct initial state", async function () {
        const { litRelayContract, owner } = await loadFixture(deployLitProtocolFixture);

        expect(await litRelayContract.owner()).to.equal(owner.address);
        expect(await litRelayContract.CHAIN_ID()).to.equal(31337); // Hardhat chain ID
        expect(await litRelayContract.authorizedRelayers(owner.address)).to.be.true;
      });

      it("Should initialize supported chains", async function () {
        const { litRelayContract } = await loadFixture(deployLitProtocolFixture);

        expect(await litRelayContract.supportedChains(1)).to.be.true; // Ethereum
        expect(await litRelayContract.supportedChains(137)).to.be.true; // Polygon
        expect(await litRelayContract.supportedChains(42161)).to.be.true; // Arbitrum
      });
    });

    describe("PKP Management", function () {
      it("Should allow authorized relayer to register PKP", async function () {
        const { litRelayContract, pkpAddress, owner } = await loadFixture(deployLitProtocolFixture);

        const publicKey = ethers.randomBytes(64); // Mock public key

        await expect(
          litRelayContract.connect(owner).registerPKP(pkpAddress.address, publicKey)
        ).to.emit(litRelayContract, "PKPRegistered")
          .withArgs(pkpAddress.address, await ethers.provider.getBlock('latest').then(b => b!.timestamp + 1));

        expect(await litRelayContract.isPKPRegistered(pkpAddress.address)).to.be.true;
      });

      it("Should reject PKP registration from unauthorized address", async function () {
        const { litRelayContract, pkpAddress, user1 } = await loadFixture(deployLitProtocolFixture);

        const publicKey = ethers.randomBytes(64);

        await expect(
          litRelayContract.connect(user1).registerPKP(pkpAddress.address, publicKey)
        ).to.be.revertedWith("Not authorized relayer");
      });

      it("Should reject duplicate PKP registration", async function () {
        const { litRelayContract, pkpAddress, owner } = await loadFixture(deployLitProtocolFixture);

        const publicKey = ethers.randomBytes(64);

        // Register PKP first time
        await litRelayContract.connect(owner).registerPKP(pkpAddress.address, publicKey);

        // Try to register again
        await expect(
          litRelayContract.connect(owner).registerPKP(pkpAddress.address, publicKey)
        ).to.be.revertedWith("PKP already registered");
      });
    });

    describe("Lit Action Management", function () {
      it("Should allow authorized relayer to register Lit Action", async function () {
        const { litRelayContract, user1, owner } = await loadFixture(deployLitProtocolFixture);

        const actionId = "test-action-1";

        await expect(
          litRelayContract.connect(owner).registerLitAction(actionId, user1.address)
        ).to.emit(litRelayContract, "LitActionRegistered")
          .withArgs(actionId, user1.address);

        const [active, lastExecution] = await litRelayContract.getLitActionStatus(actionId);
        expect(active).to.be.true;
        expect(lastExecution).to.equal(0);
      });

      it("Should allow owner to deactivate Lit Action", async function () {
        const { litRelayContract, user1, owner } = await loadFixture(deployLitProtocolFixture);

        const actionId = "test-action-2";

        // Register action
        await litRelayContract.connect(owner).registerLitAction(actionId, user1.address);

        // Deactivate action
        await litRelayContract.connect(user1).deactivateLitAction(actionId);

        const [active] = await litRelayContract.getLitActionStatus(actionId);
        expect(active).to.be.false;
      });
    });

    describe("Cross-Chain Messaging", function () {
      it("Should send cross-chain message", async function () {
        const { litRelayContract, owner } = await loadFixture(deployLitProtocolFixture);

        const message = {
          sourceChainId: 31337,
          targetChainId: 1,
          sourceContract: owner.address,
          targetContract: owner.address,
          payload: "0x1234",
          nonce: 1,
          timestamp: Math.floor(Date.now() / 1000)
        };

        await expect(
          litRelayContract.connect(owner).sendCrossChainMessage(message)
        ).to.emit(litRelayContract, "CrossChainMessageSent");
      });

      it("Should reject message to unsupported chain", async function () {
        const { litRelayContract, owner } = await loadFixture(deployLitProtocolFixture);

        const message = {
          sourceChainId: 31337,
          targetChainId: 999, // Unsupported chain
          sourceContract: owner.address,
          targetContract: owner.address,
          payload: "0x1234",
          nonce: 1,
          timestamp: Math.floor(Date.now() / 1000)
        };

        await expect(
          litRelayContract.connect(owner).sendCrossChainMessage(message)
        ).to.be.revertedWith("Chain not supported");
      });
    });
  });

  describe("LitProtocolIntegration", function () {
    describe("PKP Authentication", function () {
      it("Should authenticate user with PKP", async function () {
        const { litProtocolIntegration, litRelayContract, user1, pkpAddress, owner } = await loadFixture(deployLitProtocolFixture);

        // First register PKP in relay contract
        const publicKey = ethers.randomBytes(64);
        await litRelayContract.connect(owner).registerPKP(pkpAddress.address, publicKey);

        const pkpAuth = {
          pkpAddress: pkpAddress.address,
          publicKey: publicKey,
          threshold: 1,
          isActive: true
        };

        // Create signature (mock)
        const authHash = ethers.keccak256(
          ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "bytes", "uint256", "uint256"],
            [user1.address, pkpAuth.pkpAddress, pkpAuth.publicKey, pkpAuth.threshold, await ethers.provider.getBlock('latest').then(b => b!.timestamp + 1)]
          )
        );

        const signature = await pkpAddress.signMessage(ethers.getBytes(authHash));

        await expect(
          litProtocolIntegration.connect(owner).authenticateWithPKP(user1.address, pkpAuth, signature)
        ).to.emit(litProtocolIntegration, "PKPAuthenticated")
          .withArgs(user1.address, pkpAddress.address, await ethers.provider.getBlock('latest').then(b => b!.timestamp + 1));
      });
    });

    describe("Conditional Access", function () {
      it("Should create conditional access", async function () {
        const { litProtocolIntegration, litRelayContract, user1, pkpAddress, owner } = await loadFixture(deployLitProtocolFixture);

        // Set up PKP authentication first
        const publicKey = ethers.randomBytes(64);
        await litRelayContract.connect(owner).registerPKP(pkpAddress.address, publicKey);

        const pkpAuth = {
          pkpAddress: pkpAddress.address,
          publicKey: publicKey,
          threshold: 1,
          isActive: true
        };

        const authHash = ethers.keccak256(
          ethers.AbiCoder.defaultAbiCoder().encode(
            ["address", "address", "bytes", "uint256", "uint256"],
            [user1.address, pkpAuth.pkpAddress, pkpAuth.publicKey, pkpAuth.threshold, await ethers.provider.getBlock('latest').then(b => b!.timestamp + 1)]
          )
        );

        const signature = await pkpAddress.signMessage(ethers.getBytes(authHash));
        await litProtocolIntegration.connect(owner).authenticateWithPKP(user1.address, pkpAuth, signature);

        // Create conditional access
        const access = {
          conditionHash: ethers.ZeroHash,
          accessConditions: "portfolio_value > 1000",
          isActive: true,
          createdAt: Math.floor(Date.now() / 1000),
          expiresAt: Math.floor(Date.now() / 1000) + 86400 // 24 hours
        };

        await expect(
          litProtocolIntegration.connect(owner).createConditionalAccess(user1.address, access)
        ).to.emit(litProtocolIntegration, "ConditionalAccessCreated");
      });
    });
  });

  describe("CrossChainManager", function () {
    describe("Asset Locking", function () {
      it("Should lock asset for cross-chain operation", async function () {
        const { crossChainManager, user1, owner } = await loadFixture(deployLitProtocolFixture);

        // Deploy mock ERC20 token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const mockToken = await MockERC20.deploy("Mock Token", "MOCK", 18);

        const lockAmount = ethers.parseEther("100");
        await mockToken.mint(owner.address, lockAmount);
        await mockToken.connect(owner).approve(await crossChainManager.getAddress(), lockAmount);

        await expect(
          crossChainManager.connect(owner).lockAsset(
            user1.address,
            await mockToken.getAddress(),
            lockAmount,
            1 // Ethereum mainnet
          )
        ).to.emit(crossChainManager, "AssetLocked");
      });

      it("Should reject locking for same chain", async function () {
        const { crossChainManager, user1, owner } = await loadFixture(deployLitProtocolFixture);

        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const mockToken = await MockERC20.deploy("Mock Token", "MOCK", 18);

        const lockAmount = ethers.parseEther("100");

        await expect(
          crossChainManager.connect(owner).lockAsset(
            user1.address,
            await mockToken.getAddress(),
            lockAmount,
            31337 // Same as current chain
          )
        ).to.be.revertedWith("Cannot lock for same chain");
      });
    });

    describe("Cross-Chain Migration", function () {
      it("Should initiate cross-chain migration", async function () {
        const { crossChainManager, user1, owner } = await loadFixture(deployLitProtocolFixture);

        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const mockToken = await MockERC20.deploy("Mock Token", "MOCK", 18);

        const migrationAmount = ethers.parseEther("50");
        await mockToken.mint(owner.address, migrationAmount);
        await mockToken.connect(owner).approve(await crossChainManager.getAddress(), migrationAmount);

        await expect(
          crossChainManager.connect(owner).initiateCrossChainMigration(
            user1.address,
            await mockToken.getAddress(),
            migrationAmount,
            137 // Polygon
          )
        ).to.emit(crossChainManager, "CrossChainMigrationInitiated");
      });
    });
  });
});
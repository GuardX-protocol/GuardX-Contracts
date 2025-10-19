import { expect } from "chai";
import { ethers } from "hardhat";

describe("Core Contracts", function () {
  let crashGuardCore: any;
  let pythPriceMonitor: any;
  let emergencyExecutor: any;
  let dexAggregator: any;
  
  const mockPythAddress = "0x1234567890123456789012345678901234567890";
  
  beforeEach(async function () {
    // Deploy CrashGuardCore
    const CrashGuardCore = await ethers.getContractFactory("CrashGuardCore");
    crashGuardCore = await CrashGuardCore.deploy();
    
    // Deploy PythPriceMonitor
    const PythPriceMonitor = await ethers.getContractFactory("PythPriceMonitor");
    pythPriceMonitor = await PythPriceMonitor.deploy(mockPythAddress);
    
    // Deploy DEXAggregator
    const DEXAggregator = await ethers.getContractFactory("DEXAggregator");
    dexAggregator = await DEXAggregator.deploy();
    
    // Deploy EmergencyExecutor
    const EmergencyExecutor = await ethers.getContractFactory("EmergencyExecutor");
    emergencyExecutor = await EmergencyExecutor.deploy(
      await crashGuardCore.getAddress(),
      await dexAggregator.getAddress()
    );
  });

  it("Should deploy all contracts successfully", async function () {
    expect(await crashGuardCore.getAddress()).to.be.properAddress;
    expect(await pythPriceMonitor.getAddress()).to.be.properAddress;
    expect(await emergencyExecutor.getAddress()).to.be.properAddress;
    expect(await dexAggregator.getAddress()).to.be.properAddress;
  });

  it("Should have correct initial state", async function () {
    // Test CrashGuardCore
    expect(await crashGuardCore.supportedTokens(ethers.ZeroAddress)).to.be.true;
    
    // Test PythPriceMonitor
    expect(await pythPriceMonitor.PYTH()).to.equal(mockPythAddress);
    
    // Test EmergencyExecutor
    expect(await emergencyExecutor.crashGuardCore()).to.equal(await crashGuardCore.getAddress());
    expect(await emergencyExecutor.dexAggregator()).to.equal(await dexAggregator.getAddress());
  });
});
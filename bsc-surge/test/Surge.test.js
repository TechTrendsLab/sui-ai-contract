const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Surge Token", function () {
  let Surge, surge;
  let owner, executor, user1, user2;

  beforeEach(async function () {
    [owner, executor, user1, user2] = await ethers.getSigners();
    Surge = await ethers.getContractFactory("Surge");
    // Deploy Surge with owner
    surge = await Surge.deploy(owner.address);
    await surge.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should have correct name and symbol", async function () {
      expect(await surge.name()).to.equal("SurgeAI");
      expect(await surge.symbol()).to.equal("SGE");
    });

    it("Should have correct decimals", async function () {
      expect(await surge.decimals()).to.equal(9);
    });

    it("Should set the correct owner", async function () {
      expect(await surge.owner()).to.equal(owner.address);
    });

    it("Should have initial executor as zero address", async function () {
      expect(await surge.surgeBridgeExecutor()).to.equal(ethers.ZeroAddress);
    });
  });

  describe("Configuration", function () {
    it("Should allow owner to set bridge executor", async function () {
      await expect(surge.setSurgeBridgeExecutor(executor.address))
        .to.emit(surge, "SurgeBridgeExecutorUpdated")
        .withArgs(executor.address);

      expect(await surge.surgeBridgeExecutor()).to.equal(executor.address);
    });

    it("Should not allow non-owner to set bridge executor", async function () {
      await expect(
        surge.connect(user1).setSurgeBridgeExecutor(executor.address)
      ).to.be.revertedWithCustomError(surge, "OwnableUnauthorizedAccount");
    });

    it("Should support two-step ownership transfer", async function () {
      // 1. Owner starts transfer
      await surge.transferOwnership(user1.address);
      expect(await surge.owner()).to.equal(owner.address);
      expect(await surge.pendingOwner()).to.equal(user1.address);

      // 2. New owner accepts
      await surge.connect(user1).acceptOwnership();
      expect(await surge.owner()).to.equal(user1.address);
      expect(await surge.pendingOwner()).to.equal(ethers.ZeroAddress);
    });
  });

  describe("Bridge Operations", function () {
    beforeEach(async function () {
      // Set executor for testing
      await surge.setSurgeBridgeExecutor(executor.address);
    });

    describe("Minting", function () {
      const amount = ethers.parseUnits("100", 9);

      it("Should allow executor to mint tokens", async function () {
        await expect(surge.connect(executor).bridgeMint(user1.address, amount))
          .to.emit(surge, "BridgeMint")
          .withArgs(user1.address, amount);

        expect(await surge.balanceOf(user1.address)).to.equal(amount);
      });

      it("Should not allow non-executor to mint tokens", async function () {
        await expect(
          surge.connect(user1).bridgeMint(user1.address, amount)
        ).to.be.revertedWithCustomError(surge, "OnlySurgeBridgeExecutor");

        await expect(
          surge.connect(owner).bridgeMint(user1.address, amount)
        ).to.be.revertedWithCustomError(surge, "OnlySurgeBridgeExecutor");
      });
    });

    describe("Burning", function () {
      const amount = ethers.parseUnits("50", 9);

      beforeEach(async function () {
        // Mint some tokens to user1 first (via executor)
        const mintAmount = ethers.parseUnits("100", 9);
        await surge.connect(executor).bridgeMint(user1.address, mintAmount);
      });

      it("Should allow executor to burn tokens", async function () {
        await expect(surge.connect(executor).bridgeBurn(user1.address, amount))
          .to.emit(surge, "BridgeBurn")
          .withArgs(user1.address, amount);

        const remaining = ethers.parseUnits("50", 9);
        expect(await surge.balanceOf(user1.address)).to.equal(remaining);
      });

      it("Should not allow non-executor to burn tokens", async function () {
        await expect(
          surge.connect(user1).bridgeBurn(user1.address, amount)
        ).to.be.revertedWithCustomError(surge, "OnlySurgeBridgeExecutor");
      });

      it("Should fail if balance is insufficient", async function () {
        const tooMuch = ethers.parseUnits("200", 9);
        // ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)
        // Since OpenZeppelin 5.x, errors are custom errors.
        await expect(
          surge.connect(executor).bridgeBurn(user1.address, tooMuch)
        ).to.be.revertedWithCustomError(surge, "ERC20InsufficientBalance");
      });
    });
  });
});


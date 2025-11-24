const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SurgeBridgeExecutor", function () {
  let Surge, surge;
  let MockWormhole, wormhole;
  let SurgeBridgeExecutor, bridgeExecutor;
  let owner, user1, user2, feeRecipient;
  
  const CHAIN_ID_BSC = 56;
  const CHAIN_ID_ETH = 1;
  const WORMHOLE_CHAIN_ID_BSC = 4; // Assuming BSC Wormhole ID is 4
  const WORMHOLE_CHAIN_ID_ETH = 2; // Assuming ETH Wormhole ID is 2
  const CONSISTENCY_LEVEL = 1;
  const MIN_FEE = ethers.parseEther("0.001");
  const PAYLOAD_ID_TRANSFER = 1;

  // Helper to format address to bytes32 (Wormhole format)
  function toWormholeFormat(address) {
    return ethers.zeroPadValue(address, 32);
  }

  // Helper to create a VM struct object for the mock
  function createMockVM(
    emitterChainId,
    emitterAddress,
    payload,
    sequence = 0,
    nonce = 0,
    hash = ethers.keccak256("0x1234") // Random hash
  ) {
    return {
      version: 1,
      timestamp: Math.floor(Date.now() / 1000),
      nonce: nonce,
      emitterChainId: emitterChainId,
      emitterAddress: emitterAddress,
      sequence: sequence,
      consistencyLevel: 1,
      payload: payload,
      guardianSetIndex: 0,
      signatures: [], // Empty for mock
      hash: hash
    };
  }

  // Helper to encode VM for the mock
  function encodeMockVM(vm) {
    const abiCoder = new ethers.AbiCoder();
    // Struct definition from IWormholeCore.sol
    // struct VM { uint8 version; uint32 timestamp; uint32 nonce; uint16 emitterChainId; bytes32 emitterAddress; uint64 sequence; uint8 consistencyLevel; bytes payload; uint32 guardianSetIndex; Signature[] signatures; bytes32 hash; }
    // struct Signature { bytes32 r; bytes32 s; uint8 v; uint8 guardianIndex; }
    
    // We need to match the struct structure exactly for abi.decode in MockWormhole
    // Signature is nested.
    const signatureType = "tuple(bytes32 r, bytes32 s, uint8 v, uint8 guardianIndex)";
    const vmType = `tuple(uint8 version, uint32 timestamp, uint32 nonce, uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence, uint8 consistencyLevel, bytes payload, uint32 guardianSetIndex, ${signatureType}[] signatures, bytes32 hash)`;
    
    return abiCoder.encode([vmType], [vm]);
  }

  beforeEach(async function () {
    [owner, user1, user2, feeRecipient] = await ethers.getSigners();

    // 1. Deploy MockWormhole
    const MockWormholeFactory = await ethers.getContractFactory("MockWormhole");
    wormhole = await MockWormholeFactory.deploy();
    await wormhole.waitForDeployment();

    // 2. Deploy Surge Token
    const SurgeFactory = await ethers.getContractFactory("Surge");
    surge = await SurgeFactory.deploy(owner.address);
    await surge.waitForDeployment();

    // 3. Deploy SurgeBridgeExecutor
    const SurgeBridgeExecutorFactory = await ethers.getContractFactory("SurgeBridgeExecutor");
    bridgeExecutor = await SurgeBridgeExecutorFactory.deploy(
      await surge.getAddress(),
      await wormhole.getAddress(),
      WORMHOLE_CHAIN_ID_BSC,
      CONSISTENCY_LEVEL,
      owner.address,
      feeRecipient.address,
      MIN_FEE
    );
    await bridgeExecutor.waitForDeployment();

    // 4. Setup permissions
    // Set executor in Surge token
    await surge.setSurgeBridgeExecutor(await bridgeExecutor.getAddress());
    
    // Set trusted emitter for ETH chain (we will simulate receiving from ETH)
    // For testing, let's say the emitter on ETH is user2's address (in bytes32)
    await bridgeExecutor.setTrustedEmitter(WORMHOLE_CHAIN_ID_ETH, toWormholeFormat(user2.address));

    // 5. Mint tokens to user1 for testing
    // Since Surge owner can't mint arbitrarily (only bridgeMint), we might need to transfer initial supply or use bridgeMint if we are owner of executor.
    // Wait, Surge constructor mints? No, it's commented out in the provided code: //_mint(initialOwner, ...);
    // So we need to use bridgeMint to give user1 some tokens.
    // Since bridgeExecutor is the only one who can mint, we need a way to mint for testing.
    // BUT bridgeExecutor only mints on completeTransfer.
    // HACK: For testing setup, we can temporarily set owner as executor, mint, then set back.
    
    await surge.setSurgeBridgeExecutor(owner.address);
    const amountToMint = ethers.parseUnits("1000", 9); // 9 decimals
    await surge.bridgeMint(user1.address, amountToMint);
    await surge.setSurgeBridgeExecutor(await bridgeExecutor.getAddress());
  });

  describe("Deployment", function () {
    it("Should set the correct values", async function () {
      expect(await bridgeExecutor.surge()).to.equal(await surge.getAddress());
      expect(await bridgeExecutor.wormhole()).to.equal(await wormhole.getAddress());
      expect(await bridgeExecutor.wormholeChainId()).to.equal(WORMHOLE_CHAIN_ID_BSC);
      expect(await bridgeExecutor.feeRecipient()).to.equal(feeRecipient.address);
      expect(await bridgeExecutor.minFee()).to.equal(MIN_FEE);
    });

    it("Should not accept direct ETH deposits", async function () {
      await expect(
        owner.sendTransaction({ to: await bridgeExecutor.getAddress(), value: 100 })
      ).to.be.revertedWith("direct deposits not allowed");
    });
  });

  describe("Configuration", function () {
    it("Should allow owner to set trusted emitter", async function () {
      const newEmitter = toWormholeFormat(user1.address);
      await expect(bridgeExecutor.setTrustedEmitter(10, newEmitter))
        .to.emit(bridgeExecutor, "TrustedEmitterUpdated")
        .withArgs(10, newEmitter);
      
      expect(await bridgeExecutor.trustedEmitters(10)).to.equal(newEmitter);
    });

    it("Should not allow non-owner to set trusted emitter", async function () {
      await expect(
        bridgeExecutor.connect(user1).setTrustedEmitter(10, toWormholeFormat(user1.address))
      ).to.be.revertedWithCustomError(bridgeExecutor, "OwnableUnauthorizedAccount");
    });

    it("Should allow owner to update fee config", async function () {
      const newFee = ethers.parseEther("0.002");
      await expect(bridgeExecutor.updateFeeConfig(user2.address, newFee))
        .to.emit(bridgeExecutor, "FeeConfigUpdated")
        .withArgs(user2.address, newFee);
      
      expect(await bridgeExecutor.feeRecipient()).to.equal(user2.address);
      expect(await bridgeExecutor.minFee()).to.equal(newFee);
    });
  });

  describe("Initiate Transfer (Bridge Out)", function () {
    const amount = ethers.parseUnits("100", 9);
    const targetChain = WORMHOLE_CHAIN_ID_ETH;
    const targetAddress = ethers.zeroPadValue("0xdeadbeef", 32);

    beforeEach(async function () {
      // Approve bridge to spend user1's tokens
      await surge.connect(user1).approve(await bridgeExecutor.getAddress(), amount);
    });

    it("Should successfully initiate transfer", async function () {
      const wormholeFee = await wormhole.messageFee();
      const totalFee = wormholeFee + MIN_FEE;

      // Check balance before
      const balanceBefore = await surge.balanceOf(user1.address);
      const feeRecipientBalanceBefore = await ethers.provider.getBalance(feeRecipient.address);

      const tx = await bridgeExecutor.connect(user1).initiateTransfer(
        amount,
        targetAddress,
        targetChain,
        { value: totalFee }
      );

      // Verify events
      await expect(tx)
        .to.emit(bridgeExecutor, "TransferInitiated")
        .withArgs(user1.address, amount, targetChain, targetAddress, 0, MIN_FEE); // sequence is 0 from mock

      // Verify balances
      expect(await surge.balanceOf(user1.address)).to.equal(balanceBefore - amount);
      // Fee recipient should get minFee
      const feeRecipientBalanceAfter = await ethers.provider.getBalance(feeRecipient.address);
      expect(feeRecipientBalanceAfter - feeRecipientBalanceBefore).to.equal(MIN_FEE);
    });

    it("Should revert if fee is insufficient", async function () {
      const wormholeFee = await wormhole.messageFee();
      // Send slightly less
      const badFee = wormholeFee + MIN_FEE - 1n;

      await expect(
        bridgeExecutor.connect(user1).initiateTransfer(amount, targetAddress, targetChain, { value: badFee })
      ).to.be.revertedWithCustomError(bridgeExecutor, "InsufficientFee");
    });

    it("Should revert if amount is 0", async function () {
      const totalFee = (await wormhole.messageFee()) + MIN_FEE;
      await expect(
        bridgeExecutor.connect(user1).initiateTransfer(0, targetAddress, targetChain, { value: totalFee })
      ).to.be.revertedWithCustomError(bridgeExecutor, "InvalidAmount");
    });

    it("Should revert if target address is zero", async function () {
      const totalFee = (await wormhole.messageFee()) + MIN_FEE;
      await expect(
        bridgeExecutor.connect(user1).initiateTransfer(amount, ethers.ZeroHash, targetChain, { value: totalFee })
      ).to.be.revertedWithCustomError(bridgeExecutor, "InvalidAmount");
    });

    it("Should revert if target chain is same as source", async function () {
      const totalFee = (await wormhole.messageFee()) + MIN_FEE;
      await expect(
        bridgeExecutor.connect(user1).initiateTransfer(amount, targetAddress, WORMHOLE_CHAIN_ID_BSC, { value: totalFee })
      ).to.be.revertedWithCustomError(bridgeExecutor, "InvalidAmount");
    });
  });

  describe("Complete Transfer (Bridge In)", function () {
    const amount = ethers.parseUnits("50", 9);
    const sourceChain = WORMHOLE_CHAIN_ID_ETH;
    let sender, recipient, recipientBytes32;

    beforeEach(async function () {
        sender = toWormholeFormat("0x1111111111111111111111111111111111111111"); // arbitrary sender
        recipient = user2.address;
        recipientBytes32 = toWormholeFormat(recipient);
    });

    // Construct the payload as the contract expects:
    // payloadId(1) + sender(32) + recipient(32) + amount(32) + sourceChain(2) + targetChain(2)
    // Note: Contract uses packed encoding for this specific part, but tries abi.decode first.
    // Let's use the manual packed format as described in _decodeTransferPayload comments or implementation.
    // The implementation supports both ABI encoded (>=192 bytes) and packed.
    // Let's test packed first as it matches the assembly block logic closely.
    
    function createPackedPayload(amountVal) {
      const buffer = Buffer.alloc(1 + 32 + 32 + 32 + 2 + 2);
      let offset = 0;
      
      buffer.writeUInt8(PAYLOAD_ID_TRANSFER, offset);
      offset += 1;
      
      Buffer.from(sender.slice(2), 'hex').copy(buffer, offset);
      offset += 32;
      
      Buffer.from(recipientBytes32.slice(2), 'hex').copy(buffer, offset);
      offset += 32;
      
      // Amount is 32 bytes
      const amountHex = ethers.toBeHex(amountVal, 32);
      Buffer.from(amountHex.slice(2), 'hex').copy(buffer, offset);
      offset += 32;
      
      buffer.writeUInt16BE(sourceChain, offset);
      offset += 2;
      
      buffer.writeUInt16BE(WORMHOLE_CHAIN_ID_BSC, offset); // Target is this chain
      offset += 2;
      
      return "0x" + buffer.toString('hex');
    }

    it("Should successfully complete transfer and mint tokens", async function () {
      const payload = createPackedPayload(amount);
      const trustedEmitter = toWormholeFormat(user2.address); // We set user2 as trusted emitter for ETH earlier
      
      const vm = createMockVM(sourceChain, trustedEmitter, payload);
      const encodedVm = encodeMockVM(vm);

      const balanceBefore = await surge.balanceOf(recipient);

      const tx = await bridgeExecutor.completeTransfer(encodedVm);

      await expect(tx)
        .to.emit(bridgeExecutor, "TransferCompleted")
        .withArgs(trustedEmitter, sourceChain, recipient, amount, vm.hash);

      const balanceAfter = await surge.balanceOf(recipient);
      expect(balanceAfter - balanceBefore).to.equal(amount);
    });

    it("Should revert if emitter is unknown", async function () {
      const payload = createPackedPayload(amount);
      const unknownEmitter = toWormholeFormat(user1.address); // user1 is not trusted for ETH
      
      const vm = createMockVM(sourceChain, unknownEmitter, payload);
      const encodedVm = encodeMockVM(vm);

      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "UnknownEmitter")
        .withArgs(sourceChain, unknownEmitter);
    });

    it("Should revert if message already consumed", async function () {
      const payload = createPackedPayload(amount);
      const trustedEmitter = toWormholeFormat(user2.address);
      
      const vm = createMockVM(sourceChain, trustedEmitter, payload);
      const encodedVm = encodeMockVM(vm);

      // First time success
      await bridgeExecutor.completeTransfer(encodedVm);

      // Second time fail
      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "MessageAlreadyConsumed")
        .withArgs(vm.hash);
    });

    it("Should revert if payload has wrong target chain", async function () {
       // Construct payload with wrong target chain
      const buffer = Buffer.alloc(101);
      // ... fill mostly correct ...
      // Just manually build a bad one
      const badPayload = createPackedPayload(amount);
      // Modify last 2 bytes (targetChain) to be something else (e.g. 99)
      const badPayloadBuffer = Buffer.from(badPayload.slice(2), 'hex');
      badPayloadBuffer.writeUInt16BE(99, 99); // Offset 99 is target chain
      
      const vm = createMockVM(sourceChain, toWormholeFormat(user2.address), "0x" + badPayloadBuffer.toString('hex'));
      const encodedVm = encodeMockVM(vm);

      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidPayload");
    });

    it("Should revert if payload length is too short", async function () {
      const shortPayload = "0x01"; // Too short
      const vm = createMockVM(sourceChain, toWormholeFormat(user2.address), shortPayload);
      const encodedVm = encodeMockVM(vm);

      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidPayload");
    });

    it("Should revert if payload ID is invalid", async function () {
      const payload = createPackedPayload(amount);
      const buffer = Buffer.from(payload.slice(2), 'hex');
      buffer.writeUInt8(99, 0); // Invalid payloadId at index 0

      const vm = createMockVM(sourceChain, toWormholeFormat(user2.address), "0x" + buffer.toString('hex'));
      const encodedVm = encodeMockVM(vm);

      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidPayload");
    });

    it("Should revert if source chain does not match emitter chain", async function () {
      const payload = createPackedPayload(amount);
      // Payload has sourceChain = sourceChain (ETH)
      
      const wrongChain = sourceChain + 1;
      // We need to trust the emitter on the wrongChain too, otherwise we get UnknownEmitter.
      await bridgeExecutor.setTrustedEmitter(wrongChain, toWormholeFormat(user2.address));

      const vm = createMockVM(wrongChain, toWormholeFormat(user2.address), payload);
      
      const encodedVm = encodeMockVM(vm);

      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidPayload");
    });

    it("Should accept payload longer than 101 bytes (extra bytes ignored)", async function () {
      const payload = createPackedPayload(amount);
      // Append extra bytes
      const longPayload = payload + "ffffffff"; // + 4 bytes
      
      const vm = createMockVM(sourceChain, toWormholeFormat(user2.address), longPayload);
      const encodedVm = encodeMockVM(vm);

      const balanceBefore = await surge.balanceOf(recipient);
      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.emit(bridgeExecutor, "TransferCompleted");
        
      const balanceAfter = await surge.balanceOf(recipient);
      expect(balanceAfter - balanceBefore).to.equal(amount);
    });

    it("Should revert if recipient address is invalid (dirty high bytes)", async function () {
      // Create payload with invalid recipient (high bits set)
      const payload = createPackedPayload(amount);
      const buffer = Buffer.from(payload.slice(2), 'hex');
      
      // Recipient is at offset 1 + 32 = 33
      // Set the first byte of recipient (high byte) to non-zero
      buffer.writeUInt8(0xff, 33); 
      
      const vm = createMockVM(sourceChain, toWormholeFormat(user2.address), "0x" + buffer.toString('hex'));
      const encodedVm = encodeMockVM(vm);

      await expect(bridgeExecutor.completeTransfer(encodedVm))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");
    });
  });

  describe("Edge Cases & Coverage", function () {
    it("Should revert deployment with invalid arguments", async function () {
      const SurgeBridgeExecutorFactory = await ethers.getContractFactory("SurgeBridgeExecutor");
      
      // surgeToken = address(0)
      await expect(SurgeBridgeExecutorFactory.deploy(
        ethers.ZeroAddress,
        await wormhole.getAddress(),
        WORMHOLE_CHAIN_ID_BSC,
        CONSISTENCY_LEVEL,
        owner.address,
        feeRecipient.address,
        MIN_FEE
      )).to.be.revertedWithCustomError({ interface: bridgeExecutor.interface }, "InvalidAddress");

      // wormholeCore = address(0)
      await expect(SurgeBridgeExecutorFactory.deploy(
        await surge.getAddress(),
        ethers.ZeroAddress,
        WORMHOLE_CHAIN_ID_BSC,
        CONSISTENCY_LEVEL,
        owner.address,
        feeRecipient.address,
        MIN_FEE
      )).to.be.revertedWithCustomError({ interface: bridgeExecutor.interface }, "InvalidAddress");

      // feeRecipient = address(0)
      await expect(SurgeBridgeExecutorFactory.deploy(
        await surge.getAddress(),
        await wormhole.getAddress(),
        WORMHOLE_CHAIN_ID_BSC,
        CONSISTENCY_LEVEL,
        owner.address,
        ethers.ZeroAddress,
        MIN_FEE
      )).to.be.revertedWithCustomError({ interface: bridgeExecutor.interface }, "InvalidAddress");
    });

    it("Should revert setTrustedEmitter with invalid arguments", async function () {
      await expect(bridgeExecutor.setTrustedEmitter(0, toWormholeFormat(user1.address)))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");
        
      await expect(bridgeExecutor.setTrustedEmitter(10, ethers.ZeroHash))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");
    });

    it("Should revert updateFeeConfig with invalid recipient", async function () {
      await expect(bridgeExecutor.updateFeeConfig(ethers.ZeroAddress, 100))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");
    });

    it("Should revert rescueNative with invalid address", async function () {
      await expect(bridgeExecutor.rescueNative(ethers.ZeroAddress, 100))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");
    });

    it("Should revert rescueERC20 with invalid arguments", async function () {
      await expect(bridgeExecutor.rescueERC20(ethers.ZeroAddress, owner.address, 100))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");

      await expect(bridgeExecutor.rescueERC20(await surge.getAddress(), ethers.ZeroAddress, 100))
        .to.be.revertedWithCustomError(bridgeExecutor, "InvalidAddress");
    });
    
    it("Should fail if fee transfer fails (Recipient rejects ETH)", async function () {
        // Deploy a contract that rejects ETH receive
        const RejectorFactory = await ethers.getContractFactory("MockWormhole"); // MockWormhole doesn't have receive(), so it rejects
        const rejector = await RejectorFactory.deploy();
        
        // Update fee recipient to rejector
        await bridgeExecutor.updateFeeConfig(await rejector.getAddress(), MIN_FEE);
        
        const amount = ethers.parseUnits("10", 9);
        await surge.connect(user1).approve(await bridgeExecutor.getAddress(), amount);
        const totalFee = (await wormhole.messageFee()) + MIN_FEE;

        await expect(
            bridgeExecutor.connect(user1).initiateTransfer(amount, ethers.zeroPadValue("0x1234", 32), WORMHOLE_CHAIN_ID_ETH, { value: totalFee })
        ).to.be.revertedWith("fee transfer failed");
        
        // Restore fee recipient
        await bridgeExecutor.updateFeeConfig(feeRecipient.address, MIN_FEE);
    });

    it("Should execute transfer without fee if minFee is 0", async function () {
        // Set minFee to 0
        await bridgeExecutor.updateFeeConfig(feeRecipient.address, 0);
        
        const amount = ethers.parseUnits("10", 9);
        await surge.connect(user1).approve(await bridgeExecutor.getAddress(), amount);
        const wormholeFee = await wormhole.messageFee();
        
        // Fee recipient balance shouldn't change (except for gas if it was the sender, but here checking recipient)
        const feeRecipientBalanceBefore = await ethers.provider.getBalance(feeRecipient.address);
        
        await expect(
            bridgeExecutor.connect(user1).initiateTransfer(amount, ethers.zeroPadValue("0x1234", 32), WORMHOLE_CHAIN_ID_ETH, { value: wormholeFee })
        ).to.emit(bridgeExecutor, "TransferInitiated");
        
        const feeRecipientBalanceAfter = await ethers.provider.getBalance(feeRecipient.address);
        expect(feeRecipientBalanceAfter).to.equal(feeRecipientBalanceBefore);
        
        // Reset minFee
        await bridgeExecutor.updateFeeConfig(feeRecipient.address, MIN_FEE);
    });
  });
  
  describe("Admin Rescue", function () {
      it("Should allow owner to rescue native tokens", async function () {
         // Send some ETH to contract (forcefully or if it had a receive function without revert, but it reverts)
         // Wait, contract reverts receive(). But we can selfdestruct into it or pre-fund address (hard in test).
         // Actually, let's just assume we can mock getting money there?
         // Since `receive` reverts, normal transfers fail.
         // However, we can use `setBalance` from hardhat network helpers if needed, or just skip if logic is simple.
         // Let's use hardhat_setBalance to simulate stuck funds.
         
         const amount = ethers.parseEther("1");
         await ethers.provider.send("hardhat_setBalance", [
            await bridgeExecutor.getAddress(),
            "0x" + amount.toString(16) // hex string
         ]);
         
         const balanceBefore = await ethers.provider.getBalance(owner.address);
         await bridgeExecutor.rescueNative(owner.address, amount);
         const balanceAfter = await ethers.provider.getBalance(owner.address);
         
         expect(balanceAfter).to.be.gt(balanceBefore);
      });
      
      it("Should allow owner to rescue ERC20 tokens", async function () {
          // Send some Surge to bridge contract (accidental transfer)
          const amount = ethers.parseUnits("100", 9);
          await surge.connect(user1).transfer(await bridgeExecutor.getAddress(), amount);
          
          const balanceBefore = await surge.balanceOf(owner.address);
          await bridgeExecutor.rescueERC20(await surge.getAddress(), owner.address, amount);
          const balanceAfter = await surge.balanceOf(owner.address);
          
          expect(balanceAfter - balanceBefore).to.equal(amount);
      });
  });

});


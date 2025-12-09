const hre = require("hardhat");

async function main() {
    // ========== 配置区域：请在这里修改要添加的 emitter 地址 ==========
    
    // Executor 合约地址（如果部署在不同网络，请修改此地址）
    const EXECUTOR_ADDRESS = "0x026dEb8552D64992B3dc9ac8A67D87fb17c980b8";
    
    // 要添加的 emitter 配置
    // 格式：{ chainId: Wormhole链ID, emitter: "0x..." 地址（20字节或32字节格式都可以）}
    const EMITTERS_TO_ADD = [
        {
            chainId: 21,  // 例如：以太坊主网的 Wormhole Chain ID
            emitter: "0x68c708c6403331662b8dce33d0a4b85d60df9d5a126ef19b97699f1e13d741d0"  // 请替换为实际的 emitter 地址
        },
        // 可以添加多个 emitter
        // {
        //     chainId: 4,  // 例如：BSC 的 Wormhole Chain ID
        //     emitter: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
        // }
    ];
    
    // ===================================================================
    
    console.log("开始添加 Trusted Emitter...\n");
    console.log(`Executor 地址: ${EXECUTOR_ADDRESS}`);
    
    // 获取合约实例
    const executor = await hre.ethers.getContractAt("SurgeBridgeExecutor", EXECUTOR_ADDRESS);
    
    // 获取当前签名者（必须是 owner）
    const [signer] = await hre.ethers.getSigners();
    console.log(`当前操作账户: ${signer.address}\n`);
    
    // 检查是否为 owner
    const owner = await executor.owner();
    if (owner.toLowerCase() !== signer.address.toLowerCase()) {
        throw new Error(`错误：当前账户 ${signer.address} 不是合约的 owner (${owner})`);
    }
    
    // 处理每个 emitter
    for (const config of EMITTERS_TO_ADD) {
        const { chainId, emitter: emitterInput } = config;
        
        // 标准化地址格式（支持 20 字节和 32 字节格式）
        let emitterBytes32;
        if (emitterInput.length === 42) {
            // 20 字节地址，转换为 32 字节 Wormhole 格式
            emitterBytes32 = hre.ethers.zeroPadValue(emitterInput, 32);
        } else if (emitterInput.length === 66) {
            // 已经是 32 字节格式
            emitterBytes32 = emitterInput;
        } else {
            throw new Error(`无效的地址格式: ${emitterInput} (应为 20 字节或 32 字节)`);
        }
        
        // 检查当前配置
        const currentEmitter = await executor.trustedEmitters(chainId);
        console.log(`\n链 ID ${chainId}:`);
        console.log(`  当前 emitter: ${currentEmitter}`);
        console.log(`  新 emitter:   ${emitterBytes32}`);
        
        // 如果已经配置相同，跳过
        if (currentEmitter.toLowerCase() === emitterBytes32.toLowerCase()) {
            console.log(`  ✓ 已配置相同地址，跳过`);
            continue;
        }
        
        // 发送交易
        console.log(`  正在设置...`);
        const tx = await executor.setTrustedEmitter(chainId, emitterBytes32);
        console.log(`  交易已发送: ${tx.hash}`);
        
        // 等待确认
        const receipt = await tx.wait();
        console.log(`  ✓ 交易已确认 (区块: ${receipt.blockNumber})`);
        
        // 验证设置
        const updatedEmitter = await executor.trustedEmitters(chainId);
        if (updatedEmitter.toLowerCase() === emitterBytes32.toLowerCase()) {
            console.log(`  ✓ 验证成功：emitter 已更新`);
        } else {
            console.error(`  ✗ 验证失败：emitter 未正确设置`);
        }
    }
    
    console.log("\n所有 emitter 配置完成！");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


const hre = require("hardhat");

async function main() {
    // 1. 获取 Executor 合约实例
    const executorAddress = process.env.EXECUTOR_ADDRESS || "0xaf371B28D404c681a7DCF0b843999E084963befE";
    console.log(`Executor Address: ${executorAddress}`);
    
    const executor = await hre.ethers.getContractAt("SurgeBridgeExecutor", executorAddress);

    // 2. 查询 Executor 绑定的 Surge 代币地址
    const surgeTokenAddress = await executor.surge();
    console.log(`Bound Surge Token: ${surgeTokenAddress}`);

    // 3. 获取 Surge 代币合约实例
    const surge = await hre.ethers.getContractAt("Surge", surgeTokenAddress);

    // 4. 检查 Surge 合约中记录的 executor 是否正确
    const recordedExecutor = await surge.surgeBridgeExecutor();
    console.log(`Surge Contract's authorized Executor: ${recordedExecutor}`);

    if (recordedExecutor.toLowerCase() !== executorAddress.toLowerCase()) {
        console.error("\n[CRITICAL ERROR] 权限配置错误！");
        console.error(`Surge 代币合约只允许地址 ${recordedExecutor} 进行铸币。`);
        console.error(`但当前的 Executor 地址是 ${executorAddress}`);
        console.error("请调用 Surge 合约的 setSurgeBridgeExecutor() 方法进行授权。");
    } else {
        console.log("\n[OK] 权限配置正确。Executor 有权进行铸币。");
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});


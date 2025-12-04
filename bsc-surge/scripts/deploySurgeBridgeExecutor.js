const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

function requireEnv(variable, name) {
    if (!variable || variable.trim() === "") {
        throw new Error(`请设置环境变量 ${name}`);
    }
    return variable;
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const networkName = hre.network.name || "unknown";
    const deploymentRoot = path.join(__dirname, "..", "deployments");
    const networkDeploymentDir = path.join(deploymentRoot, networkName);

    const ensureDeploymentDir = () => {
        if (!fs.existsSync(networkDeploymentDir)) {
            fs.mkdirSync(networkDeploymentDir, { recursive: true });
        }
    };

    const readDeployment = (contractName) => {
        const filePath = path.join(networkDeploymentDir, `${contractName}.json`);
        if (!fs.existsSync(filePath)) {
            return null;
        }
        try {
            return JSON.parse(fs.readFileSync(filePath, "utf8"));
        } catch (err) {
            console.warn(`读取部署文件失败 ${filePath}:`, err);
            return null;
        }
    };

    const writeDeployment = (contractName, payload) => {
        ensureDeploymentDir();
        const filePath = path.join(networkDeploymentDir, `${contractName}.json`);
        fs.writeFileSync(filePath, JSON.stringify(payload, null, 2));
        console.log(`已写入 ${contractName} 部署信息 -> ${filePath}`);
    };

    const existingExecutor = readDeployment("SurgeBridgeExecutor");
    if (existingExecutor) {
        console.log(
            `检测到该网络已部署 SurgeBridgeExecutor (${existingExecutor.address})，如需重新部署请先删除 deployments/${networkName}/SurgeBridgeExecutor.json`
        );
        return;
    }

    const {
        SURGE_TOKEN,
        CONSISTENCY_LEVEL = "201",
        INITIAL_OWNER,
        FEE_RECIPIENT,
        MIN_FEE = "0" // 默认 0
    } = process.env;

    const resolveWormholeCore = () => {
        const candidateEnvKeys = [
            "WORMHOLE_CORE",
            `WORMHOLE_CORE_${networkName.toUpperCase()}`,
            networkName === "bsc" ? "WORMHOLE_CORE_BSC_MAINNET" : undefined,
            networkName === "bscTestnet" ? "WORMHOLE_CORE_BSC_TESTNET" : undefined,
            networkName === "sepolia" ? "WORMHOLE_CORE_SEPOLIA" : undefined
        ].filter(Boolean);

        for (const key of candidateEnvKeys) {
            if (process.env[key] && process.env[key].trim() !== "") {
                console.log(`使用环境变量 ${key} 提供的 Wormhole Core 地址`);
                return process.env[key];
            }
        }

        return undefined;
    };

    const resolveWormholeChainId = () => {
        const candidateEnvKeys = [
            "WORMHOLE_CHAIN_ID",
            `WORMHOLE_CHAIN_ID_${networkName.toUpperCase()}`,
            networkName === "bsc" ? "WORMHOLE_CHAIN_ID_BSC_MAINNET" : undefined,
            networkName === "bscTestnet" ? "WORMHOLE_CHAIN_ID_BSC_TESTNET" : undefined,
            networkName === "sepolia" ? "WORMHOLE_CHAIN_ID_SEPOLIA" : undefined
        ].filter(Boolean);

        for (const key of candidateEnvKeys) {
            if (process.env[key] && process.env[key].trim() !== "") {
                console.log(`使用环境变量 ${key} 提供 Wormhole Chain ID`);
                return process.env[key];
            }
        }

        return undefined;
    };

    const wormholeCore = requireEnv(
        resolveWormholeCore(),
        `Wormhole Core (${networkName})，请设置 WORMHOLE_CORE 或网络专用环境变量`
    );
    const wormholeChainId = Number(
        requireEnv(
            resolveWormholeChainId(),
            `Wormhole Chain ID (${networkName})，请设置 WORMHOLE_CHAIN_ID 或网络专用环境变量`
        )
    );
    const consistencyLevel = Number(CONSISTENCY_LEVEL);
    const initialOwner = INITIAL_OWNER || deployer.address;
    const feeRecipient = FEE_RECIPIENT || initialOwner;
    const minFee = BigInt(MIN_FEE);

    let surgeTokenAddress = SURGE_TOKEN;
    let surgeTokenContract;
    const existingSurgeDeployment = readDeployment("Surge");

    if (!surgeTokenAddress) {
        if (existingSurgeDeployment) {
            console.log(`检测到现有 Surge 部署记录，复用地址 ${existingSurgeDeployment.address}`);
            surgeTokenAddress = existingSurgeDeployment.address;
        } else {
            console.log("未提供 SURGE_TOKEN，开始部署新的 Surge 代币...");
            const Surge = await hre.ethers.getContractFactory("Surge");
            surgeTokenContract = await Surge.deploy(initialOwner);
            const surgeDeployTx = await surgeTokenContract.deploymentTransaction();
            const surgeReceipt = await surgeDeployTx.wait();
            await surgeTokenContract.waitForDeployment();
            surgeTokenAddress = surgeTokenContract.target;
            console.log(`Surge 代币部署成功，地址：${surgeTokenAddress}`);
            writeDeployment("Surge", {
                address: surgeTokenAddress,
                network: networkName,
                chainId: hre.network.config.chainId,
                deployer: deployer.address,
                txHash: surgeReceipt.hash,
                blockNumber: surgeReceipt.blockNumber,
                timestamp: Date.now()
            });
        }
    } else if (existingSurgeDeployment && existingSurgeDeployment.address !== surgeTokenAddress) {
        console.warn(
            `警告：环境变量 SURGE_TOKEN (${surgeTokenAddress}) 与部署记录 (${existingSurgeDeployment.address}) 不一致，请确认。`
        );
    }

    console.log("开始部署 SurgeBridgeExecutor...");
    console.table({
        deployer: deployer.address,
        surgeToken: surgeTokenAddress,
        wormholeCore,
        wormholeChainId,
        consistencyLevel,
        initialOwner,
        feeRecipient,
        minFee: minFee.toString()
    });

    const executor = await hre.ethers.deployContract("SurgeBridgeExecutor", [
        surgeTokenAddress,
        wormholeCore,
        wormholeChainId,
        consistencyLevel,
        initialOwner,
        feeRecipient,
        minFee
    ]);

    const executorDeployTx = await executor.deploymentTransaction();
    const executorReceipt = await executorDeployTx.wait();
    await executor.waitForDeployment();

    console.log(`SurgeBridgeExecutor 部署成功，地址：${executor.target}`);

    writeDeployment("SurgeBridgeExecutor", {
        address: executor.target,
        network: networkName,
        chainId: hre.network.config.chainId,
        deployer: deployer.address,
        txHash: executorReceipt.hash,
        blockNumber: executorReceipt.blockNumber,
        timestamp: Date.now(),
        surgeToken: surgeTokenAddress,
        wormholeCore,
        wormholeChainId,
        consistencyLevel,
        feeRecipient,
        minFee: minFee.toString()
    });

    if (surgeTokenContract) {
        console.log("更新新部署 Surge 代币的桥接执行器地址...");
        const tx = await surgeTokenContract.setSurgeBridgeExecutor(executor.target);
        await tx.wait();
        console.log("Surge 代币已指向新的执行器。");
    } else {
        console.log("请确保已有的 Surge 代币将执行器设置为：", executor.target);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});


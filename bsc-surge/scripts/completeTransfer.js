const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const EXECUTOR_ADDRESS =
    process.env.EXECUTOR_ADDRESS || "0x7F2f076ecE54ddcAf79C95AB780587f8C209Bd3E";
const RAW_VAA =
    process.env.ENCODED_VAA
    || "AQAAAAABAJf8ccaCXUuzW+X2qmzi/rj6dShm73QClajZuOIy9vK0KXXPTJcosvIU8ryH/QQrMOUz1hqRz0opH6VxvuIQe2kBaR7pxAAAAAAAFRJM/ok/l87dEz+PBaSZzkZ6iDB2rIxm5SHo5lrKPXQeAAAAAAAAAAAAAQarKsb3ocC3R/GewA7m4FG4n0YYakAr+NtShlCC/DV3AAAAAAAAAAAAAAAA12fX4MaASbXDwIaVKc4e6znQxgkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADo1KUQAAAVAAQ=";
const TRUSTED_NETWORK = process.env.TRUSTED_NETWORK || "bscTestnet";
const TRUSTED_CHAIN_ID = process.env.TRUSTED_CHAIN_ID || 21;
const TRUSTED_EMITTER = process.env.TRUSTED_EMITTER || "0x124cfe893f97cedd133f8f05a499ce467a883076ac8c66e521e8e65aca3d741e";
const EXECUTOR_EVENTS = [
    "event TransferInitiated(address indexed sender,uint256 amountAfterFee,uint16 indexed targetChain,bytes32 indexed targetAddress,uint64 sequence,uint256 feeTaken)",
    "event TransferCompleted(bytes32 indexed emitterAddress,uint16 indexed emitterChainId,address indexed recipient,uint256 amount,bytes32 vaaHash)",
    "event TrustedEmitterUpdated(uint16 indexed chainId, bytes32 emitter)"
];

function normalizeVaa(input) {
    if (!input) {
        throw new Error("请提供 ENCODED_VAA");
    }
    if (input.startsWith("0x")) {
        return input;
    }
    // 默认按 Base64 解析
    return `0x${Buffer.from(input, "base64").toString("hex")}`;
}

function readDeployment(networkName, contractName) {
    const deploymentPath = path.join(__dirname, "..", "deployments", networkName, `${contractName}.json`);
    if (!fs.existsSync(deploymentPath)) {
        return undefined;
    }
    return JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
}

function normalizeEmitterAddress(address) {
    if (!address) {
        return undefined;
    }
    if (address.length === 66) {
        return address.toLowerCase();
    }
    if (address.length === 42) {
        return hre.ethers.zeroPadValue(address, 32).toLowerCase();
    }
    throw new Error("TRUSTED_EMITTER 需为 20 字节地址或 32 字节 Wormhole 地址");
}

async function resolveTrustedEmitterParams() {
    const normalizedEmitter = normalizeEmitterAddress(TRUSTED_EMITTER);
    if (TRUSTED_CHAIN_ID && normalizedEmitter) {
        return { chainId: TRUSTED_CHAIN_ID, emitter: normalizedEmitter };
    }

    const deployment = readDeployment(TRUSTED_NETWORK, "SurgeBridgeExecutor");
    if (!deployment) {
        console.warn(
            `未找到 ${TRUSTED_NETWORK} 的 SurgeBridgeExecutor 部署文件，跳过 trustedEmitters 设置。`
        );
        return undefined;
    }

    if (!deployment.wormholeChainId || !deployment.address) {
        console.warn(
            `部署文件 ${TRUSTED_NETWORK}/SurgeBridgeExecutor.json 缺少 wormholeChainId 或 address 字段。`
        );
        return undefined;
    }

    return {
        chainId: Number(deployment.wormholeChainId),
        emitter: hre.ethers.zeroPadValue(deployment.address, 32).toLowerCase()
    };
}

async function ensureTrustedEmitter(executor) {
    const params = await resolveTrustedEmitterParams();
    if (!params) {
        return;
    }

    const current = (await executor.trustedEmitters(params.chainId)).toLowerCase();
    if (current === params.emitter) {
        console.log(
            `链 ${params.chainId} 的 trusted emitter 已配置为 ${params.emitter}，跳过设置。`
        );
        return;
    }

    console.log(`设置 trusted emitter: chain=${params.chainId}, emitter=${params.emitter}`);
    const tx = await executor.setTrustedEmitter(params.chainId, params.emitter);
    await tx.wait();
    console.log("trusted emitter 已更新。", tx.hash);
}

async function main() {
    if (!hre.ethers.isAddress(EXECUTOR_ADDRESS)) {
        throw new Error("请设置有效的 EXECUTOR_ADDRESS");
    }

    const encodedVm = normalizeVaa(RAW_VAA);

    const [signer] = await hre.ethers.getSigners();
    const executor = await hre.ethers.getContractAt("SurgeBridgeExecutor", EXECUTOR_ADDRESS, signer);

    await ensureTrustedEmitter(executor);

    console.log("即将执行 completeTransfer:", {
        executor: EXECUTOR_ADDRESS,
        vaaLength: (encodedVm.length - 2) / 2
    });

    try {
        // 先使用 staticCall 模拟交易执行
        // 强制指定 gasLimit 以排除 gas 不足的干扰
        await executor.completeTransfer.staticCall(encodedVm, { gasLimit: 3000000 });
    } catch (e) {
        console.error("模拟执行失败，原因可能是：");
        if (e.data && e.data !== "0x") {
             // 尝试解码自定义错误
             const iface = executor.interface;
             try {
                 const parsedError = iface.parseError(e.data);
                 console.error(`合约错误: ${parsedError.name} (${parsedError.args})`);
             } catch {
                 console.error(`无法解析的错误数据: ${e.data}`);
             }
        } else if (e.data === "0x") {
            console.error("错误数据为 0x。这通常意味着 Wormhole Core 校验 VAA 签名失败（因为使用了无效的测试 VAA），或者调用了不存在的合约。");
        } else if (e.reason) {
            console.error(`Revert Reason: ${e.reason}`);
        } else {
            console.error(e);
        }
        // 如果模拟失败，通常就不发送交易了
        throw new Error("Simulation failed");
    }

    // 发送交易时也强制指定 gasLimit
    const tx = await executor.completeTransfer(encodedVm, { gasLimit: 3000000 });
    const receipt = await tx.wait();

    console.log("完成跨链领取，交易哈希:", receipt.hash);

    const iface = new hre.ethers.Interface(EXECUTOR_EVENTS);
    const executorAddrLower = EXECUTOR_ADDRESS.toLowerCase();
    console.log("相关事件日志:");
    let matched = false;
    for (const log of receipt.logs) {
        if (log.address.toLowerCase() !== executorAddrLower) {
            continue;
        }
        try {
            const parsed = iface.parseLog(log);
            matched = true;
            const args = Object.fromEntries(
                Object.entries(parsed.args)
                    .filter(([key]) => Number.isNaN(Number(key)))
                    .map(([key, value]) => [key, typeof value === "bigint" ? value.toString() : value])
            );
            console.log(JSON.stringify({ name: parsed.name, args }, null, 2));
        } catch {
            // 非目标事件
        }
    }
    if (!matched) {
        console.log("未在该交易中解析到 SurgeBridgeExecutor 事件。");
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});


const hre = require("hardhat");

const TX_HASH = process.env.TX_HASH;
const EXECUTOR_ADDRESS = process.env.EXECUTOR_ADDRESS?.toLowerCase();

const EXECUTOR_EVENTS = [
    "event TransferInitiated(address indexed sender,uint256 amountAfterFee,uint16 indexed targetChain,bytes32 indexed targetAddress,uint64 sequence,uint256 feeTaken)",
    "event TransferCompleted(bytes32 indexed emitterAddress,uint16 indexed emitterChainId,address indexed recipient,uint256 amount,bytes32 vaaHash)"
];

async function main() {
    if (!TX_HASH) {
        throw new Error("请通过环境变量 TX_HASH 提供交易哈希");
    }

    const provider = hre.ethers.provider;
    const receipt = await provider.getTransactionReceipt(TX_HASH);
    if (!receipt) {
        throw new Error(`未在当前网络找到交易 ${TX_HASH}`);
    }

    console.log("交易基本信息:", {
        hash: receipt.transactionHash,
        status: receipt.status,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed?.toString()
    });

    const iface = new hre.ethers.Interface(EXECUTOR_EVENTS);
    const parsedLogs = [];

    for (const log of receipt.logs) {
        if (EXECUTOR_ADDRESS && log.address.toLowerCase() !== EXECUTOR_ADDRESS) {
            continue;
        }

        try {
            const parsed = iface.parseLog(log);
            parsedLogs.push({
                address: log.address,
                name: parsed.name,
                args: Object.fromEntries(
                    Object.entries(parsed.args)
                        .filter(([key]) => isNaN(Number(key)))
                        .map(([key, value]) => {
                            if (typeof value === "bigint") {
                                return [key, value.toString()];
                            }
                            return [key, value];
                        })
                )
            });
        } catch {
            // 非目标事件，忽略
        }
    }

    if (parsedLogs.length === 0) {
        console.log("未在该交易中解析到 SurgeBridgeExecutor 相关事件。");
    } else {
        console.log("解析到的事件:");
        for (const log of parsedLogs) {
            console.log(JSON.stringify(log, null, 2));
        }
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});



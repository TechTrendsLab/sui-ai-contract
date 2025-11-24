const hre = require("hardhat");

/**
 * 根据需要填写以下常量，或通过环境变量覆盖。
 */
const EXECUTOR_ADDRESS = process.env.EXECUTOR_ADDRESS || "0x06Bd9071777A3695868f30a17757711d43f1298E";
const RAW_AMOUNT = process.env.TRANSFER_AMOUNT || "250"; // 以代币人类可读数表示
const TOKEN_DECIMALS = Number(process.env.TOKEN_DECIMALS || 9);
const TARGET_CHAIN_ID = Number(process.env.TARGET_CHAIN_ID || 21); // Wormhole chainId
const TARGET_ADDRESS_HEX = process.env.TARGET_WORMHOLE_ADDRESS || "0x3858bb7c48e1b72153ec8663138740fa36258cd5c1ac75d2d74e7fe6b3ef3f3a";
const EMITTER_OVERRIDE = process.env.WORMHOLE_EMITTER;
const SOURCE_CHAIN_ID_OVERRIDE = process.env.SOURCE_WORMHOLE_CHAIN_ID || 4;

function resolveDefaultApiBase(networkTag) {
    switch (networkTag) {
        case "testnet" || "sepolia":
            return "https://api.testnet.wormholescan.io";
        case "devnet":
            return "https://api.devnet.wormholescan.io";
        default:
            return "https://api.wormholescan.io";
    }
}

async function resolveFetch() {
    if (typeof fetch !== "undefined") {
        return fetch;
    }
    try {
        const { default: nodeFetch } = await import("node-fetch");
        return nodeFetch;
    } catch (err) {
        throw new Error("当前 Node.js 版本无内置 fetch，请安装依赖 `npm install node-fetch` 后重试");
    }
}

function toBytes32Address(address) {
    return hre.ethers.zeroPadValue(address, 32);
}

async function main() {
    if (!hre.ethers.isAddress(EXECUTOR_ADDRESS)) {
        throw new Error("请设置有效的 EXECUTOR_ADDRESS");
    }
    let targetAddressBytes32;
    if (!TARGET_ADDRESS_HEX) {
        throw new Error("请设置 TARGET_WORMHOLE_ADDRESS");
    } else if (TARGET_ADDRESS_HEX.length === 42) {
        if (!hre.ethers.isAddress(TARGET_ADDRESS_HEX)) {
            throw new Error("TARGET_WORMHOLE_ADDRESS 不是有效的 EVM 地址");
        }
        targetAddressBytes32 = hre.ethers.zeroPadValue(TARGET_ADDRESS_HEX, 32);
        console.log("检测到 20 字节地址，已自动转换为 Wormhole 32 字节格式:", targetAddressBytes32);
    } else if (TARGET_ADDRESS_HEX.length === 66) {
        targetAddressBytes32 = TARGET_ADDRESS_HEX;
    } else {
        throw new Error("TARGET_WORMHOLE_ADDRESS 需为 20 字节 EVM 地址或 32 字节 Wormhole 地址");
    }

    const [signer] = await hre.ethers.getSigners();
    const executor = await hre.ethers.getContractAt("SurgeBridgeExecutor", EXECUTOR_ADDRESS, signer);

    const amount = hre.ethers.parseUnits(RAW_AMOUNT, TOKEN_DECIMALS);

    // 查询 Surge 代币并确保已授权
    const surgeTokenAddress = await executor.surge();
    const surge = new hre.ethers.Contract(
        surgeTokenAddress,
        [
            "function allowance(address owner, address spender) external view returns (uint256)",
            "function approve(address spender, uint256 amount) external returns (bool)"
        ],
        signer
    );
    const currentAllowance = await surge.allowance(signer.address, EXECUTOR_ADDRESS);
    if (currentAllowance < amount) {
        console.log(
            `当前对执行器的授权不足 (${currentAllowance.toString()}), 发送 approve 以授权 ${amount.toString()}`
        );
        const approveTx = await surge.approve(EXECUTOR_ADDRESS, amount);
        await approveTx.wait();
        console.log(`已完成授权交易: ${approveTx.hash}`);
    } else {
        console.log("检测到现有授权充足，跳过 approve");
    }

    // 查询 Wormhole message fee
    const wormholeAddress = await executor.wormhole();
    const wormhole = new hre.ethers.Contract(
        wormholeAddress,
        ["function messageFee() external view returns (uint256)"],
        signer
    );
    const messageFee = await wormhole.messageFee();
    const minFee = await executor.minFee();
    const totalRequiredValue = messageFee + minFee;

    const sourceWormholeChainId = SOURCE_CHAIN_ID_OVERRIDE
        ? Number(SOURCE_CHAIN_ID_OVERRIDE)
        : Number(await executor.wormholeChainId());

    console.log("即将发起跨链：", {
        executor: EXECUTOR_ADDRESS,
        sender: signer.address,
        amount: amount.toString(),
        targetChain: TARGET_CHAIN_ID,
        targetAddress: targetAddressBytes32,
        messageFee: messageFee.toString(),
        minFee: minFee.toString(),
        totalRequiredValue: totalRequiredValue.toString()
    });

    const tx = await executor.initiateTransfer(amount, targetAddressBytes32, TARGET_CHAIN_ID, {
        value: totalRequiredValue
    });

    const receipt = await tx.wait();
    console.log("跨链交易已提交:", receipt.hash);

    for (const log of receipt.logs) {
        try {
            const parsed = executor.interface.parseLog(log);
            if (
                parsed.name === "TransferInitiated"
            ) {
                const sequence = parsed.args.sequence.toString();
                console.log("对应 Wormhole sequence:", sequence);
                const networkTag =
                    process.env.WORMHOLE_NETWORK
                    || (hre.network.name.includes("test") ? "testnet" : "mainnet");
                const emitterHex = (EMITTER_OVERRIDE || hre.ethers.zeroPadValue(EXECUTOR_ADDRESS, 32))
                    .replace(/^0x/, "");

                const wormholeChainId = sourceWormholeChainId;
                const baseApi =
                    process.env.WORMHOLE_API_BASE
                    || resolveDefaultApiBase(networkTag);
                const vaaUrl = `${baseApi}/v1/signed_vaa/${wormholeChainId}/${emitterHex}/${sequence}`;
                console.log("可直接请求的 VAA URL:");
                console.log(vaaUrl);

                try {
                    const fetchFn = await resolveFetch();
                    const response = await fetchFn(vaaUrl);
                    if (!response.ok) {
                        throw new Error(`HTTP ${response.status} ${response.statusText}`);
                    }
                    const contentType = response.headers.get("content-type") || "";
                    const body = contentType.includes("application/json")
                        ? await response.json()
                        : await response.text();
                    const formattedBody = typeof body === "string" ? body : JSON.stringify(body, null, 2);
                    console.log("已获取 Wormhole VAA:");
                    console.log(formattedBody);
                } catch (fetchErr) {
                    console.warn(
                        "自动获取 VAA 失败，请使用上方 URL 手动请求。",
                        fetchErr.message || fetchErr
                    );
                }
                break;
            }
        } catch (err) {
            // 跳过非本合约事件
        }
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});


#!/bin/bash

# 确保在运行前已在 .env 文件中配置了 ETHERSCAN_API_KEY (即 BscScan API Key)

# Verify Surge Contract
# Constructor Args: initialOwner
echo "Verifying Surge..."
npx hardhat verify --network bsc 0xaaC01D3753A72c73872EC8D6394B48F542Fe313f "0xEf5f33b5dc37d6DC609cB1b398fb199ED9F355Ce"

# Verify SurgeBridgeExecutor Contract
# Constructor Args: 
# 1. surgeTokenAddress: 0xaaC01D3753A72c73872EC8D6394B48F542Fe313f
# 2. wormholeCore: 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B
# 3. wormholeChainId: 4
# 4. consistencyLevel: 201
# 5. initialOwner: 0xEf5f33b5dc37d6DC609cB1b398fb199ED9F355Ce
# 6. feeRecipient: 0xEf5f33b5dc37d6DC609cB1b398fb199ED9F355Ce
# 7. minFee: 0
echo "Verifying SurgeBridgeExecutor..."
npx hardhat verify --network bsc 0x026dEb8552D64992B3dc9ac8A67D87fb17c980b8 \
  "0xaaC01D3753A72c73872EC8D6394B48F542Fe313f" \
  "0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B" \
  "4" \
  "201" \
  "0xEf5f33b5dc37d6DC609cB1b398fb199ED9F355Ce" \
  "0xEf5f33b5dc37d6DC609cB1b398fb199ED9F355Ce" \
  "0"


const ethers = require('ethers');

const errors = [
    "InvalidAmount()",
    "InvalidAddress()",
    "FeeTooHigh()",
    "MessageAlreadyConsumed(bytes32)",
    "UnknownEmitter(uint16,bytes32)",
    "InvalidPayload()",
    "OnlySurgeBridgeExecutor()",
    "OwnableUnauthorizedAccount(address)",
    "OwnableInvalidOwner(address)"
];

errors.forEach(err => {
    const hash = ethers.id(err).slice(0, 10);
    console.log(`${hash} : ${err}`);
});


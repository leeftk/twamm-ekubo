# Starknet Deployment Scripts

## Account Setup and Deployment
# Create a new account
sncast account create \
    --url https://free-rpc.nethermind.io/sepolia-juno \
    --name some-name

# Deploy the account
sncast account deploy \
    --url https://free-rpc.nethermind.io/sepolia-juno \
    --name some-name \
    --fee-token strk

## Contract Declaration and Deployment
# Declare the L2TWAMMBridge contract
sncast declare \
    --account some-name \
    --url https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/oTytRAZo0rI3b1-9Ki8M0s4tKVF1Tjbt \
    --fee-token strk \
    --contract-name L2TWAMMBridge \
    --package twammbridge

# Deploy the contract using the class hash
sncast deploy \
    --account some-name \
    --url https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/oTytRAZo0rI3b1-9Ki8M0s4tKVF1Tjbt \
    --fee-token strk \
    --class-hash 0x236c715846d86b6f4ba65ff6d4136fc0ddfa5530790661b101fbb3279ab64c5


    # deploy solidity

    forge script script/DeployL1Bridge.sol:DeployL1TWAMMBridge --rpc-url https://sepolia.gateway.tenderly.co --private-key <PRIVATE_KEY> --broadcast

    # deposit and create order

    forge script script/DepositAndCreateOrder.sol:DepositAndCreateOrder --rpc-url https://sepolia.gateway.tenderly.co --private-key <PRIVATE_KEY> --broadcast
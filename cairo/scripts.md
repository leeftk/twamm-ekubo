<!-- # Starknet Deployment Scripts

## Account Setup and Deployment
# Create a new account
sncast account create \
    --url https://free-rpc.nethermind.io/sepolia-juno \
    --name some-name

# Deploy the account
sncast account deploy \
    --url https://free-rpc.nethermind.io/sepolia-juno \
    --name some-namee \
    --fee-token strk

## Contract Declaration and Deployment
# Declare the L2TWAMMBridge contract
sncast --account some-namee declare --contract-name L2TWAMMBridge --url https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/oTytRAZo0rI3b1-9Ki8M0s4tKVF1Tjbt --fee-token strk --package twammbridge

# Deploy the contract using the class hash
sncast deploy \
    --account some-name \
    --url https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/oTytRAZo0rI3b1-9Ki8M0s4tKVF1Tjbt \
    --fee-token strk \
    --class-hash 0x73ef345dcfdc1dfcc71485888b59a361694da2145dad13b656279b41a056ab1


    # deploy solidity

    forge script script/DeployL1Bridge.sol:DeployL1TWAMMBridge --rpc-url https://sepolia.gateway.tenderly.co --private-key <PRIVATE_KEY> --broadcast

    # deposit and create order

    forge script script/DepositAndCreateOrder.sol:DepositAndCreateOrder --rpc-url https://sepolia.gateway.tenderly.co --private-key <PRIVATE_KEY> --broadcast -->

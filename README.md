# Documentation
## Main Contracts

1. L1TWAMMBridge (Solidity):
   - Facilitates bridging tokens from Ethereum (L1) to StarkNet (L2) for TWAMM orders
   - Handles token deposits, withdrawals, and order creation across L1 and L2

2. L2TWAMMBridge (Cairo):
   - Receives messages from L1 and processes deposit and withdrawal operations
   - Manages order-related operations through the OrderManagerComponent
  
## Helper Contracts
1. TokenBridgeHelper (Cairo):
   - Helps to manage the mapping between the L2 token bridges and L1 token addresses

2. OrderManagerComponent
   - Handles the execute_deposit and execute_withdrawal functionality
   - Contains all the necessary helper functions for order creation and withdrawal

## Core Functions

L1TWAMMBridge:

1. depositAndCreateOrder: Deposits tokens and creates an order on L2
2. initiateWithdrawal: Initiates a withdrawal from L2 to L1
3. initiateCancelDepositRequest: Allows users to cancel their deposit requests.
4. initiateDepositReclaim: Allows users to reclaim their cancelled deposits after five days

L2TWAMMBridge:

1. msg_handler_struct: Processes incoming messages from L1
2. handle_deposit: Executes deposit operations
3. handle_withdrawal: Executes withdrawal operations
4. assert_only_owner: Checks if the caller is the contract owner

## Deployment and Script Instructions

### Deploy the L1 Contract

1. Create an env file in foundry containing your RPC URL as `SEPOLIA_RPC_URL` and your private key as `PRIVATE_KEY`
2. Create a file in the scripts folder and call it `DeployL1Bridge.sol` and paste this in it
```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {L1TWAMMBridge} from "../src/L1TWAMMBridge.sol";

contract DeployL1TWAMMBridge is Script {
function run() public returns (L1TWAMMBridge) {
address token = address(0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766);
address starknetBridge = address(0xcE5485Cfb26914C5dcE00B9BAF0580364daFC7a4);
address l2EkuboAddress = address(0x123);
uint256 l2EndpointAddress = uint256(0x073710eda3a2a82f548bf0743c3db7fc4cb1273adfac61a02ba6d4f541894fbd);

        address starknetRegistry = address(0xdc1564B4E0b554b26b2CFd2635B84A0777035d11);

        vm.startBroadcast();

        L1TWAMMBridge bridge =
            new L1TWAMMBridge(token, starknetBridge, l2EkuboAddress, l2EndpointAddress, starknetRegistry);

        vm.stopBroadcast();

        return bridge;
    }

}

```
3. Deploy the L1TWAMMBridge contract using the DeployL1TWAMMBridge script. Copy and Paste this in your terminal
```
forge script --chain sepolia script/DeployL1Bridge.sol:DeployL1TWAMMBridge --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast  -vvvv      
```
### Deploy the L2 Contract

1. Create and set up your starknet account here: https://foundry-rs.github.io/starknet-foundry/starknet/account.html
2. Declare the L2TWAMMBridge contract with by copying and pasting this in your terminal.
```
sncast --account <account_name>  declare   --url <YOUR_RPC_URL>   --fee-token eth   --contract-name L2TWAMMBridge
```
3. Deploy the L2TWAMMBridge contract on StarkNet Passing the address of the creator in the constructor.
```
sncast --account <account_name>  deploy  --url <YOUR_RPC_URL>   --fee-token eth   --class-hash <class_hash> --constructor-calldata <YOUR_ADDRESS>
```
4. Declare the TokenBridgeHelper by copying and pasting this in the terminal
```
sncast --account <account_name>  declare   --url <YOUR_RPC_URL>   --fee-token eth   --contract-name TokenBridgeHelper
```
5. Deploy the TokenBridgeHelper by copying and pasting this in the terminal
```
sncast --account <account_name>  deploy  --url <YOUR_RPC_URL>   --fee-token eth   --class-hash <class_hash> --constructor-calldata <YOUR_ADDRESS>
```
6. Set the TokenBridgeHelper address in the L2TWAMMBridge contract, by calling `set_token_bridge_helper` with the address in starkscan or voyager 

### Interact with the L1 Contract

1. Create a file in the scripts file and call it `DepositAndCreateOrder.sol` and paste this in it.
```
    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import {Script} from "forge-std/Script.sol";
    import "forge-std/console.sol";
    import {OrderParams} from "../src/types/OrderParams.sol";
    import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
    import {IStarknetMessaging} from "../src/interfaces/IStarknetMessaging.sol";

    interface IL1TWAMMBridge {
    function depositAndCreateOrder(OrderParams memory params) external payable;
    function deposit(uint256 amount, uint256 l2EndpointAddress) external payable;
    function initiateWithdrawal(uint256 amount, address l1_token) external payable;
    function _sendMessage(uint256 contractAddress, uint256 selector, uint256[] memory payload) external payable;
    function setL2EndpointAddress(uint256 _l2EndpointAddress) external;
    function initiateCancelDepositRequest(address l1_token, uint256 amount, uint256 nonce) external;
    }

    contract DepositAndCreateOrder is Script {
    function run() public {
    // Configuration
    address strkToken = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; //stark on l1 sepolia
    address usdcBuyToken = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; //usdc on l1 sepolia;
    address bridgeAddress = 0xFD0bd7eb64A790bA81d8e03c8D24b516e38Ae708;
    uint256 l2EndpointAddress = uint256(0x073710eda3a2a82f548bf0743c3db7fc4cb1273adfac61a02ba6d4f541894fbd);
    uint256 sellTokenAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; //stark on l2
    uint256 buyTokenAddress = 0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080; //usdc on l2

        // Order parameters
        uint128 currentTimestamp = uint128(block.timestamp);
        uint128 difference = 16 - (currentTimestamp % 16);  // gets the difference between the current timestamp and the next 16 second interval
        uint128 start = currentTimestamp + difference;
        uint128 end = start + 128;

        uint128 amount = 0.0007 * 10 ** 18;
        uint128 fee = 0.0005 ether;
        uint256 gasPrice = block.basefee * 1;

        vm.startBroadcast();

        // Approve token spending
        IERC20(strkToken).approve(bridgeAddress, type(uint256).max);

        // Create order parameters
        OrderParams memory params = OrderParams({
            sender: msg.sender,
            sellToken: sellTokenAddress,
            buyToken: buyTokenAddress,
            fee: 170141183460469235273462165868118016,
            start: start,
            end: end,
            amount: amount
        });


        // Create order
        IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee, gas: gasPrice}(params);

        // Initiate Withdrawal
        IL1TWAMMBridge(bridgeAddress).initiateWithdrawal{value: fee}(amount, 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);

        // Initiate deposit cancel request
        IL1TWAMMBridge(bridgeAddress).initiateCancelDepositRequest{gas: gasPrice}(0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766, amount, nonce_of_the_deposit_action);

        // Set L2 address, in case a new L2 contract is deployed
        // IL1TWAMMBridge(bridgeAddress).setL2EndpointAddress(l2EndpointAddress);
        vm.stopBroadcast();
    }

}

```

2. To create an order:
   - Approve the required amount of tokens for spending by the L1TWAMMBridge contract.
   - Call the `depositAndCreateOrder` function on the L1TWAMMBridge contract, passing the order parameters and sufficient gas fees.
    
3. To withdraw:
   - Call the `initiateWithdrawal` function on the L1TWAMMBridge contract, specifying the amount and L1 token address.

4. To Update the L2 endpoint address in the L1TWAMMBridge contract (Not necessary except in a situation when a different L2 endpoint from the one in the constructor is to be used).
   - Call the `setL2EndpointAddress` passing in the new L2 Endpoint address

5. To run the script, copy and paste this in your terminal.
```
forge script --chain sepolia script/DepositAndCreateOrder.sol:DepositAndCreateOrder --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY  --broadcast -vvvv
``` 

6. Monitor the L2TWAMMBridge contract for received messages and processed deposits/withdrawals.



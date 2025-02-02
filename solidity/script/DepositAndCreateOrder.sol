// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {OrderParams} from "../src/types/OrderParams.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStarknetMessaging} from "../src/interfaces/IStarknetMessaging.sol";
import {IStarknetTokenBridge} from "../src/interfaces/IStarknetTokenBridge.sol";
import {IL1TWAMMBridge} from "../src/interfaces/IL1TWAMMBridge.sol";


contract DepositAndCreateOrder is Script {
    function run() public {
        // Configuration
        address strkToken = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; //stark on l1 sepolia
        address usdcBuyToken = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; //usdc on l1 sepolia
        IStarknetMessaging snMessaging = IStarknetMessaging(0xE2Bb56ee936fd6433DC0F6e7e3b8365C906AA057);
        address bridgeAddress = 0x57EC6c2CC9Df888aA21b2b27C69d10b7657170E3;
        uint256 l2EndpointAddress = uint256(0x7b8349904d9c71692e79562974356da19063445ec8be1d53fc07cc87ce83ac0);
        uint256 l2FailEndpoint = uint256(0xb3fa26e2af15dda3690ff437257057ad524115b00182928b60d213d50281a6);
        uint256 sellTokenAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; //stark on l2
        uint256 buyTokenAddress = 0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080; //usdc on l2
        //  0x0703911a6196ef674fc635de02763dcd4ccc16d7cf736f68a9483cc44eccaa94;

        // Order parameters
        uint128 currentTimestamp = uint128(block.timestamp);
        uint128 difference = 16 - (currentTimestamp % 16); // gets the difference between the current timestamp and the next 16 second interval
        uint128 start = currentTimestamp + difference;
        uint128 end = start + 128;

        uint128 amount = 0.05 * 10 ** 18;
        uint128 fee = 0.0005 ether;
        // uint256 gasPrice = block.basefee * 1;

        vm.startBroadcast();

        // Approve token spending
        IERC20(strkToken).approve(bridgeAddress, type(uint256).max);

        OrderParams memory params = OrderParams({
            sender: msg.sender,
            sellToken: sellTokenAddress,
            buyToken: buyTokenAddress,
            fee: 170141183460469235273462165868118016,
            start: 1738066320,
            end: 1738066448,
            amount: amount
        });

        // IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee}(
        //     0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766, params
        // );

        IL1TWAMMBridge(bridgeAddress).initiateWithdrawal{value: fee}(params, 561);

        vm.stopBroadcast();
    }
}

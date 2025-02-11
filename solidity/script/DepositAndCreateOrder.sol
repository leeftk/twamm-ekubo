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
        // IStarknetMessaging snMessaging = IStarknetMessaging(0xE2Bb56ee936fd6433DC0F6e7e3b8365C906AA057);
        address bridgeAddress = 0x7da0c9962C68D09D1cA27EA1a4AC708A9b9867b5;
        uint256 l2EndpointAddress = uint256(0x00cb8dd429573229af63bc6d3e2a75ffb1e3f4610ab17da4f9684ad7c447a287);
        // uint256 l2FailEndpoint = uint256(0xb3fa26e2af15dda3690ff437257057ad524115b00182928b60d213d50281a6);
        uint256 sellTokenAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; //stark on l2
        uint256 buyTokenAddress = 0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080; //usdc on l2

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
            start: 1739271664,
            end: 1739271792,
            amount: amount
        });

         uint256[] memory payload = new uint256[](8);
        payload[0] = uint256(uint160(msg.sender));
        payload[1] = params.sellToken;
        payload[2] = params.buyToken;
        payload[3] = uint256(params.fee);
        payload[4] = uint256(params.start);
        payload[5] = uint256(params.end);
        payload[6] = uint256(amount);
        payload[7] = uint256(0);

        // IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee}(
        //     0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766, params
        // );

        // IL1TWAMMBridge(bridgeAddress).initiateWithdrawal{value: fee}(params, 569);

        IL1TWAMMBridge(bridgeAddress).initiateCancelDepositRequest(params, 11981, 1);
        // IStarknetTokenBridge(0xcE5485Cfb26914C5dcE00B9BAF0580364daFC7a4).depositWithMessageCancelRequest(
        //     0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766,
        //     amount,
        //     0x00cb8dd429573229af63bc6d3e2a75ffb1e3f4610ab17da4f9684ad7c447a287,
        //     payload,
        //     11976
        // );

        vm.stopBroadcast();
    }
}

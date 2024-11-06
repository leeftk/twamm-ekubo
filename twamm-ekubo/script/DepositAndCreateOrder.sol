// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {OrderParams} from "../src/types/OrderParams.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IL1TWAMMBridge {
    function depositAndCreateOrder(OrderParams memory params) external payable;
}

contract DepositAndCreateOrder is Script {
    function run() public {
        // Configuration
        address token = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766;

        address bridgeAddress = 0xFC13E72Cf2AA63004CA25Da57D7967440f3eb9d8;
        uint256 l2EndpointAddress = uint256(0x305a4711577b641812c67695b83d2431576be6453c5ac62ecc21ab574a2e358);

        // Order parameters
        uint128 start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
        uint128 end = start + 64;
        uint128 amount = 1 ether;
        uint128 fee = 0.01 ether;

        vm.startBroadcast();

        // Approve token spending
        IERC20(token).approve(bridgeAddress, amount);

        // Create order parameters
        OrderParams memory params = OrderParams({
            sender: msg.sender,
            sellToken: token,
            buyToken: token,
            fee: fee,
            start: start,
            end: end,
            amount: amount,
            l2EndpointAddress: l2EndpointAddress
        });

        // Create order
        IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee}(params);

        vm.stopBroadcast();
    }
}
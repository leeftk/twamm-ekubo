// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {OrderParams} from "../src/types/OrderParams.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IL1TWAMMBridge {
    function depositAndCreateOrder(OrderParams memory params) external payable;
    function deposit(uint256 amount, uint256 l2EndpointAddress) external payable;
}

contract DepositAndCreateOrder is Script {
    function run() public {
        // Configuration
        address token = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766;

        address bridgeAddress = 0x71ae1b856fE1584d09F4C6041C8E47aF15836fAC;
        uint256 l2EndpointAddress = uint256(0x3a4b7e2d060bd8eb48e2db10f16c1303b131c266cc928902c3a3a8ead7e386d);

        // Order parameters
        uint128 start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
        uint128 end = start + 64;
        uint128 amount = .01 ether;
        uint128 fee = 0.01 ether;

        vm.startBroadcast();

        // Approve token spending
        IERC20(token).approve(bridgeAddress, type(uint256).max);

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
        IERC20(token).transfer(bridgeAddress, amount);
        IL1TWAMMBridge(bridgeAddress).deposit{value: fee}(amount, l2EndpointAddress);
        //IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee}(params);

        vm.stopBroadcast();
    }
}
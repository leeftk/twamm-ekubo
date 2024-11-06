// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {OrderParams} from "../src/types/OrderParams.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

interface IL1TWAMMBridge {
    function depositAndCreateOrder(OrderParams memory params) external payable;
    function deposit(uint256 amount, uint256 l2EndpointAddress) external payable;
}

contract DepositAndCreateOrder is Script {
    function run() public {
        // Configuration
        address token = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

        address bridgeAddress = 0x429C016bdeFDD906F665FF42592D6B7381A3a44A;
        uint256 l2EndpointAddress = uint256(0x58879156aed8b0a9c6829a60bcd474b4f1db3ec58aa7aae9ecd5d18dfae08de);

        // Order parameters
        uint128 start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
        uint128 end = start + 64;
        uint128 amount = 0.1 * 10 ** 6;
        uint128 fee = 0.001 ether;

        uint256 gasPrice = block.basefee * 21;  // Or use a higher multiplier if needed

        vm.startBroadcast();

        // Approve token spending
        IERC20(token).approve(bridgeAddress, type(uint256).max);
        console.log("Balance of token: ", IERC20(token).balanceOf(address(msg.sender)));

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
        IL1TWAMMBridge(bridgeAddress).deposit{value: fee, gas: gasPrice}(amount, l2EndpointAddress);
        // IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee, gas: gasPrice}(params);

        vm.stopBroadcast();
    }
}
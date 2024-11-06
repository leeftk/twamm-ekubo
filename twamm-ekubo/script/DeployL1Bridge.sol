// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {L1TWAMMBridge} from "../src/L1TWAMMBridge.sol";

contract DeployL1TWAMMBridge is Script {
    function run() public returns (L1TWAMMBridge) {
     
        address token = address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        address starknetBridge = address(0x86dC0B32a5045FFa48D9a60B7e7Ca32F11faCd7B);
        address l2EkuboAddress = address(0x123);
        uint256 l2EndpointAddress = uint256(0x58879156aed8b0a9c6829a60bcd474b4f1db3ec58aa7aae9ecd5d18dfae08de);

        address starknetRegistry = address(0xdc1564B4E0b554b26b2CFd2635B84A0777035d11);

        vm.startBroadcast();

        L1TWAMMBridge bridge = new L1TWAMMBridge(
            token,
            starknetBridge,
            l2EkuboAddress,
            l2EndpointAddress,
            starknetRegistry
        );

        vm.stopBroadcast();

        return bridge;
    }
} 
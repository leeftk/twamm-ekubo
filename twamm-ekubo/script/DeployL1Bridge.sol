// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {L1TWAMMBridge} from "../src/L1TWAMMBridge.sol";

contract DeployL1TWAMMBridge is Script {
    function run() public returns (L1TWAMMBridge) {
        address token = address(0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766);
        address starknetBridge = address(0xcE5485Cfb26914C5dcE00B9BAF0580364daFC7a4);
        address l2EkuboAddress = address(0x123);
        uint256 l2EndpointAddress = uint256(0x429f7a4bd4de9fc98a94cec9163caf6f50a5d7fcec583fa30d2d9bb33a93663);

        address starknetRegistry = address(0xdc1564B4E0b554b26b2CFd2635B84A0777035d11);

        vm.startBroadcast();

        L1TWAMMBridge bridge =
            new L1TWAMMBridge(token, starknetBridge, l2EkuboAddress, l2EndpointAddress, starknetRegistry);

        vm.stopBroadcast();

        return bridge;
    }
}

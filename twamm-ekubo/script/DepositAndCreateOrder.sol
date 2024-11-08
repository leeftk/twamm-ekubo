// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {OrderParams} from "../src/types/OrderParams.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IL1TWAMMBridge {
    function depositAndCreateOrder(OrderParams memory params) external payable;
    function deposit(uint256 amount, uint256 l2EndpointAddress) external payable;
    function initiateWithdrawal(uint256 tokenId) external payable;
    function _sendMessage(uint256 contractAddress, uint256 selector, uint256[] memory payload) external payable;
}

contract DepositAndCreateOrder is Script {
    function run() public {
        // Configuration
        address strkToken = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; //stark on l1 sepolia
        address usdcSellToken = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; //usdc on l1 sepolia

        address bridgeAddress = 0x4b220A6B4f695db8CEdC121ACFC2484fCaaB8b45;
        uint256 l2EndpointAddress = uint256(0x7721d8633add90ecf6bffe9dcd71b0ce5cc5436923b9d90b56c20d3a53438cb);
        uint256 sellTokenAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; //stark on l2
        uint256 buyTokenAddress = 0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080; //usdc on l2
        // Order parameters
        uint128 start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
        uint128 end = start + 64;
        uint128 amount = 0.001 ether;
        uint128 fee = 0.001 ether;
        uint256 gasPrice = block.basefee * 1000;

        vm.startBroadcast();

        // Approve token spending
        IERC20(strkToken).approve(bridgeAddress, type(uint256).max);

        // Create order parameters
        OrderParams memory params = OrderParams({
            sender: msg.sender,
            sellToken: sellTokenAddress,
            buyToken: buyTokenAddress,
            fee: 0,
            start: start,
            end: end,
            amount: amount,
            l2EndpointAddress: l2EndpointAddress
        });

        // Create order
        // IERC20(strkToken).transfer(bridgeAddress, amount);
        // IL1TWAMMBridge(bridgeAddress).deposit{value: fee, }(amount, l2EndpointAddress);
        // IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee, gas: gasPrice}(params);

        uint256[] memory message = new uint256[](1);
        message[0] = 2;

        uint256 L2_SELECTOR_VALUE = uint256(0x005421de947699472df434466845d68528f221a52fce7ad2934c5dae2e1f1cdc);
        IL1TWAMMBridge(bridgeAddress)._sendMessage{value: amount}(l2EndpointAddress, L2_SELECTOR_VALUE, message);

        vm.stopBroadcast();
    }
}

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
    function initiateWithdrawal(uint256 tokenId) external payable;
    function _sendMessage(uint256 contractAddress, uint256 selector, uint256[] memory payload) external payable;
}

contract DepositAndCreateOrder is Script {
    function run() public {
        // Configuration
        address strkToken = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; //stark on l1 sepolia
        address usdcSellToken = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; //usdc on l1 sepolia
        IStarknetMessaging snMessaging = IStarknetMessaging(0xE2Bb56ee936fd6433DC0F6e7e3b8365C906AA057);
        address bridgeAddress = 0x123F1b6313dC07a874c3168389973f5973345250;
        uint256 l2EndpointAddress = uint256(0x583014af8c7030c842242ff18212c99d011dc6e45cac66e5952c9fee3b307e0);
        uint256 sellTokenAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; //stark on l2
        uint256 buyTokenAddress = 0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080; //usdc on l2
        uint256 tokenBridgeAddress = 0x0594c1582459ea03f77deaf9eb7e3917d6994a03c13405ba42867f83d85f085d; //stark token bridge on l2
        // Order parameters
        uint128 start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
        uint128 end = start + 64;
        uint128 amount = 0.5 * 10 ** 12;
        uint128 fee = 0.0001 ether;
        uint256 gasPrice = block.basefee * 400;

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
            amount: amount,
            l2EndpointAddress: l2EndpointAddress
        });

        uint256[] memory payload = new uint256[](9);
        // deposit
        payload[0] = uint256(0);
        payload[1] = uint256(uint160(params.sender));
        payload[2] = uint256(params.sellToken);
        payload[3] = uint256(params.buyToken);
        payload[4] = uint256(params.fee);
        payload[5] = uint256(params.start);
        payload[6] = uint256(params.end);
        payload[7] = uint256(params.amount);
        payload[8] = tokenBridgeAddress;
        // Create order
        IERC20(strkToken).transfer(bridgeAddress, amount);
        // console.log("Balance of User: ", IERC20(strkToken).balanceOf(address(msg.sender)));
        IL1TWAMMBridge(bridgeAddress).deposit{value: fee}(amount, l2EndpointAddress);
        //withdraw
        uint256[] memory message = new uint256[](9);
        message[0] = 0;
        message[1] = uint256(uint160(msg.sender));
        message[2] = 0;
        message[3] = 0;
        message[4] = 0;
        message[5] = 0;
        message[6] = 0;
        message[7] = amount;
        message[8] = tokenBridgeAddress;
        /// bridge to L1
        uint256[] memory withdrawal_message = new uint256[](9);
        withdrawal_message[0] = 3;
        withdrawal_message[1] = uint256(uint160(msg.sender));
        withdrawal_message[2] = 0;
        withdrawal_message[3] = uint256(uint160(strkToken));
        withdrawal_message[4] = 0;
        withdrawal_message[5] = 0;
        withdrawal_message[6] = 0;
        withdrawal_message[7] = amount;
        withdrawal_message[8] = tokenBridgeAddress;

        uint256 L2_SELECTOR_VALUE = uint256(0x00f1149cade9d692862ad41df96b108aa2c20af34f640457e781d166c98dc6b0);
        // IL1TWAMMBridge(bridgeAddress)._sendMessage{value: fee, gas: gasPrice}(l2EndpointAddress, L2_SELECTOR_VALUE, payload);
        snMessaging.sendMessageToL2{value: fee}(l2EndpointAddress, L2_SELECTOR_VALUE, withdrawal_message);
        vm.stopBroadcast();
    }

}

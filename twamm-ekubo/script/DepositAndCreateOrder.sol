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
        address usdcBuyToken = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; //usdc on l1 sepolia
        IStarknetMessaging snMessaging = IStarknetMessaging(0xE2Bb56ee936fd6433DC0F6e7e3b8365C906AA057);
        address bridgeAddress = 0x0Ed0e15f0D7362b95A7F4441FCBfb948b63FD61b;
        uint256 l2EndpointAddress = uint256(0x26aece05eedcf29505f498ee637e2595c65944423abe26175677e484a72c3af);
        uint256 sellTokenAddress = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d; //stark on l2
        uint256 buyTokenAddress = 0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080; //usdc on l2
        uint256 sellTokenBridgeAddress = 0x0594c1582459ea03f77deaf9eb7e3917d6994a03c13405ba42867f83d85f085d; //strk token bridge on l2
        uint256 buyTokenBridgeAddress = 0x3913d184e537671dfeca3f67015bb845f2d12a26e5ec56bdc495913b20acb08; //usdc token bridge on l2
        // Order parameters
        uint128 start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
        uint128 end = start + 64;
        uint128 amount = 0.0005 * 10 ** 18;
        uint128 fee = 0.0005 ether;
        uint256 gasPrice = block.basefee * 4;

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

        uint256[] memory payload = new uint256[](8);
        // deposit
        payload[0] = uint256(3);
        payload[1] = uint256(uint160(params.sender));
        payload[2] = uint256(params.sellToken);
        payload[3] = uint256(params.buyToken);
        payload[4] = uint256(params.fee);
        payload[5] = uint256(params.start);
        payload[6] = uint256(params.end);
        payload[7] = uint256(params.amount);
        // Create order
        // IERC20(strkToken).transfer(0xcE5485Cfb26914C5dcE00B9BAF0580364daFC7a4, amount);
        // console.log("Balance of User: ", IERC20(strkToken).balanceOf(address(msg.sender)));
        // IL1TWAMMBridge(0xcE5485Cfb26914C5dcE00B9BAF0580364daFC7a4).deposit{value: fee}(amount, l2EndpointAddress);


        //withdraw
        uint256[] memory withdrawal_message = new uint256[](8);
        withdrawal_message[0] = 3;
        withdrawal_message[1] = uint256(uint160(msg.sender));
        withdrawal_message[2] = 0;
        withdrawal_message[3] = uint256(uint160(usdcBuyToken));
        withdrawal_message[4] = 0;
        withdrawal_message[5] = 0;
        withdrawal_message[6] = 0;
        withdrawal_message[7] = amount;
        // withdrawal_message[8] = buyTokenBridgeAddress;

        // IL1TWAMMBridge(bridgeAddress).initiateCancelDepositRequest{gas: gasPrice}(0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766, amount, 10631);
        // IL1TWAMMBridge(bridgeAddress).depositAndCreateOrder{value: fee, gas:gasPrice}(params);
        // uint256 L2_SELECTOR_VALUE = uint256(0x00f1149cade9d692862ad41df96b108aa2c20af34f640457e781d166c98dc6b0);
        IL1TWAMMBridge(bridgeAddress).initiateWithdrawal{value: fee}(amount, 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        // IL1TWAMMBridge(bridgeAddress).setL2EndpointAddress{gas: gasPrice}(l2EndpointAddress);
        // IL1TWAMMBridge(bridgeAddress).deposit{value: fee}(amount, l2EndpointAddress);
        // snMessaging.sendMessageToL2{value: fee}(l2EndpointAddress, L2_SELECTOR_VALUE, withdrawal_message);
        vm.stopBroadcast();
    }

}
//10576

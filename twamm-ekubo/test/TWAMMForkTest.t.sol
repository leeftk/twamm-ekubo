// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/L1TWAMMBridge.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockStarknetTokenBridge.sol";
import {OrderParams} from "../src/types/OrderParams.sol";
import {IStarknetMessaging} from "../src/interfaces/IStarknetMessaging.sol";

contract L1TWAMMBridgeTest is Test {
    L1TWAMMBridge public bridge;
    MockERC20 public token;
    MockStarknetTokenBridge public starknetBridge;

    event DepositAndCreateOrder(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount, uint256 nonce);

    address public user = address(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045);
    address public l2BridgeAddress = address(456);
    address public l2TokenAddress = address(789);
    address public l2EkuboAddress = address(1);
    uint256 public l2EndpointAddress = uint256(0x820ab2bc3e99e3522daabb53c0da6da0e3e584da48c013d1f4cb762d1f936b);
    //end - start should % 16 = 0

    uint128 public currentTimestamp = uint128(block.timestamp);
    uint128 public difference = 16 - (currentTimestamp % 16);
    uint128 public start = currentTimestamp + difference;
    uint128 public end = start + DEFAULT_DURATION;

    uint128 public fee = 0.001 ether;
    address public rocketPoolAddress = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    uint128 constant DEFAULT_AMOUNT = 100 ether;
    uint128 constant INITIAL_USER_BALANCE = 1000 ether;
    uint128 constant DEFAULT_DURATION = 64;
    uint128 constant DEFAULT_FEE = 170141183460469235273462165868118016;

    event DepositWithMessage(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 l2Recipient,
        bytes message,
        uint256 nonce,
        uint256 fee
    );

    event WithdrawalInitiated(address indexed l1Recipient, uint256 amount);

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");

        // DAI token address on Ethereum mainnet
        address daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        token = MockERC20(daiAddress);

        bridge = new L1TWAMMBridge(
            address(daiAddress),
            address(0xCA14057f85F2662257fd2637FdEc558626bCe554),
            l2EkuboAddress,
            l2EndpointAddress,
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812)
        );
        console.log("bridge address", address(bridge));

        // Mint DAI to the user
        deal(address(token), user, 1000 * 10 ** 18);
        vm.deal(user, 100000000 ether);
    }

    function testDeposit() public {
        uint256 amount = 1 ether;

        console.log("Initial DAI balance of user:", token.balanceOf(user));
        console.log("Initial ETH balance of user:", user.balance);

        vm.startPrank(user);
        token.approve(address(bridge), UINT256_MAX);
        token.transfer(address(bridge), amount);

        vm.stopPrank();
        // vm.prank(address(bridge));
        // token.approve(address(bridge), UINT256_MAX);

        vm.prank(user);
        //bridge.deposit{value: 0.001 ether}(amount, l2EndpointAddress);
        vm.stopPrank();
    }

    function testDepositAndCreateOrder() public {
        uint256 amount = 1 ether;

        // Debug logs to understand initial state
        console.log("Initial DAI balance of user:", token.balanceOf(user));
        console.log("Initial ETH balance of user:", user.balance);
        console.log("Initial DAI balance of bridge:", token.balanceOf(address(bridge)));

        vm.startPrank(user);
        token.approve(address(bridge), UINT256_MAX);
        token.transfer(address(bridge), amount);
        vm.stopPrank();

        // Set up bridge approval separately
        vm.startPrank(address(bridge));
        token.approve(address(0xCA14057f85F2662257fd2637FdEc558626bCe554), UINT256_MAX);
        vm.stopPrank();

        // Debug logs after transfer
        console.log("DAI balance of user after transfer:", token.balanceOf(user));
        console.log("DAI balance of bridge after transfer:", token.balanceOf(address(bridge)));

        OrderParams memory params = OrderParams({
            sender: user,
            sellToken: uint256(0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d),
            buyToken: uint256(0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8),
            fee: DEFAULT_FEE,
            start: start,
            end: end,
            amount: DEFAULT_AMOUNT
        });

        vm.prank(user);
        bridge.depositAndCreateOrder{value: 0.001 ether}(params);

        vm.stopPrank();
    }

    function testInitiateWithdrawalUnauthorized() public {
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;
        address l1Recipient = address(0x3);
        uint128 amount = 100 ether;

        vm.expectRevert();
        vm.prank(user);
        bridge.initiateWithdrawal(id, address(token));
    }

    function testInvalidTimeRange() public {
        uint128 amount = 100 ether;

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        vm.expectRevert();
        OrderParams memory order = OrderParams(
            msg.sender,
            uint256(0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d),
            uint256(0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080),
            fee,
            start,
            start + 64,
            amount
        );
        bridge.depositAndCreateOrder(order);
        vm.stopPrank();
    }

    function testGetBridge() public view {
        address token_bridge = IStarknetRegistry(0x1268cc171c54F2000402DfF20E93E60DF4c96812).getBridge(
            address(0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766)
        );
        console.log("Bridge:", token_bridge);
    }

    function testInvalidInitiateCancelDepositRequest() public {
        //should revert with the wrong nonce
        vm.expectRevert("NO_MESSAGE_TO_CANCEL");
        bridge.initiateCancelDepositRequest(address(token), 100, 0);
    }

    function testInvalidInitiateDepositReclaim() public {
        //should revert with the wrong nonce
        vm.expectRevert("NO_MESSAGE_TO_CANCEL");
        bridge.initiateDepositReclaim(address(token), 100, 10631);
    }
}

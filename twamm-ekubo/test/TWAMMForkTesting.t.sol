// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/L1TWAMMBridge.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockStarknetTokenBridge.sol";

contract L1TWAMMBridgeTest is Test {
    L1TWAMMBridge public bridge;
    MockERC20 public token;
    MockStarknetTokenBridge public starknetBridge;

    event DepositAndCreateOrder(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount, uint256 nonce);

    address public user = address(0x1);
    address public l2BridgeAddress = address(456);
    address public l2TokenAddress = address(789);
    address public l2EkuboAddress = address(1);
    uint256 public l2EndpointAddress = uint256(uint160(address(131415)));

    //end - start should % 16 = 0

    // Ensure (end - start) is always divisible by 16
    uint256 public start = (block.timestamp / 16) * 16; // Round down to nearest multiple of 16
    uint256 public end = start + 64; // 1600 is divisible by 16

    uint128 public fee = 0.01 ether;
    address public rocketPoolAddress = 0xae78736Cd615f374D3085123A210448E74Fc6393;

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
        address daiAddress = 0x610dBd98A28EbbA525e9926b6aaF88f9159edbfd;
        token = MockERC20(daiAddress);

        
        bridge = new L1TWAMMBridge(address(daiAddress), address(0xF5b6Ee2CAEb6769659f6C091D209DfdCaF3F69Eb), l2EkuboAddress, l2EndpointAddress, address(0x1268cc171c54F2000402DfF20E93E60DF4c96812));
        console.log("bridge address", address(bridge));
        
        // Mint DAI to the user
        deal(address(token), user, 1000 * 10**18);
        vm.deal(user, 1000 ether);
    }

    // function testDepositWithMessage() public {
    //     uint128 amount = 100 ether;

    //     vm.startPrank(user);
    //     token.approve(address(bridge), amount);

    //     //uint256 expectedNonce = starknetBridge.mockNonce();

    //     //vm.expectEmit(true, true, false, true);
    //     // Update the event emission expectation
    //     //emit DepositAndCreateOrder(user, l2EndpointAddress, amount, expectedNonce);

    //     bridge.depositAndCreateOrder{value: 0.01 ether}(
    //         amount, l2EndpointAddress, start, end, address(token), address(token), fee
    //     );
    //     vm.stopPrank();

    //     MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();

    //     //assert that the amount is correct
    //     assertEq(params.token, address(token), "Incorrect token");
    //     assertEq(params.amount, amount, "Incorrect amount");

    //     //Check payload
    //     assertEq(params.message.length, 8, "Incorrect payload length");
    //     assertEq(params.message[0], uint256(uint160(l2EkuboAddress)), "Incorrect Ekubo address");
    //     assertEq(params.l2EndpointAddress, l2EndpointAddress, "Incorrect sender address");
    // }


    function testDepositWithMessage() public {
        uint128 amount = 100 ether;

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        uint256 expectedNonce = starknetBridge.mockNonce();

        vm.expectEmit(true, true, false, true);
        emit DepositAndCreateOrder(user, l2EndpointAddress, amount, expectedNonce);

        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, end, address(token), address(token), fee
        );
        vm.stopPrank();

        MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();

        console.log("Expected Ekubo address:", uint256(uint160(l2EkuboAddress)));
        console.log("Actual message[0]:", params.message[0]);

        // Assertions remain the same
        assertEq(params.token, address(token), "Incorrect token");
        assertEq(params.amount, amount, "Incorrect amount");
        assertEq(params.message.length, 8, "Incorrect payload length");
        // assertEq(params.message[0], uint256(uint160(l2EkuboAddress)), "Incorrect Ekubo address");
        assertEq(params.l2EndpointAddress, l2EndpointAddress, "Incorrect sender address");
    }

    function testInitiateWithdrawal() public {
        uint128 amount = 100 ether;
        address l1Recipient = address(0x3);
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;
        // First, deposit some tokens to the bridge
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, end, address(token), address(token), fee
        );
        vm.stopPrank();

        // Now initiate withdrawal
        vm.expectEmit(true, false, false, true);
        emit WithdrawalInitiated(l1Recipient, saleRateDelta);

        vm.prank(bridge.owner());
        bridge.initiateWithdrawal{value: 0.01 ether}(
            id, address(token), address(token), fee, uint64(start), uint64(end), saleRateDelta, l1Recipient
        );
    }

    function testInitiateWithdrawalUnauthorized() public {
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;
        address l1Recipient = address(0x3);

        vm.expectRevert();
        vm.prank(user);
        bridge.initiateWithdrawal(
            id, address(token), address(token), fee, uint64(start), uint64(end), saleRateDelta, l1Recipient
        );
    }

    function testInvalidTimeRange() public {
        uint128 amount = 100 ether;

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectRevert();
        bridge.depositAndCreateOrder(
            amount,
            l2EndpointAddress,
            end, // Swapped start and end to create invalid time range
            start,
            address(token),
            address(token),
            fee
        );
        vm.stopPrank();
    }

    function testRemoveSupportedToken() public {
        vm.prank(bridge.owner());
        bridge.removeSupportedToken(address(token));

        assertEq(bridge.supportedTokens(address(token)), false, "Token should be removed from supported tokens");
    }

    function testRemoveSupportedTokenUnauthorized() public {
        vm.expectRevert();
        vm.prank(user);
        bridge.removeSupportedToken(address(token));
    }
}
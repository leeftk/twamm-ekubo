// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/L1TWAMMBridge.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockStarknetTokenBridge.sol";

contract L1TWAMMBridgeTest is Test {
    uint128 constant DEFAULT_AMOUNT = 100 ether;
    uint128 constant INITIAL_USER_BALANCE = 1000 ether;
    uint128 constant DEFAULT_DURATION = 64;
    uint128 constant DEFAULT_FEE = 0.02 ether;

    L1TWAMMBridge public bridge;
    MockERC20 public token;
    MockStarknetTokenBridge public starknetBridge;

    address public user = address(0x1);
    address public l2EkuboAddress = address(0x2);
    uint256 public l2EndpointAddress = uint256(0x4fe8b6644cdf2a469abc0dcf097cdd3608e2f89c1c189962f0a6d8a1d7e0a11);
    uint128 public currentTimestamp = uint128(block.timestamp);
    uint128 public difference = 16 - (currentTimestamp % 16);
    uint128 public start = currentTimestamp + difference;
    uint128 public end = start + DEFAULT_DURATION;

    event DepositAndCreateOrder(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount, uint256 nonce);
    event WithdrawalInitiated(address indexed l1Recipient, uint256 amount);

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK");
        starknetBridge = new MockStarknetTokenBridge();
        vm.warp(1000);

        bridge = new L1TWAMMBridge(
            address(token),
            address(starknetBridge),
            l2EkuboAddress,
            l2EndpointAddress,
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812)
        );

        token.mint(user, INITIAL_USER_BALANCE);
        token.approve(address(bridge), type(uint256).max);

        starknetBridge.setServicingToken(address(token), true);

        vm.deal(user, 10 ether); // Allocate ETH for user
    }

    function testDepositAndCreateOrder() public {
        vm.startPrank(user);

        token.approve(address(bridge), DEFAULT_AMOUNT);

        OrderParams memory params = OrderParams({
            sender: user,
            sellToken: uint256(uint160(address(token))),
            buyToken: uint256(uint160(address(0x123))),
            fee: DEFAULT_FEE,
            start: start,
            end: end,
            amount: DEFAULT_AMOUNT
        });

        // Expect the event to be emitted
        // vm.expectEmit(true, true, true, true);
        // emit DepositAndCreateOrder(user, l2EndpointAddress, DEFAULT_AMOUNT, 1);

        // Call the deposit function
        bridge.depositAndCreateOrder{value: DEFAULT_FEE}(params);

        vm.stopPrank();

        // Assert token transfer
        assertEq(token.balanceOf(address(starknetBridge)), DEFAULT_AMOUNT, "Token transfer failed");

        // Assert state of the Starknet bridge
        MockStarknetTokenBridge.DepositParams memory depositParams = starknetBridge.getLastDepositParams();
        assertEq(depositParams.token, address(token), "Incorrect token");
        assertEq(depositParams.amount, DEFAULT_AMOUNT, "Incorrect amount");
    }

    // function testInitiateWithdrawal() public {
    //     vm.startPrank(user);

    //     // Mock withdrawal event
    //     address recipient = address(0x4);
    //     uint256 withdrawalAmount = 50 ether;

    //     vm.expectEmit(true, true, false, true);
    //     emit WithdrawalInitiated(recipient, withdrawalAmount);

    //     vm.stopPrank();

    //     // Perform withdrawal
    //     vm.prank(bridge.owner());
    //     bridge.initiateWithdrawal{value: DEFAULT_FEE}(withdrawalAmount, address(token));
    // }

    // function testInvalidTimeRangeReverts() public {
    //     vm.startPrank(user);

    //     token.approve(address(bridge), DEFAULT_AMOUNT);

    //     OrderParams memory params = OrderParams({
    //         sender: user,
    //         sellToken: uint256(uint160(address(token))),
    //         buyToken: uint256(uint160(address(0x123))),
    //         fee: DEFAULT_FEE,
    //         start: start,
    //         end: start - 1, // Invalid time range
    //         amount: DEFAULT_AMOUNT,
    //         l2EndpointAddress: l2EndpointAddress
    //     });

    //     vm.expectRevert(L1TWAMMBridge.InvalidTimeRange.selector);
    //     bridge.depositAndCreateOrder{value: DEFAULT_FEE}(params);

    //     vm.stopPrank();
    // }

    // function testUnsupportedTokenReverts() public {
    //     vm.startPrank(user);

    //     MockERC20 unsupportedToken = new MockERC20("Unsupported", "UST");
    //     unsupportedToken.mint(user, DEFAULT_AMOUNT);
    //     unsupportedToken.approve(address(bridge), DEFAULT_AMOUNT);

    //     OrderParams memory params = OrderParams({
    //         sender: user,
    //         sellToken: uint256(uint160(address(unsupportedToken))),
    //         buyToken: uint256(uint160(address(0x123))),
    //         fee: DEFAULT_FEE,
    //         start: start,
    //         end: start + DEFAULT_DURATION,
    //         amount: DEFAULT_AMOUNT,
    //         l2EndpointAddress: l2EndpointAddress
    //     });

    //     vm.expectRevert(L1TWAMMBridge.NotSupportedToken.selector);
    //     bridge.depositAndCreateOrder{value: DEFAULT_FEE}(params);

    //     vm.stopPrank();
    // }

    // function testUnauthorizedAccessReverts() public {
    //     vm.startPrank(user);

    //     // Attempt to call owner-only function
    //     vm.expectRevert();
    //     bridge.setL2EndpointAddress(123);

    //     vm.stopPrank();
    // }

    // function testValidateTimeCorrectness() public {
    //     uint256 interval = 16;
    //     uint256;
    //     testTimes[0] = start;
    //     testTimes[1] = start + interval;
    //     testTimes[2] = start + 2 * interval;
    //     testTimes[3] = start + 64; // Custom offset
    //     testTimes[4] = start + 128;

    //     for (uint256 i = 0; i < testTimes.length; i++) {
    //         bool isValid = bridge.isTimeValidExternal(start, testTimes[i]);
    //         if ((testTimes[i] - start) % interval == 0) {
    //             assertTrue(isValid, "Time should be valid");
    //         } else {
    //             assertFalse(isValid, "Time should be invalid");
    //         }
    //     }
    // }
}

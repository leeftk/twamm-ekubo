// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/L1TWAMMBridge.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockStarknetTokenBridge.sol";
import "forge-std/console2.sol";

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

    // Ensure timestamps are aligned with the required step sizes
    uint128 public currentTimestamp = uint128(block.timestamp);
    uint128 public difference = 16 - (currentTimestamp % 16);
    uint128 public start = currentTimestamp + difference;
    // Let's test with MASSIVE intervals
    uint128 public end = start + 64; // 16 * 1048576 = 16777216      (~4.5 hours)

    uint128 public fee = 0.01 ether;

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
        token = new MockERC20("Mock Token", "MTK");
        starknetBridge = new MockStarknetTokenBridge();
        vm.warp(start);

        bridge = new L1TWAMMBridge(
            address(token),
            address(starknetBridge),
            l2EkuboAddress,
            l2EndpointAddress,
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812)
        );

        token.mint(user, 1000 ether);
        starknetBridge.setServicingToken(address(token), true);
        vm.deal(user, 1000 ether);

        vm.mockCall(
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812), // starknetTokenBridge address
            abi.encodeWithSelector(IStarknetRegistry.getBridge.selector, address(token)),
            abi.encode(address(starknetBridge))
        );
    }

    function testDepositWithMessage() public {
        uint128 amount = 100 ether;

        // Mock the registry response BEFORE making the deposit
        vm.mockCall(
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812), // starknetRegistry address
            abi.encodeWithSelector(IStarknetRegistry.getBridge.selector, address(token)),
            abi.encode(address(starknetBridge))
        );

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        uint256 expectedNonce = starknetBridge.mockNonce();

        vm.expectEmit(true, true, false, true);
        emit DepositAndCreateOrder(address(user), l2EndpointAddress, amount, expectedNonce);

        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, start + 64, address(token), address(token), fee
        );
        vm.stopPrank();

        MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();

        console.log("Expected Ekubo address:", uint256(uint160(l2EkuboAddress)));
        console.log("Actual message[0]:", params.message[0]);

        // Assertions remain the same
        assertEq(params.token, address(token), "Incorrect token");
        assertEq(params.amount, amount, "Incorrect amount");
        assertEq(params.message.length, 7, "Incorrect payload length");
        // assertEq(params.message[0], uint256(uint160(l2EkuboAddress)), "Incorrect Ekubo address");
        assertEq(params.l2EndpointAddress, l2EndpointAddress, "Incorrect sender address");
    }

    function testInitiateWithdrawal() public {
        uint128 amount = 100 ether;
        address l1Recipient = address(0x3);
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;

        uint256 testEnd = start + 64;

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, start + 64, address(token), address(token), fee
        );
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit WithdrawalInitiated(l1Recipient, amount);

        vm.prank(bridge.owner());
        bridge.initiateWithdrawal{value: 0.01 ether}(address(token), l1Recipient, amount);
    }

    function testInitiateWithdrawalUnauthorized() public {
        uint128 amount = 100 ether;
        address l1Recipient = address(0x3);

        vm.expectRevert();
        vm.prank(user);
        bridge.initiateWithdrawal(address(token), l1Recipient, amount);
    }

    function testInvalidTimeRange() public {
        uint128 amount = 100 ether;

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectRevert(L1TWAMMBridge.InvalidTimeRange.selector);
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
        vm.expectRevert();
        bridge.removeSupportedToken(address(token));
    }

    function testValidBridge() public {
        uint128 amount = 100 ether;

        vm.mockCall(
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812),
            abi.encodeWithSelector(IStarknetRegistry.getBridge.selector, address(token)),
            abi.encode(address(starknetBridge))
        );

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        uint256 expectedNonce = starknetBridge.mockNonce();

        vm.expectEmit(true, true, false, true);
        emit DepositAndCreateOrder(
            user, // l1Sender
            l2EndpointAddress, // l2Recipient
            amount, // amount
            expectedNonce // nonce
        );

        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, start + 64, address(token), address(token), fee
        );
        vm.stopPrank();

        MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();
        assertEq(params.token, address(token), "Incorrect token");
    }

    function testUnauthorizedAccess() public {
        address nonOwner = address(0x123);
        vm.startPrank(nonOwner);
        vm.expectRevert();
        bridge.setL2EndpointAddress(2);
        vm.stopPrank();
    }

    function testTimeValidation() public {
        // Let's test various intervals and print results
        uint256[] memory intervals = new uint256[](6);
        intervals[0] = 16; // Basic interval
        intervals[1] = 256; // 16 * 16
        intervals[2] = 4096; // 16 * 256
        intervals[3] = 65536; // 16 * 4096
        intervals[4] = 1048576; // 16 * 65536
        intervals[5] = 16777216; // 16 * 1048576

        vm.warp(start);

        for (uint256 i = 0; i < intervals.length; i++) {
            uint256 targetTime = start + intervals[i];
            // Round target time to the nearest valid interval based on distance
            uint256 distance = intervals[i];
            uint256 logScale = 4; // log base 2 of 16
            uint256 msb = mostSignificantBit(distance);
            uint256 step;

            if (distance <= 16) {
                step = 16;
            } else {
                uint256 power = (msb / logScale) * logScale;
                step = 1 << power; // 2^power
            }

            uint256 roundedTime = (targetTime / step) * step;

            bool isValid = bridge.isTimeValidExternal(start, roundedTime);
            
            // console.log(
            //     "Testing interval:",
            //     intervals[i],
            //     "Step size:",
            //     step,
            //     "Valid:",
            //     isValid
            // );
            assertTrue(isValid, "Time should be valid after rounding");
        }
    }

    // Helper function to find most significant bit
    function mostSignificantBit(uint256 x) internal pure returns (uint256) {
        uint256 r = 0;
        while (x > 0) {
            x = x >> 1;
            r++;
        }
        return r > 0 ? r - 1 : 0;
    }
}

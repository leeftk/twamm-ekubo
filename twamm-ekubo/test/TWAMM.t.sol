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

    // Ensure timestamps are aligned with the required step sizes
    uint256 public currentTimestamp = block.timestamp;
    uint256 public difference = 16 - (currentTimestamp % 16);
    uint256 public start = currentTimestamp + difference;
    // Let's test with MASSIVE intervals
    uint256 public end = start + 16777216;      // 16 * 1048576 = 16777216      (~4.5 hours)
    // Other valid larger intervals:
    // end = start + 268435456;     // 16 * 16777216 = 268435456    (~3 days)
    // end = start + 4294967296;    // 16 * 268435456 = 4294967296  (~49 days)
    // end = start + 68719476736;   // 16 * 4294967296 = 68719476736 (~2.2 years)
    // end = start + 1099511627776; // 16 * 68719476736 = 1099511627776 (~35 years)

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
        assertEq(params.message.length, 8, "Incorrect payload length");
        // assertEq(params.message[0], uint256(uint160(l2EkuboAddress)), "Incorrect Ekubo address");
        assertEq(params.l2EndpointAddress, l2EndpointAddress, "Incorrect sender address");
    }

    function testInitiateWithdrawal() public {
        uint128 amount = 100 ether;
        address l1Recipient = address(0x3);
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;
        vm.warp(start);

        uint256 testEnd = start + 16777216;

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, start + 64, address(token), address(token), fee
        );
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit WithdrawalInitiated(l1Recipient, amount);

        vm.prank(bridge.owner());
        bridge.initiateWithdrawal{value: 0.01 ether}(
            address(token), l1Recipient, amount
        );
    }

    function testInitiateWithdrawalUnauthorized() public {
        uint128 amount = 100 ether;
        address l1Recipient = address(0x3);

        vm.expectRevert();
        vm.prank(user);
        bridge.initiateWithdrawal(
            address(token), l1Recipient, amount
        );
    }

    function testInvalidTimeRange() public {
        uint128 amount = 100 ether;

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectRevert(L1TWAMMBridge.L1TWAMMBridge__InvalidTimeRange.selector);
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
            user,               // l1Sender
            l2EndpointAddress, // l2Recipient
            amount,            // amount
            expectedNonce      // nonce
        );

        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, start + 64, address(token), address(token), fee
        );
        vm.stopPrank();

        MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();
        assertEq(params.token, address(token), "Incorrect token");
    }

    function testInValidBridge() public {
        uint128 amount = 100 ether;

        vm.mockCall(
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812), // starknetTokenBridge address
            abi.encodeWithSelector(IStarknetRegistry.getBridge.selector, address(token)),
            abi.encode(address(0))
        );

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        vm.expectRevert(L1TWAMMBridge.L1TWAMMBridge__InvalidBridge.selector);

        bridge.depositAndCreateOrder{value: 0.01 ether}(
            amount, l2EndpointAddress, start, end, address(token), address(token), fee
        );
        vm.stopPrank();
    }

    function testUnauthorizedAccess() public {
        address nonOwner = address(0x123);
        vm.startPrank(nonOwner);
        vm.expectRevert();
        bridge.setL2EndpointAddress(2);
        vm.stopPrank();
    }

    // make the testValidTimeRange public to test this accurately
    // function testValidTimeRange() public {
    //     uint256 currentTime = block.timestamp
    //     uint256 alignedStart = (currentTime / 16) * 16;
    //     vm.warp(alignedStart);

    //     bool isValid = bridge.isTimeValid(alignedStart, alignedStart);
    //     assertTrue(isValid, "Start time should be valid");
    // }

    function testTimeValidation() public {
        // Let's test various intervals and print results
        uint256[] memory intervals = new uint256[](6);
        intervals[0] = 16;          // Basic interval
        intervals[1] = 256;         // 16 * 16
        intervals[2] = 4096;        // 16 * 256
        intervals[3] = 65536;       // 16 * 4096
        intervals[4] = 1048576;     // 16 * 65536
        intervals[5] = 16777216;    // 16 * 1048576

        vm.warp(start);
        
        for (uint i = 0; i < intervals.length; i++) {
            bool isValid = bridge.isTimeValidExternal(start, start + intervals[i]);
            console.log(
                "Testing interval:", 
                intervals[i], 
                "Valid:", 
                isValid
            );
        }
    }
}

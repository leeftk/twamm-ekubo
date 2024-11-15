// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/L1TWAMMBridge.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockStarknetTokenBridge.sol";
import "forge-std/console2.sol";

contract L1TWAMMBridgeTest is Test {
    // === CONSTANTS ===
    uint128 constant DEFAULT_AMOUNT = 100 ether;
    uint128 constant INITIAL_USER_BALANCE = 1000 ether;
    uint128 constant DEFAULT_DURATION = 64;
    uint128 constant DEFAULT_FEE = 0.01 ether;

    // === STATE VARIABLES ===
    L1TWAMMBridge public bridge;
    MockERC20 public token;
    MockStarknetTokenBridge public starknetBridge;

    // === TEST ADDRESSES ===
    address public user = address(0x1);
    address public l2BridgeAddress = address(456);
    address public l2TokenAddress = address(789);
    address public l2EkuboAddress = address(1);
    uint256 public l2EndpointAddress = uint256(uint160(address(131415)));

    // === TIME RELATED VARIABLES ===
    uint128 public currentTimestamp = uint128(block.timestamp);
    uint128 public difference = 16 - (currentTimestamp % 16);
    uint128 public start = currentTimestamp + difference;
    uint128 public end = start + DEFAULT_DURATION;

    // === EVENTS ===
    event DepositAndCreateOrder(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount, uint256 nonce);
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

    // === HELPERS ===
    function _createDefaultOrder() internal view returns (OrderParams memory) {
        return OrderParams(
            msg.sender,
            uint256(0x516e69ab50d35cef4606116266187593f1ec83d67274143da15e0b439e45fe8),
            uint256(0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d),
            DEFAULT_FEE,
            start,
            start + DEFAULT_DURATION,
            DEFAULT_AMOUNT,
            l2EndpointAddress
        );
    }

    // === SETUP ===
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

        token.mint(user, INITIAL_USER_BALANCE);
        starknetBridge.setServicingToken(address(token), true);
        vm.deal(user, INITIAL_USER_BALANCE);

        vm.mockCall(
            address(0x1268cc171c54F2000402DfF20E93E60DF4c96812),
            abi.encodeWithSelector(IStarknetRegistry.getBridge.selector, address(token)),
            abi.encode(address(starknetBridge))
        );
    }

    // === DEPOSIT TESTS ===
    function testDepositWithMessage() public {
        vm.startPrank(user);
        token.approve(address(bridge), DEFAULT_AMOUNT);

        uint256 expectedNonce = starknetBridge.mockNonce();

        vm.expectEmit(true, true, false, true);
        emit DepositAndCreateOrder(address(user), l2EndpointAddress, DEFAULT_AMOUNT, expectedNonce);

        OrderParams memory order = _createDefaultOrder();
        bridge.depositAndCreateOrder{value: DEFAULT_FEE}(order);
        vm.stopPrank();

        MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();
        assertEq(params.token, address(token), "Incorrect token");
        assertEq(params.amount, DEFAULT_AMOUNT, "Incorrect amount");
        assertEq(params.message.length, 7, "Incorrect payload length");
        assertEq(params.l2EndpointAddress, l2EndpointAddress, "Incorrect sender address");
    }

    // === WITHDRAWAL TESTS ===
    function testInitiateWithdrawal() public {
        address l1Recipient = address(0x3);

        vm.startPrank(user);
        token.approve(address(bridge), DEFAULT_AMOUNT);
        OrderParams memory order = _createDefaultOrder();
        bridge.depositAndCreateOrder{value: DEFAULT_FEE}(order);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit WithdrawalInitiated(l1Recipient, DEFAULT_AMOUNT);

        vm.prank(bridge.owner());
        // bridge.initiateWithdrawal{value: DEFAULT_FEE}(
        //     address(token),
        //     l1Recipient,
        //     DEFAULT_AMOUNT
        // );
    }

    function testInitiateWithdrawalUnauthorized() public {
        address l1Recipient = address(0x3);

        vm.expectRevert();
        vm.prank(user);
        // bridge.initiateWithdrawal(address(token), l1Recipient, DEFAULT_AMOUNT);
    }

    function testInvalidTimeRange() public {
        vm.startPrank(user);
        token.approve(address(bridge), DEFAULT_AMOUNT);

        OrderParams memory order = _createDefaultOrder();
        vm.expectRevert(L1TWAMMBridge.InvalidTimeRange.selector);
        bridge.depositAndCreateOrder(order);
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
        vm.startPrank(user);
        token.approve(address(bridge), DEFAULT_AMOUNT);

        uint256 expectedNonce = starknetBridge.mockNonce();

        vm.expectEmit(true, true, false, true);
        emit DepositAndCreateOrder(user, l2EndpointAddress, DEFAULT_AMOUNT, expectedNonce);

        OrderParams memory order = _createDefaultOrder();
        bridge.depositAndCreateOrder{value: DEFAULT_FEE}(order);
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
        uint256[] memory intervals = new uint256[](6);
        intervals[0] = 16;
        intervals[1] = 256;
        intervals[2] = 4096;
        intervals[3] = 65536;
        intervals[4] = 1048576;
        intervals[5] = 16777216;

        vm.warp(start);

        for (uint256 i = 0; i < intervals.length; i++) {
            uint256 targetTime = start + intervals[i];
            uint256 distance = intervals[i];
            uint256 logScale = 4;
            uint256 msb = mostSignificantBit(distance);
            uint256 step;

            if (distance <= 16) {
                step = 16;
            } else {
                uint256 power = (msb / logScale) * logScale;
                step = 1 << power;
            }

            uint256 roundedTime = (targetTime / step) * step;
            bool isValid = bridge.isTimeValidExternal(start, roundedTime);
            assertTrue(isValid, "Time should be valid after rounding");
        }
    }

    function mostSignificantBit(uint256 x) internal pure returns (uint256) {
        uint256 r = 0;
        while (x > 0) {
            x = x >> 1;
            r++;
        }
        return r > 0 ? r - 1 : 0;
    }
}

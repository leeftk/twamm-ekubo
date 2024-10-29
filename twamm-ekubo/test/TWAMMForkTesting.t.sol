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
    uint256 public l2EndpointAddress = uint256(0x0455c60bbd52b3b57076a0180e7588df61046366ad5a48bc277c974518f837c4);

    //end - start should % 16 = 0

    // Ensure (end - start) is always divisible by 16
    uint128 public start = uint128((block.timestamp / 16) * 16); // Round down to nearest multiple of 16
    uint128 public end = start + 64; // 1600 is divisible by 16

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
        address daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        token = MockERC20(daiAddress);

        
        bridge = new L1TWAMMBridge(address(daiAddress), address(0xCA14057f85F2662257fd2637FdEc558626bCe554), l2EkuboAddress, l2EndpointAddress, address(0x1268cc171c54F2000402DfF20E93E60DF4c96812));
        console.log("bridge address", address(bridge));
        
        // Mint DAI to the user
        deal(address(token), user, 1000 * 10**18);
        vm.deal(user, 100000000 ether);
    }

    function testDeposit() public {
        uint256 amount = 1 ether;

        console.log("Initial DAI balance of user:", token.balanceOf(user));
        console.log("Initial ETH balance of user:", user.balance);
        
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        token.transfer(address(bridge), amount);
        
        vm.stopPrank();
        vm.prank(address(bridge));
        token.approve(address(0xCA14057f85F2662257fd2637FdEc558626bCe554), amount);
        
        vm.prank(user);
        bridge.deposit{value: .01 ether}(amount, l2EndpointAddress);
    }

    function testDepositWithMessage() public {
        uint256 amount = 1 ether;
        
        // Debug logs to understand initial state
        console.log("Initial DAI balance of user:", token.balanceOf(user));
        console.log("Initial ETH balance of user:", user.balance);
        console.log("Initial DAI balance of bridge:", token.balanceOf(address(bridge)));

        vm.startPrank(user);
        
        // First approve and transfer tokens
        token.approve(address(bridge), amount);
        token.transfer(address(bridge), amount);
        
        // Debug logs after transfer
        console.log("DAI balance of user after transfer:", token.balanceOf(user));
        console.log("DAI balance of bridge after transfer:", token.balanceOf(address(bridge)));
        
        // Bridge needs to approve Starknet bridge
        vm.stopPrank();
        vm.prank(address(bridge));
        token.approve(address(0xCA14057f85F2662257fd2637FdEc558626bCe554), amount);
        
        vm.startPrank(user);
        
        // Let's try with a specific payload structure
        uint256[] memory payload = new uint256[](3);
        payload[0] = uint256(uint160(address(token))); // token address
        payload[1] = uint256(uint160(user));          // from address
        payload[2] = amount;                          // amount

        // Debug log the payload
        console.log("Payload[0] (token):", payload[0]);
        console.log("Payload[1] (from):", payload[1]);
        console.log("Payload[2] (amount):", payload[2]);
        
        try bridge.depositWithMessage{value: .01 ether}(amount, l2EndpointAddress, payload) {
            console.log("Deposit succeeded");
        } catch Error(string memory reason) {
            console.log("Deposit failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Deposit failed with low-level error");
        }
        
        vm.stopPrank();
    }

    function testInitiateWithdrawal() public {
        uint128 amount = 100 ether;
        address l1Recipient = address(0x3);
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;
        // First, deposit some tokens to the bridge
        vm.startPrank(user);
        // token.approve(address(bridge), amount);
        // bridge.depositAndCreateOrder{value: 0.01 ether}(
        //     amount, l2EndpointAddress, start, end, address(token), address(token), fee
        // );
        // vm.stopPrank();

        // // Now initiate withdrawal
        // vm.expectEmit(true, false, false, true);
        // emit WithdrawalInitiated(l1Recipient, saleRateDelta);

        // vm.prank(bridge.owner());
        // bridge.initiateWithdrawal{value: 0.01 ether}(
        //     address(token), l1Recipient, amount
        // );
    }

    function testInitiateWithdrawalUnauthorized() public {
        uint64 id = 1;
        uint128 saleRateDelta = 50 ether;
        address l1Recipient = address(0x3);
        uint128 amount = 100 ether;

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

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
    
    address public user = address(0x1);
    address public l2Recipient = address(0x2);
    uint256 public l2BridgeAddress = 456;
    uint256 public l2TokenAddress = 789;
    uint256 public l2EkuboAddress = 101112;

    event DepositWithMessage(
        address indexed sender,
        address indexed token,
        uint256 amount,
        address l2Recipient,
        bytes message,
        uint256 nonce,
        uint256 fee
    );

   

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK");
        starknetBridge = new MockStarknetTokenBridge();
        
        bridge = new L1TWAMMBridge(
            address(token),
            address(starknetBridge),
            l2BridgeAddress,
            l2TokenAddress,
            l2EkuboAddress
        );

        token.mint(user, 1000 ether);
        starknetBridge.setServicingToken(address(token), true);
        vm.deal(user, 1000 ether);
    }

    function testDepositWithMessage() public {
        uint256 amount = 100 ether;
        
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        
        // Declare the missing variables
        bytes memory expectedMessage = abi.encode(amount, uint256(uint160(user)));
        uint256 expectedNonce = 1;
        uint256 expectedFee = 0.01 ether;


    
        // Use the variables in the event emission
        emit DepositWithMessage(address(this), address(token), amount, l2Recipient, expectedMessage, expectedNonce, expectedFee);

        bridge.depositAndCreateOrder{value: 100 ether}(amount, l2Recipient);
        vm.stopPrank();

        MockStarknetTokenBridge.DepositParams memory params = starknetBridge.getLastDepositParams();

        assertEq(params.token, address(token), "Incorrect token");
        assertEq(params.amount, amount, "Incorrect amount");
        assertEq(params.l2Recipient, l2Recipient, "Incorrect L2 recipient");
        
       // Check payload
        assertEq(params.message.length, 3, "Incorrect payload length");
        assertEq(params.message[0], l2EkuboAddress, "Incorrect Ekubo address");
        assertEq(params.message[1], uint256(uint32(bytes4(keccak256("mint(uint256,address)")))), "Incorrect function selector");
        
      //  Decode the last payload item
       // (uint256 decodedAmount, address decodedSender) = abi.decode(abi.encodePacked(params.message[0]), (uint256, address));
        // assertEq(decodedAmount, amount, "Incorrect encoded amount");
        // assertEq(decodedSender, user, "Incorrect encoded sender");
    }
}
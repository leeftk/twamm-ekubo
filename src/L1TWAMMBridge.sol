// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IStarknetTokenBridge {
    function depositWithMessage(
        address token,
        uint256 amount,
        address l2Recipient,
        uint256[] calldata message
    ) external payable returns (uint256);
}

contract L1TWAMMBridge is Ownable {
    IERC20 public token;
    IStarknetTokenBridge public starknetBridge;
    uint256 public l2BridgeAddress;
    uint256 public l2TokenAddress;
    uint256 public l2EkuboAddress;

    // Function signature for the mint function on L2
    bytes4 constant MINT_SELECTOR = bytes4(keccak256("mint(uint256,address)"));

    event DepositAndCreateOrder(address indexed l1Sender, address indexed l2Recipient, uint256 amount, uint256 nonce);

    constructor(
        address _token,
        address _starknetBridge,
        uint256 _l2BridgeAddress,
        uint256 _l2TokenAddress,
        uint256 _l2EkuboAddress
    ) Ownable(msg.sender) {
        token = IERC20(_token);
        starknetBridge = IStarknetTokenBridge(_starknetBridge);
        l2BridgeAddress = _l2BridgeAddress;
        l2TokenAddress = _l2TokenAddress;
        l2EkuboAddress = _l2EkuboAddress;
    }

    function depositAndCreateOrder(uint256 amount, address l2Recipient) external payable {
        token.transferFrom(msg.sender, address(this), amount);
        token.approve(address(starknetBridge), amount);
        
        // Prepare the payload for L2
        uint256[] memory payload = new uint256[](3);
        payload[0] = l2EkuboAddress;  // Ekubo address on L2
        payload[1] = uint256(uint32(MINT_SELECTOR));  // Selector for the 'mint' function
        
        // Encode the function parameters
        bytes memory params = abi.encode(amount, uint256(uint160(msg.sender)));
        payload[2] = uint256(bytes32(params));

   


        uint256 nonce = starknetBridge.depositWithMessage{value: msg.value}(
            address(token),
            amount,
            l2Recipient, 
            payload
        );
        
        emit DepositAndCreateOrder(msg.sender, l2Recipient, amount, nonce);
    }

    // Additional functions like withdrawal can be added here
}
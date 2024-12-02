// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

error InvalidToken();

contract MockStarknetTokenBridge {
    uint256 constant HANDLE_DEPOSIT_WITH_MESSAGE_SELECTOR = 1234567890;

    event DepositWithMessage(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 l2EndpointAddress,
        uint256[] message,
        uint256 nonce,
        uint256 fee
    );

    event Deposit(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 indexed l2Recipient,
        uint256 nonce,
        uint256 fee
    );

    struct DepositParams {
        address token;
        uint256 amount;
        uint256 l2EndpointAddress;
        uint256[] message;
        uint256 nonce;
        uint256 fee;
    }

    DepositParams public lastDeposit;
    uint256 public mockNonce = 1;
    uint256 public mockFee = 0.01 ether;
    mapping(address => bool) public servicingTokens;

    function setServicingToken(address token, bool isServicing) external {
        servicingTokens[token] = isServicing;
    }

    function depositWithMessage(address token, uint256 amount, uint256 l2EndpointAddress, uint256[] calldata message)
        external
        payable
    {
        uint256 nonce = mockNonce++;

        lastDeposit = DepositParams({
            token: token,
            amount: amount,
            l2EndpointAddress: l2EndpointAddress,
            message: message,
            nonce: nonce,
            fee: mockFee
        });

        emit DepositWithMessage(msg.sender, token, amount, l2EndpointAddress, message, nonce, mockFee);
    }

    function getLastDepositParams() external view returns (DepositParams memory) {
        return lastDeposit;
    }

    function getBridge(address tokenAddress) external view returns (address) {
        if (tokenAddress == address(0)) revert InvalidToken();
        return address(this);
    }

    function deposit(address token, uint256 amount, uint256 l2EndpointAddress) external payable {
        uint256 nonce = mockNonce++;
        uint256[] memory noMessage = new uint256[](0);
        lastDeposit = DepositParams({
            token: token,
            amount: amount,
            l2EndpointAddress: l2EndpointAddress,
            message: noMessage,
            nonce: nonce,
            fee: mockFee
        });

        emit Deposit(msg.sender, token, amount, l2EndpointAddress, nonce, mockFee);
    }

    receive() external payable {}
}

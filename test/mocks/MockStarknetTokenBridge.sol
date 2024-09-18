// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MockStarknetTokenBridge {
    uint256 constant HANDLE_DEPOSIT_WITH_MESSAGE_SELECTOR = 1234567890; // Replace with actual selector if known

    event DepositWithMessage(
        address indexed sender,
        address indexed token,
        uint256 amount,
        address indexed l2Recipient,
        uint256[] message,
        uint256 nonce,
        uint256 fee
    );

    struct DepositParams {
        address token;
        uint256 amount;
        address l2Recipient;
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

    function depositWithMessage(
        address token,
        uint256 amount,
        address l2Recipient,
        uint256[] calldata message
    ) external payable returns (uint256) {
        //require(servicingTokens[token], "Token not serviced");
        //require(msg.value >= mockFee, "Insufficient fee");

        uint256 nonce = mockNonce++;
        
        lastDeposit = DepositParams({
            token: token,
            amount: amount,
            l2Recipient: l2Recipient,
            message: message,
            nonce: nonce,
            fee: mockFee
        });

        // emit DepositWithMessage(
        //     msg.sender,
        //     token,
        //     amount,
        //     l2Recipient,
        //     message,
        //     nonce,
        //     mockFee
        // );
    }

    function getLastDepositParams() external view returns (DepositParams memory) {
        return lastDeposit;
    }
    receive() external payable {}
}
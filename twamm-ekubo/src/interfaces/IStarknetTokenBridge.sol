// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.0;

interface IStarknetTokenBridge {
    function depositWithMessage(address token, uint256 amount, uint256 l2Recipient, uint256[] calldata message)
        external
        payable;

    function deposit(address token, uint256 amount, uint256 l2Recipient) external payable;
    function sendMessageToL2(uint256 l2Recipient, uint256 selector, uint256[] calldata payload) external payable;
    function estimateDepositFeeWei() external pure returns (uint256);
    function depositWithMessageCancelRequest(
        address token,
        uint256 amount,
        uint256 l2Recipient,
        uint256[] calldata message,
        uint256 nonce
    ) external;
    function depositWithMessageReclaim(
        address token,
        uint256 amount,
        uint256 l2Recipient,
        uint256[] calldata message,
        uint256 nonce
    ) external;

    function withdraw(address token, uint256 amount, address recipient) external;
}

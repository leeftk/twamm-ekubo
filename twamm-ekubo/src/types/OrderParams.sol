    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Helper struct for order parameters and payload encoding
struct OrderParams {
    address sender;
    uint256 sellToken;
    uint256 buyToken;
    uint128 fee;
    uint128 start;
    uint128 end;
    uint128 amount;
}

struct WithdrawalParams {
    address sender;
    address receiver;
    uint256 buyToken;
    uint64 order_id;
}
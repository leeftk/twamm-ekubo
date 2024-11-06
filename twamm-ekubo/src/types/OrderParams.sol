 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.20;
 
 /// @dev Helper struct for order parameters and payload encoding
    struct OrderParams {
        address sender;
        address sellToken;
        address buyToken;
        uint128 fee;
        uint128 start;
        uint128 end;
        uint128 amount;
    uint256 l2EndpointAddress;
}
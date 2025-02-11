// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.0;

import {OrderParams} from "../types/OrderParams.sol";

interface IL1TWAMMBridge {
    function validateBridge(address tokenAddress) external view returns (bool);

    function depositAndCreateOrder(address _token, OrderParams memory params) external payable;

    function initiateWithdrawal(OrderParams memory params, uint64 order_id) external payable;

    function initiateCancelDepositRequest(OrderParams memory params, uint256 nonce, uint64 _depositId) external;

    function initiateCancelDepositReclaim(OrderParams memory params, uint256 nonce, uint64 _depositId) external;
}

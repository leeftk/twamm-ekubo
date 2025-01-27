// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";
import {IStarknetMessaging} from "./interfaces/IStarknetMessaging.sol";
import {IStarknetTokenBridge} from "./interfaces/IStarknetTokenBridge.sol";
import {OrderParams} from "./types/OrderParams.sol";

interface IStarknetRegistry {
    function getBridge(address token) external view returns (address);
}

/// @title L1TWAMMBridge
/// @notice Facilitates bridging tokens from Ethereum (L1) to StarkNet (L2) for TWAMM orders
/// @dev Handles token deposits, withdrawals, and order creation across L1 and L2
contract L1TWAMMBridge is Ownable {
    using SafeERC20 for IERC20;

    // Updated constants visibility to internal
    uint256 internal constant TIME_SPACING_SIZE = 16;
    uint256 internal constant LOG_SCALE_FACTOR = 4;
    uint256 internal constant DEPOSIT_OPERATION = 0;
    uint256 internal constant WITHDRAWAL_OPERATION = 2;
    uint256 internal constant DEFAULT_NONCE = 1;
    uint256 internal constant WITHDRAWAL_PAYLOAD_SIZE = 8;
    uint256 internal constant DEPOSIT_PAYLOAD_SIZE = 7;
    uint256 internal constant ON_RECEIVE_SELECTOR =
        uint256(
            0x00f1149cade9d692862ad41df96b108aa2c20af34f640457e781d166c98dc6b0
        );

    // State variables
    IERC20 public immutable token;
    IStarknetTokenBridge public immutable starknetBridge;
    IStarknetRegistry public immutable starknetRegistry;
    IStarknetMessaging public immutable snMessaging =
        IStarknetMessaging(0xE2Bb56ee936fd6433DC0F6e7e3b8365C906AA057);
    uint256 public l2EndpointAddress;
    mapping(address => bool) public supportedTokens;

    // Events
    event DepositAndCreateOrder(
        address indexed l1Sender,
        uint256 indexed l2Recipient,
        uint256 amount,
        uint256 nonce
    );
    event WithdrawalInitiated(address indexed l1Recipient, uint64 order_id);
    event Deposit(
        address indexed l1Sender,
        uint256 indexed l2Recipient,
        uint256 amount
    );
    event SupportedTokenRemoved(address token);
    event L2EndpointAddressSet(uint256 l2EndpointAddress);

    // Errors
    error ZeroAddress(string context);
    error InvalidBridge();
    error InvalidTime();
    error NotSupportedToken();
    error ZeroValue();

    /// @notice Creates a new L1TWAMMBridge instance
    /// @param _token Address of the token to be bridged
    /// @param _starknetBridge Address of the StarkNet bridge contract
    /// @param _l2EndpointAddress Address of the L2 endpoint
    /// @param _starknetRegistry Address of the StarkNet registry contract
    constructor(
        address _token,
        address _starknetBridge,
        uint256 _l2EndpointAddress,
        address _starknetRegistry
    ) Ownable(msg.sender) {
        address[] memory addresses = new address[](3);
        addresses[0] = _token;
        addresses[1] = _starknetBridge;
        addresses[2] = _starknetRegistry;
        _validateAddresses(addresses, "constructor");

        token = IERC20(_token);
        starknetBridge = IStarknetTokenBridge(_starknetBridge);
        l2EndpointAddress = _l2EndpointAddress;
        starknetRegistry = IStarknetRegistry(_starknetRegistry);
        supportedTokens[_token] = true;
    }

    /// @notice Validates if a bridge exists for the given token
    /// @param tokenAddress The address of the token to validate
    /// @return bool True if a valid bridge exists, false otherwise
    function validateBridge(address tokenAddress) internal view returns (bool) {
        address bridge = starknetRegistry.getBridge(tokenAddress);
        return bridge != address(0);
    }

    /// @notice Deposits tokens and creates an order on L2
    /// @param params Order parameters including amount, tokens, time range, and fees
    /// @dev Requires msg.value to cover bridge fees
    function depositAndCreateOrder(
        address _token,
        OrderParams memory params
    ) external payable {
        if (!validateBridge(address(token))) revert InvalidBridge();
        if (msg.value == 0) revert ZeroValue();
        address tokenBridge = starknetRegistry.getBridge(address(_token));
        _handleTokenTransfer(params.amount, address(_token), tokenBridge);
        uint256[] memory payload = _encodeDepositPayload(
            msg.sender,
            params.sellToken,
            params.buyToken,
            params.fee,
            params.start,
            params.end,
            params.amount
        );
        IStarknetTokenBridge(tokenBridge).depositWithMessage{value: msg.value}(
            address(_token),
            params.amount,
            l2EndpointAddress,
            payload
        );

        emit DepositAndCreateOrder(
            msg.sender,
            l2EndpointAddress,
            params.amount,
            DEFAULT_NONCE
        );
    }

    /// @notice Initiates a withdrawal from L2 to L1
    /// @param receiver Address that will receive the withdrawn tokens
    /// @param params Order parameters including amount, tokens, time range, and fees
    /// @param order_id ID of the order to withdraw from
    /// @dev Requires msg.value to cover messaging fees
    function initiateWithdrawal(
        address receiver,
        OrderParams memory params
    ) external payable {
     uint256[] memory payload = _encodeWithdrawalPayload(
            receiver,
            params.sellToken,
            params.buyToken,
            params.fee,
            params.start,
            params.end,
            params.amount,
            order_id
        );

        _sendMessage(
            l2EndpointAddress,
            ON_RECEIVE_SELECTOR,
            payload,
            msg.value
        );

        // emit WithdrawalInitiated(msg.sender, order_id);
    }

    /// @notice Claims withdrawn tokens from L2 to L1
    /// @param _token Address of the token to withdraw
    /// @param _amount Amount of tokens to withdraw
    /// @param _recipient Address that will receive the withdrawn tokens
    /// @dev Uses the Starknet registry to find the appropriate bridge for the token
    function claimWithdrawal(
        address _token,
        uint256 _amount,
        address _recipient
    ) external {
        address tokenBridge = starknetRegistry.getBridge(_token);
        IStarknetTokenBridge(tokenBridge).withdraw(_token, _amount, _recipient);
    }

    /// @notice Initiates a request to cancel a deposit
    /// @param l1_token Address of the token deposited
    /// @param params Order parameters including amount, tokens, time range, and fees
    /// @param nonce Unique identifier for the deposit
    function initiateCancelDepositRequest(
        address l1_token,
        OrderParams memory params,
        uint256 nonce
    ) external {
        address tokenBridge = starknetRegistry.getBridge(address(token));
        uint256[] memory payload = _encodeDepositPayload(
            msg.sender,
            params.sellToken,
            params.buyToken,
            params.fee,
            params.start,
            params.end,
            params.amount
        );
        uint256 amount = params.amount;
        IStarknetTokenBridge(tokenBridge).depositWithMessageCancelRequest(
            l1_token,
            amount,
            l2EndpointAddress,
            payload,
            nonce
        );
    }

    /// @notice Reclaims tokens from a cancelled deposit
    /// @param l1_token Address of the token to reclaim
    /// @param params Order parameters including amount, tokens, time range, and fees
    /// @param nonce Unique identifier for the deposit
    function initiateCancelDepositReclaim(
        address l1_token,
        OrderParams memory params,
        uint256 nonce
    ) external {
        address tokenBridge = starknetRegistry.getBridge(address(token));
        uint256[] memory payload = _encodeDepositPayload(
            msg.sender,
            params.sellToken,
            params.buyToken,
            params.fee,
            params.start,
            params.end,
            params.amount
        );
        uint256 amount = params.amount;
        IStarknetTokenBridge(tokenBridge).depositWithMessageReclaim(
            l1_token,
            amount,
            l2EndpointAddress,
            payload,
            nonce
        );
    }

    // Internal functions
    /// @notice Validates an array of addresses
    /// @param addresses Array of addresses to validate
    /// @param errorContext Context string for error messages
    /// @dev Reverts if any address is zero
    function _validateAddresses(
        address[] memory addresses,
        string memory errorContext
    ) private pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == address(0)) revert ZeroAddress(errorContext);
        }
    }

    /// @notice Sends a message to L2
    /// @param contractAddress Target contract address on L2
    /// @param selector Function selector on L2
    /// @param payload Message payload
    function _sendMessage(
        uint256 contractAddress,
        uint256 selector,
        uint256[] memory payload,
        uint256 feePaid
    ) internal {
        snMessaging.sendMessageToL2{value: feePaid}(
            contractAddress,
            selector,
            payload
        );
    }

    /// @notice Handles the transfer of tokens from sender to bridge
    /// @param amount Amount of tokens to transfer
    /// @param tokenAddress Address of the token
    /// @param bridge Address of the bridge contract
    function _handleTokenTransfer(
        uint256 amount,
        address tokenAddress,
        address bridge
    ) private {
        IERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        IERC20(tokenAddress).approve(bridge, amount);
    }

    /// @notice Encodes the payload for a deposit operation
    /// @param sender Address of the sender
    /// @param sellToken Token to sell
    /// @param buyToken Token to buy
    /// @param fee Fee amount
    /// @param start Start time
    /// @param end End time
    /// @param amount Amount of tokens
    /// @return Encoded payload array
    function _encodeDepositPayload(
        address sender,
        uint256 sellToken,
        uint256 buyToken,
        uint256 fee,
        uint128 start,
        uint128 end,
        uint128 amount
    ) internal view returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](8);
        payload[0] = uint256(0); // deposit operation
        payload[1] = uint256(uint160(sender));
        payload[2] = sellToken;
        payload[3] = buyToken;
        payload[4] = uint256(fee);
        payload[5] = uint256(start);
        payload[6] = uint256(end);
        payload[7] = uint256(amount);
        return payload;
    }

    /// @notice Encodes the payload for a withdrawal operation
    /// @param sellToken Token to sell
    /// @param buyToken Token to buy
    /// @param fee Fee amount
    /// @param start Start time
    /// @param end End time
    /// @param amount Amount of tokens
    function _encodeWithdrawalPayload(
        address receiver,
        uint256 sellToken,
        uint256 buyToken,
        uint256 fee,
        uint128 start,
        uint128 end,
        uint128 amount
        uint64 order_id
    ) internal view returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](9);
        payload[0] = WITHDRAWAL_OPERATION;
        payload[1] = uint256(uint160(receiver));
        payload[2] = sellToken;
        payload[3] = buyToken;
        payload[4] = uint256(fee);
        payload[5] = uint256(start);
        payload[6] = uint256(end);
        payload[7] = uint256(amount);
        payload[8] = uint256(order_id)
        return payload;
    }
}

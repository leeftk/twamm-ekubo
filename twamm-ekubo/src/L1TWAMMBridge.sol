// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";
import {IStarknetMessaging} from "./interfaces/IStarknetMessaging.sol";
import {OrderParams} from "./types/OrderParams.sol";

interface IStarknetTokenBridge {
    function depositWithMessage(
        address token,
        uint256 amount,
        uint256 l2Recipient,
        uint256[] calldata message
    ) external payable;

    function deposit(
        address token,
        uint256 amount,
        uint256 l2Recipient
    ) external payable;
    function sendMessageToL2(
        uint256 l2Recipient,
        uint256 selector,
        uint256[] calldata payload
    ) external payable;
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
}

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
    address public immutable l2EkuboAddress;
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
    error InvalidTimeRange();
    error InvalidBridge();
    error InvalidTime();
    error NotSupportedToken();
    error ZeroValue();

    /// @notice Creates a new L1TWAMMBridge instance
    /// @param _token Address of the token to be bridged
    /// @param _starknetBridge Address of the StarkNet bridge contract
    /// @param _l2EkuboAddress Address of the L2 Ekubo contract
    /// @param _l2EndpointAddress Address of the L2 endpoint
    /// @param _starknetRegistry Address of the StarkNet registry contract
    constructor(
        address _token,
        address _starknetBridge,
        address _l2EkuboAddress,
        uint256 _l2EndpointAddress,
        address _starknetRegistry
    ) Ownable(msg.sender) {
        address[] memory addresses = new address[](4);
        addresses[0] = _token;
        addresses[1] = _starknetBridge;
        addresses[2] = _l2EkuboAddress;
        addresses[3] = _starknetRegistry;
        _validateAddresses(addresses, "constructor");

        token = IERC20(_token);
        starknetBridge = IStarknetTokenBridge(_starknetBridge);
        l2EkuboAddress = _l2EkuboAddress;
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
    function depositAndCreateOrder(OrderParams memory params) external payable {
        // if (!validateBridge(address(token))) revert InvalidBridge();
        if (msg.value == 0) revert ZeroValue();
        _validateTimeParams(params.start, params.end);
        // address tokenBridge = starknetRegistry.getBridge(address(token));
        _handleTokenTransfer(
            params.amount,
            address(token),
            address(starknetBridge)
        );
        uint256[] memory payload = _encodeDepositPayload(
            msg.sender,
            params.sellToken,
            params.buyToken,
            params.fee,
            params.start,
            params.end,
            params.amount
        );
        starknetBridge.depositWithMessage{value: msg.value}(
            address(token),
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
    /// @param receiver Address of the receiver
    /// @param order_id Amount of tokens to withdraw
    /// @param l1_token Address of the L1 token to receive
    /// @dev Requires msg.value to cover messaging fees
    function initiateWithdrawal(
        address receiver,
        address l1_token,
        uint64 order_id
    ) external payable {
        uint256[] memory message = _encodeWithdrawalPayload(
            msg.sender,
            receiver,
            l1_token,
            order_id
        );

        _sendMessage(
            l2EndpointAddress,
            ON_RECEIVE_SELECTOR,
            message,
            msg.value
        );

        emit WithdrawalInitiated(msg.sender, order_id);
    }

    /// @notice Initiates a request to cancel a deposit
    /// @param l1_token Address of the token deposited
    /// @param nonce Unique identifier for the deposit
    function initiateCancelDepositRequest(
        address l1_token,
        OrderParams memory params,
        uint256 nonce
    ) external {
        // address tokenBridge = starknetRegistry.getBridge(address(token));
        address tokenBridge = address(starknetBridge);
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
    /// @param nonce Unique identifier for the deposit
    function initiateCancelDepositReclaim(
        address l1_token,
        OrderParams memory params,
        uint256 nonce
    ) external {
        // address tokenBridge = starknetRegistry.getBridge(address(token));
        address tokenBridge = address(starknetBridge);
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

    /// @notice Updates the L2 endpoint address
    /// @param _l2EndpointAddress New L2 endpoint address
    /// @dev Can only be called by the contract owner
    function setL2EndpointAddress(
        uint256 _l2EndpointAddress
    ) external onlyOwner {
        l2EndpointAddress = _l2EndpointAddress;
        emit L2EndpointAddressSet(_l2EndpointAddress);
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

    /// @notice Validates start and end time parameters
    /// @param start Start time for the order
    /// @param end End time for the order
    /// @dev Reverts if times are invalid or out of range
    function _validateTimeParams(uint128 start, uint128 end) private view {
        if (start >= end) revert InvalidTimeRange();

        uint256 currentTime = block.timestamp;
        if (
            !_isTimeValid(currentTime, start) || !_isTimeValid(currentTime, end)
        ) {
            revert InvalidTime();
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
        IERC20(tokenAddress).approve(address(this), amount);
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
        uint256[] memory payload = new uint256[](9);
        payload[0] = uint256(0); // deposit operation
        payload[1] = uint256(uint160(sender));
        payload[2] = sellToken;
        payload[3] = buyToken;
        payload[4] = uint256(fee);
        payload[5] = uint256(start);
        payload[6] = uint256(end);
        payload[7] = uint256(amount);
        payload[8] = uint256(uint160(address(this)));
        return payload;
    }

    /// @notice Encodes the payload for a withdrawal operation
    /// @param sender Address of the sender
    /// @param l1Token Address of the L1 token

    /// @return Encoded payload array
    function _encodeWithdrawalPayload(
        address sender,
        address receiver,
        address l1Token,
        uint64 order_id
    ) internal view returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](6);
        payload[0] = WITHDRAWAL_OPERATION;
        payload[1] = uint256(uint160(sender));
        payload[2] = uint256(uint160(receiver));
        payload[3] = uint256(uint160(l1Token));
        payload[4] = uint256(order_id);
        payload[5] = uint256(uint160(address(this)));
        return payload;
    }

    /// @notice Validates if a given time is valid according to spacing rules
    /// @param now_ Current timestamp
    /// @param time Time to validate
    /// @return bool True if time is valid, false otherwise
    function _isTimeValid(
        uint256 now_,
        uint256 time
    ) internal pure returns (bool) {
        uint256 step;
        if (time <= (now_ + TIME_SPACING_SIZE)) {
            step = TIME_SPACING_SIZE;
        } else {
            uint256 timeDiff = time - now_;
            uint256 msbResult = _mostSignificantBit(timeDiff);
            uint256 power = LOG_SCALE_FACTOR * (msbResult / LOG_SCALE_FACTOR);
            step = 1 << power;
        }
        return time % step == 0;
    }

    /// @notice Calculates the most significant bit of a number
    /// @param x Number to analyze
    /// @return Position of the most significant bit
    function _mostSignificantBit(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 result = 0;
        while (x != 0) {
            x >>= 1;
            result += 1;
        }
        return result - 1;
    }

    /// @notice External function to validate time parameters
    /// @param start Start time to validate
    /// @param end End time to validate
    /// @return bool True if both times are valid
    function isTimeValidExternal(
        uint256 start,
        uint256 end
    ) external pure returns (bool) {
        return _isTimeValid(start, end);
    }
}

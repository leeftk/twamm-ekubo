// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IStarknetTokenBridge {
    function depositWithMessage(address token, uint256 amount, uint256 l2Recipient, uint256[] calldata message)
        external
        payable
        returns (uint256);}

interface IStarknetRegistry {
    function getBridge(address token) external view returns (address);
}

/// @title L1TWAMMBridge
/// @notice This contract facilitates bridging tokens from Ethereum (L1) to StarkNet (L2) for TWAMM orders
/// @dev Inherits from Ownable for access control
contract L1TWAMMBridge is Ownable {
    // State variables
    /// @notice The ERC20 token being bridged
    IERC20 public immutable token;
    /// @notice The StarkNet token bridge interface
    IStarknetTokenBridge public immutable starknetBridge;
    /// @notice The StarkNet registry interface
    IStarknetRegistry public immutable starknetRegistry;
    /// @notice The L2 bridge address on StarkNet
    address public immutable l2BridgeAddress;
    /// @notice The L2 Ekubo address on StarkNet
    address public immutable l2EkuboAddress;
    /// @notice The L2 endpoint address on StarkNet
    uint256 public l2EndpointAddress;

    // Events
    /// @notice Emitted when a deposit and order creation is initiated
    /// @param l1Sender The address of the sender on L1
    /// @param l2Recipient The address of the recipient on L2
    /// @param amount The amount of tokens being deposited
    /// @param nonce The nonce of the transaction
    event DepositAndCreateOrder(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount, uint256 nonce);

    /// @notice Emitted when a withdrawal is initiated
    /// @param l1Recipient The address of the recipient on L1
    /// @param amount The amount of tokens being withdrawn
    event WithdrawalInitiated(address indexed l1Recipient, uint256 amount);

    // Errors
    /// @notice Thrown when an unsupported token is used
    error L1TWAMMBridge__NotSupportedToken();
    /// @notice Thrown when an invalid time range is provided
    error L1TWAMMBridge__InvalidTimeRange();
    /// @notice Thrown when an invalid bridge is used
    error L1TWAMMBridge__InvalidBridge();

    // Mappings
    /// @notice Mapping to track supported tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Constructor to initialize the contract
    /// @param _token The address of the ERC20 token to be bridged
    /// @param _starknetBridge The address of the StarkNet token bridge
    /// @param _l2EkuboAddress The address of the L2 Ekubo contract
    /// @param _l2EndpointAddress The address of the L2 endpoint
    constructor(address _token, address _starknetBridge, address _l2EkuboAddress, uint256 _l2EndpointAddress, address _starknetRegistry)
        Ownable(msg.sender)
    {
        token = IERC20(_token);
        starknetBridge = IStarknetTokenBridge(_starknetBridge);
        l2EkuboAddress = _l2EkuboAddress;
        l2EndpointAddress = _l2EndpointAddress;
        supportedTokens[_token] = true;
        starknetRegistry = IStarknetRegistry(_starknetRegistry);
    }

    /// @notice Sets the L2 endpoint address
    /// @param _l2EndpointAddress The new L2 endpoint address
    function setL2EndpointAddress(uint256 _l2EndpointAddress) external onlyOwner {
        l2EndpointAddress = _l2EndpointAddress;
    }

    /// @notice Validates if a bridge exists for the given token
    /// @param tokenAddress The address of the token to validate
    /// @return A boolean indicating if the bridge is valid
    function validateBridge(address tokenAddress) internal view returns (bool) {
        address bridge = starknetRegistry.getBridge(tokenAddress);
        return bridge != address(0);
    }

    /// @notice Deposits tokens and creates a TWAMM order on L2
    /// @param amount The amount of tokens to deposit
    /// @param l2EndpointAddress The L2 endpoint address
    /// @param start The start time of the TWAMM order
    /// @param end The end time of the TWAMM order
    /// @param sellToken The address of the token to sell
    /// @param buyToken The address of the token to buy
    /// @param fee The fee for the TWAMM order
    function depositAndCreateOrder(
        uint128 amount,
        uint256 l2EndpointAddress,
        uint256 start,
        uint256 end,
        address sellToken,
        address buyToken,
        uint128 fee
    ) external payable {
       if (validateBridge(address(token)) == false) revert L1TWAMMBridge__InvalidBridge();
        // if (start >= end) revert L1TWAMMBridge__InvalidTimeRange();

        // // New time validation 
        // uint256 currentTime = block.timestamp;
        // if (!isTimeValid(currentTime, start) || !isTimeValid(currentTime, end)) {
        //     revert L1TWAMMBridge__InvalidTimeRange();
        // }

        token.transferFrom(msg.sender, address(this), amount);
        token.approve(address(starknetBridge), 0);
        token.approve(address(starknetBridge), amount);

        uint256[] memory payload = _encodeDepositPayload(msg.sender, sellToken, buyToken, fee, start, end, amount);
        uint256 nonce =
            starknetBridge.depositWithMessage{value: msg.value}(address(token), amount, l2EndpointAddress, payload);

        emit DepositAndCreateOrder(msg.sender, l2EndpointAddress, amount, nonce);
    }

    /// @notice Initiates a withdrawal of tokens from L2 to L1
    /// @param id The ID of the TWAMM order
    /// @param sellToken The address of the sell token in the order
    /// @param buyToken The address of the buy token in the order
    /// @param fee The fee associated with the order
    /// @param start The start time of the order
    /// @param end The end time of the order
    /// @param saleRateDelta The amount to decrease the sale rate by
    /// @param l1Recipient The address of the recipient on L1
    function initiateWithdrawal(
        uint64 id,
        address sellToken,
        address buyToken,
        uint128 fee,
        uint64 start,
        uint64 end,
        uint128 saleRateDelta,
        address l1Recipient
    ) external payable onlyOwner {
        if (validateBridge(address(token)) == false) revert L1TWAMMBridge__InvalidBridge();

        uint256[] memory payload = _encodeWithdrawalPayload(id, sellToken, buyToken, fee, start, end, saleRateDelta);
        starknetBridge.depositWithMessage{value: msg.value}(address(token), 0, l2EndpointAddress, payload);

        emit WithdrawalInitiated(l1Recipient, saleRateDelta);
    }

    /// @notice Encodes the payload for a deposit transaction
    /// @param sender The address of the sender
    /// @param sellToken The address of the token to sell
    /// @param buyToken The address of the token to buy
    /// @param fee The fee for the TWAMM order
    /// @param start The start time of the TWAMM order
    /// @param end The end time of the TWAMM order
    /// @param amount The amount of tokens to deposit
    /// @return A uint256 array containing the encoded payload
    function _encodeDepositPayload(
        address sender,
        address sellToken,
        address buyToken,
        uint128 fee,
        uint256 start,
        uint256 end,
        uint128 amount
    ) internal pure returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](8);
        payload[0] = 0; // Operation ID for buys
        payload[1] = uint256(uint160(sender));
        payload[2] = uint256(uint160(sellToken));
        payload[3] = uint256(uint160(buyToken));
        payload[4] = uint256(fee);
        payload[5] = uint256(uint64(start));
        payload[6] = uint256(uint64(end));
        payload[7] = uint256(amount);
        return payload;
    }

    /// @notice Encodes the payload for a withdrawal transaction
    /// @param id The ID of the TWAMM order
    /// @param sellToken The address of the sell token in the order
    /// @param buyToken The address of the buy token in the order
    /// @param fee The fee associated with the order
    /// @param start The start time of the order
    /// @param end The end time of the order
    /// @param saleRateDelta The amount to decrease the sale rate by
    /// @return A uint256 array containing the encoded payload
    function _encodeWithdrawalPayload(
        uint64 id,
        address sellToken,
        address buyToken,
        uint128 fee,
        uint64 start,
        uint64 end,
        uint128 saleRateDelta
    ) internal pure returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](8);
        payload[0] = 1; // Operation ID for withdrawals or sales
        payload[1] = uint256(id);
        payload[2] = uint256(uint160(sellToken));
        payload[3] = uint256(uint160(buyToken));
        payload[4] = uint256(fee);
        payload[5] = uint256(start);
        payload[6] = uint256(end);
        payload[7] = uint256(saleRateDelta);
        return payload;
    }

    /// @notice Removes a token from the list of supported tokens
    /// @param _token The address of the token to remove
    function removeSupportedToken(address _token) external onlyOwner {
        supportedTokens[_token] = false;
    }

    // New helper function for time validation
    function isTimeValid(uint256 now, uint256 time) internal pure returns (bool) {
        uint256 TIME_SPACING_SIZE = 16;
        uint8 LOG_SCALE_FACTOR = 4;

        if (time <= now) return false;

        uint256 step;
        if (time <= (now + TIME_SPACING_SIZE)) {
            step = TIME_SPACING_SIZE;
        } else {
            uint256 timeDiff = time - now;
            uint256 msb = mostSignificantBit(timeDiff);
            uint256 exponent = (msb / LOG_SCALE_FACTOR) * LOG_SCALE_FACTOR;
            step = 1 << exponent;
        }

        return time % step == 0;
    }

    // Helper function to find the most significant bit
    function mostSignificantBit(uint256 x) internal pure returns (uint8) {
        uint8 r = 0;
        while (x > 0) {
            x >>= 1;
            r++;
        }
        return r - 1;
    }
}

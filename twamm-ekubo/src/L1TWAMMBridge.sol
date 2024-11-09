// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OrderParams} from "./types/OrderParams.sol";
import "forge-std/console.sol";
import {IStarknetMessaging} from "./interfaces/IStarknetMessaging.sol";

interface IStarknetTokenBridge {
    function depositWithMessage(address token, uint256 amount, uint256 l2Recipient, uint256[] calldata message)
        external
        payable;

    function deposit(address token, uint256 amount, uint256 l2Recipient) external payable;

    function sendMessageToL2(uint256 l2Recipient, uint256 selector, uint256[] calldata payload) external payable;
}

interface IStarknetRegistry {
    function getBridge(address token) external view returns (address);
}

/// @title L1TWAMMBridge
/// @notice Facilitates bridging tokens from Ethereum (L1) to StarkNet (L2) for TWAMM orders
contract L1TWAMMBridge is Ownable {
    using SafeERC20 for IERC20;

    // Updated constants visibility to internal
    uint256 internal constant TIME_SPACING_SIZE = 16;
    uint256 internal constant LOG_SCALE_FACTOR = 4;
    uint256 internal constant DEPOSIT_OPERATION = 0;
    uint256 internal constant WITHDRAWAL_OPERATION = 1;
    uint256 internal constant DEFAULT_NONCE = 1;
    uint256 internal constant WITHDRAWAL_PAYLOAD_SIZE = 8;
    uint256 internal constant DEPOSIT_PAYLOAD_SIZE = 8;
    uint256 internal constant ON_RECEIVE_SELECTOR =
        uint256(0x00f1149cade9d692862ad41df96b108aa2c20af34f640457e781d166c98dc6b0);

    // State variables
    IERC20 public immutable token;
    IStarknetTokenBridge public immutable starknetBridge;
    IStarknetRegistry public immutable starknetRegistry;
    IStarknetMessaging public immutable snMessaging = IStarknetMessaging(0xE2Bb56ee936fd6433DC0F6e7e3b8365C906AA057);
    address public immutable l2EkuboAddress;
    uint256 public l2EndpointAddress;
    mapping(address => bool) public supportedTokens;

    // Events
    event DepositAndCreateOrder(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount, uint256 nonce);
    event WithdrawalInitiated(address indexed l1Recipient, uint256 amount);
    event Deposit(address indexed l1Sender, uint256 indexed l2Recipient, uint256 amount);
    event SupportedTokenRemoved(address token);
    event L2EndpointAddressSet(uint256 l2EndpointAddress);

    // Errors
    error ZeroAddress(string context);
    error InvalidTimeRange();
    error InvalidBridge();
    error InvalidTime();
    error NotSupportedToken();

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
    function validateBridge(address tokenAddress) internal view returns (bool) {
        address bridge = starknetRegistry.getBridge(tokenAddress);
        return bridge != address(0);
    }

    function depositAndCreateOrder(OrderParams memory params) external payable {
        //if (!validateBridge(address(token))) revert InvalidBridge();

        _validateTimeParams(params.start, params.end);
        _handleTokenTransfer(params.amount, address(token), address(starknetBridge));

        uint256[] memory payload = _encodeDepositPayload(params);
       
        _depositWithMessage(params.amount, payload);

        emit DepositAndCreateOrder(msg.sender, l2EndpointAddress, params.amount, DEFAULT_NONCE);
    }

    // function initiateWithdrawal(address sellToken, address l1Recipient, uint128 amount) external payable onlyOwner {
    //     if (!validateBridge(address(token))) revert InvalidBridge();

    //     //uint256[] memory payload = _encodeWithdrawalPayload(sellToken, l1Recipient, amount, 0);
    //     starknetBridge.depositWithMessage{value: msg.value}(address(token), 0, l2EndpointAddress, payload);

    //     emit WithdrawalInitiated(l1Recipient, amount);
    // }

    function removeSupportedToken(address _token) external onlyOwner {
        supportedTokens[_token] = false;
        emit SupportedTokenRemoved(_token);
    }

    function deposit(uint256 amount, uint256 l2Recipient) external payable {
        token.approve(address(starknetBridge), amount);
        starknetBridge.deposit{value: msg.value}(address(token), amount, l2EndpointAddress);
    }

    
    function initiateWithdrawal(uint256 tokenId) external payable {
        //if (!validateBridge(address(token))) revert InvalidBridge();
        uint256[] memory message = new uint256[](8); //Padding this payload with zeroes to match the struct params on L2
        message[0] = 2;
        message[1] = 0;
        message[2] = 0;
        message[3] = 0;
        message[4] = 0;
        message[5] = 0;
        message[6] = 0;
        message[7] = 0;

        _sendMessage(l2EndpointAddress, ON_RECEIVE_SELECTOR, message);

        emit WithdrawalInitiated(msg.sender, tokenId);
    }

    /// @notice Sets the L2 endpoint address
    function setL2EndpointAddress(uint256 _l2EndpointAddress) external onlyOwner {
        l2EndpointAddress = _l2EndpointAddress;
        emit L2EndpointAddressSet(_l2EndpointAddress);
    }

    // Internal functions
    function _validateAddresses(address[] memory addresses, string memory errorContext) private pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == address(0)) revert ZeroAddress(errorContext);
        }
    }

    function _validateTimeParams(uint128 start, uint128 end) private view {
        if (start >= end) revert InvalidTimeRange();

        uint256 currentTime = block.timestamp;
        if (!_isTimeValid(currentTime, start) || !_isTimeValid(currentTime, end)) {
            revert InvalidTime();
        }
    }

    /// @notice Deposits tokens and sends a message to L2
    /// @dev This function splits the value sent, half for the deposit and half for the message fee, to avoid an out of funds error
    function _depositWithMessage(uint256 amount,  uint256[] memory message) public payable {
        uint256 value_allocated = msg.value / 2;
       starknetBridge.deposit{value: value_allocated}(address(token), amount, l2EndpointAddress);
       snMessaging.sendMessageToL2{value: value_allocated}(l2EndpointAddress, ON_RECEIVE_SELECTOR, message);
    }


    function _sendMessage(uint256 contractAddress, uint256 selector, uint256[] memory payload) public payable {
        snMessaging.sendMessageToL2{value: msg.value/2}(contractAddress, selector, payload);
    }

    function _handleTokenTransfer(uint256 amount, address tokenAddress, address bridge) private {
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(tokenAddress).approve(bridge, 0);
        IERC20(tokenAddress).approve(bridge, amount);
    }

    function _encodeDepositPayload(OrderParams memory params) internal pure returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](DEPOSIT_PAYLOAD_SIZE);

        payload[0] = DEPOSIT_OPERATION;
        payload[1] = uint256(uint160(params.sender));
        payload[2] = uint256(params.sellToken);
        payload[3] = uint256(params.buyToken);
        payload[4] = uint256(params.fee);
        payload[5] = uint256(params.start);
        payload[6] = uint256(params.end);
        payload[7] = uint256(params.amount);

        return payload;
    }

    // function _encodeWithdrawalPayload(address sellToken, address l1Recipient, uint128 amount, uint256 message)
    //     internal
    //     pure
    //     returns (uint256[] memory)
    // {
    //     uint256[] memory payload = new uint256[](WITHDRAWAL_PAYLOAD_SIZE);
    //     payload[0] = WITHDRAWAL_OPERATION;
    //     payload[1] = uint256(params.sellToken);
    //     payload[2] = uint256(uint160(l1Recipient));
    //     payload[3] = uint256(amount);
    //     payload[4] = message;
    //     return payload;
    // }

    function _isTimeValid(uint256 now_, uint256 time) internal pure returns (bool) {
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

    function _mostSignificantBit(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 result = 0;
        while (x != 0) {
            x >>= 1;
            result += 1;
        }
        return result - 1;
    }

    // External view functions
    function isTimeValidExternal(uint256 start, uint256 end) external view returns (bool) {
        return _isTimeValid(start, end);
    }
}

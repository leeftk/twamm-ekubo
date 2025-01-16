use starknet::{ContractAddress, get_contract_address, contract_address_const, get_caller_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess,
};
use ekubo::extensions::interfaces::twamm::{OrderKey, OrderInfo};
use ekubo::types::keys::PoolKey;
use ekubo::types::i129::{i129};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};
use starknet::EthAddress;
use super::token_bridge_helper::{
    ITokenBridgeHelper, ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait,
};
use super::types::{OrderDetails, OrderKey_Copy, WithdrawalDetails};
use super::interfaces::{
    ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait, IERC20, IERC20Dispatcher,
    IERC20DispatcherTrait,
};
use super::order_manager::OrderManagerComponent;
use super::errors::{ERROR_UNAUTHORIZED, ERROR_INVALID_L1_ADDRESS};


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn set_token_bridge_helper(ref self: TContractState, address: ContractAddress);
    fn set_l1_contract_address(ref self: TContractState, address: EthAddress);
    fn get_contract_owner(self: @TContractState) -> ContractAddress;
    fn get_token_bridge_helper(self: @TContractState) -> ContractAddress;
    fn get_l1_contract_address(self: @TContractState) -> EthAddress;
    fn on_receive(
        ref self: TContractState,
        l2_token: ContractAddress,
        amount: u256,
        depositor: EthAddress,
        message: Span<felt252>,
    ) -> bool;
}

#[starknet::contract]
mod L2TWAMMBridge {
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::extensions::interfaces::twamm::{OrderKey};
    use starknet::{
        ContractAddress, get_contract_address, contract_address_const, get_block_timestamp,
    };

    use super::{
        Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess,
    };
    use super::{ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::EthAddress;
    use super::{get_caller_address};
    use core::array::ArrayTrait;
    use super::OrderDetails;
    use super::WithdrawalDetails;
    use super::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use super::OrderKey_Copy;
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
    use super::OrderManagerComponent;
    use super::{ERROR_UNAUTHORIZED, ERROR_INVALID_L1_ADDRESS};

    // Manages order-related operations
    component!(path: OrderManagerComponent, storage: order_manager, event: OrderManagerEvent);

    // Storage
    #[storage]
    pub struct Storage {
        contract_owner_address: ContractAddress,
        token_bridge_helper: ContractAddress,
        l1_contract_address: EthAddress,
        #[substorage(v0)]
        order_manager: OrderManagerComponent::Storage,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MessageReceived: MessageReceived,
        #[flat]
        OrderManagerEvent: OrderManagerComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct MessageReceived {
        message: OrderDetails,
    }

    // Core Order Manager operations
    impl OrderManagerImpl = OrderManagerComponent::OrderManagerImpl<ContractState>;

    // constructor
    #[constructor]
    fn constructor(ref self: ContractState, contract_owner: ContractAddress) {
        self.contract_owner_address.write(contract_owner);
    }

    //l1_handler
    #[l1_handler]
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: WithdrawalDetails) {
        if data.order_operation == 2 {
            self.handle_withdrawal(data);
        }
    }


    // External Functions
    #[external(v0)]
    #[abi(embed_v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {
        fn on_receive(
            ref self: ContractState,
            l2_token: ContractAddress,
            amount: u256,
            depositor: EthAddress,
            message: Span<felt252>,
        ) -> bool {
            // Create order or execute deposit with these parameters
            let message_struct = self.order_manager.span_to_order_details(message);
            if message_struct.order_operation == 0 {
                self.handle_deposit(message_struct);
            } else {
                return false;
            }
            return true;
        }

        // Admin functionsto set token bridge helper address
        fn set_token_bridge_helper(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.token_bridge_helper.write(address);
        }

        fn set_l1_contract_address(ref self: ContractState, address: EthAddress) {
            self.assert_only_owner();
            self.l1_contract_address.write(address);
        }
        // View functions
        fn get_contract_owner(self: @ContractState) -> ContractAddress {
            return self.contract_owner_address.read();
        }

        fn get_l1_contract_address(self: @ContractState) -> EthAddress {
            return self.l1_contract_address.read();
        }

        fn get_token_bridge_helper(self: @ContractState) -> ContractAddress {
            return self.token_bridge_helper.read();
        }
    }

    // Internal helper functions
    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        // Processes deposit message from L1
        fn handle_deposit(ref self: ContractState, message: OrderDetails) {
            let l1_contract_address = self.l1_contract_address.read();
            assert(
                message.l1_contract.try_into().unwrap() == l1_contract_address,
                ERROR_INVALID_L1_ADDRESS,
            );
            self.order_manager.execute_deposit(message);
        }
        // Processes withdrawal message from L1
        fn handle_withdrawal(ref self: ContractState, message: WithdrawalDetails) {
            let l1_contract_address = self.l1_contract_address.read();
            assert(
                message.l1_contract.try_into().unwrap() == l1_contract_address,
                ERROR_INVALID_L1_ADDRESS,
            );
            self.order_manager.execute_withdrawal(message, self.token_bridge_helper.read());
        }
        // Only Owner modifier
        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner_address.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }
    }
}


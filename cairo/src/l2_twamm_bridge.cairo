use starknet::{ContractAddress, EthAddress, get_caller_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess,
};
use super::token_bridge_helper::{
    ITokenBridgeHelper, ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait,
};
use super::types::{OrderDetails};
use super::order_manager::OrderManagerComponent;
use super::errors::{ERROR_UNAUTHORIZED};


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn set_token_bridge_helper(ref self: TContractState, address: ContractAddress);
    fn get_contract_owner(self: @TContractState) -> ContractAddress;
    fn get_token_bridge_helper(self: @TContractState) -> ContractAddress;
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
    use super::{
        Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess, EthAddress, ContractAddress, get_caller_address,
    };
    use super::OrderDetails;
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
    use super::OrderManagerComponent;
    use super::{ERROR_UNAUTHORIZED};

    // Manages order-related operations
    component!(path: OrderManagerComponent, storage: order_manager, event: OrderManagerEvent);

    // Storage
    #[storage]
    pub struct Storage {
        contract_owner_address: ContractAddress,
        token_bridge_helper: ContractAddress,
        #[substorage(v0)]
        order_manager: OrderManagerComponent::Storage,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OrderManagerEvent: OrderManagerComponent::Event,
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
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: OrderDetails) {
        self.handle_withdrawal(data);
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
            self.handle_deposit(message_struct);
            return true;
        }

        // Admin functions to set token bridge helper address
        fn set_token_bridge_helper(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.token_bridge_helper.write(address);
        }

        // View functions
        fn get_contract_owner(self: @ContractState) -> ContractAddress {
            return self.contract_owner_address.read();
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
            self.order_manager.execute_deposit(message);
        }
        // Processes withdrawal message from L1
        fn handle_withdrawal(ref self: ContractState, message: OrderDetails) {
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


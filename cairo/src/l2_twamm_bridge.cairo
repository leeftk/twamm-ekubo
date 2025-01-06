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
use super::types::{OrderDetails, OrderKey_Copy};
use super::interfaces::{
    ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait, IERC20, IERC20Dispatcher,
    IERC20DispatcherTrait,
};
use super::order_manager::OrderManagerComponent;
use super::errors::{ERROR_UNAUTHORIZED};


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn set_token_bridge_helper(ref self: TContractState, address: ContractAddress);
    fn get_contract_owner(self: @TContractState) -> ContractAddress;
    fn get_token_bridge_helper(self: @TContractState) -> ContractAddress;
    fn to_order_details(ref self: TContractState, span: Span<felt252>) -> OrderDetails;
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
    use super::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use super::OrderKey_Copy;
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
    use super::OrderManagerComponent;
    use super::ERROR_UNAUTHORIZED;

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
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: OrderDetails) {
      if data.order_operation == 2 {
            self.emit(MessageReceived { message: data });
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
            let message_struct = self.to_order_details(message);
            self.emit(MessageReceived { message: message_struct });
            if message_struct.order_operation == 0 {
            // Create order or execute deposit with these parameters
                self.handle_deposit(message_struct)
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

        // View functions

        fn get_contract_owner(self: @ContractState) -> ContractAddress {
            return self.contract_owner_address.read();
        }

        fn get_token_bridge_helper(self: @ContractState) -> ContractAddress {
            return self.token_bridge_helper.read();
        }

        fn to_order_details(ref self: ContractState, span: Span<felt252>) -> OrderDetails {
            assert(span.len() == 8, 'Invalid span length');

            let mut data = span.snapshot;
            let order_operation = *data[0];
            let sender = *data[1];
            let sell_token = *data[2];
            let buy_token = *data[3];
            let fee = *data[4];
            let start = *data[5];
            let end = *data[6];
            let amount = *data[7];

            return OrderDetails {
                order_operation, sender, sell_token, buy_token, fee, start, end, amount,
            };
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
//0x26aece05eedcf29505f498ee637e2595c65944423abe26175677e484a72c3af


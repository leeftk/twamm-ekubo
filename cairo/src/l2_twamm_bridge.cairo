use starknet::{ContractAddress, get_contract_address, contract_address_const, get_caller_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use ekubo::extensions::interfaces::twamm::{OrderKey, OrderInfo};
use ekubo::types::keys::PoolKey;
use ekubo::types::i129::{i129};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};
use starknet::EthAddress;
use super::token_bridge_helper::{ITokenBridgeHelper, ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
use super::types::{OrderDetails, OrderKey_Copy};
use super::interfaces::{ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait, IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use super::order_manager::OrderManagerComponent;


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
    fn set_token_bridge_address(ref self: TContractState, address: ContractAddress);
    fn set_token_bridge_helper(ref self: TContractState, address: ContractAddress);
}

#[starknet::contract]
mod L2TWAMMBridge {
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::extensions::interfaces::twamm::{OrderKey};
    use starknet::{ContractAddress, get_contract_address, contract_address_const, get_block_timestamp};

    use super::{Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess};
    use super::{ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::EthAddress;
    use super::{get_caller_address};
    use core::array::ArrayTrait;
    use super::OrderDetails;
    use super::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use super::OrderKey_Copy;
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait };
    use super::OrderManagerComponent;

    component!(path: OrderManagerComponent, storage: order_manager, event: OrderManagerEvent);

    const ERROR_NO_TOKENS_MINTED: felt252 = 'No tokens minted';
    const ERROR_NO_TOKENS_SOLD: felt252 = 'No tokens sold';
    const ERROR_NOT_ORDER_OWNER: felt252 = 'Not order owner';
    const ERROR_INVALID_ADDRESS: felt252 = 'Invalid address';
    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';
    const ERROR_ZERO_AMOUNT: felt252 = 'Amount cannot be zero';
    const ALREADY_WITHDRAWN: felt252 = 'Order has been withdrawn';

    #[storage]
    pub struct Storage {
        sender_to_amount: Map::<EthAddress, u256>,
        positions_address: ContractAddress,
        token_bridge_address: ContractAddress,
        contract_owner_address: ContractAddress,
        token_bridge_helper: ContractAddress,
        order_manager_address: ContractAddress,

        #[substorage(v0)]
        order_manager: OrderManagerComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MessageReceived: MessageReceived,
        #[flat]
        OrderManagerEvent: OrderManagerComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct MessageReceived {
        message: OrderDetails
    }
  
    impl OrderManagerImpl = OrderManagerComponent::OrderManagerImpl<ContractState>;

    #[constructor]
    fn constructor(ref self: ContractState, contract_owner: ContractAddress) {
        self.contract_owner_address.write(contract_owner);
    }


    #[l1_handler]
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: OrderDetails) {
        if data.order_operation == 0 {
            self.emit(MessageReceived { message: data });
            self.handle_deposit(data);
        }
        else if data.order_operation == 2 {
            self.emit(MessageReceived { message: data });
           self.handle_withdrawal(data);        
        } 
    }

    #[external(v0)]
    fn get_contract_owner(self: @ContractState) -> ContractAddress {
       return self.contract_owner_address.read();
    }

    #[external(v0)]
    fn get_token_bridge_helper(self: @ContractState) -> ContractAddress {
        return self.token_bridge_helper.read();
    }

    #[external(v0)]
    #[abi(embed_v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {

        fn set_token_bridge_address(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.token_bridge_address.write(address);
        }

        fn set_positions_address(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.positions_address.write(address);
        }
        fn set_token_bridge_helper(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.token_bridge_helper.write(address);
        } 
    }
    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {

        fn handle_deposit(ref self: ContractState, message: OrderDetails) {
            self.order_manager.execute_deposit(message);
        }

        fn handle_withdrawal(ref self: ContractState, message: OrderDetails) {
            self.order_manager.execute_withdrawal(message, self.positions_address.read(), self.token_bridge_helper.read());
        }

        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner_address.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }
    }
}
//contract_address: 0x2c9b0e967948762be38c87ac131d2958f7988d6aff58885993f1c186a5333b8
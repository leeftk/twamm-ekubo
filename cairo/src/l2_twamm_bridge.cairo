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
use super::order_manager::{IOrderManagerDispatcher, IOrderManagerDispatcherTrait};
use super::types::{MyData, OrderKey_Copy};


#[starknet::interface]
pub(crate) trait IERC20<TContractState> {
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, account: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait ITokenBridge<TContractState> {
    fn initiate_token_withdraw(
        ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256
    );
    fn handle_deposit(
        ref self: TContractState,
        from_address: felt252,
        l2_recipient: ContractAddress,
        amount: u256,
    );
}

#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
    fn set_token_bridge_address(ref self: TContractState, address: ContractAddress);
    fn set_token_bridge_helper(ref self: TContractState, address: ContractAddress);
    fn set_order_manager(ref self: TContractState, address: ContractAddress);
    fn send_token_to_l1(ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256);
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
    use super::MyData;
    use super::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use super::OrderKey_Copy;
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait };
    use super::{IOrderManagerDispatcher, IOrderManagerDispatcherTrait};

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
        order_id_to_depositor: Map::<u64, EthAddress>,
        order_depositor_to_id: Map::<EthAddress, u64>,
        order_depositor_to_id_to_withdrawal_status: Map::<EthAddress, Map<u64, bool>>,
        contract_owner: ContractAddress,
        token_bridge_helper: ContractAddress,
        order_manager: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MessageReceived: MessageReceived,
    }

    #[derive(Drop, starknet::Event)]
    struct MessageReceived {
        message: MyData
    }


    #[constructor]
    fn constructor(ref self: ContractState, contract_owner: ContractAddress) {
        self.contract_owner.write(contract_owner);
    }


    #[l1_handler]
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: MyData) {
        if data.deposit_operation == 0 {
            self.emit(MessageReceived { message: data });
            self.handle_deposit(data);
            } else if data.deposit_operation == 2 {
            self.emit(MessageReceived { message: data });
           self.handle_withdrawal(data);        
        } 
        else if data.deposit_operation == 3 {
            self.emit(MessageReceived { message: data });
            self.send_token_to_l1(data.buy_token.try_into().unwrap(), data.sender.try_into().unwrap(), data.amount.try_into().unwrap());
        }
    }

    #[external(v0)]
    fn get_contract_owner(self: @ContractState) -> ContractAddress {
       return self.contract_owner.read();
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

        fn set_order_manager(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.order_manager.write(address);
        }
        
        fn send_token_to_l1(ref self: ContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256) {
            let helper = ITokenBridgeHelperDispatcher { contract_address: self.token_bridge_helper.read() };
            helper.send_token_to_l1(l1_token, l1_recipient, amount);
        }
       
    }
    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {

        fn handle_deposit(ref self: ContractState, message: MyData) {
            let order_manager = IOrderManagerDispatcher { contract_address: self.order_manager.read() };
            order_manager.execute_deposit(message);
        }

        fn handle_withdrawal(ref self: ContractState, message: MyData) {
            let order_manager = IOrderManagerDispatcher { contract_address: self.order_manager.read() };
            order_manager.execute_withdrawal(message, self.positions_address.read(), self.token_bridge_helper.read());
        }

        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }
    }
}
//contract_address: 0x3ab3e22ed982eee791557781ca80a3859afc78f5e6cce579d15bed1fa66972
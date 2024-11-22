use starknet::{ContractAddress, get_contract_address, contract_address_const, get_caller_address, get_block_timestamp};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use ekubo::extensions::interfaces::twamm::{OrderKey};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use starknet::EthAddress;
use super::types::{MyData, OrderKey_Copy};

#[derive(Drop, Serde, starknet::Store)]
struct Order_Created {
    order_key: OrderKey_Copy,
    id: u64,
} 

#[starknet::interface]
trait IOrderManager<TContractState> {
    fn create_order_key(ref self: TContractState, message: MyData) -> OrderKey;
    fn decode_order_key_from_stored_copy(ref self: TContractState, message: OrderKey_Copy) -> OrderKey;
    fn execute_deposit(ref self: TContractState, message: MyData) -> (u64, OrderKey);
    fn execute_withdrawal(ref self: TContractState, message: MyData, positions_address: ContractAddress) -> u128;
    fn get_depositor_from_id(ref self: TContractState, id: u64) -> EthAddress;
    fn get_id_from_depositor(ref self: TContractState, depositor: EthAddress) -> u64;
    fn get_withdrawal_status(ref self: TContractState, depositor: EthAddress, id: u64) -> bool;
    fn get_order_created(ref self: TContractState, depositor: EthAddress) -> Order_Created;
}

#[starknet::contract]
mod OrderManager {
    use super::{OrderKey, OrderKey_Copy, MyData, Order_Created, EthAddress, ContractAddress};
    use super::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePath,
        StoragePathEntry, IPositionsDispatcher, IPositionsDispatcherTrait};
    use starknet::{get_block_timestamp, get_caller_address, contract_address_const, get_contract_address};

    const ERROR_NO_TOKENS_MINTED: felt252 = 'No tokens minted';
    const ERROR_ZERO_AMOUNT: felt252 = 'Amount cannot be zero';
    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';

    #[storage]
    struct Storage {
        order_id_to_depositor: Map::<u64, EthAddress>,
        order_depositor_to_id: Map::<EthAddress, u64>,
        order_depositor_to_id_to_withdrawal_status: Map::<EthAddress, Map<u64, bool>>,
        order_depositor_to_order_created: Map::<EthAddress, Order_Created>,
        contract_owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.contract_owner.write(get_caller_address());
    }

    #[external(v0)]
    impl OrderManager of super::IOrderManager<ContractState> {
        fn create_order_key(ref self: ContractState, message: MyData) -> OrderKey {
            OrderKey {
                sell_token: (message.sell_token).try_into().unwrap(),
                buy_token: (message.buy_token).try_into().unwrap(),
                fee: (message.fee).try_into().unwrap(),
                start_time: (message.start).try_into().unwrap(),
                end_time: (message.end).try_into().unwrap(),
            }
        }

        fn decode_order_key_from_stored_copy(ref self: ContractState, message: OrderKey_Copy) -> OrderKey {
            OrderKey {
                sell_token: message.sell_token,
                buy_token: message.buy_token,
                fee: message.fee,
                start_time: message.start_time,
                end_time: message.end_time,
            }
        }

        fn execute_deposit(
            ref self: ContractState, message: MyData
        ) -> (u64, OrderKey) {
            let current_timestamp = get_block_timestamp();
            let difference = 16 - (current_timestamp % 16);
            let start_time = (current_timestamp + difference);
            let end_time = start_time + 64;

            let new_sell_token: ContractAddress = (message.sell_token).try_into().unwrap();
            let new_buy_token: ContractAddress = (message.buy_token).try_into().unwrap();
            let new_fee: u128 = (message.fee).try_into().unwrap();

            let order_key = OrderKey {
                sell_token: new_sell_token,
                buy_token: new_buy_token,
                fee: new_fee,
                start_time: start_time,
                end_time: end_time,
            };

            let order_key_copy = OrderKey_Copy {
                sell_token: new_sell_token,
                buy_token: new_buy_token,
                fee: new_fee,
                start_time: start_time,
                end_time: end_time,
            };

            let positions = IPositionsDispatcher {
                contract_address: contract_address_const::<
                0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5>()
            };

            let amount_u128: u128 = message.amount.try_into().unwrap();
            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount_u128);
            
            assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            assert(id != 0, ERROR_ZERO_AMOUNT);
            
            self.order_depositor_to_id.write(message.sender.try_into().unwrap(), id);
            self.order_id_to_depositor.write(id, message.sender.try_into().unwrap());
            self.order_depositor_to_order_created.write(
                message.sender.try_into().unwrap(), 
                Order_Created { order_key: order_key_copy, id: id }
            );

            (id, order_key)
        }

        fn execute_withdrawal(
            ref self: ContractState, 
            message: MyData,
            positions_address: ContractAddress
        ) -> u128 {
            let depositor: EthAddress = message.sender.try_into().unwrap();
            let order_created = self.order_depositor_to_order_created.read(depositor);
            
            let order_key = self.decode_order_key_from_stored_copy(order_created.order_key);
            let id: u64 = order_created.id;
            
            let user = self.get_depositor_from_id(id);
            let withdrawal_status = self.get_withdrawal_status(depositor, id);

            assert(user == depositor, ERROR_ZERO_AMOUNT);
            assert(withdrawal_status == false, ERROR_ZERO_AMOUNT);

            let positions = IPositionsDispatcher { contract_address: positions_address };
            let this_contract_address = get_contract_address();
            
            positions.withdraw_proceeds_from_sale_to(id, order_key, this_contract_address)
        }

        fn get_depositor_from_id(ref self: ContractState, id: u64) -> EthAddress {
            self.order_id_to_depositor.read(id)
        }

        fn get_id_from_depositor(ref self: ContractState, depositor: EthAddress) -> u64 {
            self.order_depositor_to_id.read(depositor)
        }

        fn get_withdrawal_status(ref self: ContractState, depositor: EthAddress, id: u64) -> bool {
            self.order_depositor_to_id_to_withdrawal_status.entry(depositor).entry(id).read()
        }

        fn get_order_created(ref self: ContractState, depositor: EthAddress) -> Order_Created {
            self.order_depositor_to_order_created.read(depositor)
        }
    }
}
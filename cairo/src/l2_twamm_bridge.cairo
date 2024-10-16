use starknet::{ContractAddress, get_contract_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use super::types::order_key::OrderKey;
use super::types::pool_key::PoolKey;
use crate::types::i129::i129;


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn on_receive(
        ref self: TContractState,
        l2_token: ContractAddress,
        amount: u256,
        depositor: ContractAddress,
        message: Span<felt252>
    ) -> bool;
    fn get_contract_version(self: @TContractState) -> felt252;
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
}

#[starknet::interface]
pub trait IPositions<TContractState> {
    fn mint_and_increase_sell_amount(
        ref self: TContractState, order_key: OrderKey, amount: u128
    ) -> (u64, u128);
}

#[starknet::interface]
pub trait ICore<TContractState> {
    // Initialize a pool. This can happen outside of a lock callback because it does not require any
    // tokens to be spent.
    fn initialize_pool(ref self: TContractState, pool_key: PoolKey, initial_tick: i129) -> u256;
}


#[starknet::contract]
mod L2TWAMMBridge {
    use super::IPositions;
    use super::IPositionsDispatcher;
    use super::OrderKey;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        sender_to_amount: Map::<ContractAddress, u128>,
        positions_address: ContractAddress,
    }


    #[external(v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {
        fn on_receive(
            ref self: ContractState,
            l2_token: ContractAddress,
            amount: u256,
            depositor: ContractAddress,
            message: Span<felt252>
        ) -> bool {
            assert(message.len() >= 5, 'Invalid message length');

            //on_receive should decode the message and assign the values to the order_key
            let mut message_span = message;
            let order_key: OrderKey = Serde::<OrderKey>::deserialize(ref message_span).unwrap();

            let position_address = starknet::contract_address_const::<
                0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
            >();
            let positions = IPositionsDispatcher { contract_address: position_address };
            let (minted_amount, new_sell_amount) =
            positions.mint_and_increase_sell_amount(order_key, amount);
            true
        }

        fn set_positions_address(ref self: ContractState, address: ContractAddress) {
            self.positions_address.write(address);
        }

        fn get_contract_version(self: @ContractState) -> felt252 {
            'L2TWAMMBridge v1.0'
        }
    }
}



//notes on whats left
//First let's import all of the interfaces from the Ekubo repo

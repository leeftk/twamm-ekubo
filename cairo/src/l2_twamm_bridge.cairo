use starknet::{ContractAddress, get_contract_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use crate::types::order_key::OrderKey;


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn on_receive(ref self: TContractState, l2_token: ContractAddress, amount: u256, depositor: felt252, message: Span<felt252>) -> bool;
    fn get_contract_version(self: @TContractState) -> felt252;
    fn mint_and_increase_sell_amount(ref self: TContractState, order_key: OrderKey, amount: u128) -> (u64, u128);
}

#[starknet::contract]
mod L2TWAMMBridge {
    use super::OrderKey;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        sender_to_amount: Map::<ContractAddress, u128>,
    }

    #[external(v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {
        fn on_receive(
            ref self: ContractState,
            l2_token: ContractAddress,
            amount: u256,
            depositor: felt252,
            message: Span<felt252>
        ) -> bool {
            assert(message.len() >= 7, 'Invalid message length');

            let sender: ContractAddress = starknet::contract_address_const::<0x123abc>();
            let sell_token: ContractAddress = starknet::contract_address_const::<0x456def>();
            let buy_token: ContractAddress = starknet::contract_address_const::<0x456de1>();
            let tick: u128 = 1200_u128;
            let amount: u128 = 500000_u128;
            let this_contract_address: ContractAddress = get_contract_address();

            let order_key = OrderKey { 
                token0: sell_token, 
                token1: buy_token, 
                tick: tick 
            };

            let (minted_amount, new_sell_amount) = self.mint_and_increase_sell_amount(order_key, amount.try_into().unwrap());

            true
        }

        fn get_contract_version(self: @ContractState) -> felt252 {
            'L2TWAMMBridge v1.0'
        }

        fn mint_and_increase_sell_amount(
            ref self: ContractState,
            order_key: OrderKey,
            amount: u128
        ) -> (u64, u128) {
            // Implement the logic here
            let minted_amount = amount / 2_u128; // Example calculation
            let current_sell_amount = self.sender_to_amount.read(order_key.token0);
            let new_sell_amount = current_sell_amount + amount;
            self.sender_to_amount.write(order_key.token0, new_sell_amount);
            
            (minted_amount.try_into().unwrap(), new_sell_amount)
        }
    }
}
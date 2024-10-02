use starknet::{ContractAddress, get_contract_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use crate::types::order_key::OrderKey;
use crate::extensions::mock_twamm::IMockTWAMM;
use crate::extensions::mock_twamm::IMockTWAMMDispatcher;
use crate::extensions::mock_twamm::IMockTWAMMDispatcherTrait;

#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn on_receive(ref self: TContractState, l2_token: ContractAddress, amount: u256, depositor: felt252, message: Span<felt252>) -> bool;
}

#[starknet::contract]
mod L2TWAMMBridge {
    use super::OrderKey;
    use super::IMockTWAMM;
    use super::IMockTWAMMDispatcher;
    use super::IMockTWAMMDispatcherTrait;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        sender_to_amount: Map::<ContractAddress, u128>,
    }

    #[external(v0)]
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

        let mock_twamm = IMockTWAMMDispatcher { contract_address: this_contract_address };
        let (minted_amount, new_sell_amount) = mock_twamm.mint_and_increase_sell_amount(order_key, amount);

        self.sender_to_amount.write(sender, new_sell_amount);
                true
    }

}
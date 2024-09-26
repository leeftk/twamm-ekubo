use starknet::{ContractAddress, storage_access::{StorePacking}};
use core::option::OptionTrait;
use core::result::ResultTrait;
use core::traits::TryInto;

#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderKey {
    // The first token sorted by address
    pub token0: ContractAddress,
    // The second token sorted by address
    pub token1: ContractAddress,
    // The price at which the token should be bought/sold. Must be a multiple of 100. If even,
    // selling token1.
    pub tick: u128,
}


#[starknet::interface]
trait ITWAMM<TContractState> {
    fn mint_and_increase_sell_amount(
        ref self: TContractState,
        order_key: OrderKey,
        amount: u128
    ) -> (u64, u128);
}


#[starknet::contract]
mod L2TWAMMBridge {
    use super::ITWAMM;
    use super::OrderKey;
    use starknet::ContractAddress;
    use core::integer::u128_try_from_felt252;
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        sender_to_amount: Map<ContractAddress, u128>,
        twamm_contract: ContractAddress,
    }

    /// external on_receive function
    /// this functnion decodes the message and set the parameters based on the followin solidity function that sent it
// this function will decode each of the params and call the mint_and_increase_sell_amount function
    #[external(v0)]
    fn on_receive(
        ref self: ContractState,
        l2_token: ContractAddress,
        amount: u256,
        depositor: felt252,
        message: Span<felt252>
    ) -> bool {
        // Assuming the message contains at least 7 elements
        assert(message.len() >= 7, 'Invalid message length');

        let sender: ContractAddress = starknet::contract_address_const::<0x123abc>();
        let sell_token: ContractAddress = starknet::contract_address_const::<0x456def>();
        let buy_token: ContractAddress = starknet::contract_address_const::<0x456de1>();
        let tick: u128 = 1200_u128; // Random multiple of 100
        let amount: u128 = 500000_u128; // Random amount

        let order_key = OrderKey { 
            token0: sell_token, 
            token1: buy_token, 
            tick: tick 
        };
        
        let mut twamm_contract = self.twamm_contract.read();
        let (minted_amount, new_sell_amount) = ITWAMM::mint_and_increase_sell_amount(
            ref twamm_contract,
            order_key,
            amount
        );

        self.sender_to_amount.write(sender, new_sell_amount);
        true
    }
}

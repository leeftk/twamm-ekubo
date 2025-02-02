use starknet::{ContractAddress, EthAddress};

#[derive(Drop, Serde, Copy)]
pub struct OrderDetails {
    pub sender: felt252,
    pub sell_token: felt252,
    pub buy_token: felt252,
    pub fee: felt252,
    pub start: felt252,
    pub end: felt252,
    pub amount:felt252,
    pub order_id: felt252
}


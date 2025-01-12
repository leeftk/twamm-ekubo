use starknet::{ContractAddress, EthAddress};

#[derive(Drop, Serde, Copy)]
pub struct OrderDetails {
    pub order_operation: felt252,
    pub sender: felt252,
    pub sell_token: felt252,
    pub buy_token: felt252,
    pub fee: felt252,
    pub start: felt252,
    pub end: felt252,
    pub amount: felt252,
    pub l1_contract: felt252
}

#[derive(Drop, Serde, Copy)]
pub struct WithdrawalDetails {
    pub order_operation: felt252,
    pub sender: felt252,
    pub receiver: felt252,
    pub buy_token: felt252,
    pub order_id: felt252,
    pub l1_contract: felt252
}

#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct OrderKey_Copy {
    pub sell_token: ContractAddress,
    pub buy_token: ContractAddress,
    pub fee: u128,
    pub start_time: u64,
    pub end_time: u64
}

#[derive(Drop, Serde, starknet::Store)]
struct Order_Created {
    order_key: OrderKey_Copy,
    creator: EthAddress,
}
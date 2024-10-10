use starknet::ContractAddress;

#[derive(Drop, Copy, Serde, Hash, PartialEq, Debug)]
pub struct OrderKey {
    pub sell_token: ContractAddress,
    pub buy_token: ContractAddress,
    pub fee: u128,
    pub start_time: u64,
    pub end_time: u64
}

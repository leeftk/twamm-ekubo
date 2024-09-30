use starknet::ContractAddress;

#[derive(Drop, Serde, Copy, Hash)]
pub struct OrderKey {
    // The first token sorted by address
    pub token0: ContractAddress,
    // The second token sorted by address
    pub token1: ContractAddress,
    // The price at which the token should be bought/sold. Must be a multiple of 100. If even,
    // selling token1.
    pub tick: u128,
}

use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, PartialEq, Hash)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

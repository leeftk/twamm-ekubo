// src/extensions/mock_twamm_impl.cairo

use starknet::ContractAddress;
use crate::types::order_key::OrderKey;
use super::mock_twamm::IMockTWAMM;

#[starknet::contract]
mod MockTWAMMImpl {
    use super::OrderKey;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MockTWAMMImpl of super::IMockTWAMM<ContractState> {
        fn mint_and_increase_sell_amount(
            ref self: ContractState,
            order_key: OrderKey,
            amount: u128
        ) -> (u64, u128) {
            // Always return 1 and 2, regardless of input
            (1_u64, 2_u128)
        }
    }
}
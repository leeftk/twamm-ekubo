use crate::types::order_key::OrderKey;
use starknet::ContractAddress;

#[starknet::interface]
trait IMockTWAMM<TContractState> {
    fn mint_and_increase_sell_amount(
        ref self: TContractState, 
        order_key: OrderKey, 
        amount: u128
    ) -> (u64, u128);
}
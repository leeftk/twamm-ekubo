use starknet::ContractAddress;
use core::option::OptionTrait;
use core::result::ResultTrait;
use std::convert::TryFrom;
use core::result::Result;


impl TryFrom<(ContractAddress, ContractAddress, felt252, felt252)> for OrderKey {
    type Error = felt252;

    fn try_from(value: (ContractAddress, ContractAddress, felt252, felt252)) -> Result<OrderKey, felt252> {
        let (sell_token, buy_token, start_felt, end_felt) = value;
        
        match (u64::try_from(start_felt), u64::try_from(end_felt)) {
            (Ok(start), Ok(end)) => {
                Ok(OrderKey { sell_token, buy_token, start, end })
            },
            _ => Err('Invalid start or end time'),
        }
    }
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
        twamm_contract: ContractAddress, // Add this line to store the TWAMM contract address
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

        let sender = ContractAddress::try_from(message[0]);
        let sell_token = ContractAddress::try_from(message[1]);
        let buy_token = ContractAddress::try_from(message[2]);
        let fee = ContractAddress::try_from(message[3]);
        let start = u64::try_from(message[4]);
        let end = u64::try_from(message[5]);
        let amount = u128::try_from(message[6]);

        let order_key = OrderKey { sell_token, buy_token, start, end };
        
        let (minted_amount, new_sell_amount) = ITWAMM::mint_and_increase_sell_amount(
            self.twamm_contract.read(),
            order_key,
            amount
        );

        self.sender_to_amount.write(sender, new_sell_amount);
        true
    }
}

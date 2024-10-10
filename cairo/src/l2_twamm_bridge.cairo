use starknet::{ContractAddress, get_contract_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use crate::types::order_key::OrderKey;


#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn on_receive(ref self: TContractState, l2_token: ContractAddress, amount: u256, depositor: felt252, message: Span<felt252>) -> bool;
    fn get_contract_version(self: @TContractState) -> felt252;
    fn set_ekubo_address(ref self: TContractState, address: ContractAddress);
}

#[starknet::interface]
pub trait IPositions<TContractState> {
    fn mint_and_increase_sell_amount(ref self: TContractState, order_key: OrderKey, amount: u128) -> (u64, u128);
}


#[starknet::contract]
mod L2TWAMMBridge {
    use super::IPositions;
    use super::IPositionsDispatcher;
    use super::OrderKey;
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        sender_to_amount: Map::<ContractAddress, u128>,
        ekubo_address: ContractAddress,
    }

    

    #[external(v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {
        
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
            let start_time = 1680302400_u64; // Example start time (Unix timestamp)
            let end_time = 1680388800_u64;   // Example end time (Unix timestamp)

            let order_key = OrderKey { 
                sell_token: sell_token, 
                buy_token: buy_token, 
                fee: 0,
                start_time: start_time,
                end_time: end_time
            };

            let positions_address = starknet::contract_address_const::<0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067>();
    
            // // Get the contract class from the address
            // let positions_contract = contract_class_from_address(positions_address);

            let positions = IPositionsDispatcher { contract_address: positions_address };


            
            println!("positions_contract: {:?}", positions.contract_address);
            //let (minted_amount, new_sell_amount) = positions.mint_and_increase_sell_amount(order_key, amount);

            true
        }

        fn set_ekubo_address(ref self: ContractState, address: ContractAddress) {
            self.ekubo_address.write(address);
        }

        fn get_contract_version(self: @ContractState) -> felt252 {
            'L2TWAMMBridge v1.0'
        }

    //     fn mint_and_increase_sell_amount(
    //         ref self: ContractState,
    //         order_key: OrderKey,
    //         amount: u128
    //     ) -> (u64, u128) {

    //         let ekubo_address = self.ekubo_address.read();
    //         let ekubo_contract = IEkuboDispatcher { contract_address: ekubo_address };
    //         let mut mutable_order_key = order_key;
    //         let mut mutable_amount = amount;
    //         let (minted_amount, new_sell_amount) = ekubo_contract.mint_and_increase_sell_amount(ref mutable_order_key, ref mutable_amount);   
    //         // Implement the logic here
    //         // let minted_amount = amount / 2_u128; // Example calculation
    //         // let current_sell_amount = self.sender_to_amount.read(order_key.token0);
    //         // let new_sell_amount = current_sell_amount + amount;
    //         // self.sender_to_amount.write(order_key.token0, new_sell_amount);
            
    //         // (minted_amount.try_into().unwrap(), new_sell_amount)

    //         (minted_amount, new_sell_amount)
    //     }
    }
}
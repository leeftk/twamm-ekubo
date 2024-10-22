use starknet::{ContractAddress, get_contract_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use ekubo::extensions::interfaces::twamm::{OrderKey, OrderInfo};
use ekubo::types::keys::PoolKey;
use ekubo::types::i129::{i129};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};




#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn on_receive(
        ref self: TContractState,
        l2_token: ContractAddress,
        amount: u128,
        depositor: ContractAddress,
        message: Span<felt252>
    ) -> bool;
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
    fn decrease_sale_rate_to(ref self: TContractState, id: u64, order_key: OrderKey, sale_rate_delta: u128) -> u128;
}


#[starknet::contract]
mod L2TWAMMBridge {
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::extensions::interfaces::twamm::{OrderKey};
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        sender_to_amount: Map::<ContractAddress, u128>,
        positions_address: ContractAddress,
    }

    #[derive(Drop, Serde)]
    struct Message {
        operation_type: u8,
        order_key: OrderKey,
    }
    #[external(v0)]
    #[abi(embed_v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {
fn on_receive(
    ref self: ContractState,
    l2_token: ContractAddress,
    amount: u128,
    depositor: ContractAddress,
    message: Span<felt252>
) -> bool {     
    let mut message_span = message;
    
    // Deserialize the message, handling potential failure
    match Serde::<Message>::deserialize(ref message_span) {
        Option::Some(deserialized_message) => {
            if deserialized_message.operation_type == 0 { 
                let order_key = deserialized_message.order_key;
                
                let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
                let (minted, amount) = positions.mint_and_increase_sell_amount(order_key, amount);
                assert(minted != 0, 'No tokens minted');
                assert(amount != 0, 'No tokens sold');
                self.sender_to_amount.write(depositor, amount);
                true
            } else {
           
                    //    // Handle deserialization failure
                    //    let order_key = deserialized_message.order_key;
                    //    let id = deserialized_message.id;
                    //    let sale_rate_delta = deserialized_message.sale_rate_delta;
                    //    let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
                    //    positions.decrease_sale_rate_to(id,order_key, sale_rate_delta, get_contract_address());
                       false
            }
        },
        Option::None => {
            // Handle deserialization failure
            false
        }
    }
}

        fn decrease_sale_rate_to(ref self: ContractState, id: u64, order_key: OrderKey, sale_rate_delta: u128) -> u128 {
            let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
            let number_of_tokens_sold = positions.decrease_sale_rate_to(
                id,
                order_key,
                sale_rate_delta,
                get_contract_address()
            );
            
           // If number_of_tokens_sold is 0, panic with an error message
            assert(number_of_tokens_sold != 0, 'No tokens sold');
            number_of_tokens_sold
        }

        fn set_positions_address(ref self: ContractState, address: ContractAddress) {
            self.positions_address.write(address);
        }
    }
}

use starknet::{ContractAddress, get_contract_address, contract_address_const};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use ekubo::extensions::interfaces::twamm::{OrderKey, OrderInfo};
use ekubo::types::keys::PoolKey;
use ekubo::types::i129::{i129};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};
use starknet::EthAddress;

#[starknet::interface]
pub trait ITokenBridge<TContractState> {
    fn initiate_token_withdraw(
        ref self: TContractState,
        l1_token: EthAddress,
        l1_recipient: EthAddress,
        amount: u256
    );
}

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
    fn withdraw_proceeds_from_sale_to_self(ref self: TContractState, id: u64, order_key: OrderKey) -> u128;
    fn set_token_bridge_address(ref self: TContractState, address: ContractAddress);
}


#[starknet::contract]
mod L2TWAMMBridge {
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::extensions::interfaces::twamm::{OrderKey};
    use starknet::{ContractAddress, get_contract_address};
    use starknet::storage::Map;
    use super::{ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::EthAddress;
    #[storage]
    struct Storage {
        sender_to_amount: Map::<ContractAddress, u128>,
        positions_address: ContractAddress,
        token_bridge_address: ContractAddress,

    }

    #[derive(Drop, Serde)]
    struct Message {
        operation_type: u8,
        order_key: OrderKey,
        id: u64,
        sale_rate_delta: u128,
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
           
                       // Handle deserialization failure
                       let order_key = deserialized_message.order_key;
                       let id = deserialized_message.id;
                    //    let l1_recipient = EthAddress(depositor);
                    //    let sale_rate_delta = deserialized_message.sale_rate_delta;
                    //    let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
                    //    let amount_sold = positions.withdraw_proceeds_from_sale_to_self(id, order_key);
                    //    //decrease amount in mapping
                    //    self.sender_to_amount.write(depositor, amount - amount_sold);
                    //    //send tokens cross chain in bridge
                    //    let token_bridge = ITokenBridgeDispatcher { 
                    //     contract_address: starknet::contract_address_const::<0x07754236934aeaf4c29d287b94b5fde8687ba7d59466ea6b80f3f57d6467b7d6>() 
                    // };      

                    // let l1_token = EthAddress { address: 0x6B175474E89094C44Da98b954EedeAC495271d0F };    
                    // let u256_amount_sold = u256 { low: amount_sold, high: 0 };          
                    // token_bridge.initiate_token_withdraw(l1_token, l1_recipient, u256_amount_sold);
                       false
            }
        },
        Option::None => {
            // Handle deserialization failure
            false
        }
    }
}

fn withdraw_proceeds_from_sale_to_self(
    ref self: ContractState, id: u64, order_key: OrderKey
) -> u128 {
    let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
    positions.withdraw_proceeds_from_sale_to_self(id, order_key)
}
fn set_token_bridge_address(ref self: ContractState, address: ContractAddress) {
    self.token_bridge_address.write(address);
}

        fn set_positions_address(ref self: ContractState, address: ContractAddress) {
            self.positions_address.write(address);
        }
    }
}

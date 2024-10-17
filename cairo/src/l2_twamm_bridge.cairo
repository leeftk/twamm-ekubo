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
            assert(message.len() >= 5, 'Invalid message length');

            //on_receive should decode the message and assign the values to the order_key
            let mut message_span = message;
            let order_key: OrderKey = Serde::<OrderKey>::deserialize(ref message_span).unwrap();

            let position_address = starknet::contract_address_const::<
                0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
            >();
            let positions = IPositionsDispatcher { contract_address: position_address };
            let (minted, amount) = positions.mint_and_increase_sell_amount(order_key, amount);
            //if minted is 0, return false, otherwise return true
            if minted == 0 && amount == 0 {
                return false;
            } else {
                return true;
            }
        }

        fn set_positions_address(ref self: ContractState, address: ContractAddress) {
            self.positions_address.write(address);
        }
    }
}

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
    fn handle_deposit(
    ref self: TContractState, 
    from_address: felt252, 
    l2_recipient: ContractAddress, 
    amount: u256,
);
}

#[starknet::interface]
pub trait IL2TWAMMBridge<TContractState> {
    fn on_receive(
        ref self: TContractState,
        l2_token: ContractAddress,
        amount: u128,
        depositor: EthAddress,
        message: Span<felt252>
    ) -> bool;
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
    fn withdraw_proceeds_from_sale_to_self(
        ref self: TContractState, id: u64, order_key: OrderKey
    ) -> u128;
    fn set_token_bridge_address(ref self: TContractState, address: ContractAddress);
    fn get_token_id_by_depositor(ref self: TContractState, depositor: EthAddress) -> u64;
    
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
        sender_to_amount: Map::<EthAddress, u128>,
        positions_address: ContractAddress,
        token_bridge_address: ContractAddress,
        order_id_to_depositor: Map::<u64, EthAddress>,
        order_depositor_to_id: Map::<EthAddress, u64>,
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
            depositor: EthAddress,
            message: Span<felt252>
        ) -> bool {     
            let mut message_span = message;
            
            match Serde::<Message>::deserialize(ref message_span) {
                Option::Some(message) => {
                    match message.operation_type {
                        0 => self.execute_deposit(depositor, amount, message),
                        _ => self.execute_withdrawal(depositor, amount, message)
                    }
                },
                Option::None => false
            }
        }

        fn withdraw_proceeds_from_sale_to_self(
            ref self: ContractState, 
            id: u64, 
            order_key: OrderKey
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
        fn get_token_id_by_depositor(ref self: ContractState, depositor: EthAddress) -> u64 {
            self.order_depositor_to_id.read(depositor)
        }

    }





    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn execute_deposit(
            ref self: ContractState,
            depositor: EthAddress,
            amount: u128,
            message: Message
        ) -> bool {
            let order_key = message.order_key;
            
            let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount);
            assert(minted != 0, 'No tokens minted');
            assert(amount != 0, 'No tokens sold');
            
            self.order_id_to_depositor.write(id, depositor);
            self.order_depositor_to_id.write(depositor, id);
            
            self.sender_to_amount.write(depositor, amount);
            true
        }

        fn execute_withdrawal(
            ref self: ContractState,
            depositor: EthAddress,
            amount: u128,
            message: Message
        ) -> bool {
            let order_key = message.order_key;
            let id = message.id;
            
            let owner = self.order_id_to_depositor.read(id);
            assert(owner == depositor, 'Not order owner');
            
            let positions = IPositionsDispatcher { contract_address: self.positions_address.read() };
            let amount_sold = positions.withdraw_proceeds_from_sale_to_self(id, order_key);
            assert(amount_sold != 0, 'No tokens sold');
            
            self.sender_to_amount.write(depositor, amount - amount_sold);
            
            // let token_bridge = ITokenBridgeDispatcher { 
            //     contract_address: self.token_bridge_address.read()
            // };      

            // let l1_token = EthAddress { address: 0x6B175474E89094C44Da98b954EedeAC495271d0F };    
            // let u256_amount_sold = u256 { low: amount_sold, high: 0 };          
            // token_bridge.initiate_token_withdraw(l1_token, depositor, u256_amount_sold);
            true
        }
    }
}

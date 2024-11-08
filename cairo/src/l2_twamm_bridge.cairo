use starknet::{ContractAddress, get_contract_address, contract_address_const, get_caller_address};
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
        ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256
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
        amount: u256,
        depositor: EthAddress,
        message: Span<felt252>
    ) -> bool;
    fn set_positions_address(ref self: TContractState, address: ContractAddress);

    fn withdraw_proceeds_from_sale_to_self(
        ref self: TContractState, id: u64, order_key: OrderKey
    ) -> u128;
    fn set_token_bridge_address(ref self: TContractState, address: ContractAddress);
    fn get_depositor_from_id(ref self: TContractState, id: u64) -> EthAddress;
    fn get_token_id_by_depositor(ref self: TContractState, depositor: EthAddress) -> u64;
    fn get_l2_bridge_by_l2_token(
        ref self: TContractState, buy_token: ContractAddress
    ) -> ContractAddress;
    fn get_l1_token_by_l2_token(ref self: TContractState, l2_token: ContractAddress) -> EthAddress;
    fn get_id_from_depositor(ref self: TContractState, depositor: EthAddress) -> u64;
}

#[starknet::contract]
mod L2TWAMMBridge {
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::extensions::interfaces::twamm::{OrderKey};

    use starknet::{ContractAddress, get_contract_address};

    use super::{Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess};
    use super::{ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::EthAddress;
    use super::{get_caller_address};
    use core::array::ArrayTrait;

    const ERROR_NO_TOKENS_MINTED: felt252 = 'No tokens minted';
    const ERROR_NO_TOKENS_SOLD: felt252 = 'No tokens sold';
    const ERROR_NOT_ORDER_OWNER: felt252 = 'Not order owner';
    const ERROR_INVALID_ADDRESS: felt252 = 'Invalid address';
    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';
    const ERROR_ZERO_AMOUNT: felt252 = 'Amount cannot be zero';

    #[storage]
    struct Storage {
        sender_to_amount: Map::<EthAddress, u128>,
        positions_address: ContractAddress,
        token_bridge_address: ContractAddress,
        order_id_to_depositor: Map::<u64, EthAddress>,
        order_depositor_to_id: Map::<EthAddress, u64>,
        l2_bridge_to_l2_token: Map::<ContractAddress, ContractAddress>,
        l2_token_to_l1_token: Map::<ContractAddress, EthAddress>,
        contract_owner: ContractAddress,
        token_id_to_depositor: Map<u64, EthAddress>,
        depositor_ids: Map<EthAddress, Array<u64>>,
        
    }

    #[derive(Drop, Serde)]
    struct Message {
        operation_type: u8,
        order_key: OrderKey,
        id: u64,
        sale_rate_delta: u128,
    }
    //Added event for testing
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MessageReceived: MessageReceived,
    }

    #[derive(Drop, starknet::Event)]
    struct MessageReceived {
        l2_token: ContractAddress,
        amount: u256,
        depositor: EthAddress,
        message: Span<felt252>
    }

    #[derive(Drop, Serde, Copy)]
    struct Payload {
        deposit_operation: felt252,
        sender: felt252,
        sell_token: felt252,
        buy_token: felt252,
        fee: felt252,
        start: felt252,
        end: felt252,
        amount: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MessageReceived: MessageReceived,
    }

    #[derive(Drop, starknet::Event)]
    struct MessageReceived {
        message: Payload
    }


    #[constructor]
    fn constructor(ref self: ContractState) {
        self.contract_owner.write(get_caller_address());
    }

    #[l1_handler]
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: Payload) {
        self.emit(MessageReceived {
            message: data
        });
        // if data.deposit_operation == 0 {
 

            // let order_key = OrderKey{
            //     sell_token: data.sell_token.try_into().unwrap(),
            //     buy_token: data.buy_token.try_into().unwrap(),
            //     fee: data.fee.try_into().unwrap(),
            //     start_time: data.start.try_into().unwrap(),
            //     end_time: data.end.try_into().unwrap(),
            // };

            // let positions = IPositionsDispatcher {
            //     // contract_address: self.positions_address.read()
            //     contract_address:  contract_address_const::<
            //     0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5
            // >()
            // };
            // //Overflow vuln here
            // let amount_u128: u128 = data.amount.try_into().unwrap();

            // let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount_u128);
            // assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            // assert(id != 0, ERROR_ZERO_AMOUNT);
            // self.order_depositor_to_id.write(from_address.try_into().unwrap(), id);
            
        //     // self.order_id_to_depositor.write(id, from_address.try_into().unwrap());
        // } else if data.deposit_operation == 2 {
        //     self.emit(MessageReceived {
        //         message: data
        //     });

        // }
    //     let current_timestamp = get_block_timestamp();
    //     let difference = 16 - (current_timestamp % 16);
    //     let start_time = (current_timestamp + difference);
    //     let end_time = start_time + 64;
    //     let amount = 1_u256;

    //     let mut sellTokenAddress =  contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>();
    //     let mut buyTokenAddress =  contract_address_const::<0x053b40a647cedfca6ca84f542a0fe36736031905a9639a7f19a3c1e66bfd5080>();
    
    // let order_key = OrderKey{
    //                 sell_token: sellTokenAddress,
    //                 buy_token: buyTokenAddress,
    //                 fee: 0,
    //                 start_time: start_time,
    //                 end_time: end_time,
    //             }; 

    //             let positions = IPositionsDispatcher {
    //                 // contract_address: self.positions_address.read()
    //                 contract_address:  contract_address_const::<
    //                 0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5
    //             >()
    //             };

    //         let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount.try_into().unwrap());

        // self.execute_deposit(from_address, amount, message)
        
    }

    #[external(v0)]
    #[abi(embed_v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {

        fn on_receive(
            ref self: ContractState,
            l2_token: ContractAddress,
            amount: u256,
            depositor: EthAddress,
            message: Span<felt252>
        ) -> bool {
            self.emit(MessageReceived { l2_token, amount, depositor, message });
            let mut message_span = message;
            let first_element = *message[0];
            let from_address: EthAddress = (*message[1]).try_into().unwrap(); 
            let amount_128 : u128 = amount.try_into().unwrap();
            
            if first_element == 0 {     
                // Create order or execute deposit with these parameters
                self.execute_deposit(from_address, amount_128, message)
           } else {
                true
           }
           
        }

        fn withdraw_proceeds_from_sale_to_self(
            ref self: ContractState, id: u64, order_key: OrderKey
        ) -> u128 {
            let positions = IPositionsDispatcher {
                // contract_address: self.positions_address.read()
                contract_address:  contract_address_const::<
                0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5
            >()
            };
            positions.withdraw_proceeds_from_sale_to_self(id, order_key)
        }

        fn set_token_bridge_address(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.token_bridge_address.write(address);
        }

        fn set_positions_address(ref self: ContractState, address: ContractAddress) {
            self.assert_only_owner();
            self.positions_address.write(address);
        }
        
        fn get_depositor_from_id(ref self: ContractState, id: u64) -> EthAddress {
            self.order_id_to_depositor.read(id)
        }
        fn get_id_from_depositor(ref self: ContractState, depositor: EthAddress) -> u64 {
            self.order_depositor_to_id.read(depositor)
        }

        fn get_l2_bridge_by_l2_token(
            ref self: ContractState, buy_token: ContractAddress
        ) -> ContractAddress {
            self.assert_only_owner();
            self.l2_bridge_to_l2_token.read(buy_token)
        }
        fn get_token_id_by_depositor(ref self: ContractState, depositor: EthAddress) -> u64 {
            self.order_depositor_to_id.read(depositor)
        }   

        fn get_l1_token_by_l2_token(
            ref self: ContractState, l2_token: ContractAddress
        ) -> EthAddress {
            self.assert_only_owner();
            self.l2_token_to_l1_token.read(l2_token)
        }

    }
    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn execute_deposit(
            ref self: ContractState, depositor: EthAddress, amount: u128, message: Span<felt252>
        ) -> bool {

    




            let positions = IPositionsDispatcher {
                // contract_address: self.positions_address.read()
                contract_address:  contract_address_const::<
                0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5
            >()
            };

            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount);
            assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            assert(id != 0, ERROR_ZERO_AMOUNT);
            self.order_depositor_to_id.write(depositor, id);
            
            self.order_id_to_depositor.write(id, depositor);
            // true
        }

        fn execute_withdrawal(
            ref self: ContractState, depositor: EthAddress, amount: u128, message: Span<felt252>
        ) -> bool {
            let order_key = OrderKey{
                sell_token: (*message[5]).try_into().unwrap(),
                buy_token: (*message[6]).try_into().unwrap(),
                fee: (*message[7]).try_into().unwrap(),
                start_time: (*message[8]).try_into().unwrap(),
                end_time: (*message[9]).try_into().unwrap(),
            };

            let id: u64 = (*message[10]).try_into().unwrap();

            let user = self.get_depositor_from_id(id);

            assert(user == depositor, ERROR_ZERO_AMOUNT);

            let amount_sold = self.withdraw_proceeds_from_sale_to_self(id, order_key);
            assert(amount_sold != 0, ERROR_NO_TOKENS_SOLD);
            let new_amount = amount - amount_sold;
            self.sender_to_amount.write(depositor, new_amount);
            let bridge_address = self.get_l2_bridge_by_l2_token(order_key.buy_token);

            let token_bridge = ITokenBridgeDispatcher { contract_address: bridge_address };
            let l1_token = self.get_l1_token_by_l2_token(order_key.buy_token);

            // token_bridge.initiate_token_withdraw(l1_token, depositor, amount_sold);
            true
        }
        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }
    }
}
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

#[derive(Drop, Serde, Copy)]
struct MyData {
    deposit_operation: felt252,
    sender: felt252,
    sell_token: felt252,
    buy_token: felt252,
    fee: felt252,
    start: felt252,
    end: felt252,
    amount: felt252,
}

#[starknet::interface]
pub(crate) trait IERC20<TContractState> {
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, account: ContractAddress, amount: u256) -> bool;
}

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
    fn withdraw_proceeds_from_sale_to_self(
        ref self: TContractState, id: u64, order_key: OrderKey
    ) -> u128;
    fn create_order_key(ref self: TContractState, message: MyData) -> OrderKey;
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
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
    use starknet::{ContractAddress, get_contract_address, contract_address_const, get_block_timestamp};

    use super::{Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess};
    use super::{ITokenBridge, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::EthAddress;
    use super::{get_caller_address};
    use core::array::ArrayTrait;
    use super::MyData;
    use super::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};

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
        counter: u64,
        
    }

    #[derive(Drop, Serde)]
    struct Message {
        operation_type: u8,
        order_key: OrderKey,
        id: u64,
        sale_rate_delta: u128,
    } 

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MessageReceived: MessageReceived,
    }

    #[derive(Drop, starknet::Event)]
    struct MessageReceived {
        message: MyData
    }


    #[constructor]
    fn constructor(ref self: ContractState) {
        self.contract_owner.write(get_caller_address());
    }


    #[l1_handler]
    fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: MyData) {
        if data.deposit_operation == 0 {
            self.emit(MessageReceived { message: data });
            self.execute_deposit(data);
        } else if data.deposit_operation == 2 {
        self.emit(MessageReceived { message: data });
        }
        
    }


    #[external(v0)]
    #[abi(embed_v0)]
    impl L2TWAMMBridge of super::IL2TWAMMBridge<ContractState> {



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
        fn create_order_key(ref self: ContractState, message: MyData) -> OrderKey {
            OrderKey {
                sell_token: (message.sell_token).try_into().unwrap(),
                buy_token: (message.buy_token).try_into().unwrap(),
                fee: (message.fee).try_into().unwrap(),
                start_time: (message.start).try_into().unwrap(),
                end_time: (message.end).try_into().unwrap(),
            }
        }
    }
    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn create_order_key(message: MyData) -> OrderKey {
            OrderKey {
                sell_token: (message.sell_token).try_into().unwrap(),
                buy_token: (message.buy_token).try_into().unwrap(),
                fee: (message.fee).try_into().unwrap(),
                start_time: (message.start).try_into().unwrap(),
                end_time: (message.end).try_into().unwrap(),
            }
        }

        fn execute_deposit(
<<<<<<< HEAD
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
=======
            ref self: ContractState, message: MyData
        ) {
            let current_timestamp = get_block_timestamp();
            let difference = 16 - (current_timestamp % 16);
            let start_time = (current_timestamp + difference);
            let end_time = start_time + 64;

            let new_sell_token: ContractAddress = (message.sell_token).try_into().unwrap();
            let new_buy_token: ContractAddress = (message.buy_token).try_into().unwrap();
            let new_fee: u128 = (message.fee).try_into().unwrap();
                let order_key = OrderKey{
                sell_token: new_sell_token,
                buy_token: new_buy_token,
                fee: new_fee,
                start_time: start_time,
                end_time: end_time,
                }; 

            let positions = IPositionsDispatcher {
        // contract_address: self.positions_address.read()
            contract_address:  contract_address_const::<
            0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5
            >()
        };
               //Overflow vuln here
            let amount_u128: u128 = message.amount.try_into().unwrap();
            // IERC20Dispatcher { contract_address: message.sell_token.try_into().unwrap() }
            // .transfer(positions.contract_address, message.amount.try_into().unwrap());
             
            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount_u128);
<<<<<<< HEAD
            // assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            // assert(id != 0, ERROR_ZERO_AMOUNT);
            // self.order_depositor_to_id.write(depositor, id);
>>>>>>> 39f9f49 (debug-create-order)
=======
            assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            assert(id != 0, ERROR_ZERO_AMOUNT);
            self.order_depositor_to_id.write(message.sender.try_into().unwrap(), id);
>>>>>>> a4bf47e (deposit and create order working)
            
            self.order_id_to_depositor.write(id, message.sender.try_into().unwrap());
            // true
        }

        fn execute_withdrawal(
<<<<<<< HEAD
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
=======
            ref self: ContractState, depositor: EthAddress, amount: u256, message: MyData
        ) -> bool {
            let order_key = self.create_order_key(message);
            let id: u64 = (0).try_into().unwrap();// are we pasing a withdrawal id from the L1?
>>>>>>> 39f9f49 (debug-create-order)

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
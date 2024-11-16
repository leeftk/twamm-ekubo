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
    token_bridge_address: felt252,
}
// This is a copy of the OrderKey struct that allows it to be stored in the contract
// Probably not the best way to do this
#[derive(Drop, Serde, Copy, starknet::Store)]
pub struct OrderKey_Copy {
    pub sell_token: ContractAddress,
    pub buy_token: ContractAddress,
    pub fee: u128,
    pub start_time: u64,
    pub end_time: u64
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
    fn withdraw_proceeds_from_sale_to(
        ref self: TContractState, id: u64, order_key: OrderKey
    ) -> u128;
    fn create_order_key(ref self: TContractState, message: MyData) -> OrderKey;
    fn decode_order_key_from_stored_copy(ref self: TContractState, message: OrderKey_Copy) -> OrderKey;
    fn set_positions_address(ref self: TContractState, address: ContractAddress);
    fn set_token_bridge_address(ref self: TContractState, address: ContractAddress);
    fn get_depositor_from_id(ref self: TContractState, id: u64) -> EthAddress;
    fn get_token_id_by_depositor(ref self: TContractState, depositor: EthAddress) -> u64;
    fn get_l2_bridge_by_l2_token(
        ref self: TContractState, buy_token: ContractAddress
    ) -> ContractAddress;
    fn get_l1_token_by_l2_token(ref self: TContractState, l2_token: ContractAddress) -> EthAddress;
    fn get_id_from_depositor(ref self: TContractState, depositor: EthAddress) -> u64;
    fn send_token_to_l1(ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256, message: MyData);
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
    use super::OrderKey_Copy;

    const ERROR_NO_TOKENS_MINTED: felt252 = 'No tokens minted';
    const ERROR_NO_TOKENS_SOLD: felt252 = 'No tokens sold';
    const ERROR_NOT_ORDER_OWNER: felt252 = 'Not order owner';
    const ERROR_INVALID_ADDRESS: felt252 = 'Invalid address';
    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';
    const ERROR_ZERO_AMOUNT: felt252 = 'Amount cannot be zero';
    const ALREADY_WITHDRAWN: felt252 = 'Order has been withdrawn';

    #[storage]
    pub struct Storage {
        sender_to_amount: Map::<EthAddress, u256>,
        positions_address: ContractAddress,
        token_bridge_address: ContractAddress,
        order_id_to_depositor: Map::<u64, EthAddress>,
        order_depositor_to_id: Map::<EthAddress, u64>,
        order_depositor_to_id_to_withdrawal_status: Map::<EthAddress, Map<u64, bool>>,
        l2_bridge_to_l2_token: Map::<ContractAddress, ContractAddress>,
        l2_token_to_l1_token: Map::<ContractAddress, EthAddress>,
        contract_owner: ContractAddress,
        token_id_to_depositor: Map<u64, EthAddress>,
        depositor_ids: Map<EthAddress, Array<u64>>,
        counter: u64,
        order_depositor_to_order_created: Map::<EthAddress, Order_Created>, 
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct Order_Created {
        order_key: OrderKey_Copy,
        id: u64,
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
            self.withdraw(data);
            
        } 
        else if data.deposit_operation == 3 {
            self.emit(MessageReceived { message: data });
            self.send_token_to_l1(data.buy_token.try_into().unwrap(), data.sender.try_into().unwrap(), data.amount.try_into().unwrap(), data);
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

        fn withdraw_proceeds_from_sale_to(
            ref self: ContractState, id: u64, order_key: OrderKey
        ) -> u128 {
            let positions = IPositionsDispatcher {
                // contract_address: self.positions_address.read()
                contract_address:  contract_address_const::<
                0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5
            >()
            };

            let this_contract_address = get_contract_address();

            positions.withdraw_proceeds_from_sale_to(id, order_key, this_contract_address)
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
        fn get_withdrawal_status_from_depositor_id(ref self: ContractState, depositor: EthAddress, id: u64) -> bool {
            self.order_depositor_to_id_to_withdrawal_status.entry(depositor).entry(id).read()
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

        fn decode_order_key_from_stored_copy(ref self: ContractState, message: OrderKey_Copy) -> OrderKey {
    
            OrderKey {
                sell_token: (message.sell_token).try_into().unwrap(),
                buy_token: (message.buy_token).try_into().unwrap(),
                fee: (message.fee).try_into().unwrap(),
                start_time: (message.start_time).try_into().unwrap(),
                end_time: (message.end_time).try_into().unwrap(),
            }
        }

        fn send_token_to_l1(ref self: ContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256, message:MyData) {
            let token_bridge = ITokenBridgeDispatcher { contract_address:
                message.token_bridge_address.try_into().unwrap() };
            token_bridge.initiate_token_withdraw(l1_token, l1_recipient, amount);
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

            let order_key_copy = OrderKey_Copy{
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
            // .transfer(positions.contract_address, message.amount.try_into().unwrap())
             
            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount_u128);
            assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            assert(id != 0, ERROR_ZERO_AMOUNT);
            self.order_depositor_to_id.write(message.sender.try_into().unwrap(), id);
            
            self.order_id_to_depositor.write(id, message.sender.try_into().unwrap());

            self.order_depositor_to_order_created.write(message.sender.try_into().unwrap(), Order_Created { order_key: order_key_copy, id: id });
            // true
        }

        fn execute_withdrawal(
            ref self: ContractState, depositor: EthAddress, amount: u256, message: MyData
        ) -> bool {

            //fetch the order details from the depositor
            ///These lines of code work and are what I use to retrieve the created order details
            let order_created = self.order_depositor_to_order_created.read(depositor);
            let order_key_copy = order_created.order_key;
            let order_key = self.decode_order_key_from_stored_copy(order_key_copy);
            let id: u64 = (order_created.id).try_into().unwrap();

            let user = self.get_depositor_from_id(id);

            assert(user == depositor, ERROR_ZERO_AMOUNT);

            let amount_sold = self.withdraw_proceeds_from_sale_to_self(id, order_key);
            assert(amount_sold != 0, ERROR_NO_TOKENS_SOLD);
            let amount_sold_u256: u256 = amount_sold.into();

            let new_amount: u256 = amount - amount_sold_u256;
            self.sender_to_amount.write(depositor, new_amount);
            let bridge_address = self.get_l2_bridge_by_l2_token(order_key.buy_token);

            let token_bridge = ITokenBridgeDispatcher { contract_address: bridge_address };
            let l1_token = self.get_l1_token_by_l2_token(order_key.buy_token);

            token_bridge.initiate_token_withdraw(l1_token, depositor, amount_sold.into());
            true
        }

        fn withdraw(ref self: ContractState, message: MyData){
            let depositor:EthAddress = message.sender.try_into().unwrap();
            let order_created = self.order_depositor_to_order_created.read(depositor);

            let order_key_copy = order_created.order_key;
            let order_key = self.decode_order_key_from_stored_copy(order_key_copy);
            let id: u64 = (order_created.id).try_into().unwrap();
            let user = self.get_depositor_from_id(id);

            assert(user == depositor, ERROR_ZERO_AMOUNT);

            let amount_sold = self.withdraw_proceeds_from_sale_to(id, order_key);

            let token_bridge = ITokenBridgeDispatcher { contract_address:
                message.token_bridge_address.try_into().unwrap() };
            token_bridge.initiate_token_withdraw(message.buy_token.try_into().unwrap(), depositor, amount_sold.into());
         
        }

        fn get_l2_bridge_from_l1_token(ref self: ContractState, tokenAddress: felt252) -> ContractAddress {
            //ETH
            if tokenAddress == 0x0000000000000000000000000000000000455448 {
                contract_address_const::<0x04c5772d1914fe6ce891b64eb35bf3522aeae1315647314aac58b01137607f3f>()
            }
            //STRK 
            else if tokenAddress == 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766 {
                contract_address_const::<0x0594c1582459ea03f77deaf9eb7e3917d6994a03c13405ba42867f83d85f085d>()
            }
            // USDC
            else if tokenAddress == 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 {
                contract_address_const::<0x0028729b12ce1140cbc1e7cbc7245455d3c15fa0c7f5d2e9fc8e0441567f6b50>()
            }
            //USDT
             else if tokenAddress == 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0 {
                contract_address_const::<0x3913d184e537671dfeca3f67015bb845f2d12a26e5ec56bdc495913b20acb08>()
            } 
            //WBTC
            else if tokenAddress == 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC {
                contract_address_const::<0x025a3820179262679392e872d7daaa44986af7caae1f41b7eedee561ca35a169>()
            }
            //wstETH 
            else if tokenAddress == 0xB82381A3fBD3FaFA77B3a7bE693342618240067b {
                contract_address_const::<0x0172393a285eeac98ea136a4be473986a58ddd0beaf158517bc32166d0328824>()
            } else {
                panic!("Invalid token address")
            }
        }
        
        

        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }
    }
}
use starknet::{ContractAddress, get_contract_address, contract_address_const, get_caller_address, get_block_timestamp};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use starknet::EthAddress;
use ekubo::extensions::interfaces::twamm::{OrderKey};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use super::token_bridge_helper::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
use super::interfaces::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
use super::types::{OrderDetails, OrderKey_Copy};


#[derive(Drop, Serde, starknet::Store)]
struct Order_Created {
    order_key: OrderKey_Copy,
    id: u64,
}

#[starknet::interface]
trait IOrderManager<TContractState> {
    fn create_order_key( ref self: TContractState ,message: OrderDetails) -> OrderKey;
    fn decode_order_key_from_stored_copy( ref self: TContractState, stored_key: OrderKey_Copy) -> OrderKey;
    fn execute_deposit( ref self: TContractState, message: OrderDetails);
    fn execute_withdrawal( ref self: TContractState, message: OrderDetails, positions_address: ContractAddress, token_bridge_helper_address: ContractAddress);
    fn get_depositor_from_id( ref self: TContractState ,id: u64) -> EthAddress;
    fn get_id_from_depositor( ref self: TContractState, depositor: EthAddress) -> u64;
    fn get_withdrawal_status( ref self: TContractState, depositor: EthAddress, id: u64) -> bool;
    fn get_order_created( ref self: TContractState, depositor: EthAddress) -> Order_Created;
}

#[starknet::component]
mod OrderManagerComponent {
    use super::{OrderKey, OrderKey_Copy, OrderDetails, Order_Created, EthAddress, ContractAddress};
    use super::{Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePath,
        StoragePathEntry, IPositionsDispatcher, IPositionsDispatcherTrait};
    use starknet::{get_block_timestamp, get_caller_address, contract_address_const, get_contract_address};
    use super::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
    

    const ERROR_NO_TOKENS_MINTED: felt252 = 'No tokens minted';
    const ERROR_ZERO_AMOUNT: felt252 = 'Amount cannot be zero';
    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';
    const ERROR_ALREADY_WITHDRAWN: felt252 = 'Already Withdrawn';
    const U128_MAX: u256 = 0xffffffffffffffffffffffffffffffff; 


    #[storage]
    struct Storage {
        order_id_to_depositor: Map::<u64, EthAddress>,
        order_depositor_to_id: Map::<EthAddress, u64>,
        order_depositor_to_id_to_withdrawal_status: Map::<EthAddress, Map<u64, bool>>,
        order_depositor_to_order_created: Map::<EthAddress, Order_Created>,
        contract_owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OrderCreated: OrderCreated,
        OrderWithdrawn: OrderWithdrawn,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderCreated {
        id: u64,
        sender: EthAddress,
        amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderWithdrawn {
        id: u64,
        sender: EthAddress,
        amount_sold: u128,
    }

    #[embeddable_as(OrderManagerImpl)]
    impl OrderManager<
    TContractState,
    +HasComponent<TContractState>,
    > of super::IOrderManager<ComponentState<TContractState>>{
        fn create_order_key(
             ref self: ComponentState<TContractState>,
            message: OrderDetails
        ) -> OrderKey {
            OrderKey {
                sell_token: message.sell_token.try_into().unwrap(),
                buy_token: message.buy_token.try_into().unwrap(),
                fee: message.fee.try_into().unwrap(),
                start_time: message.start.try_into().unwrap(),
                end_time: message.end.try_into().unwrap(),
            }
        }

        // Decode order key from stored copy
        fn decode_order_key_from_stored_copy(
             ref self: ComponentState<TContractState>,
            stored_key: OrderKey_Copy
        ) -> OrderKey {
            OrderKey {
                sell_token: stored_key.sell_token,
                buy_token: stored_key.buy_token,
                fee: stored_key.fee,
                start_time: stored_key.start_time,
                end_time: stored_key.end_time,
            }
        }

        // Execute deposit
        fn execute_deposit(
             ref self: ComponentState<TContractState>,
            message: OrderDetails
        ) {
            let current_timestamp = get_block_timestamp();
            let difference = 16 - (current_timestamp % 16);
            let start_time = (current_timestamp + difference);
            let end_time = start_time + 64;

            let new_sell_token: ContractAddress = message.sell_token.try_into().unwrap();
            let new_buy_token: ContractAddress = message.buy_token.try_into().unwrap();
            let new_fee: u128 = message.fee.try_into().unwrap();

            assert(message.amount.try_into().unwrap() <= U128_MAX, 'Amount exceeds u128 max');
            let amount_u128: u128 = message.amount.try_into().unwrap();

            let order_key = OrderKey {
                sell_token: new_sell_token,
                buy_token: new_buy_token,
                fee: new_fee,
                start_time: start_time,
                end_time: end_time,
            };

            let order_key_copy = OrderKey_Copy {
                sell_token: new_sell_token,
                buy_token: new_buy_token,
                fee: new_fee,
                start_time: start_time,
                end_time: end_time,
            };

            let positions = IPositionsDispatcher {
                contract_address: contract_address_const::<0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5>()
            };

            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount_u128);
            
            assert(minted != 0, ERROR_NO_TOKENS_MINTED);
            assert(id != 0, ERROR_ZERO_AMOUNT);

            let sender: EthAddress = message.sender.try_into().unwrap();
            
            // Store order data
            self.order_id_to_depositor.write(id, sender);
            self.order_depositor_to_id.write(sender, id);
            self.order_depositor_to_order_created.write(
                sender, 
                Order_Created { order_key: order_key_copy, id }
            );

            // Emit event
            self.emit(OrderCreated { id, sender, amount: amount_u128 });
        }

        // Execute withdrawal
        fn execute_withdrawal(
             ref self: ComponentState<TContractState>,
            message: OrderDetails,
            positions_address: ContractAddress,
            token_bridge_helper_address: ContractAddress
        ) {
            let depositor: EthAddress = message.sender.try_into().unwrap();
            let order_created = self.order_depositor_to_order_created.read(depositor);
            
            let order_key = self.decode_order_key_from_stored_copy(order_created.order_key);
            let id = order_created.id;
            
            let user = self.get_depositor_from_id(id);
            let withdrawal_status = self.get_withdrawal_status(depositor, id);

            assert(user == depositor, ERROR_UNAUTHORIZED);
            assert(!withdrawal_status, ERROR_ALREADY_WITHDRAWN);

            let positions = IPositionsDispatcher { contract_address: positions_address };
            let this_contract_address = get_contract_address();
            
            let amount_sold = positions.withdraw_proceeds_from_sale_to(id, order_key, this_contract_address);

            // Mark as withdrawn
            self.order_depositor_to_id_to_withdrawal_status.entry(depositor).entry(id).write(true);

            // Handle token bridge withdrawal
            let helper = ITokenBridgeHelperDispatcher { contract_address: token_bridge_helper_address };
            let l2_bridge = helper.get_l2_bridge_from_l1_token(message.buy_token.try_into().unwrap());
            let token_bridge = ITokenBridgeDispatcher { contract_address: l2_bridge };
            // token_bridge.initiate_token_withdraw(message.buy_token.try_into().unwrap(), depositor, amount_sold.into());

            // Emit event
            self.emit(OrderWithdrawn { id, sender: depositor, amount_sold });
        }

        // Getter functions
        fn get_depositor_from_id(
             ref self: ComponentState<TContractState>,
            id: u64
        ) -> EthAddress {
            self.order_id_to_depositor.read(id)
        }

        fn get_id_from_depositor(
             ref self: ComponentState<TContractState>,
            depositor: EthAddress
        ) -> u64 {
            self.order_depositor_to_id.read(depositor)
        }

        fn get_withdrawal_status(
             ref self: ComponentState<TContractState>,
            depositor: EthAddress, 
            id: u64
        ) -> bool {
            self.order_depositor_to_id_to_withdrawal_status.entry(depositor).entry(id).read()
        }

        fn get_order_created(
             ref self: ComponentState<TContractState>,
            depositor: EthAddress
        ) -> Order_Created {
            self.order_depositor_to_order_created.read(depositor)
        }
    }
}
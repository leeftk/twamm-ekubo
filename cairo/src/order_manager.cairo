use starknet::{ContractAddress, get_contract_address, contract_address_const, EthAddress};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess,
};
use ekubo::extensions::interfaces::twamm::{OrderKey};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use super::token_bridge_helper::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};
use super::interfaces::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
use super::types::{OrderDetails};

#[derive(Drop)]
#[starknet::interface]
trait IOrderManager<TContractState> {
    fn create_order_key(ref self: TContractState, message: OrderDetails) -> OrderKey;
    fn execute_deposit(ref self: TContractState, message: OrderDetails);
    fn execute_withdrawal(
        ref self: TContractState,
        message: OrderDetails,
        token_bridge_helper_address: ContractAddress,
    );
    fn span_to_order_details(ref self: TContractState, span: Span<felt252>) -> OrderDetails;
}

#[starknet::component]
mod OrderManagerComponent {
    use super::IOrderManager;
    use super::{OrderKey, OrderDetails};
    use super::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess, StoragePath, StoragePathEntry, IPositionsDispatcher,
        IPositionsDispatcherTrait, contract_address_const, get_contract_address, EthAddress,
        ContractAddress,
    };
    use super::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
    use super::{ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait};

    const U128_MAX: u256 = 0xffffffffffffffffffffffffffffffff;

    // Storage
    #[storage]
    struct Storage {
        order_id_to_l1_creator_address: Map::<u64, EthAddress>,
        contract_owner: ContractAddress,
    }

    // Events
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
        TContractState, +HasComponent<TContractState>,
    > of super::IOrderManager<ComponentState<TContractState>> {
        fn create_order_key(
            ref self: ComponentState<TContractState>, message: OrderDetails,
        ) -> OrderKey {
            OrderKey {
                sell_token: message.sell_token.try_into().unwrap(),
                buy_token: message.buy_token.try_into().unwrap(),
                fee: message.fee.try_into().unwrap(),
                start_time: message.start.try_into().unwrap(),
                end_time: message.end.try_into().unwrap(),
            }
        }

        // Execute deposit
        fn execute_deposit(ref self: ComponentState<TContractState>, message: OrderDetails) {
            // Validate and convert message amount to u128
            assert(message.amount.try_into().unwrap() <= U128_MAX, 'Amount exceeds u128 max');
            let amount_u128: u128 = message.amount.try_into().unwrap();

            // Create an OrderKey instance with the message details
            let order_key = self.create_order_key(message);

            let positions = IPositionsDispatcher {
                contract_address: contract_address_const::<
                    0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5,
                >(),
            };

            let (id, minted) = positions.mint_and_increase_sell_amount(order_key, amount_u128);

            let sender: EthAddress = message.sender.try_into().unwrap();

            // Map order_id to creator
            self.order_id_to_l1_creator_address.write(id, sender);
        }

        // Execute withdrawal
        fn execute_withdrawal(
            ref self: ComponentState<TContractState>,
            message: OrderDetails,
            token_bridge_helper_address: ContractAddress,
        ) {
            let order_id: u64 = message.order_id.try_into().unwrap();

            let order_creator = self.order_id_to_l1_creator_address.read(order_id);

            // Decode order key from stored copy
            let order_key = self.create_order_key(message);

            let positions = IPositionsDispatcher {
                contract_address: contract_address_const::<
                    0x06a2aee84bb0ed5dded4384ddd0e40e9c1372b818668375ab8e3ec08807417e5,
                >(),
            };
            let this_contract_address = get_contract_address();

            let amount_sold = positions
                .withdraw_proceeds_from_sale_to(order_id, order_key, this_contract_address);

            // Handle token bridge withdrawal
            let helper = ITokenBridgeHelperDispatcher {
                contract_address: token_bridge_helper_address,
            };

            // Get L2 bridge
            let l2_bridge = helper
                .get_l2_bridge_from_l2_token(order_key.buy_token.try_into().unwrap());
            let token_bridge = ITokenBridgeDispatcher { contract_address: l2_bridge };

            // Get L1 token
            let l1_token = token_bridge.get_l1_token(order_key.buy_token);

            // This function will fail if the amount being withdrawn is zero
            token_bridge.initiate_token_withdraw(l1_token, order_creator, amount_sold.into());
        }

        // Helper function to convert Span<felt252> to OrderDetails
        fn span_to_order_details(
            ref self: ComponentState<TContractState>, span: Span<felt252>,
        ) -> OrderDetails {
            let mut data = span.snapshot;
            let sender = *data[0];
            let sell_token = *data[1];
            let buy_token = *data[2];
            let fee = *data[3];
            let start = *data[4];
            let end = *data[5];
            let amount = *data[6];

            return OrderDetails {
                sender, sell_token, buy_token, fee, start, end, amount, order_id: 0,
            };
        }
    }
}

#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, contract_address_const, get_caller_address};
    use snforge_std::{
        declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
        DeclareResultTrait, spy_events, EventSpy, EventSpyTrait, EventSpyAssertionsTrait, Event,
        L1Handler, L1HandlerTrait,
    };
    use twammbridge::l2_twamm_bridge;
    use twammbridge::l2_twamm_bridge::{
        L2TWAMMBridge, IL2TWAMMBridge, IL2TWAMMBridgeDispatcher, IL2TWAMMBridgeDispatcherTrait,
    };
    use twammbridge::types::{OrderDetails};
    use twammbridge::errors::{ERROR_UNAUTHORIZED};
    use twammbridge::token_bridge_helper::{
        ITokenBridgeHelperDispatcher, ITokenBridgeHelperDispatcherTrait,
    };
    use twammbridge::mocks::mock_twamm_bridge::{
        MockTWAMMBridge, IMockTWAMMBridgeDispatcher, IMockTWAMMBridgeDispatcherTrait,
    };

    fn deploy_mock_l2twamm_bridge() -> (IMockTWAMMBridgeDispatcher, ContractAddress) {
        let contract = declare("MockTWAMMBridge").unwrap().contract_class();

        let (contract_address, _) = contract.deploy(@array![]).unwrap();
        let dispatcher = IMockTWAMMBridgeDispatcher { contract_address };
        (dispatcher, contract_address)
    }

    fn create_mock_order_details() -> OrderDetails {
        OrderDetails {
            order_operation: 0, //deposit operation
            sender: 123.try_into().unwrap(), // Mock ETH address
            sell_token: 0x123.try_into().unwrap(), // Mock sell token address
            buy_token: 0x456.try_into().unwrap(), // Mock buy token address
            amount: 1000,
            fee: 3,
            start: 1000,
            end: 2000,
        }
    }

    #[test]
    fn test_msg_handler_struct_deposit() {
        let (bridge, contract_address) = deploy_mock_l2twamm_bridge();
        // println!("{:?}", contract_address);

        let l1_handler = L1HandlerTrait::new(
            target: contract_address, selector: selector!("msg_handler_struct"),
        );

        let mut spy = spy_events();

        let message = create_mock_order_details();

        let serialized_order = array![
            message.order_operation.into(),
            message.sender.into(),
            message.sell_token.into(),
            message.buy_token.into(),
            message.amount.into(),
            message.fee.into(),
            message.start.into(),
            message.end.into(),
        ];

        let message_span = serialized_order.span();

        let result = l1_handler.execute('123', message_span);

        let events = spy.get_events();

        assert_eq!(events.events.len(), 2);

        let (from, event) = events.events.at(0);
        assert(event.keys.at(0) == @selector!("MessageReceived"), 'Wrong event name');

        let (from, event) = events.events.at(1);
        assert(event.keys.at(0) == @selector!("OrderCreated"), 'Wrong event name');
    }


    #[test]
    fn test_msg_handler_struct_withdraw() {
        let (bridge, contract_address) = deploy_mock_l2twamm_bridge();

        let caller: ContractAddress = starknet::contract_address_const::<0x123626789>();

        let l1_handler = L1HandlerTrait::new(
            target: contract_address, selector: selector!("msg_handler_struct"),
        );

        let mut spy = spy_events();

        let message = create_mock_order_details();

        let withdrawal_payload = array![
            2, //withdrawal_operation
            message.sender.into(),
            message.sell_token.into(),
            message.buy_token.into(),
            message.amount.into(),
            message.fee.into(),
            message.start.into(),
            message.end.into(),
        ];

        start_cheat_caller_address(contract_address, caller);
        let (id, minted) = bridge.execute_deposit(message);

        let withdrawal_message_span = withdrawal_payload.span();
        let withdrawal_result = l1_handler.execute('123', withdrawal_message_span);
        stop_cheat_caller_address(contract_address);

        let events = spy.get_events();
        let withdrawn = bridge.get_withdrawal_status(message.sender.try_into().unwrap(), id);

        assert_eq!(events.events.len(), 3);
        assert_eq!(withdrawn, true);

        let (from, event) = events.events.at(0);
        assert(event.keys.at(0) == @selector!("OrderCreated"), 'Wrong event name');

        let (from, event) = events.events.at(1);
        assert(event.keys.at(0) == @selector!("MessageReceived"), 'Wrong event name');

        let (from, event) = events.events.at(2);
        assert(event.keys.at(0) == @selector!("OrderWithdrawn"), 'Wrong event name');
    }
}

#[starknet::interface]
trait ITWAMM<TContractState> {
    fn mint_and_increase_sell_amount(
        ref self: TContractState, order_key: OrderKey, amount: u128
    ) -> (u64, u128);
}

#[starknet::contract]
mod L2TWAMMBridge {
    use starknet::ContractAddress;
    use array::ArrayTrait;
    use box::BoxTrait;
    use option::OptionTrait;
    use traits::Into;
    use zeroable::Zeroable;

    #[storage]
    struct Storage {
        twamm_contract: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OrderCreated: OrderCreated,
    }

    #[derive(Drop, starknet::Event)]
    struct OrderCreated {
        sender: ContractAddress,
        order_id: u64,
        sale_rate: u128,
    }

    #[derive(Drop, Serde)]
    struct OrderKey {
        sell_token: ContractAddress,
        buy_token: ContractAddress,
        fee: u128,
        start_time: u64,
        end_time: u64,
    }

    #[external(v0)]
    fn handle_deposit(ref self: ContractState, from_address: felt252, payload: Array<felt252>) {
        // Decode the payload
        let sender: ContractAddress = payload[0].try_into().unwrap();
        let sell_token: ContractAddress = payload[1].try_into().unwrap();
        let buy_token: ContractAddress = payload[2].try_into().unwrap();
        let fee: u128 = payload[3].try_into().unwrap();
        let start_time: u64 = payload[4].try_into().unwrap();
        let end_time: u64 = payload[5].try_into().unwrap();
        let amount: u128 = payload[6].try_into().unwrap();

        // Create OrderKey struct
        let order_key = OrderKey {
            sell_token: sell_token,
            buy_token: buy_token,
            fee: fee,
            start_time: start_time,
            end_time: end_time,
        };

        // Call TWAMM contract
        let twamm_contract = self.twamm_contract.read();
        let twamm_dispatcher = ITWAMM::dispatcher(twamm_contract);
        let (order_id, sale_rate) = twamm_dispatcher.mint_and_increase_sell_amount(order_key, amount);

        // Emit event
        self.emit(Event::OrderCreated(OrderCreated {
            sender: sender,
            order_id: order_id,
            sale_rate: sale_rate,
        }));
    }

    #[external(v0)]
    fn set_twamm_contract(ref self: ContractState, address: ContractAddress) {
        self.twamm_contract.write(address);
    }

    #[external]
    fn on_receive(
        l2_token: ContractAddress,
        amount: u256,
        depositor: felt252,
        message: Span<felt252>
    ) -> bool {
        // Ensure the message contains the required parameters
        assert(message.len() == 4, 'Invalid message length');

        // Extract parameters from the message
        let other_token = *message[0];
        let is_long = *message[1] != 0;
        let interval = *message[2].try_into().unwrap();
        let min_output = *message[3].try_into().unwrap();

        // Call mint_position with the extracted parameters
        mint_position(
            token_a: l2_token,
            token_b: other_token.try_into().unwrap(),
            is_long,
            interval,
            amount,
            min_output
        );

        // Return true to indicate successful processing
        true
    }
}

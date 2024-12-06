use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use starknet::{EthAddress, ContractAddress};
use ekubo::extensions::interfaces::twamm::{OrderKey};
use twammbridge::types::{OrderDetails, OrderKey_Copy, Order_Created};
use twammbridge::errors::{ERROR_UNAUTHORIZED, ERROR_ALREADY_WITHDRAWN, ERROR_ZERO_AMOUNT, ERROR_NO_TOKENS_MINTED};

#[starknet::interface]
pub trait IMockTWAMMBridge<TContractState> {
    fn execute_deposit ( ref self: TContractState, message: OrderDetails)-> (u64, u128);
    fn execute_withdrawal( ref self: TContractState, message: OrderDetails);
    fn get_withdrawal_status(
        self: @TContractState,
        depositor: EthAddress,
        id: u64,
    ) -> bool;
}

#[starknet::contract]
pub mod MockTWAMMBridge {
    use super::{EthAddress, ContractAddress};
    use super::{OrderKey};
    use super::{OrderDetails, OrderKey_Copy, Order_Created};
    use twammbridge::errors::{ERROR_UNAUTHORIZED, ERROR_ALREADY_WITHDRAWN, ERROR_ZERO_AMOUNT, ERROR_NO_TOKENS_MINTED};
    use super::{Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess};


    #[storage]
    pub struct Storage {
        order_depositor_to_id_to_withdrawal_status: Map::<EthAddress, Map<u64, bool>>,
    }

   // Events
   #[event]
   #[derive(Drop, starknet::Event)]
   enum Event {
        MessageReceived: MessageReceived,
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

   #[derive(Drop, starknet::Event)]
   struct MessageReceived {
       message: OrderDetails
   }

   #[l1_handler]
   fn msg_handler_struct(ref self: ContractState, from_address: felt252, data: OrderDetails) {
       if data.order_operation == 0 {
           self.emit(MessageReceived { message: data });
           self.execute_deposit(data);
       }
       else if data.order_operation == 2 {
           self.emit(MessageReceived { message: data });
          self.execute_withdrawal(data);        
       } 
   }

    #[external(v0)]
    #[abi(embed_v0)]
    impl  MockTWAMMBridge of super::IMockTWAMMBridge<ContractState>  {
   
        fn execute_deposit(
            ref self: ContractState,
           message: OrderDetails
       ) -> (u64, u128) {

        let sender: EthAddress = message.sender.try_into().unwrap();
        //    assert(message.amount.try_into().unwrap() <= U128_MAX, 'Amount exceeds u128 max');
           let amount_u128: u128 = message.amount.try_into().unwrap();

           let order_key = OrderKey {
               sell_token: message.sell_token.try_into().unwrap(),
               buy_token: message.buy_token.try_into().unwrap(),
               fee: message.fee.try_into().unwrap(),
               start_time: message.start.try_into().unwrap(),
               end_time: message.end.try_into().unwrap(),
           };
           let mut id:u64 = 0;
           id = id + 1;

           let mut minted:u128 = 0;
           minted = minted + 1;

           self.emit(OrderCreated { id, sender, amount: amount_u128 });

           //to simulate return values from the ekubo positions contract
           (id, minted)
       }


        fn execute_withdrawal(
            ref self: ContractState,
           message: OrderDetails,
       ) {
            let depositor: EthAddress = message.sender.try_into().unwrap();

            let mut id:u64 = 0;
           id = id + 1;
            
           let stored_order_key = OrderKey {
            sell_token: 0x123.try_into().unwrap(),
            buy_token: 0x456.try_into().unwrap(),
            fee: 3,
            start_time: 1000,
            end_time: 2000,
        };

            let amount_sold: u128 = 1;

            // Mark as withdrawn
            self.order_depositor_to_id_to_withdrawal_status.entry(depositor).entry(id).write(true);

            self.emit(OrderWithdrawn { id, sender: depositor, amount_sold });
        }

        fn get_withdrawal_status(
            self: @ContractState,
            depositor: EthAddress,
            id: u64,
        ) -> bool {
            return self.order_depositor_to_id_to_withdrawal_status.entry(depositor).entry(id).read();
        }
    }
}

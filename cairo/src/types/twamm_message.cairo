// use starknet::{ContractAddress, EthAddress};
// use core::array::ArrayTrait;

// /// Represents a message for TWAMM operations between L1 and L2
// #[derive(Drop, Serde)]
// struct TWAMMMessage {
//     // Common fields
//     operation_type: u8,  // 0 for deposit, 1 for withdrawal
//     l1_token: EthAddress,
//     l1_sender: EthAddress,
//     l2_token: ContractAddress,
//     fee: u128,
//     start_time: u128,
//     end_time: u128,
//     amount: u128,
//     token_id: Option<u64>, // Only used for withdrawals
// }

// /// Trait to convert TWAMMMessage to and from felt252 arrays
// trait TWAMMMessageTrait {
//     fn to_felt_array(self: @TWAMMMessage) -> Array<felt252>;
//     fn from_felt_array(arr: Span<felt252>) -> TWAMMMessage;
// }

// impl TWAMMMessageImpl of TWAMMMessageTrait {
    
//     fn to_felt_array(self: @TWAMMMessage) -> Array<felt252> {
//         let mut arr = array![
//             (*self.operation_type).into(),
//             (*self.l1_token).into(),
//             (*self.l1_sender).into(),
//             (*self.l2_token).into(),
//             (*self.fee).into(),
//             (*self.start_time).into(),
//             (*self.end_time).into(),
//             (*self.amount).into(),
//         ];

//         // Add token_id for withdrawal messages
//         if self.operation_type == 1 {
//             if let Option::Some(id) = self.token_id {
//                 arr.append((*id).into());
//             }
//         }
        
//         arr
//     }

//     fn from_felt_array(arr: Span<felt252>) -> TWAMMMessage {
//         TWAMMMessage {
//             operation_type: (*arr[0]).try_into().unwrap(),
//             l1_token: (*arr[1]).try_into().unwrap(),
//             l1_sender: (*arr[2]).try_into().unwrap(),
//             l2_token: (*arr[3]).try_into().unwrap(),
//             fee: (*arr[4]).try_into().unwrap(),
//             start_time: (*arr[5]).try_into().unwrap(),
//             end_time: (*arr[6]).try_into().unwrap(),
//             amount: (*arr[7]).try_into().unwrap(),
//             token_id: if arr.len() > 8 { 
//                 Option::Some((*arr[8]).try_into().unwrap()) 
//             } else { 
//                 Option::None 
//             }
//         }
//     }
// }

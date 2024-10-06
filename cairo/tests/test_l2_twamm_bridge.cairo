use starknet::{
    get_contract_address, 
    get_block_timestamp, 
    contract_address_const, 
    ContractAddress, 
    syscalls::deploy_syscall
};
use array::ArrayTrait;
use snforge_std::{declare, DeclareResultTrait, ContractClassTrait, cheat_block_timestamp, CheatSpan, ContractClass};
use ekubo::l2_twamm_bridge::L2TWAMMBridge;
use ekubo::l2_twamm_bridge::IL2TWAMMBridgeDispatcher;
use ekubo::l2_twamm_bridge::IL2TWAMMBridgeDispatcherTrait;
use core::result::ResultTrait;

fn deploy_contract() -> ContractAddress {
    let contract = declare("L2TWAMMBridge").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}



#[test]
fn test_on_receive() {

    let contract_address = deploy_contract();


    // // Create a dispatcher to interact with the contract
    let bridge = IL2TWAMMBridgeDispatcher{contract_address};

    // Set up test parameters
    let l2_token: ContractAddress = contract_address_const::<0x123456789abcdef0>();
    let amount: u256 = 1000_u256;
    let depositor: felt252 = 0x123456;
    let message: Array<felt252> = array![1, 2, 3, 4, 5, 6, 7];

    // // Call the on_receive function
    let result = bridge.get_contract_version();

    // // Assert the result
    assert(result == 'L2TWAMMBridge v1.0', 'Incorrect contract version');

    // Call the on_receive function
    let result = bridge.on_receive(l2_token, amount, depositor, message.span());

    // Assert the result
    assert(result == true, 'on_receive should return true');

    // You can add more assertions here to check the state changes
    // For example, if you add a getter function to check sender_to_amount, you could use it here
}
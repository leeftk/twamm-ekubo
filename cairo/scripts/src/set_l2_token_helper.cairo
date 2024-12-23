use starknet::ContractAddress;
use sncast_std::{invoke, InvokeResult, get_nonce, FeeSettings, EthFeeSettings};

// Replace this with your deployed contract address
const CONTRACT_ADDRESS: felt252 = 
0x01542690fe52674d19297722ff58fe56532369b294080eb08461376dbac80c85;

fn main() {
    let max_fee = 999999999999999;
    let invoke_nonce = get_nonce('pending');
    
    // Replace this with the address you want to set
    let new_helper_address = 0x5e53e3a82f60396ee66d83170d81d23c626d3cad08e41bc84473c99115a8d90; // Your desired TokenBridgeHelper address

    let invoke_result = invoke(
        CONTRACT_ADDRESS.try_into().unwrap(),
        selector!("set_token_bridge_helper"), // Replace with your actual setter function name
        array![new_helper_address],
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(invoke_nonce)
    ).expect('set token bridge helper failed');

    assert(invoke_result.transaction_hash != 0, 'Invalid transaction');
    println!("Set TokenBridgeHelper Address Transaction: {:?}", invoke_result);
}
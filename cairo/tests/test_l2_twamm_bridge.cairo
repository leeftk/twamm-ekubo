use starknet::{
    get_contract_address, 
    get_block_timestamp, 
    contract_address_const, 
    ContractAddress, 
    syscalls::deploy_syscall
};
use array::ArrayTrait;
use snforge_std::{declare, DeclareResultTrait, ContractClassTrait, cheat_block_timestamp, CheatSpan, ContractClass};
use core::result::ResultTrait;
use ekubo::l2_twamm_bridge::L2TWAMMBridge;
use ekubo::l2_twamm_bridge::{IL2TWAMMBridgeDispatcher,IL2TWAMMBridgeDispatcherTrait};
use ekubo::l2_twamm_bridge::{OrderKey};
use ekubo::l2_twamm_bridge::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::test_token::{IERC20Dispatcher, IERC20DispatcherTrait};



fn deploy_contract() -> ContractAddress {
    let contract = declare("L2TWAMMBridge").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn positions() -> IPositionsDispatcher {
    IPositionsDispatcher {
        contract_address: contract_address_const::<
            0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
        >()}
}

fn deploy_token(
    class: @ContractClass, recipient: ContractAddress, amount: u256
) -> IERC20Dispatcher {
    let (contract_address, _) = class
        .deploy(@array![recipient.into(), amount.low.into(), amount.high.into()])
        .expect('Deploy token failed');

    IERC20Dispatcher { contract_address }
}



#[test]
#[fork("mainnet")]
fn test_on_receive() {

    let contract_address = deploy_contract();
    //contract.set_ekubo_address(contract_address);


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
    //let result = bridge.on_receive(l2_token, amount, depositor, message.span());

    // You can add more assertions here to check the state changes
    // For example, if you add a getter function to check sender_to_amount, you could use it here
}

#[test]
#[fork("mainnet")]
fn test_mint_and_increase_sell_amount() {

    let token_class = declare("TestToken").unwrap().contract_class();
    let this_contract_address: ContractAddress = get_contract_address();
    let (tokenA, tokenB) = (
        deploy_token(
            token_class,
            this_contract_address,
            amount: 1000000000000000000
        ),
        deploy_token(
            token_class,
            this_contract_address,
            amount: 1000000000000000000
        )
    );

    // let result = IERC20Dispatcher { contract_address: tokenA.contract_address }
    //         .mint(positions_contract.contract_address, transfer_amount);
    //     assert(result == true, 'mint should return true');

   let (token0, token1) = if tokenA.contract_address < tokenB.contract_address {
    (tokenA, tokenB)
    } else {
        (tokenB, tokenA)
    };
    // let contract_address = deploy_contract();
    // contract.set_ekubo_address(contract_address);
    let positions_contract = positions();
       

    // Set up test parameters
let tick: u128 = 1200_u128;
let amount: u128 = 500000_u128;
let this_contract_address: ContractAddress = get_contract_address();
let start_time = 1600302400_u64; // Example start time (Unix timestamp)
let end_time = 1680388800_u64;   // Example end time (Unix timestamp)

let order_key = OrderKey { 
    sell_token: token0.contract_address, 
    buy_token: token1.contract_address, 
    fee: 3000,
    start_time: start_time,
    end_time: end_time
}; // You need to define this based on your OrderKey struct
        // Approve the positions contract to spend tokens
        let transfer_amount = 10_u256;
        // Transfer tokens to the positions contract
       let result = IERC20Dispatcher { contract_address: tokenA.contract_address }
            .transfer(positions_contract.contract_address, transfer_amount);
        assert(result == true, 'transfer should return true');
        let result = IERC20Dispatcher { contract_address: tokenB.contract_address }
            .transfer(positions_contract.contract_address, transfer_amount);
    
    // Call the function using the dispatcher
    //positions_contract.mint_and_increase_sell_amount(order_key, 10);

    // Assert the results
    // assert(minted_amount > 0, 'Should have minted some amount');
    // assert(new_sell_amount > amount, 'New sell amount should be greater than original amount');

    // assert(result == true, 'mint_and_increase_sell_amount should return true');

    // You can add more assertions here to check the state changes
    // For example, if you add a getter function to check sender_to_amount, you could use it here
}


// //idea here is that we want to fork the mainnet and then instatiate the contract
//for ekubo and then we want to call mint on that so we'll fork mainnet deploy this with the address and 
//call it to see what it reutnrs

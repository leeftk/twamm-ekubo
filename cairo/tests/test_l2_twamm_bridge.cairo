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
use ekubo::l2_twamm_bridge::{IL2TWAMMBridgeDispatcher, IL2TWAMMBridgeDispatcherTrait};
use ekubo::types::order_key::OrderKey;
use ekubo::types::pool_key::PoolKey;
use ekubo::types::i129::i129;
use ekubo::l2_twamm_bridge::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::l2_twamm_bridge::{ICoreDispatcher, ICoreDispatcherTrait};
use ekubo::test_token::{IERC20Dispatcher, IERC20DispatcherTrait};

fn deploy_contract() -> ContractAddress {
    let contract = declare("L2TWAMMBridge").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn ekubo_core() -> ICoreDispatcher {
    ICoreDispatcher {
        contract_address: contract_address_const::<
            0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
        >()
    }
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


fn setup() -> PoolKey {
    let token_class = declare("TestToken").unwrap().contract_class();
    let owner = get_contract_address();
    let (tokenA, tokenB) = (
        deploy_token(
            token_class,
            owner,
            100000
        ),
        deploy_token(
            token_class,
            owner,
            100000
        )
    );
    let (token0, token1) = if tokenA.contract_address < tokenB.contract_address {
        (tokenA, tokenB)
    } else {
        (tokenB, tokenA)
    };
    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 354892,
        extension: contract_address_const::<0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc>(),
    };
    (pool_key)
}



#[test]
#[fork("mainnet")]
fn test_mint_and_increase_sell_amount() {

    

    let pool_key = setup();
    let positions_contract = positions(); 

    let pool_key = PoolKey {
        token0: pool_key.token0,
        token1: pool_key.token1,
        fee: 0,
        tick_spacing: 354892,
        extension: contract_address_const::<0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc>(),
    };

    ekubo_core().initialize_pool(pool_key, i129 { mag: 0, sign: false });
//     // Set up test parameters
    let current_timestamp = get_block_timestamp();
    // let duration = 7 * 24 * 60 * 60; // 7 days in seconds
    let difference = 16 - (current_timestamp % 16);
    let power_of_16 = 16 * 16; // 16 hours in seconds
    let start_time = (current_timestamp + difference);
    let end_time = start_time + 64;

    let order_key = OrderKey { 
        sell_token: pool_key.token0, 
        buy_token: pool_key.token1, 
        fee: 0,
        start_time: start_time,
        end_time: end_time
    };
        // Approve the positions contract to spend tokens
    let transfer_amount = 10000_u256;
    // Transfer tokens to the positions contract
   let result = IERC20Dispatcher { contract_address: pool_key.token0 }.transfer(positions_contract.contract_address, transfer_amount);
    assert(result == true, 'transfer should return true');
    let result = IERC20Dispatcher { contract_address: pool_key.token1 }.transfer(positions_contract.contract_address, transfer_amount);
    
//     // Call the function using the dispatcher
    let (minted_amount, new_sell_amount) = positions_contract.mint_and_increase_sell_amount(order_key, 10000);

    //Assert the results
   // ... existing code ...
// ... existing code ...
assert_eq!(minted_amount > 0, true, "New sell amount should be greater than original amount");
assert_eq!(new_sell_amount > 10000, true, "New sell amount should be greater than original amount");
// ... existing code ...

    
}

//     // Approve the positions contract to spend tokens
//     let transfer_amount = 10000_u256;
//     // Transfer tokens to the positions contract
//    let result = IERC20Dispatcher { contract_address: token0.contract_address }.transfer(positions_contract.contract_address, transfer_amount);
//     assert(result == true, 'transfer should return true');
//     let result = IERC20Dispatcher { contract_address: token1.contract_address }.transfer(positions_contract.contract_address, transfer_amount);
    
// //     // Call the function using the dispatcher
//      positions_contract.mint_and_increase_sell_amount(order_key, 10000);

    // Assert the results
    // assert(minted_amount > 0, 'Should have minted some amount');
    // assert(new_sell_amount > amount, 'New sell amount should be greater than original amount');

    // assert(result == true, 'mint_and_increase_sell_amount should return true');

//}


// // #[test]
// // #[fork("mainnet")]
// // fn test_on_receive() {

// //     let contract_address = deploy_contract();
// //     //contract.set_positions_address(contract_address);
// //     // // Create a dispatcher to interact with the contract
// //     // let (tokenA, tokenB) = setUpTokens();
// //     // let (token0, token1) = if tokenA.contract_address < tokenB.contract_address {
// //     //     (tokenA, tokenB)
// //     //     } else {
// //     //         (tokenB, tokenA)
// //     //     };
// //     let bridge = IL2TWAMMBridgeDispatcher{contract_address};
// //     //create a message with encoded parameters for mint_and_increase_sell_amount
// //     let start_time = 1717286400;
// //     let end_time = 1717372800;

// //     let order_key = OrderKey { 
// //         sell_token: ContractAddress::from(0x1), 
// //         buy_token: ContractAddress::from(0x2), 
// //         fee: 3000,
// //         start_time: start_time,
// //         end_time: end_time
// //     };

// //     let mut serialized = order_key.serialize(ref output_array);

// //     // Call the on_receive function
// //     // let result = bridge.get_contract_version();

// //     // // // Assert the result
// //     // assert(result == 'L2TWAMMBridge v1.0', 'Incorrect contract version');

// //     // Call the on_receive function
// //     //let result = bridge.on_receive(l2_token, amount, depositor, message.span());

    
// // }




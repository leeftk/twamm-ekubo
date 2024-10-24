use starknet::{
    get_contract_address, get_block_timestamp, contract_address_const, ContractAddress,
    syscalls::deploy_syscall
};
use array::ArrayTrait;
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, cheat_block_timestamp, CheatSpan, ContractClass
};
use core::result::ResultTrait;
use twammbridge::l2_twamm_bridge::L2TWAMMBridge;
use twammbridge::l2_twamm_bridge::{IL2TWAMMBridgeDispatcher, IL2TWAMMBridgeDispatcherTrait};
use twammbridge::test_token::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::types::keys::{PoolKey};
use ekubo::extensions::interfaces::twamm::{OrderKey, OrderInfo};
use ekubo::types::i129::i129;
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};


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
        >()
    }
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
        deploy_token(token_class, owner, 100000), deploy_token(token_class, owner, 100000)
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
        extension: contract_address_const::<
            0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc
        >(),
    };
    (pool_key)
}

#[derive(Drop, Serde)]
struct Message {
    operation_type: u8,
    order_key: OrderKey,
    id: u64,
    sale_rate_delta: u128,
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
        extension: contract_address_const::<
            0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc
        >(),
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
    let result = IERC20Dispatcher { contract_address: pool_key.token0 }
        .transfer(positions_contract.contract_address, transfer_amount);
    assert(result == true, 'transfer should return true');
    let result = IERC20Dispatcher { contract_address: pool_key.token1 }
        .transfer(positions_contract.contract_address, transfer_amount);

    //     // Call the function using the dispatcher
    let (minted_amount, new_sell_amount) = positions_contract
        .mint_and_increase_sell_amount(order_key, 10000);

    assert_eq!(minted_amount > 0, true, "New sell amount should be greater than original amount");
    assert_eq!(
        new_sell_amount > 10000, true, "New sell amount should be greater than original amount"
    );
}

#[test]
#[fork("mainnet")]
fn test_on_receive() {
    let pool_key = setup();
    let positions_contract = positions();
    let pool_key = PoolKey {
        token0: pool_key.token0,
        token1: pool_key.token1,
        fee: 0,
        tick_spacing: 354892,
        extension: contract_address_const::<
            0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc
        >(),
    };

    ekubo_core().initialize_pool(pool_key, i129 { mag: 0, sign: false });
    // Set up test parameters

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

    
    let contract_address = deploy_contract();
    let bridge = IL2TWAMMBridgeDispatcher { contract_address };
    bridge.set_positions_address(positions_contract.contract_address);

    let order_key = OrderKey {
        sell_token: pool_key.token0,
        buy_token: pool_key.token1,
        fee: 0,
        start_time: start_time,
        end_time: end_time
    };
    
    let message = Message {
        operation_type: 0, 
        order_key,
        id: 0,
        sale_rate_delta: 0,
    };
    let mut output_array = array![];
    message.serialize(ref output_array);
    
    let mut span_array = output_array.span();
    assert(span_array.len() > 0, 'span_array should not be empty');
    // Define the missing variables
    let l2_token = pool_key.token0; // Using token0 as an example
    let amount = 1000_u128; // Example amount
    let depositor = get_contract_address();

    // Transfer tokens to the positions contract
    let result = IERC20Dispatcher { contract_address: pool_key.token0 }
        .transfer(positions_contract.contract_address, 10000);
    assert(result == true, 'transfer should return true');
    let result = IERC20Dispatcher { contract_address: pool_key.token1 }
        .transfer(positions_contract.contract_address, 10000);

    // Call the on_receive function
    let result = bridge.on_receive(l2_token, amount, depositor, span_array);
    assert(result == true, 'on_receive should return true');
}

// #[test]
// #[fork("mainnet")]
// fn test_on_receive_with_sale_rate_delta() {
//     let pool_key = setup();
//     let positions_contract = positions();
//     let pool_key = PoolKey {
//         token0: pool_key.token0,
//         token1: pool_key.token1,
//         fee: 0,
//         tick_spacing: 354892,
//         extension: contract_address_const::<
//             0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc
//         >(),
//     };

//     ekubo_core().initialize_pool(pool_key, i129 { mag: 0, sign: false });
//     // Set up test parameters

//     let current_timestamp = get_block_timestamp();
//     // let duration = 7 * 24 * 60 * 60; // 7 days in seconds
//     let difference = 16 - (current_timestamp % 16);
//     let power_of_16 = 16 * 16; // 16 hours in seconds
//     let start_time = (current_timestamp + difference);
//     let end_time = start_time + 64;

//     let order_key = OrderKey {
//         sell_token: pool_key.token0,
//         buy_token: pool_key.token1,
//         fee: 0,
//         start_time: start_time,
//         end_time: end_time
//     };

    
//     let contract_address = deploy_contract();
//     let bridge = IL2TWAMMBridgeDispatcher { contract_address };
//     bridge.set_positions_address(positions_contract.contract_address);
//     bridge.set_token_bridge_address(token_bridge_address);
//     let order_key = OrderKey {
//         sell_token: pool_key.token0,
//         buy_token: pool_key.token1,
//         fee: 0,
//         start_time: start_time,
//         end_time: end_time
//     };
    
//     let message = Message {
//         operation_type: 1, 
//         order_key,
//         id: 0,
//         sale_rate_delta: 0,
//     };
//     let mut output_array = array![];
//     message.serialize(ref output_array);
    
//     let mut span_array = output_array.span();
//     assert(span_array.len() > 0, 'span_array should not be empty');
//     // Define the missing variables
//     let l2_token = pool_key.token0; // Using token0 as an example
//     let amount = 1000_u128; // Example amount
//     let depositor = get_contract_address();

//     // Transfer tokens to the positions contract
//     let result = IERC20Dispatcher { contract_address: pool_key.token0 }
//         .transfer(positions_contract.contract_address, 10000);
//     assert(result == true, 'transfer should return true');
//     let result = IERC20Dispatcher { contract_address: pool_key.token1 }
//         .transfer(positions_contract.contract_address, 10000);

//     // Call the on_receive function
//     let result = bridge.on_receive(l2_token, amount, depositor, span_array);
//     assert(result == false, 'on_receive should return true');
// }

use starknet::{
    get_contract_address, get_block_timestamp, contract_address_const, ContractAddress,
    syscalls::deploy_syscall
};
use array::ArrayTrait;
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, cheat_block_timestamp, CheatSpan, ContractClass, start_cheat_caller_address
};
use core::result::ResultTrait;
use twammbridge::l2_twamm_bridge::L2TWAMMBridge;
use twammbridge::l2_twamm_bridge::{IL2TWAMMBridgeDispatcher, IL2TWAMMBridgeDispatcherTrait};
use ekubo::interfaces::mathlib::{IMathLibDispatcherTrait, dispatcher as mathlib};
use twammbridge::test_token::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::types::keys::{PoolKey};
use ekubo::extensions::interfaces::twamm::{ITWAMMDispatcher,ITWAMMDispatcherTrait,OrderKey, OrderInfo};
use ekubo::types::i129::i129;
use ekubo::types::bounds::{Bounds};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};
use ekubo::interfaces::router::{IRouterDispatcher, IRouterDispatcherTrait, RouteNode, TokenAmount};
use starknet::EthAddress;
use core::num::traits::{Zero, Sqrt, WideMul};


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

// fn twamm() -> ITWAMMDispatcher{
//     ITWAMMDispatcher{
//         contract_address_const::<
//                 0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc
//             >()

//     }
// }

fn positions() -> IPositionsDispatcher {
    IPositionsDispatcher {
        contract_address: contract_address_const::<
            0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
        >()
    }
}

fn router() -> IRouterDispatcher {
    IRouterDispatcher {
        contract_address: contract_address_const::<
            0x0199741822c2dc722f6f605204f35e56dbc23bceed54818168c4c49e4fb8737e
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
        deploy_token(token_class, owner, 10000000000000), deploy_token(token_class, owner, 10000000000)
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

// assumes there is 0 liquidity so swaps are free
fn move_price_to_tick(pool_key: PoolKey, tick: i129) {
    let tick_current = ekubo_core().get_pool_price(pool_key).tick;
    if tick_current < tick {
        router()
            .swap(
                RouteNode {
                    pool_key, sqrt_ratio_limit: mathlib().tick_to_sqrt_ratio(tick), skip_ahead: 0,
                },
                TokenAmount { token: pool_key.token1, amount: i129 { mag: 1000, sign: false }, }
            );
    } else if tick_current > tick {
        router()
            .swap(
                RouteNode {
                    pool_key,
                    sqrt_ratio_limit: mathlib().tick_to_sqrt_ratio(tick) + 1,
                    skip_ahead: 0,
                },
                TokenAmount { token: pool_key.token0, amount: i129 { mag: 1000, sign: false }, }
            );
    }
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
fn test_mint_and_withdraw_proceeds_from_sale_to_self() {
    let MAX_TICK_SPACING: u128 = 354892;
    let pool_key = setup();
    let positions_contract = positions();

    
    ekubo_core().initialize_pool(pool_key, i129 { mag: 0, sign: false });
    IERC20Dispatcher { contract_address: pool_key.token0 }
    .transfer(positions().contract_address, 100);
    IERC20Dispatcher { contract_address: pool_key.token1 }
    .transfer(positions().contract_address, 100);

   positions()
   .mint_and_deposit(
       pool_key,
       Bounds { 
        lower: i129 { mag: 88368108, sign: true },
        upper: i129 { mag: 88368108, sign: false },
       },
       Zero::zero()
   );
   // Get the liquidity of the pool
   let liquidity = ekubo_core().get_pool_liquidity(pool_key);
   assert(liquidity > 0, 'liquidity should be greater');
   
    // Set up time parameters
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
    
    let fake_caller = contract_address_const::<'fake_caller'>();
    let token0_balance = IERC20Dispatcher { contract_address: pool_key.token0 }
    .balanceOf(get_contract_address());
    let token1_balance = IERC20Dispatcher { contract_address: pool_key.token1 }
    .balanceOf(get_contract_address());
    assert(token0_balance >= 1000000, 'Insufficient token0 balance');
    assert(token1_balance >= 1000000, 'Insufficient token1 balance');
    //transfer tokens to positions contract
    IERC20Dispatcher { contract_address: pool_key.token0 }
    .transfer(positions().contract_address, 1000000);  // Increased to 1M tokens
    IERC20Dispatcher { contract_address: pool_key.token1 }
    .transfer(positions().contract_address, 1000000);  // 

    let token0_balance = IERC20Dispatcher { contract_address: pool_key.token0 }
    .balanceOf(positions().contract_address);
    let token1_balance = IERC20Dispatcher { contract_address: pool_key.token1 }
    .balanceOf(positions().contract_address);
    assert(token0_balance >= 1000000, 'Insufficient token0 balance');
    assert(token1_balance >= 1000000, 'Insufficient token1 balance');
    // // Call the function using the dispatcher
    let (token_id, new_sell_amount) = positions_contract
        .mint_and_increase_sell_amount(order_key, 100);

    assert_eq!(token_id > 0, true, "token_id should be greater than 0");
    assert_eq!(
        new_sell_amount > 10000, true, "New sell amount should be greater than original amount"
    );
     let twam_address = contract_address_const::<
                0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc
            >();
    cheat_block_timestamp(twam_address, start_time + 16, CheatSpan::Indefinite);
    IERC20Dispatcher { contract_address: pool_key.token0 }
    .transfer(router().contract_address, 1000000);
    IERC20Dispatcher { contract_address: pool_key.token1 }
    .transfer(router().contract_address, 1000000);
    move_price_to_tick(pool_key, i129 { mag: 354892, sign: false });
    
    let initial_time = get_block_timestamp();
    let new_time = initial_time + 3600; // 1 hour later
    cheat_block_timestamp(twam_address, new_time, CheatSpan::Indefinite);

    let result = positions_contract.withdraw_proceeds_from_sale_to_self(token_id, order_key);
    assert(result != 0, 'withdraw_proceeds_from');
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
//     bridge.set_token_bridge_address(contract_address_const::<
//         0x07754236934aeaf4c29d287b94b5fde8687ba7d59466ea6b80f3f57d6467b7d6
//     >());
//     //bridge.set_token_bridge_address(token_bridge_address);
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
//     let depositor = EthAddress { address: 0x6B175474E89094C44Da98b954EedeAC495271d0F }; 

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

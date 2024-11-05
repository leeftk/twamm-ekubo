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

// At the top after imports
const TWAMM_ADDRESS: felt252 = 0x043e4f09c32d13d43a880e85f69f7de93ceda62d6cf2581a582c6db635548fdc;
const TOKEN_BRIDGE_ADDRESS: felt252 = 0x07754236934aeaf4c29d287b94b5fde8687ba7d59466ea6b80f3f57d6467b7d6;
const L1_DAI_ADDRESS: felt252 = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

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

/// Sets up a pool with initial liquidity
fn setup_pool_with_liquidity(pool_key: PoolKey) {
    ekubo_core().initialize_pool(pool_key, i129 { mag: 0, sign: false });
    
    // Transfer initial liquidity
    IERC20Dispatcher { contract_address: pool_key.token0 }
        .transfer(positions().contract_address, 100);
    IERC20Dispatcher { contract_address: pool_key.token1 }
        .transfer(positions().contract_address, 100);

    // Mint initial position
    positions()
        .mint_and_deposit(
            pool_key,
            Bounds { 
                lower: i129 { mag: 88368108, sign: true },
                upper: i129 { mag: 88368108, sign: false },
            },
            Zero::zero()
        );
}

/// Creates an order key with standard test parameters
fn create_test_order_key(pool_key: PoolKey) -> OrderKey {
    let current_timestamp = get_block_timestamp();
    let difference = 16 - (current_timestamp % 16);
    let start_time = (current_timestamp + difference);
    let end_time = start_time + 64;

    OrderKey {
        sell_token: pool_key.token0,
        buy_token: pool_key.token1,
        fee: 0,
        start_time: start_time,
        end_time: end_time
    }
}

/// Transfers tokens to a target contract
fn transfer_tokens_to_contract(token0: ContractAddress, token1: ContractAddress, target: ContractAddress, amount: u256) {
    IERC20Dispatcher { contract_address: token0 }
        .transfer(target, amount);
    IERC20Dispatcher { contract_address: token1 }
        .transfer(target, amount);
}

/// Asserts token balances are sufficient
fn assert_token_balances(token0: ContractAddress, token1: ContractAddress, owner: ContractAddress, min_amount: u256) {
    let token0_balance = IERC20Dispatcher { contract_address: token0 }
        .balanceOf(owner);
    let token1_balance = IERC20Dispatcher { contract_address: token1 }
        .balanceOf(owner);
    assert(token0_balance >= min_amount, 'Insufficient token0 balance');
    assert(token1_balance >= min_amount, 'Insufficient token1 balance');
}

/// Deploys and configures the bridge contract
fn setup_bridge() -> IL2TWAMMBridgeDispatcher {
    let contract_address = deploy_contract();
    let bridge = IL2TWAMMBridgeDispatcher { contract_address };
    bridge.set_positions_address(positions().contract_address);
    bridge.set_token_bridge_address(contract_address_const::<TOKEN_BRIDGE_ADDRESS>());
    bridge
}

#[starknet::interface]
pub trait ITokenBridge<TContractState> {
    fn initiate_token_withdraw(
        ref self: TContractState,
        l1_token: EthAddress,
        l1_recipient: EthAddress,
        amount: u256
    );

    fn handle_deposit(
        ref self: TContractState, 
        from_address: felt252, 
        l2_recipient: ContractAddress, 
        amount: u256,
    );

    fn handle_deposit_with_message(
        ref self: TContractState,
        from_address: felt252,
        l1_token: EthAddress,
        depositor: EthAddress,
        l2_recipient: ContractAddress,
        amount: u256,
        message: Span<felt252>,
    );
}



#[test]
#[fork("mainnet")]
fn test_on_receive_create_twamm_order() {
    // Initial setup
    let pool_key = setup();
    setup_pool_with_liquidity(pool_key);
    
    // Assert initial balances and transfer tokens
    assert_token_balances(pool_key.token0, pool_key.token1, get_contract_address(), 10000);
    transfer_tokens_to_contract(pool_key.token0, pool_key.token1, positions().contract_address, 10000);
    
    // Setup bridge and order
    let bridge = setup_bridge();
    let order_key = create_test_order_key(pool_key);
    
    // Create message array with new format
    let mut message_array = array![
        0, // operation_type
        L1_DAI_ADDRESS, // from_address/depositor
        0, // padding/unused
        0, // padding/unused
        0, // padding/unused
        pool_key.token0.into(), // sell_token
        pool_key.token1.into(), // buy_token
        0, // fee
        order_key.start_time.into(), // start_time
        order_key.end_time.into(), // end_time
    ];
    
    // Test parameters and execution
    let amount = 1000_u128;
    let depositor = EthAddress { address: L1_DAI_ADDRESS };
    let result = bridge.on_receive(pool_key.token0, amount, depositor, message_array.span());
    assert(result == true, 'on_receive should return true');
}


#[test]
#[fork("mainnet")]
fn test_withdraw_proceeds_via_message() {
    // Initial setup
    let pool_key = setup();
    setup_pool_with_liquidity(pool_key);
    
    // Assert initial balances and transfer tokens
    assert_token_balances(pool_key.token0, pool_key.token1, get_contract_address(), 10000);
    transfer_tokens_to_contract(pool_key.token0, pool_key.token1, positions().contract_address, 10000);
    
    // Setup bridge and order
    let bridge = setup_bridge();
    let order_key = create_test_order_key(pool_key);
    
    // Initial deposit message
    let mut deposit_message = array![
        0, // operation_type
        L1_DAI_ADDRESS, // from_address/depositor
        0, // padding/unused
        0, // padding/unused
        0, // padding/unused
        pool_key.token0.into(), // sell_token
        pool_key.token1.into(), // buy_token
        0, // fee
        order_key.start_time.into(), // start_time
        order_key.end_time.into(), // end_time
    ];
    
    // // Test parameters and execution
    let amount = 1000_u128;
    let depositor = EthAddress { address: L1_DAI_ADDRESS };
    // let result = bridge.on_receive(pool_key.token0, amount, depositor, deposit_message.span());
    // assert(result == true, 'deposit should succeed');

    // Time and price setup remains the same
    let twam_address = contract_address_const::<TWAMM_ADDRESS>();
    cheat_block_timestamp(twam_address, order_key.start_time + 16, CheatSpan::Indefinite);
    
    transfer_tokens_to_contract(pool_key.token0, pool_key.token1, router().contract_address, 1000000);
    move_price_to_tick(pool_key, i129 { mag: 354892, sign: false });
    
    let new_time = get_block_timestamp() + 3600;
    cheat_block_timestamp(twam_address, new_time, CheatSpan::Indefinite);
    
    let token_id = bridge.get_id_from_depositor(depositor);
    
    // Withdrawal message with new format
    let mut withdrawal_message = array![
        1, // operation_type for withdrawal
        L1_DAI_ADDRESS, // from_address/depositor
        0, // padding/unused
        0, // padding/unused
        0, // padding/unused
        pool_key.token0.into(), // sell_token
        pool_key.token1.into(), // buy_token
        0, // fee
        order_key.start_time.into(), // start_time
        order_key.end_time.into(), // end_time
        token_id.into(), // token_id
    ];

    // let result = bridge.on_receive(pool_key.token0, amount, depositor, withdrawal_message.span());
    // assert(result == true, 'withdrawal should succeed');
}



#[test]
#[fork("mainnet")]
fn test_send_message_to_bridge() {
    // L2 DAI token address
    let l2_dai_address = contract_address_const::<0x06abf2636072eb8716d55cb1a9f885cb2c5ed9013c69d8c8e035a8fb49c414e3>();
    let token_bridge_address = contract_address_const::<0x0616757a151c21f9be8775098d591c2807316d992bbc3bb1a5c1821630589256>();
    
    // Create DAI dispatcher
    let l2_dai = IERC20Dispatcher { contract_address: l2_dai_address };
    let caller_address = contract_address_const::<0x04758595201d9d01be9f8bd232fe3a1c0b5c7b953219c9faa35779b3e73c214c>();
    start_cheat_caller_address(get_contract_address(), caller_address);
 
    // Swap the order of arguments - first arg should be the address to spoof FROM, second arg is the address to spoof TO
    
    //verify balance is greater than 100
    start_cheat_caller_address(l2_dai_address, caller_address);
    // assert(l2_dai.balanceOf(caller_address) > 100, 'Balance should');
    // let result = l2_dai.transfer(get_contract_address(), 100);
    // assert(result == true, 'Transfer should return true');
    // assert(l2_dai.balanceOf(get_contract_address()) > 0, 'Balance should1');
    let l1_dai_bridge_address = EthAddress { address: 0xCA14057f85F2662257fd2637FdEc558626bCe554 };
    // // Approve the bridge to spend our tokens
    // l2_dai.approve(token_bridge_address, 100);
    ITokenBridgeDispatcher { contract_address: token_bridge_address }
        .handle_deposit(l1_dai_bridge_address.into(), get_contract_address(), 100);
  
    // ITokenBridgeDispatcher { contract_address: token_bridge_address }
    //     .initiate_token_withdraw(
    //         EthAddress { address: 0x6B175474E89094C44Da98b954EedeAC495271d0F }, // L1 DAI address
    //         EthAddress { address: 0x1B382A7b4496F14e0AAA2DA1E1626Da400426A03 }, // L1 recipient (using same address for example)
    //         100
    //     );
}


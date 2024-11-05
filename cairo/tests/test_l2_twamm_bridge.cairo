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

/// Creates a standard message array for TWAMM operations
fn create_twamm_message(
    operation_type: u8,
    pool_key: PoolKey,
    order_key: OrderKey,
    token_id: Option<u64>
) -> Array<felt252> {
    let mut message = array![
        operation_type.into(),
        L1_DAI_ADDRESS.into(),
        0,
        0,
        0,
        pool_key.token0.into(),
        pool_key.token1.into(),
        0,
        order_key.start_time.into(),
        order_key.end_time.into(),
    ];
    
    // Add token_id for withdrawal messages
    if operation_type == 1 {
        message.append(token_id.unwrap().into());
    }
    
    message
}

/// Sets up a standard test environment
fn setup_test_environment() -> (PoolKey, IL2TWAMMBridgeDispatcher, OrderKey) {
    let pool_key = setup();
    setup_pool_with_liquidity(pool_key);
    
    assert_token_balances(pool_key.token0, pool_key.token1, get_contract_address(), 10000);
    transfer_tokens_to_contract(pool_key.token0, pool_key.token1, positions().contract_address, 10000);
    
    let bridge = setup_bridge();
    let order_key = create_test_order_key(pool_key);
    
    (pool_key, bridge, order_key)
}

#[test]
#[fork("mainnet")]
fn test_on_receive_create_twamm_order() {
    let (pool_key, bridge, order_key) = setup_test_environment();
    
    let message = create_twamm_message(0, pool_key, order_key, Option::None);
    let amount = 1000_u128;
    let depositor = EthAddress { address: L1_DAI_ADDRESS };
    
    let result = bridge.on_receive(pool_key.token0, amount, depositor, message.span());
    assert(result == true, 'on_receive should return true');
}

#[test]
#[fork("mainnet")]
fn test_withdraw_proceeds_via_message() {
    let (pool_key, bridge, order_key) = setup_test_environment();
    
    // Initial deposit
    let deposit_message = create_twamm_message(0, pool_key, order_key, Option::None);
    let amount = 1000_u128;
    let depositor = EthAddress { address: L1_DAI_ADDRESS };
    let result = bridge.on_receive(pool_key.token0, amount, depositor, deposit_message.span());
    assert(result == true, 'deposit should succeed');

    // Setup time and price conditions
    let twam_address = contract_address_const::<TWAMM_ADDRESS>();
    cheat_block_timestamp(twam_address, order_key.start_time + 16, CheatSpan::Indefinite);
    
    transfer_tokens_to_contract(pool_key.token0, pool_key.token1, router().contract_address, 1000000);
    move_price_to_tick(pool_key, i129 { mag: 354892, sign: false });
    
    let new_time = get_block_timestamp() + 3600;
    cheat_block_timestamp(twam_address, new_time, CheatSpan::Indefinite);
    
    // Withdrawal
    let token_id = bridge.get_id_from_depositor(depositor);
    let withdrawal_message = create_twamm_message(1, pool_key, order_key, Option::Some(token_id));
    
    let result = bridge.on_receive(pool_key.token0, amount, depositor, withdrawal_message.span());
    assert(result == true, 'withdrawal should succeed');
}


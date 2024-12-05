use starknet::{ContractAddress, contract_address_const, get_caller_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use starknet::EthAddress;
use super::interfaces::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};
use super::constants::TOKEN_BRIDGE_MAPPING;
use super::errors::{ERROR_UNAUTHORIZED, ERROR_INVALID_TOKEN};

#[starknet::interface]
trait ITokenBridgeHelper<TContractState> {
    fn get_l2_bridge_from_l1_token(
        self: @TContractState, 
        token_address: felt252
    ) -> ContractAddress;
}

#[starknet::contract]
mod TokenBridgeHelper {
    use super::{
        ContractAddress, contract_address_const, get_caller_address, EthAddress, Map, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait,
        TOKEN_BRIDGE_MAPPING, ERROR_UNAUTHORIZED, ERROR_INVALID_TOKEN
    };

    // Storage
    #[storage]
    struct Storage {
        l1_token_to_l2_token_bridge: Map::<felt252, ContractAddress>,
        contract_owner: ContractAddress,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState) {
        self.contract_owner.write(get_caller_address());
        self.initialize_bridge_mappings()
    }

    // External functions
    #[abi(embed_v0)]
    impl TokenBridgeHelper of super::ITokenBridgeHelper<ContractState> {
        // Retrieves the L2 bridge address associated with a given L1 token address.
        fn get_l2_bridge_from_l1_token(
            self: @ContractState, 
            token_address: felt252
        ) -> ContractAddress {
            let bridge = self.l1_token_to_l2_token_bridge.read(token_address);
            // Ensures the bridge address is not zero, indicating a valid token.
            assert(!bridge.is_zero(), 'Invalid Token');
            bridge
        }
    }

    // Internal helper functions
    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }

        
        // Initializes the mapping of L1 token addresses to their corresponding L2 bridge addresses.
        fn initialize_bridge_mappings(
            ref self: ContractState, 
        ) {     
            let span = TOKEN_BRIDGE_MAPPING.span();
            for tuple in span {
                let (l1_address, l2_bridge) = *tuple;
                self.l1_token_to_l2_token_bridge.write(l1_address.try_into().unwrap(), l2_bridge.try_into().unwrap());
            };
        }
    }
}
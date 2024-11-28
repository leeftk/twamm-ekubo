use starknet::{ContractAddress, contract_address_const, get_caller_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use starknet::EthAddress;
use super::interfaces::{ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait};

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
        ContractAddress, contract_address_const, get_caller_address, EthAddress, Map, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait
    };

    // Error Constants
    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';
    const ERROR_INVALID_TOKEN: felt252 = 'Invalid token address';

    // Storage
    #[storage]
    struct Storage {
        l2_bridge_to_l2_token: Map::<ContractAddress, ContractAddress>,
        l2_token_to_l1_token: Map::<ContractAddress, EthAddress>,
        l1_token_to_l2_token_bridge: Map<felt252, ContractAddress>,
        contract_owner: ContractAddress,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState) {
        self.contract_owner.write(get_caller_address());

        self.l1_token_to_l2_token_bridge.write(
            0x0000000000000000000000000000000000455448, // ETH
            contract_address_const::<0x04c5772d1914fe6ce891b64eb35bf3522aeae1315647314aac58b01137607f3f>()
        );
        
        self.l1_token_to_l2_token_bridge.write(
            0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766, // STRK
            contract_address_const::<0x0594c1582459ea03f77deaf9eb7e3917d6994a03c13405ba42867f83d85f085d>()
        );
        
        self.l1_token_to_l2_token_bridge.write(
            0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC
            contract_address_const::<0x0028729b12ce1140cbc1e7cbc7245455d3c15fa0c7f5d2e9fc8e0441567f6b50>()
        );
        
        self.l1_token_to_l2_token_bridge.write(
            0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0, // USDT
            contract_address_const::<0x3913d184e537671dfeca3f67015bb845f2d12a26e5ec56bdc495913b20acb08>()
        );
        
        self.l1_token_to_l2_token_bridge.write(
            0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC, // WBTC
            contract_address_const::<0x025a3820179262679392e872d7daaa44986af7caae1f41b7eedee561ca35a169>()
        );
        
        self.l1_token_to_l2_token_bridge.write(
            0xB82381A3fBD3FaFA77B3a7bE693342618240067b, // wstETH
            contract_address_const::<0x0172393a285eeac98ea136a4be473986a58ddd0beaf158517bc32166d0328824>()
        );
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
    }
}


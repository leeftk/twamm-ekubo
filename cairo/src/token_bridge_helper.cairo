use starknet::{ContractAddress, contract_address_const, get_caller_address};
use starknet::storage::{
    Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
    StoragePathEntry, StorageMapWriteAccess
};
use starknet::EthAddress;

#[starknet::interface]
pub(crate) trait IERC20<TContractState> {
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, account: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait ITokenBridge<TContractState> {
    fn initiate_token_withdraw(
        ref self: TContractState, l1_token: EthAddress, l1_recipient: EthAddress, amount: u256
    );
    fn handle_deposit(
        ref self: TContractState,
        from_address: felt252,
        l2_recipient: ContractAddress,
        amount: u256,
    );
}

#[starknet::interface]
trait ITokenBridgeHelper<TContractState> {
    fn get_l2_bridge_by_l2_token(
        ref self: TContractState, buy_token: ContractAddress
    ) -> ContractAddress;
    fn get_l1_token_by_l2_token(
        ref self: TContractState, l2_token: ContractAddress
    ) -> EthAddress;
    fn get_l2_bridge_from_l1_token(
        ref self: TContractState, token_address: felt252
    ) -> ContractAddress;
    fn send_token_to_l1(
        ref self: TContractState, 
        l1_token: EthAddress, 
        l1_recipient: EthAddress, 
        amount: u256
    );
}

#[starknet::contract]
mod TokenBridgeHelper {
    use super::{
        ContractAddress, contract_address_const, get_caller_address, EthAddress, Map, ITokenBridgeDispatcher, ITokenBridgeDispatcherTrait
    };

    const ERROR_UNAUTHORIZED: felt252 = 'Unauthorized';
    const ERROR_INVALID_TOKEN: felt252 = 'Invalid token address';

    #[storage]
    struct Storage {
        l2_bridge_to_l2_token: Map::<ContractAddress, ContractAddress>,
        l2_token_to_l1_token: Map::<ContractAddress, EthAddress>,
        contract_owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.contract_owner.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl TokenBridgeHelper of super::ITokenBridgeHelper<ContractState> {
        fn get_l2_bridge_by_l2_token(
            ref self: ContractState, 
            buy_token: ContractAddress
        ) -> ContractAddress {
            self.assert_only_owner();
            self.l2_bridge_to_l2_token.read(buy_token)
        }

        fn get_l1_token_by_l2_token(
            ref self: ContractState, 
            l2_token: ContractAddress
        ) -> EthAddress {
            self.assert_only_owner();
            self.l2_token_to_l1_token.read(l2_token)
        }

        // I'm still not clear on this
        fn get_l2_bridge_from_l1_token(
            ref self: ContractState, 
            token_address: felt252
        ) -> ContractAddress {
            //ETH
            if token_address == 0x0000000000000000000000000000000000455448 {
                contract_address_const::<0x04c5772d1914fe6ce891b64eb35bf3522aeae1315647314aac58b01137607f3f>()
            }
            //STRK 
            else if token_address == 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766 {
                contract_address_const::<0x0594c1582459ea03f77deaf9eb7e3917d6994a03c13405ba42867f83d85f085d>()
            }
            // USDC
            else if token_address == 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 {
                contract_address_const::<0x0028729b12ce1140cbc1e7cbc7245455d3c15fa0c7f5d2e9fc8e0441567f6b50>()
            }
            //USDT
            else if token_address == 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0 {
                contract_address_const::<0x3913d184e537671dfeca3f67015bb845f2d12a26e5ec56bdc495913b20acb08>()
            } 
            //WBTC
            else if token_address == 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC {
                contract_address_const::<0x025a3820179262679392e872d7daaa44986af7caae1f41b7eedee561ca35a169>()
            }
            //wstETH 
            else if token_address == 0xB82381A3fBD3FaFA77B3a7bE693342618240067b {
                contract_address_const::<0x0172393a285eeac98ea136a4be473986a58ddd0beaf158517bc32166d0328824>()
            } else {
                panic!("Invalid Token")
            }
        }

        fn send_token_to_l1(
            ref self: ContractState,
            l1_token: EthAddress,
            l1_recipient: EthAddress,
            amount: u256
        ) {
            let l2_bridge = self.get_l2_bridge_from_l1_token(l1_token.address);
            let token_bridge = ITokenBridgeDispatcher { contract_address: l2_bridge };
            token_bridge.initiate_token_withdraw(l1_token, l1_recipient, amount);
        }
    }

    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.contract_owner.read();
            assert(caller == owner, ERROR_UNAUTHORIZED);
        }
    }
}
//contract_address: 0x5551e87e8e4d4084f0e5be9b32205039168bb3313304fbbe8dbdd6204e4dd39
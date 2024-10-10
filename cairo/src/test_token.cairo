use starknet::{ContractAddress};

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

#[starknet::contract]
pub(crate) mod TestToken {
    use starknet::storage::StorageMapReadAccess;
    use starknet::storage::StorageMapWriteAccess;
    use starknet::storage::{Map};
    use starknet::{ContractAddress, get_caller_address};
    use super::{IERC20};

    #[storage]
    struct Storage {
        pub balances: Map<ContractAddress, u256>,
        pub allowances: Map<(ContractAddress, ContractAddress), u256>,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        self.balances.write(recipient, amount);
    }

    #[abi(embed_v0)]
    impl IERC20Impl of IERC20<ContractState> {
        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account).into()
        }
        fn mint(ref self: ContractState, account: ContractAddress, amount: u256) -> bool {
            self.balances.write(account, self.balances.read(account) + amount);
            true
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.allowances.read((owner, spender)).into()
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let balance = self.balances.read(get_caller_address());
            assert(balance >= amount, 'INSUFFICIENT_TRANSFER_BALANCE');
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.balances.write(get_caller_address(), balance - amount);
            true
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let allowance = self.allowances.read((sender, get_caller_address()));
            assert(allowance >= amount, 'INSUFFICIENT_ALLOWANCE');
            let balance = self.balances.read(sender);
            assert(balance >= amount, 'INSUFFICIENT_TF_BALANCE');
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.balances.write(sender, balance - amount);
            self.allowances.write((sender, get_caller_address()), allowance - amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.allowances.write((get_caller_address(), spender), amount.try_into().unwrap());
            true
        }
    }
}
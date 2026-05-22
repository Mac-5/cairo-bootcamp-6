#[starknet::interface]
pub trait IRestrictedToken<TContractState> {
    // ── reads
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: starknet::ContractAddress) -> u256;
    fn allowance(
        self: @TContractState, owner: starknet::ContractAddress, spender: starknet::ContractAddress,
    ) -> u256;
    fn spending_limit(self: @TContractState) -> u256;
    fn is_revoked(self: @TContractState) -> bool;

    // ── writes
    // ─────────────────────────────────────────────────────────────
    fn transfer(
        ref self: TContractState, recipient: starknet::ContractAddress, amount: u256,
    ) -> bool;
    fn transfer_from(
        ref self: TContractState,
        sender: starknet::ContractAddress,
        recipient: starknet::ContractAddress,
        amount: u256,
    ) -> bool;
    fn approve(ref self: TContractState, spender: starknet::ContractAddress, amount: u256) -> bool;
    fn decrease_allowance_by_spender(
        ref self: TContractState, owner: starknet::ContractAddress, subtracted_value: u256,
    ) -> bool;

    // ── admin
    // ──────────────────────────────────────────────────────────────
    fn set_spending_limit(ref self: TContractState, new_limit: u256);
    fn revoke(ref self: TContractState);
    fn restore(ref self: TContractState);
    fn burn(ref self: TContractState, account: starknet::ContractAddress, amount: u256);
}
#[starknet::contract]
pub mod RestrictedToken {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    const MAX_LIMIT: u256 = 10_000;

    //storage
    #[storage]
    pub struct Storage {
        name: ByteArray,
        symbol: ByteArray,
        decimals: u8,
        total_supply: u256,
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        admin: ContractAddress,
        spending_limit: u256,
        is_revoked: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Transfer: Transfer,
        Approval: Approval,
        SpendingLimitUpdated: SpendingLimitUpdated,
        Revoked: Revoked,
        Restored: Restored,
        Burn: Burn,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Transfer {
        #[key]
        pub from: ContractAddress,
        #[key]
        pub to: ContractAddress,
        pub amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    pub struct Approval {
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub spender: ContractAddress,
        pub amount: u256,
    }
    #[derive(Drop, starknet::Event)]
    pub struct SpendingLimitUpdated {
        pub old_limit: u256,
        pub new_limit: u256,
    }
    #[derive(Drop, starknet::Event)]
    pub struct Revoked {
        pub by: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    pub struct Restored {
        pub by: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    pub struct Burn {
        #[key]
        pub account: ContractAddress,
        pub amount: u256,
    }

    pub mod Errors {
        pub const NOT_ADMIN: felt252 = 'caller is not admin';
        pub const REVOKED: felt252 = 'transfers revoked';
        pub const EXCEEDS_LIMIT: felt252 = 'amount exceeds limit';
        pub const EXCEEDS_MAX_LIMIT: felt252 = 'limit exceeds MAX_LIMIT';
        pub const INSUFFICIENT_BALANCE: felt252 = 'insufficient balance';
        pub const INSUFFICIENT_ALLOWANCE: felt252 = 'insufficient allowance';
        pub const ZERO_ADDRESS: felt252 = 'zero address not allowed';
        pub const ZERO_AMOUNT: felt252 = 'amount cannot be zero';
        pub const ALREADY_REVOKED: felt252 = 'already revoked';
        pub const NOT_REVOKED: felt252 = 'not revoked';
        pub const SELF_TRANSFER: felt252 = 'cannot transfer to self';
        pub const SELF_APPROVAL: felt252 = 'cannot approve self';
        pub const SAME_LIMIT: felt252 = 'limit already set';
        pub const RESET_ALLOWANCE_FIRST: felt252 = 'reset allowance first';
    }
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        admin: ContractAddress,
        initial_supply: u256,
    ) {
        assert(!admin.is_zero(), Errors::ZERO_ADDRESS);
        self.name.write(name);
        self.symbol.write(symbol);
        self.decimals.write(18);
        self.admin.write(admin);
        self.spending_limit.write(MAX_LIMIT);
        self.is_revoked.write(false);

        self.total_supply.write(0); // Initialized to 0, then we mint
        self._mint(admin, initial_supply);
    }
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_only_admin(self: @ContractState) {
            assert(get_caller_address() == self.admin.read(), Errors::NOT_ADMIN);
        }

        fn assert_not_revoked(self: @ContractState) {
            assert(!self.is_revoked.read(), Errors::REVOKED);
        }

        fn assert_within_limit(self: @ContractState, amount: u256) {
            assert(amount <= self.spending_limit.read(), Errors::EXCEEDS_LIMIT);
        }

        fn validate_transfer(self: @ContractState, recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), Errors::ZERO_ADDRESS);
            assert(amount > 0, Errors::ZERO_AMOUNT);
            self.assert_not_revoked();
            self.assert_within_limit(amount);
        }

        fn execute_transfer(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) {
            assert(from != to, Errors::SELF_TRANSFER);
            let from_balance = self.balances.read(from);
            assert(from_balance >= amount, Errors::INSUFFICIENT_BALANCE);

            self.balances.write(from, from_balance - amount);
            self.balances.write(to, self.balances.read(to) + amount);
            self.emit(Transfer { from, to, amount });
        }

        fn _mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            assert(!to.is_zero(), Errors::ZERO_ADDRESS);
            self.total_supply.write(self.total_supply.read() + amount);
            self.balances.write(to, self.balances.read(to) + amount);
            self.emit(Transfer { from: Zero::zero(), to, amount });
        }

        fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), Errors::ZERO_ADDRESS);
            let balance = self.balances.read(account);
            assert(balance >= amount, Errors::INSUFFICIENT_BALANCE);

            self.balances.write(account, balance - amount);
            // Explicitly track burned tokens in the zero address balance
            self.balances.write(Zero::zero(), self.balances.read(Zero::zero()) + amount);
            self.total_supply.write(self.total_supply.read() - amount);
            self.emit(Transfer { from: account, to: Zero::zero(), amount });
        }
    }


    #[abi(embed_v0)]
    impl RestrictedTokenImpl of super::IRestrictedToken<ContractState> {
        // reads
        fn name(self: @ContractState) -> ByteArray {
            self.name.read()
        }
        fn symbol(self: @ContractState) -> ByteArray {
            self.symbol.read()
        }
        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }
        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }
        fn spending_limit(self: @ContractState) -> u256 {
            self.spending_limit.read()
        }
        fn is_revoked(self: @ContractState) -> bool {
            self.is_revoked.read()
        }

        // transfer
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.validate_transfer(recipient, amount);
            self.execute_transfer(get_caller_address(), recipient, amount);
            true
        }

        // transfer_from
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            assert(!sender.is_zero(), Errors::ZERO_ADDRESS);
            self.validate_transfer(recipient, amount);

            let caller = get_caller_address();
            let current_allowance = self.allowances.read((sender, caller));
            assert(current_allowance >= amount, Errors::INSUFFICIENT_ALLOWANCE);
            self.allowances.write((sender, caller), current_allowance - amount);

            self.execute_transfer(sender, recipient, amount);
            true
        }

        // approve
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            assert(!spender.is_zero(), Errors::ZERO_ADDRESS);
            let owner = get_caller_address();
            assert(!owner.is_zero(), Errors::ZERO_ADDRESS);
            assert(owner != spender, Errors::SELF_APPROVAL);

            // Prevent the multiple withdrawal attack (approve front-running bug)
            // Enforce that allowances must be reset to zero first before changing.
            let current_allowance = self.allowances.read((owner, spender));
            assert(amount == 0 || current_allowance == 0, Errors::RESET_ALLOWANCE_FIRST);

            self.allowances.write((owner, spender), amount);
            self.emit(Approval { owner, spender, amount });
            true
        }

        // decrease_allowance_by_spender
        fn decrease_allowance_by_spender(
            ref self: ContractState, owner: ContractAddress, subtracted_value: u256,
        ) -> bool {
            let spender = get_caller_address();
            assert(!spender.is_zero(), Errors::ZERO_ADDRESS);
            assert(!owner.is_zero(), Errors::ZERO_ADDRESS);

            let current_allowance = self.allowances.read((owner, spender));
            assert(current_allowance >= subtracted_value, Errors::INSUFFICIENT_ALLOWANCE);

            let new_allowance = current_allowance - subtracted_value;
            self.allowances.write((owner, spender), new_allowance);
            self.emit(Approval { owner, spender, amount: new_allowance });
            true
        }

        // ── admin functions
        // ───────────────────────────────────────────────

        fn set_spending_limit(ref self: ContractState, new_limit: u256) {
            self.assert_only_admin();
            assert(new_limit <= MAX_LIMIT, Errors::EXCEEDS_MAX_LIMIT);
            assert(new_limit > 0, Errors::ZERO_AMOUNT);

            let old_limit = self.spending_limit.read();
            assert(old_limit != new_limit, Errors::SAME_LIMIT);
            self.spending_limit.write(new_limit);
            self.emit(SpendingLimitUpdated { old_limit, new_limit });
        }

        fn revoke(ref self: ContractState) {
            self.assert_only_admin();
            assert(!self.is_revoked.read(), Errors::ALREADY_REVOKED);
            self.is_revoked.write(true);
            self.emit(Revoked { by: get_caller_address() });
        }

        fn restore(ref self: ContractState) {
            self.assert_only_admin();
            assert(self.is_revoked.read(), Errors::NOT_REVOKED);
            self.is_revoked.write(false);
            self.emit(Restored { by: get_caller_address() });
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.assert_only_admin();
            assert(amount > 0, Errors::ZERO_AMOUNT);
            self._burn(account, amount);
            self.emit(Burn { account, amount });
        }
    }
}

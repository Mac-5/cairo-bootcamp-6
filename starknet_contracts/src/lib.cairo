/// Interface representing `HelloContract`.
/// This interface allows modification and retrieval of the contract's storage count.
#[starknet::interface]
pub trait ICounter<T> {
    /// Increase count.
    fn increase_count(ref self: T, amount: u32);
    /// Retrieve count.
    fn get_count(self: @T) -> u32;
}

/// Simple contract for managing count.
#[starknet::contract]
mod Counter {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        count: u32,
    }

    #[abi(embed_v0)]
    impl CounterImpl of super::ICounter<ContractState> {
        fn increase_count(ref self: ContractState, amount: u32) {
            assert(amount != 0, 'Amount cannot be 0');
            self.count.write(self.count.read() + amount);
        }

        fn get_count(self: @ContractState) -> u32 {
            self.count.read()
        }
    }
}

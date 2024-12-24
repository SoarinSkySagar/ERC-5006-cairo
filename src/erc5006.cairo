#[starknet::component]
pub mod ERC5006Component {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };

    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::ERC1155Component::InternalImpl as ERC1155InternalImpl;
    use openzeppelin_token::erc1155::ERC1155Component::ERC1155Impl;
    use openzeppelin_token::erc1155::ERC1155Component;

    use erc5006_cairo::uintset::UintSet::{UintSet, UintSetTrait};
    use erc5006_cairo::types::UserRecord;

    #[storage]
    pub struct Storage {
        frozens: Map<u256, Map<ContractAddress, u256>>,
        records: Map<u256, UserRecord>,
        user_record_ids: Map<u256, Map<ContractAddress, UintSet>>,
        cur_record_id: u256,
        record_limit: u256
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        CreateUserRecord: CreateUserRecord,
        DeleteUserRecord: DeleteUserRecord
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct CreateUserRecord {
        #[key]
        pub record_id: u256,
        pub token_id: ContractAddress,
        pub amount: u256,
        pub owner: u64,
        pub user: ContractAddress,
        pub expiry: u256
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct DeleteUserRecord {
        #[key]
        pub record_id: u256
    }

    #[embeddable_as(ERC5006Impl)]
    pub impl ERC5006<
        TContractState,
        +HasComponent<TcontractState>,
        impl ERC1155: ERC1155Component::HasComponent<TContractState>,
        +ERC1155Component::ERC1155HooksTrait<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC5006<ComponentState<TContractState>> {
        fn usable_balance_of(self: @TState, account: ContractAddress, token_id: u256) -> u256 {
            let record_ids = self.user_record_ids.entry(token_id).read(account);

            let mut amount: u256 = 0;

            for index in 0
                ..record_ids
                    .size
                    .read() {
                        if (get_block_timestamp() <= self
                            .records
                            .entry(record_ids.values.entry(index).read())
                            .read()
                            .expiry) {
                            amount = amount
                                + self
                                    .records
                                    .entry(record_ids.values.entry(index).read())
                                    .read()
                                    .amount;
                        }
                    }
            amount
        }

        fn frozen_balance_of(self: @TState, account: ContractAddress, token_id: u256) -> u256 {
            self.frozens.entry(token_id).read(account)
        }

        fn user_record_of(self: @TState, record_id: u256) -> UserRecord {
            self.records.entry(record_id).read()
        }

        fn create_user_record(
            ref self: TState,
            owner: ContractAddress,
            user: ContractAddress,
            token_id: u256,
            amount: u64,
            expiry: u64
        ) -> u256 {
            let zero: ContractAddress = 0.try_into().unwrap();
            assert(user != zero, 'User cannot be the zero address');
            assert(amount > 0, "amount must be greater than 0");
            assert(expiry > get_block_timestamp, 'expiry must after the block timestamp');
            assert(
                self.user_record_ids.entry(token_id).read(user).size <= recordLimit,
                'user cannot have more records'
            );
            let prev_frozen = self.frozens.entry(token_id).read(owner);
            self.frozens.entry(token_id).write(owner, prev_frozen + amount);
            self.cur_record_id.write(self.cur_record_id.read() + 1);
            let record = UserRecord { token_id, owner, amount, user, expiry };
            self.records.entry(self.cur_record_id.read()).write(record);

            self
                .emit(
                    CreateUserRecord {
                        record_id: self.cur_record_id.read(), token_id, amount, owner, user, expiry
                    }
                );
            self.user_record_ids.entry(token_id).entry(user).deref().add(cur_record_id);
            return self.cur_record_id.read();
        }

        fn delete_user_record(ref self: TState, record_id: u256) {
            let record = self.records.entry(record_id).read();
            let prev_frozen = self.frozens.entry(record.token_id).read(record.owner);
            self.frozens.entry(record.token_id).write(record.owner, prev_frozen - record.amount);
            self
                .user_record_ids
                .entry(record.token_id)
                .entry(record.user)
                .deref()
                .remove(record_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            let empty = UserRecord { token_id: 0, owner: zero, amount: 0, user: zero, expiry: 0 };
            self.records.entry(record_id).write(empty);
            self.emit(DeleteUserRecord { record_id });
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TcontractState>,
        impl ERC1155: ERC1155Component::HasComponent<TContractState>,
        +ERC1155Component::ERC1155HooksTrait<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(record_limit: u256) {
            self.record_limit.write(record_limit)
        }
    }
}

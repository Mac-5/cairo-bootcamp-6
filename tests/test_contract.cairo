use core::num::traits::Zero;
use erc_contract::RestrictedToken::{
    Approval, Burn, Event, Restored, Revoked, SpendingLimitUpdated, Transfer,
};
use erc_contract::{IRestrictedTokenDispatcher, IRestrictedTokenDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, spy_events, start_cheat_caller_address,
    stop_cheat_caller_address, 
    EventSpyAssertionsTrait,
};
use starknet::ContractAddress;


//constants
const INIITAL_SUPPLY: u256 = 1_000_000;
const MAX_LIMIT: u256 = 10_000;

fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}
fn USER1() -> ContractAddress {
    'USER1'.try_into().unwrap()
}
fn USER2() -> ContractAddress {
    'USER2'.try_into().unwrap()
}

fn __deploy__() -> IRestrictedTokenDispatcher {
    let contract_class = declare("RestrictedToken").expect('failed to declare').contract_class();
    let name: ByteArray = "TestToken";
    let symbol: ByteArray = "TTK";
    let mut calldata: Array<felt252> = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    ADMIN().serialize(ref calldata);
    INIITAL_SUPPLY.serialize(ref calldata);

    let (contract_address, _) = contract_class.deploy(@calldata).expect('failed
    to deploy');

    IRestrictedTokenDispatcher { contract_address }
}

//test deployment
#[test]
fn test_deploy_sets_name() {
    let token = __deploy__();
    assert(token.name() == "TestToken", 'wrong name');
}
#[test]
fn test_deploy_sets_symbol() {
    let token = __deploy__();
    assert(token.symbol() == "TTK", 'wrong symbol');
}

#[test]
fn test_deploy_sets_decimals() {
    let token = __deploy__();
    assert(token.decimals() == 18, 'wrong decimals');
}

#[test]
fn test_deploy_sets_total_supply() {
    let token = __deploy__();
    assert(token.total_supply() == INIITAL_SUPPLY, 'wrong total supply');
}

#[test]
fn test_deploy_mints_supply_to_admin() {
    let token = __deploy__();
    assert(token.balance_of(ADMIN()) == INIITAL_SUPPLY, 'admin should hold supply');
}

#[test]
fn test_deploy_sets_spending_limit_to_max() {
    let token = __deploy__();
    assert(token.spending_limit() == MAX_LIMIT, 'limit should be MAX_LIMIT');
}

#[test]
fn test_deploy_not_revoked() {
    let token = __deploy__();
    assert(!token.is_revoked(), 'should not be revoked');
}

#[test]
fn test_deploy_emits_mint_transfer_event() {
    let contract_class = declare("RestrictedToken").expect('Failed to declare').contract_class();

    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "TestToken";
    let symbol: ByteArray = "TTK";
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    ADMIN().serialize(ref calldata);
    INIITAL_SUPPLY.serialize(ref calldata);

    let mut spy = spy_events();
    let (contract_address, _) = contract_class.deploy(@calldata).expect('failed to deploy');

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    Event::Transfer(
                        Transfer { from: Zero::zero(), to: ADMIN(), amount: INIITAL_SUPPLY },
                    ),
                ),
            ],
        );
}

#[test]
fn test_transfer_succeeds_within_limit() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    let result = token.transfer(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    assert(result, 'transfer should return true');
    assert(token.balance_of(USER1()) == 500, 'user1 should have 500');
    assert(token.balance_of(ADMIN()) == INIITAL_SUPPLY - 500, 'admin balance wrong');
}

#[test]
fn test_transfer_at_exact_limit() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    let result = token.transfer(USER1(), MAX_LIMIT);
    stop_cheat_caller_address(token.contract_address);

    assert(result, 'transfer at limit should pass');
    assert(token.balance_of(USER1()) == MAX_LIMIT, 'user1 balance wrong');
}

#[test]
fn test_transfer_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.transfer(USER1(), 100);
    stop_cheat_caller_address(token.contract_address);

    spy
        .assert_emitted(
            @array![
                (
                    token.contract_address,
                    Event::Transfer(Transfer { from: ADMIN(), to: USER1(), amount: 100 }),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'amount exceeds limit')]
fn test_transfer_fails_above_limit() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.transfer(USER1(), MAX_LIMIT + 1);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'insufficient balance')]
fn test_transfer_fails_insufficient_balance() {
    let token = __deploy__();

    // USER1 has no tokens
    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer(USER2(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'zero address not allowed')]
fn test_transfer_fails_to_zero_address() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.transfer(Zero::zero(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'amount cannot be zero')]
fn test_transfer_fails_zero_amount() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.transfer(USER1(), 0);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'transfers revoked')]
fn test_transfer_fails_when_revoked() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    token.transfer(USER1(), 100);
    stop_cheat_caller_address(token.contract_address);
}

// ─── approve & transfer_from
// ───────────────────────────────────────────────

#[test]
fn test_approve_sets_allowance() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    assert(token.allowance(ADMIN(), USER1()) == 500, 'allowance should be 500');
}

#[test]
fn test_approve_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    spy
        .assert_emitted(
            @array![
                (
                    token.contract_address,
                    Event::Approval(Approval { owner: ADMIN(), spender: USER1(), amount: 500 }),
                ),
            ],
        );
}

#[test]
fn test_transfer_from_succeeds_with_allowance() {
    let token = __deploy__();

    // admin approves USER1 to spend 500
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    // USER1 spends on behalf of ADMIN → USER2
    start_cheat_caller_address(token.contract_address, USER1());
    let result = token.transfer_from(ADMIN(), USER2(), 300);
    stop_cheat_caller_address(token.contract_address);

    assert(result, 'transfer_from should succeed');
    assert(token.balance_of(USER2()) == 300, 'USER2 should have 300');
    assert(token.allowance(ADMIN(), USER1()) == 200, 'allowance should decrease');
}

#[test]
#[should_panic(expected: 'insufficient allowance')]
fn test_transfer_from_fails_without_allowance() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer_from(ADMIN(), USER2(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'zero address not allowed')]
fn test_transfer_from_fails_zero_sender() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer_from(Zero::zero(), USER2(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'transfers revoked')]
fn test_transfer_from_fails_when_revoked() {
    let token = __deploy__();

    // Admin approves USER1
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    token.revoke();
    stop_cheat_caller_address(token.contract_address);

    // transfer_from should fail because revoked
    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer_from(ADMIN(), USER2(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'amount exceeds limit')]
fn test_transfer_from_fails_above_limit() {
    let token = __deploy__();

    // Admin approves USER1 for a large amount
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), MAX_LIMIT + 1);
    stop_cheat_caller_address(token.contract_address);

    // transfer_from should fail because amount > spending limit
    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer_from(ADMIN(), USER2(), MAX_LIMIT + 1);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'zero address not allowed')]
fn test_approve_fails_zero_spender() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(Zero::zero(), 500);
    stop_cheat_caller_address(token.contract_address);
}

// ─── set_spending_limit
// ────────────────────────────────────────────────────

#[test]
fn test_admin_can_lower_spending_limit() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.set_spending_limit(5000);
    stop_cheat_caller_address(token.contract_address);

    assert(token.spending_limit() == 5000, 'limit should be 5000');
}

#[test]
fn test_set_spending_limit_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.set_spending_limit(5000);
    stop_cheat_caller_address(token.contract_address);

    spy
        .assert_emitted(
            @array![
                (
                    token.contract_address,
                    Event::SpendingLimitUpdated(
                        SpendingLimitUpdated { old_limit: MAX_LIMIT, new_limit: 5000 },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'limit exceeds MAX_LIMIT')]
fn test_set_spending_limit_cannot_exceed_max() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.set_spending_limit(MAX_LIMIT + 1);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'amount cannot be zero')]
fn test_set_spending_limit_cannot_be_zero() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.set_spending_limit(0);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'caller is not admin')]
fn test_non_admin_cannot_set_limit() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, USER1());
    token.set_spending_limit(5000);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'amount exceeds limit')]
fn test_transfer_fails_after_limit_lowered() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.set_spending_limit(100);
    // this should panic since 500 > new limit of 100
    token.transfer(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);
}

// ─── revoke / restore
// ──────────────────────────────────────────────────────

#[test]
fn test_admin_can_revoke() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    stop_cheat_caller_address(token.contract_address);

    assert(token.is_revoked(), 'should be revoked');
}

#[test]
fn test_revoke_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    stop_cheat_caller_address(token.contract_address);

    spy.assert_emitted(@array![(token.contract_address, Event::Revoked(Revoked { by: ADMIN() }))]);
}

#[test]
#[should_panic(expected: 'already revoked')]
fn test_revoke_twice_panics() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    token.revoke(); // second call should panic
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'caller is not admin')]
fn test_non_admin_cannot_revoke() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, USER1());
    token.revoke();
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_admin_can_restore() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    token.restore();
    stop_cheat_caller_address(token.contract_address);

    assert(!token.is_revoked(), 'should not be revoked');
}

#[test]
fn test_restore_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    token.restore();
    stop_cheat_caller_address(token.contract_address);

    spy
        .assert_emitted(
            @array![(token.contract_address, Event::Restored(Restored { by: ADMIN() }))],
        );
}

#[test]
#[should_panic(expected: 'not revoked')]
fn test_restore_without_revoke_panics() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.restore(); // not revoked yet, should panic
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'caller is not admin')]
fn test_non_admin_cannot_restore() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(token.contract_address, USER1());
    token.restore();
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_transfer_works_after_restore() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    token.restore();
    let result = token.transfer(USER1(), 100);
    stop_cheat_caller_address(token.contract_address);

    assert(result, 'transfer should work');
    assert(token.balance_of(USER1()) == 100, 'USER1 should have 100');
}

// ─── burn (admin-only)
// ──────────────────────────────────────────────────────

#[test]
fn test_admin_can_burn_tokens() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.burn(ADMIN(), 1000);
    stop_cheat_caller_address(token.contract_address);

    assert(token.balance_of(ADMIN()) == INIITAL_SUPPLY - 1000, 'balance should decrease');
    assert(token.total_supply() == INIITAL_SUPPLY - 1000, 'total supply should decrease');
}

#[test]
fn test_burn_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.burn(ADMIN(), 500);
    stop_cheat_caller_address(token.contract_address);

    // ERC-20 standard: burn emits Transfer to zero address
    spy
        .assert_emitted(
            @array![
                (
                    token.contract_address,
                    Event::Transfer(
                        Transfer { from: ADMIN(), to: Zero::zero(), amount: 500 },
                    ),
                ),
            ],
        );

    // Also emits the custom Burn event
    spy
        .assert_emitted(
            @array![
                (
                    token.contract_address,
                    Event::Burn(Burn { account: ADMIN(), amount: 500 }),
                ),
            ],
        );
}

#[test]
fn test_admin_can_burn_other_account() {
    let token = __deploy__();

    // Give USER1 some tokens first
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.transfer(USER1(), 5000);
    token.burn(USER1(), 2000);
    stop_cheat_caller_address(token.contract_address);

    assert(token.balance_of(USER1()) == 3000, 'USER1 should have 3000');
    assert(token.total_supply() == INIITAL_SUPPLY - 2000, 'supply should decrease by 2000');
}

#[test]
#[should_panic(expected: 'caller is not admin')]
fn test_non_admin_cannot_burn() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, USER1());
    token.burn(ADMIN(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'zero address not allowed')]
fn test_burn_fails_zero_address() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.burn(Zero::zero(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'amount cannot be zero')]
fn test_burn_fails_zero_amount() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.burn(ADMIN(), 0);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'insufficient balance')]
fn test_burn_fails_insufficient_balance() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.burn(ADMIN(), INIITAL_SUPPLY + 1);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_burn_works_while_revoked() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.revoke();
    // Burn is an admin privilege — works even when transfers are revoked
    token.burn(ADMIN(), 1000);
    stop_cheat_caller_address(token.contract_address);

    assert(token.balance_of(ADMIN()) == INIITAL_SUPPLY - 1000, 'burn should work when revoked');
    assert(token.total_supply() == INIITAL_SUPPLY - 1000, 'supply should decrease');
}

// ─── additional validation tests
// ──────────────────────────────────────────────────────

#[test]
#[should_panic(expected: 'cannot transfer to self')]
fn test_transfer_to_self_fails() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.transfer(ADMIN(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'cannot transfer to self')]
fn test_transfer_from_to_self_fails() {
    let token = __deploy__();

    // Admin approves USER1 to spend on their behalf
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    // USER1 tries to transfer from ADMIN back to ADMIN
    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer_from(ADMIN(), ADMIN(), 100);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'cannot approve self')]
fn test_approve_self_fails() {
    let token = __deploy__();

    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(ADMIN(), 500);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: 'limit already set')]
fn test_set_spending_limit_same_value_fails() {
    let token = __deploy__();

    // MAX_LIMIT is the default; setting it again should fail
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.set_spending_limit(MAX_LIMIT);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_decrease_allowance_by_spender_works() {
    let token = __deploy__();

    // ADMIN approves USER1 for 500
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    // USER1 decides to decrease their own allowance by 200
    start_cheat_caller_address(token.contract_address, USER1());
    token.decrease_allowance_by_spender(ADMIN(), 200);
    stop_cheat_caller_address(token.contract_address);

    // The allowance should now be 300
    assert(token.allowance(ADMIN(), USER1()) == 300, 'allowance should be 300');
}

#[test]
#[should_panic(expected: 'insufficient allowance')]
fn test_decrease_allowance_fails_insufficient() {
    let token = __deploy__();

    // ADMIN approves USER1 for 500
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    // USER1 tries to decrease their allowance by 600 (more than they have)
    start_cheat_caller_address(token.contract_address, USER1());
    token.decrease_allowance_by_spender(ADMIN(), 600);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_decrease_allowance_emits_event() {
    let token = __deploy__();
    let mut spy = spy_events();

    // ADMIN approves USER1 for 500
    start_cheat_caller_address(token.contract_address, ADMIN());
    token.approve(USER1(), 500);
    stop_cheat_caller_address(token.contract_address);

    // USER1 decreases allowance by 200
    start_cheat_caller_address(token.contract_address, USER1());
    token.decrease_allowance_by_spender(ADMIN(), 200);
    stop_cheat_caller_address(token.contract_address);

    // Expect Approval event with the NEW allowance (300)
    spy
        .assert_emitted(
            @array![
                (
                    token.contract_address,
                    Event::Approval(Approval { owner: ADMIN(), spender: USER1(), amount: 300 }),
                ),
            ],
        );
}

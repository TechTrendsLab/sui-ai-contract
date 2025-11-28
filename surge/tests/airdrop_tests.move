#[test_only]
module surge::airdrop_tests;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::test_scenario as ts;
use std::unit_test::{ assert_eq};
use surge::surge::{Self, SURGE};
use surge::vesting::{Self, ACL, SurgeVestingState};
use surge::surge::SuperAdmin;
use sui::address;

const ADMIN: address = @0x1;
const WHITELIST_ADMIN: address = @0x2;
const ROBOT_ADMIN: address = @0x3;
const USER1: address = @0x4;
const USER2: address = @0x5;
const USER3: address = @0x6;

const AIRDROP_AMOUNT_USER1: u64 = 1_000_000_000_000_000; // 1M SURGE
const AIRDROP_AMOUNT_USER2: u64 = 2_000_000_000_000_000; // 2M SURGE
const AIRDROP_AMOUNT_USER3: u64 = 3_000_000_000_000_000; // 3M SURGE
const MAX_AIRDROP: u64 = 80_000_000_000_000_000; // 80M SURGE
const TGE_TIMESTAMP: u64 = 1000000000000;
const VESTING_TIMESTAMP: u64 = 1000000001000; // vesting_timestamp must be > tge_timestamp 

fun create_clock_at_time(time: u64, ctx: &mut TxContext): Clock {
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, time);
    clock
}

fun setup_test_env(scenario: &mut ts::Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        surge::init_for_testing(ts::ctx(scenario));
    };

    ts::next_tx(scenario, ADMIN);
    {
        vesting::init_for_testing(ts::ctx(scenario));
    };

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let treasury_cap = ts::take_from_sender<TreasuryCap<SURGE>>(scenario);
        
        vesting::initialize_surge_vest_state(
            &super_admin,
            treasury_cap,
            ts::ctx(scenario),
        );
        
        ts::return_to_sender(scenario, super_admin);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::set_whitelist_admin(&super_admin, &mut acl, WHITELIST_ADMIN);
        vesting::set_robot_admin(&super_admin, &mut acl, ROBOT_ADMIN);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        vesting::set_tge_timestamp(&super_admin, &mut vesting_state, TGE_TIMESTAMP, VESTING_TIMESTAMP);
        
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };
}

#[test]
fun test_initialization() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let whitelist_admins = vesting::get_whitelist_admin(&acl);
        let robot_admins = vesting::get_robot_admin(&acl);
        
        assert_eq!(vector::length(&whitelist_admins), 1);
        assert_eq!(vector::length(&robot_admins), 1);
        assert!(vector::contains(&whitelist_admins, &WHITELIST_ADMIN), 0);
        assert!(vector::contains(&robot_admins, &ROBOT_ADMIN), 1);
        
        ts::return_shared(acl);
    };

    ts::end(scenario_val);
}

#[test]
fun test_set_whitelist() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let addresses = vector[USER1, USER2];
        let amounts = vector[AIRDROP_AMOUNT_USER1, AIRDROP_AMOUNT_USER2];
        
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            addresses,
            amounts,
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}
#[test]
fun test_claim_airdrop_success() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[AIRDROP_AMOUNT_USER1],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER1);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), AIRDROP_AMOUNT_USER1);
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_multiple_users_claim_airdrop() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1, USER2, USER3],
            vector[AIRDROP_AMOUNT_USER1, AIRDROP_AMOUNT_USER2, AIRDROP_AMOUNT_USER3],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER2);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 2000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER3);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 3000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER1);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), AIRDROP_AMOUNT_USER1);
        ts::return_to_sender(scenario, coin);
    };

    ts::next_tx(scenario, USER2);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), AIRDROP_AMOUNT_USER2);
        ts::return_to_sender(scenario, coin);
    };

    ts::next_tx(scenario, USER3);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), AIRDROP_AMOUNT_USER3);
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidTgeTimestamp)]
fun test_claim_before_tge_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[AIRDROP_AMOUNT_USER1],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_non_whitelist_user_claim_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[AIRDROP_AMOUNT_USER1],   
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER2);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

// #[test]
// fun test_verify_vaa() {
//     let mut scenario_val = ts::begin(ADMIN);
//     let scenario = &mut scenario_val;
//     setup_test_env(scenario);

//     ts::next_tx(scenario, ADMIN);
//     {
//         let buf = "01000000000100464c1b60ddb7f88dc95339113365e7ca68c6bb7ed36c7751aad54a37a58871045656f6b621b6817951c6af22634a6db618ac52c594167bf1d7d71f38f6586f4901691eb02e000000020004000000000000000000000000af371b28d404c681a7dcf0b843999e084963befe00000000000000020f0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000d767d7e0c68049b5c3c0869529ce1eeb39d0c6093858bb7c48e1b72153ec8663138740fa36258cd5c1ac75d2d74e7fe6b3ef3f3a0000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000015";
//         let buf = string::as_bytes(&buf);
//         let mut cur = cursor::new(*buf);
//         let payload_id = bytes::take_u8(&mut cur);
//         print(&payload_id);
//         cursor::take_rest(cur);
//     };
//     ts::end(scenario_val);
// }

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_double_claim_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[AIRDROP_AMOUNT_USER1],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 2000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
fun test_update_whitelist_amount() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[AIRDROP_AMOUNT_USER1],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    let new_amount = 5_000_000_000_000;
    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[new_amount],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER1);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), new_amount + AIRDROP_AMOUNT_USER1);
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_remove_whitelist() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1, USER2],
            vector[AIRDROP_AMOUNT_USER1, AIRDROP_AMOUNT_USER2],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::remove_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER2);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER2);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), AIRDROP_AMOUNT_USER2);
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EOverAirdropAmount)]
fun test_exceed_max_airdrop_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[MAX_AIRDROP + 1],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario_val);
}

#[test]
fun test_batch_set_whitelist_max_length() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        let mut addresses = vector::empty<address>();
        let mut amounts = vector::empty<u64>();
        
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        
        // Start from i=1 to avoid @0x0 address
        let mut i = 1;
        while (i <= 500) {
            vector::push_back(&mut addresses, address::from_u256(i as u256));
            vector::push_back(&mut amounts, 1_000_000);
            i = i + 1;
        };
        
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            addresses,
            amounts,
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidLength)]
fun test_batch_set_whitelist_exceed_max_length_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        let mut addresses = vector::empty<address>();
        let mut amounts = vector::empty<u64>();
        let mut i = 0;
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        while (i < 1001) {
            vector::push_back(&mut addresses, address::from_u256(i as u256));
            vector::push_back(&mut amounts, 1_000_000);
            i = i + 1;
        };
        
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            addresses,
            amounts,
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddressAndValueLength)]
fun test_address_amount_length_mismatch_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1, USER2, USER3],
            vector[AIRDROP_AMOUNT_USER1, AIRDROP_AMOUNT_USER2],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
/// 测试：非白名单管理员设置白名单应失败
fun test_non_whitelist_admin_set_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // USER1（非白名单管理员）尝试设置白名单
    ts::next_tx(scenario, USER1);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER2],
            vector[AIRDROP_AMOUNT_USER2],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EAlreadySetTgeTimestamp)]
/// 测试：重复设置TGE时间戳应失败
fun test_duplicate_set_tge_timestamp_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 尝试再次设置TGE时间戳（应该失败）
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        vesting::set_tge_timestamp(&super_admin, &mut vesting_state, TGE_TIMESTAMP + 1000, TGE_TIMESTAMP + 2000);
        
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EAlreadyExistAdmin)]
/// 测试：重复添加管理员应失败
fun test_duplicate_add_admin_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 尝试重复添加WHITELIST_ADMIN
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::set_whitelist_admin(&super_admin, &mut acl, WHITELIST_ADMIN);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
/// 测试：移除和重新添加管理员
fun test_remove_and_readd_admin() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 移除白名单管理员
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::remove_whitelist_admin(&super_admin, &mut acl, WHITELIST_ADMIN);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    // 重新添加白名单管理员
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::set_whitelist_admin(&super_admin, &mut acl, WHITELIST_ADMIN);
        
        let whitelist_admins = vesting::get_whitelist_admin(&acl);
        assert!(vector::contains(&whitelist_admins, &WHITELIST_ADMIN), 0);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
/// 测试：空投总量累计计算
fun test_airdrop_amount_accumulation() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 第一批白名单
    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1],
            vector[10_000_000_000_000], // 10M
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    // 第二批白名单
    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER2],
            vector[20_000_000_000_000], // 20M
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    // 第三批白名单（总计不超过80M）
    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER3],
            vector[50_000_000_000_000], // 50M, 总计80M 
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    // 所有用户都能成功领取
    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER2);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 2000, ts::ctx(scenario));
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, USER3);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 3000, ts::ctx(scenario));
        vesting::claim_airdrop(&mut vesting_state, &clock, ts::ctx(scenario));
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
/// 测试：发送给早期支持者
fun test_send_to_early_backers() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置早期支持者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_early_backers_address(&super_admin, &mut vesting_state, @0x1);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    // 早期支持者可以在 vesting_timestamp + 1年后领取
    // VESTING_TIMESTAMP + YEAR_TIME_MS
    let claim_time = VESTING_TIMESTAMP + 31556926000 + 1000; // vesting + 1年 + 1秒

    // ROBOT_ADMIN 发送给早期支持者
    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_early_backers(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    // 验证早期支持者收到代币
    ts::next_tx(scenario, @0x1); // EARLY_BACKERS_ADDRESS
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), 2_777_777_777_777_777); // EARLY_BACKERS_AIRDROP_MONTH
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidTime)]
/// 测试：早期支持者在时间未到时领取应失败
fun test_send_to_early_backers_before_time_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置早期支持者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_early_backers_address(&super_admin, &mut vesting_state, @0x1);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    // 尝试在 vesting_timestamp + 1年之前发送（应该失败）
    let claim_time = VESTING_TIMESTAMP + 31556926000 - 1000; // vesting + 1年 - 1秒

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_early_backers(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
/// 测试：非机器人管理员发送给早期支持者应失败
fun test_send_to_early_backers_non_robot_admin_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置早期支持者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_early_backers_address(&super_admin, &mut vesting_state, @0x1);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP + 31556926000 + 1000;

    // USER1（非机器人管理员）尝试发送（应该失败）
    ts::next_tx(scenario, USER1);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_early_backers(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
/// 测试：发送给核心贡献者
fun test_send_to_core_contributors() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置核心贡献者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_core_contributors_address(&super_admin, &mut vesting_state, @0x2);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    // 核心贡献者可以在 vesting_timestamp + 1年后领取
    let claim_time = VESTING_TIMESTAMP + 31556926000 + 1000;

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_core_contributors(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    // 验证核心贡献者收到代币
    ts::next_tx(scenario, @0x2); // CORE_CONTRIBUTORS_ADDRESS
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), 2_777_777_777_777_777); // CORE_CONTRIBUTORS_AIRDROP_MONTH
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
/// 测试：发送给生态系统
fun test_send_to_ecosystem() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置生态系统地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_ecosystem_address(&super_admin, &mut vesting_state, @0x3);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP + 1000;

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_ecosystem(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, @0x3);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), 4_166_666_666_666_666); // ECOSYSTEM_AIRDROP_MONTH
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_send_to_community() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_community_address(&super_admin, &mut vesting_state, @0x4);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP + 1000;

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_community(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, @0x4);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), 6_527_777_777_777_777); // COMMUNITY_AIRDROP_MONTH
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_send_to_early_backers_monthly() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置早期支持者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_early_backers_address(&super_admin, &mut vesting_state, @0x1);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let first_claim_time = VESTING_TIMESTAMP + 31556926000 + 1000;
    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(first_claim_time, ts::ctx(scenario));
        
        vesting::send_to_early_backers(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    let second_claim_time = first_claim_time + 2629746000 + 1000;
    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(second_claim_time, ts::ctx(scenario));
        
        vesting::send_to_early_backers(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::next_tx(scenario, @0x1);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), 2_777_777_777_777_777);
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_set_addresses() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        vesting::set_early_backers_address(&super_admin, &mut vesting_state, USER1);
        vesting::set_core_contributors_address(&super_admin, &mut vesting_state, USER2);
        vesting::set_ecosystem_address(&super_admin, &mut vesting_state, USER3);
        vesting::set_community_address(&super_admin, &mut vesting_state, USER1);
        
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_get_airdrop_amount() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置白名单
    ts::next_tx(scenario, WHITELIST_ADMIN);
    {
        let mut acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP - 1000, ts::ctx(scenario));
        vesting::set_whitelist_admin_list(
            &mut acl,
            &mut vesting_state,
            vector[USER1, USER2],
            vector[AIRDROP_AMOUNT_USER1, AIRDROP_AMOUNT_USER2],
            ts::ctx(scenario),
        );
        
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
        clock::destroy_for_testing(clock);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        
        let amount1 = vesting::get_user_airdrop_amount(&vesting_state, USER1);
        let amount2 = vesting::get_user_airdrop_amount(&vesting_state, USER2);
        let amount3 = vesting::get_user_airdrop_amount(&vesting_state, USER3);
        
        assert_eq!(amount1, AIRDROP_AMOUNT_USER1);
        assert_eq!(amount2, AIRDROP_AMOUNT_USER2);
        assert_eq!(amount3, 0);
        
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
fun test_claim_liquidity_and_listing() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::send_liquidity_and_listing(
            &super_admin,
            ROBOT_ADMIN,
            &mut vesting_state,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        assert_eq!(coin::value(&coin), 50_000_000_000_000_000); // LIQUIDITY_AND_LISTING
        ts::return_to_sender(scenario, coin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EAlreadyLiquidityAndListing)]
fun test_claim_liquidity_and_listing_twice_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        vesting::send_liquidity_and_listing(
            &super_admin,
            ROBOT_ADMIN,
            &mut vesting_state,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 2000, ts::ctx(scenario));
        
        vesting::send_liquidity_and_listing(
            &super_admin,
            ROBOT_ADMIN,
            &mut vesting_state,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_remove_robot_admin() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::remove_robot_admin(&super_admin, &mut acl, ROBOT_ADMIN);
        
        let robot_admins = vesting::get_robot_admin(&acl);
        assert_eq!(vector::length(&robot_admins), 0);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_remove_robot_admin_not_exists_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::remove_robot_admin(&super_admin, &mut acl, USER1);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_remove_whitelist_admin_not_exists_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut acl = ts::take_shared<ACL>(scenario);
        
        vesting::remove_whitelist_admin(&super_admin, &mut acl, USER1);
        
        ts::return_shared(acl);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidTime)]
fun test_send_to_core_contributors_before_time_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置核心贡献者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_core_contributors_address(&super_admin, &mut vesting_state, @0x2);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    // 尝试在 vesting_timestamp + 1年之前发送（应该失败）
    let claim_time = VESTING_TIMESTAMP + 31556926000 - 1000; // vesting + 1年 - 1秒

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_core_contributors(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_send_to_core_contributors_non_robot_admin_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置核心贡献者地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_core_contributors_address(&super_admin, &mut vesting_state, @0x2);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP + 31556926000 + 1000;

    // USER1（非机器人管理员）尝试发送（应该失败）
    ts::next_tx(scenario, USER1);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_core_contributors(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidTime)]
fun test_send_to_ecosystem_before_time_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置生态系统地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_ecosystem_address(&super_admin, &mut vesting_state, @0x3);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP - 1000;

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_ecosystem(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_send_to_ecosystem_non_robot_admin_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // 设置生态系统地址
    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_ecosystem_address(&super_admin, &mut vesting_state, @0x3);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP + 1000;
    ts::next_tx(scenario, USER1);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_ecosystem(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidTime)]
fun test_send_to_community_before_time_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_community_address(&super_admin, &mut vesting_state, @0x4);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    // 尝试在 vesting_timestamp 之前发送（应该失败）
    let claim_time = VESTING_TIMESTAMP - 1000;

    ts::next_tx(scenario, ROBOT_ADMIN);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_community(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = vesting::EInvalidAddress)]
fun test_send_to_community_non_robot_admin_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        vesting::set_community_address(&super_admin, &mut vesting_state, @0x4);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    let claim_time = VESTING_TIMESTAMP + 1000;

    // USER1（非机器人管理员）尝试发送（应该失败）
    ts::next_tx(scenario, USER1);
    {
        let acl = ts::take_shared<ACL>(scenario);
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(claim_time, ts::ctx(scenario));
        
        vesting::send_to_community(&acl, &mut vesting_state, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(acl);
        ts::return_shared(vesting_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure]
fun test_claim_liquidity_and_listing_non_robot_admin_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, USER1);
    {
        let mut vesting_state = ts::take_shared<SurgeVestingState>(scenario);
        let clock = create_clock_at_time(TGE_TIMESTAMP + 1000, ts::ctx(scenario));
        
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        
        vesting::send_liquidity_and_listing(
            &super_admin,
            USER1,
            &mut vesting_state,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(vesting_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

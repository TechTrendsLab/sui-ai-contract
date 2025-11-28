#[test_only]
module surge::cross_chain_tests;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::sui::SUI;
use sui::test_scenario as ts;
use std::unit_test::{ assert_eq};
use surge::surge::{Self, SURGE, SurgeBridgeState, SuperAdmin};
use wormhole::external_address::{Self};
use wormhole::state::State;
use wormhole::wormhole_scenario::{Self};
use sui::coin::burn_for_testing;
use surge::lock_message;


const ADMIN: address = @0x1;
const USER1: address = @0x2;
const USER2: address = @0x3;
const RECIPIENT: address = @0x4;

const LOCK_AMOUNT: u64 = 1_000_000_000_000; // 1M SURGE
const FEE_AMOUNT: u64 = 10_000_000; // 10 SUI
const WORMHOLE_MESSAGE_FEE: u64 = 0;
const BSC_CHAIN_ID: u16 = 4;

const VAA_BYTES: vector<u8> = x"010000000001000358a0146ad12a67ff647a53e4cd275e280aaf7fe8971804ab6247e0a95369f26b95b6ca0ed79869e514644efb867e03f32b9a8b6e58747278c12495841a324e00692031b9000000000004000000000000000000000000ed23281b0902aa40c53154dfeea277f38070782e0000000000000000c801000000000000000000000000d767d7e0c68049b5c3c0869529ce1eeb39d0c60906ab2ac6f7a1c0b747f19ec00ee6e051b89f46186a402bf8db52865082fc357700000000000000000000000000000000000000000000000000000002540be40000040015";

const ALLOWED_EMITTER_ADDRESS: vector<u8> = x"000000000000000000000000ED23281b0902AA40C53154dFeEA277F38070782e";

fun create_clock_at_time(time: u64, ctx: &mut TxContext): Clock {
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, time);
    clock
}

fun setup_test_env(scenario: &mut ts::Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        wormhole_scenario::set_up_wormhole(scenario, WORMHOLE_MESSAGE_FEE);
    };

    ts::next_tx(scenario, ADMIN);
    {
        surge::init_for_testing(ts::ctx(scenario));
    };

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let wormhole_state = ts::take_shared<State>(scenario);
        
        surge::new(&super_admin, &wormhole_state, ts::ctx(scenario));
        
        ts::return_shared(wormhole_state);
        ts::return_to_sender(scenario, super_admin);
    };
}

fun get_recipient_bytes(addr: address): vector<u8> {
    external_address::to_bytes(external_address::from_address(addr))
}

#[test]
fun test_initialization() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        assert_eq!(surge::nonce(&surge_state), 0);
        ts::return_shared(surge_state);
    };

    ts::end(scenario_val);
}

#[test]
fun test_lock() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let mut treasury = ts::take_from_sender<TreasuryCap<SURGE>>(scenario);
        let coin = surge::mint(&mut treasury, LOCK_AMOUNT, ts::ctx(scenario));
        transfer::public_transfer(coin, USER1);
        ts::return_to_sender(scenario, treasury);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let fee_coin = coin::mint_for_testing<SUI>(100000000000, ts::ctx(scenario));
        transfer::public_transfer(fee_coin, USER1);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut wormhole_state = ts::take_shared<State>(scenario);
        let mut surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        let  coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        let mut fee = ts::take_from_sender<Coin<SUI>>(scenario);
        let clock = create_clock_at_time(1000000000, ts::ctx(scenario));
        let fee_coin = coin::split(&mut fee, FEE_AMOUNT, ts::ctx(scenario));
        let recipient_bytes = get_recipient_bytes(RECIPIENT);
        burn_for_testing(fee);
        surge::lock(
            &mut wormhole_state,
            &mut surge_state,
            coin,
            fee_coin,
            recipient_bytes,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(wormhole_state);
        ts::return_shared(surge_state);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        assert_eq!(surge::nonce(&surge_state), 1);
        ts::return_shared(surge_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = surge::EInvalidAmount)]
fun test_lock_fee_amount_fails() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let mut treasury = ts::take_from_sender<TreasuryCap<SURGE>>(scenario);
        let coin = surge::mint(&mut treasury, LOCK_AMOUNT, ts::ctx(scenario));
        transfer::public_transfer(coin, USER1);
        ts::return_to_sender(scenario, treasury);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let fee_coin = coin::mint_for_testing<SUI>(FEE_AMOUNT - 1, ts::ctx(scenario));
        transfer::public_transfer(fee_coin, USER1);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut wormhole_state = ts::take_shared<State>(scenario);
        let mut surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        let fee = ts::take_from_sender<Coin<SUI>>(scenario);
        let clock = create_clock_at_time(1000000000, ts::ctx(scenario));
        
        let recipient_bytes = get_recipient_bytes(RECIPIENT);
        
        surge::lock(
            &mut wormhole_state,
            &mut surge_state,
            coin,
            fee,
            recipient_bytes,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(wormhole_state);
        ts::return_shared(surge_state);
    };

    ts::end(scenario_val);
}

#[test]
#[expected_failure(abort_code = surge::EInvalidAmount)]
fun test_lock_invalid_fee_amount() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let mut treasury = ts::take_from_sender<TreasuryCap<SURGE>>(scenario);
        let coin = surge::mint(&mut treasury, LOCK_AMOUNT, ts::ctx(scenario));
        transfer::public_transfer(coin, USER1);
        ts::return_to_sender(scenario, treasury);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let fee_coin = coin::mint_for_testing<SUI>(FEE_AMOUNT - 1, ts::ctx(scenario));
        transfer::public_transfer(fee_coin, USER1);
    };
    
    ts::next_tx(scenario, USER1);
    {
        let mut wormhole_state = ts::take_shared<State>(scenario);
        let mut surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        let fee = ts::take_from_sender<Coin<SUI>>(scenario);
        let clock = create_clock_at_time(1000000000, ts::ctx(scenario));
        
        let recipient_bytes = get_recipient_bytes(RECIPIENT);
        
        surge::lock(
            &mut wormhole_state,
            &mut surge_state,
            coin,
            fee,
            recipient_bytes,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(wormhole_state);
        ts::return_shared(surge_state);
    };

    ts::end(scenario_val);
}

#[test]
fun test_add_allowed_emitter() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let super_admin = ts::take_from_sender<SuperAdmin>(scenario);
        let mut surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        
        let emitter_address = x"0000000000000000000000000000000000000000000000000000000000000001";
        surge::add_allowed_emitter(&super_admin, &mut surge_state, BSC_CHAIN_ID, emitter_address);
        
        ts::return_shared(surge_state);
        ts::return_to_sender(scenario, super_admin);
    };

    ts::end(scenario_val);
}

#[test]
fun test_multiple_locks() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    ts::next_tx(scenario, ADMIN);
    {
        let mut treasury = ts::take_from_sender<TreasuryCap<SURGE>>(scenario);
        let coin1 = surge::mint(&mut treasury, LOCK_AMOUNT, ts::ctx(scenario));
        let coin2 = surge::mint(&mut treasury, LOCK_AMOUNT, ts::ctx(scenario));
        transfer::public_transfer(coin1, USER1);
        transfer::public_transfer(coin2, USER2);
        ts::return_to_sender(scenario, treasury);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let fee_coin1 = coin::mint_for_testing<SUI>(FEE_AMOUNT, ts::ctx(scenario));
        let fee_coin2 = coin::mint_for_testing<SUI>(FEE_AMOUNT, ts::ctx(scenario));
        transfer::public_transfer(fee_coin1, USER1);
        transfer::public_transfer(fee_coin2, USER2);
    };

    ts::next_tx(scenario, USER1);
    {
        let mut wormhole_state = ts::take_shared<State>(scenario);
        let mut surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        let fee = ts::take_from_sender<Coin<SUI>>(scenario);
        let clock = create_clock_at_time(1000000000, ts::ctx(scenario));
        
        let recipient_bytes = get_recipient_bytes(RECIPIENT);
        
        surge::lock(
            &mut wormhole_state,
            &mut surge_state,
            coin,
            fee,
            recipient_bytes,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(wormhole_state);
        ts::return_shared(surge_state);
    };

    ts::next_tx(scenario, USER2);
    {
        let mut wormhole_state = ts::take_shared<State>(scenario);
        let mut surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        let coin = ts::take_from_sender<Coin<SURGE>>(scenario);
        let fee = ts::take_from_sender<Coin<SUI>>(scenario);
        let clock = create_clock_at_time(1000000001, ts::ctx(scenario));
        
        let recipient_bytes = get_recipient_bytes(RECIPIENT);
        
        surge::lock(
            &mut wormhole_state,
            &mut surge_state,
            coin,
            fee,
            recipient_bytes,
            &clock,
            ts::ctx(scenario),
        );
        
        clock::destroy_for_testing(clock);
        ts::return_shared(wormhole_state);
        ts::return_shared(surge_state);
    };

    ts::next_tx(scenario, ADMIN);
    {
        let surge_state = ts::take_shared<SurgeBridgeState>(scenario);
        assert_eq!(surge::nonce(&surge_state), 2);
        ts::return_shared(surge_state);
    };

    ts::end(scenario_val);
}

#[test]
fun test_lock_message_serialization() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    let lock_message = lock_message::new_lock_message(1, external_address::from_address(USER1), external_address::from_address(RECIPIENT), 1000000000000000000, 1, BSC_CHAIN_ID);
    let lock_message_copy = lock_message::new_lock_message(1, external_address::from_address(USER1), external_address::from_address(RECIPIENT), 1000000000000000000, 1, BSC_CHAIN_ID);
    let serialized = lock_message::serialize(lock_message);
    let (amount, sender, source_chain, recipient_address, target_chain) = lock_message::unpack(lock_message_copy);
    let deserialized = lock_message::deserialize(serialized);
    let (deserialized_amount, deserialized_sender, deserialized_source_chain, deserialized_recipient_address, deserialized_target_chain) = lock_message::unpack(deserialized);
    assert_eq!(amount, deserialized_amount);
    assert_eq!(sender, deserialized_sender);
    assert_eq!(recipient_address, deserialized_recipient_address);
    assert_eq!(source_chain, deserialized_source_chain);
    assert_eq!(target_chain, deserialized_target_chain);

    ts::end(scenario_val);
}

#[test]
fun test_bsc_payload_deserialization() {
    let mut scenario_val = ts::begin(ADMIN);
    let scenario = &mut scenario_val;

    setup_test_env(scenario);

    // Payload: payload_id=1, sender=0xD767d7e0C68049b5C3c0869529Ce1eEB39d0c609, 
    // recipient=0x06ab2ac6f7a1c0b747f19ec00ee6e051b89f46186a402bf8db52865082fc3577,
    // amount=100000000000, source_chain=4, target_chain=21
    let payload = x"01000000000000000000000000d767d7e0c68049b5c3c0869529ce1eeb39d0c60906ab2ac6f7a1c0b747f19ec00ee6e051b89f46186a402bf8db52865082fc3577000000000000000000000000000000000000000000000000000000174876e80000040015";
    
    // Expected values
    let expected_amount: u256 = 100000000000;
    let expected_sender_bytes = x"000000000000000000000000d767d7e0c68049b5c3c0869529ce1eeb39d0c609";
    let expected_sender = external_address::new(wormhole::bytes32::from_bytes(expected_sender_bytes));
    let expected_recipient_bytes = x"06ab2ac6f7a1c0b747f19ec00ee6e051b89f46186a402bf8db52865082fc3577";
    let expected_recipient = external_address::new(wormhole::bytes32::from_bytes(expected_recipient_bytes));
    let expected_source_chain: u16 = 4;
    let expected_target_chain: u16 = 21;

    // Deserialize payload
    let deserialized = lock_message::deserialize(payload);
    let (deserialized_amount, deserialized_sender, deserialized_source_chain, deserialized_recipient_address, deserialized_target_chain) = lock_message::unpack(deserialized);
    
    // Verify deserialized values
    assert_eq!(expected_amount, deserialized_amount);
    assert_eq!(expected_sender, deserialized_sender);
    assert_eq!(expected_recipient, deserialized_recipient_address);
    assert_eq!(expected_source_chain, deserialized_source_chain);
    assert_eq!(expected_target_chain, deserialized_target_chain);

    ts::end(scenario_val);
}

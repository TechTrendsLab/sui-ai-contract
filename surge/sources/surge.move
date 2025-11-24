
module surge::surge;

use std::ascii::string;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::event;
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::url;
use surge::lock_message;
use wormhole::consumed_vaas::{Self, ConsumedVAAs};
use wormhole::emitter::{Self, EmitterCap};
use wormhole::external_address::{Self, ExternalAddress};
use wormhole::publish_message;
use wormhole::state::State;
use wormhole::vaa;

public struct SURGE has drop {}

const DECIMALS: u8 = 9;
const SYMBOL: vector<u8> = b"SurgeAI";
const NAME: vector<u8> = b"SGE";
const DESCRIPTION: vector<u8> = b"Surge is the first dedicated AI Agent launchpad on Sui Network.";
const ICON_URL: vector<u8> = b"https://www.surge.ai/favicon.ico";
const MAX_SUPPLY: u64 = 1_000_000_000_000_000_000;

const DEFAULT_FEE_COIN_AMOUNT: u64 = 10_000_000;
const DEFAULT_RECIPIENT_ADDRESS: address = @0x1;

const SUI_CHAIN_ID: u16 = 21;
const BSC_CHAIN_ID: u16 = 4;
const PAYLOAD_ID: u8 = 1;

const EInvalidMint: u64 = 0;
const EInvalidAmount: u64 = 1;
const EInvalidEmitterAddress: u64 = 2;

public struct SurgeBridgeState has key {
    id: UID,
    nonce: u32,
    consumed_vaas: ConsumedVAAs,
    allowed_emitters: Table<u16, ExternalAddress>,
    locked_pool: Balance<SURGE>,
    fee_recipient_address: address,
    fee_coin_amount: u64,
    emitter_cap: EmitterCap,
}

public struct CoinMinted has copy, drop {
    amount: u64,
}

public struct BridgeLockEvent has copy, drop {
    sender: ExternalAddress,
    recipient_address: ExternalAddress,
    amount: u256,
}

public struct BridgeUnlockEvent has copy, drop {
    sender: ExternalAddress,
    recipient_address: ExternalAddress,
    amount: u256,
}

public struct SuperAdmin has key, store {
    id: UID,
}

fun init(witness: SURGE, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        witness,
        DECIMALS,
        SYMBOL,
        NAME,
        DESCRIPTION,
        option::some(url::new_unsafe(string(ICON_URL))),
        ctx,
    );

    let super_admin = SuperAdmin {
        id: object::new(ctx),
    };

    transfer::public_transfer(super_admin, ctx.sender());
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury, ctx.sender());
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(SURGE {}, ctx);
}

public fun test_mint(treasury: &mut TreasuryCap<SURGE>, amount: u64, ctx: &mut TxContext) {
    assert!(coin::total_supply(treasury) + amount <= MAX_SUPPLY, EInvalidMint);
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, ctx.sender());
}

public fun new(_: &SuperAdmin, wormhole_state: &State, ctx: &mut TxContext) {
    let surge_state = SurgeBridgeState {
        id: object::new(ctx),
        nonce: 0,
        consumed_vaas: consumed_vaas::new(ctx),
        allowed_emitters: table::new(ctx),
        locked_pool: balance::zero<SURGE>(),
        fee_recipient_address: DEFAULT_RECIPIENT_ADDRESS,
        fee_coin_amount: DEFAULT_FEE_COIN_AMOUNT,
        emitter_cap: emitter::new(wormhole_state, ctx),
    };
    transfer::share_object(surge_state);
}

public(package) fun mint(
    treasury: &mut TreasuryCap<SURGE>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SURGE> {
    assert!(coin::total_supply(treasury) + amount <= MAX_SUPPLY, EInvalidMint);
    event::emit(CoinMinted {
        amount: amount,
    });
    coin::mint(treasury, amount, ctx)
}

public fun lock(
    state: &mut State,
    config: &mut SurgeBridgeState,
    coin: Coin<SURGE>,
    mut fee: Coin<SUI>,
    recipient: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let cross_amount = coin::value(&coin);
    let amount = coin::value(&fee);
    assert!(amount == config.fee_coin_amount, EInvalidAmount);
    let balance = coin::into_balance(coin);
    balance::join(&mut config.locked_pool, balance);
    let sender = external_address::from_address(tx_context::sender(ctx));
    let recipient_bytes = wormhole::bytes32::from_bytes(recipient);
    let lock_message = lock_message::new_lock_message(
        PAYLOAD_ID,
        sender,
        external_address::new(recipient_bytes),
        cross_amount as u256,
        SUI_CHAIN_ID,
        BSC_CHAIN_ID,
    );
    let payload = lock_message::serialize(lock_message);
    let nonce = config.nonce;
    let fee_coin = coin::split(&mut fee, config.fee_coin_amount, ctx);
    let ticket = publish_message::prepare_message(&mut config.emitter_cap, nonce, payload);
    publish_message::publish_message(state, fee, ticket, clock);
    config.nonce = nonce + 1;
    transfer::public_transfer(fee_coin, config.fee_recipient_address);
    event::emit(BridgeLockEvent {
        sender: sender,
        recipient_address: external_address::new(recipient_bytes),
        amount: cross_amount as u256,
    });
}

public fun unlock(
    surge_state: &mut SurgeBridgeState,
    state: &mut State,
    buf: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let vaa = vaa::parse_and_verify(state, buf, clock);
    let emitter_chain = vaa::emitter_chain(&vaa);
    let emitter_address = vaa::emitter_address(&vaa);
    assert!(
        emitter_address == table::borrow(&surge_state.allowed_emitters, emitter_chain),
        EInvalidEmitterAddress,
    );
    vaa::consume(&mut surge_state.consumed_vaas, &vaa);
    let payload = vaa::take_payload(vaa);
    let unlock_message = lock_message::deserialize(payload);
    let (amount, sender, source_chain, recipient_address, target_chain) = lock_message::unpack(
        unlock_message,
    );
    assert!(balance::value(&surge_state.locked_pool) >= amount as u64, EInvalidAmount);
    let coin = coin::take(&mut surge_state.locked_pool, amount as u64, ctx);
    transfer::public_transfer(coin, external_address::to_address(recipient_address));
    event::emit(BridgeUnlockEvent {
        sender: sender,
        recipient_address: recipient_address,
        amount: amount as u256,
    });
}

public fun add_allowed_emitter(
    _: &SuperAdmin,
    state: &mut SurgeBridgeState,
    emitter_chain: u16,
    emitter_address: vector<u8>,
) {
    let emitter_address = external_address::new(wormhole::bytes32::from_bytes(emitter_address));
    table::add(&mut state.allowed_emitters, emitter_chain, emitter_address);
}

#[test_only]
public fun nonce(state: &SurgeBridgeState): u32 {
    state.nonce
}

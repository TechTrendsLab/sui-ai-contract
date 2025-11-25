module surge::vesting;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::event;
use sui::table::{Self, Table};
use surge::surge::{SURGE, SuperAdmin};

const VERSION: u64 = 0;

const MAX_LENGTH: u64 = 500;
const MONTH_TIME_MS: u64 = 1000 * 60 * 2;
const YEAR_TIME_MS: u64 = 1000 * 60 * 24;
const TOTAL_ECOSYSTEM_AIRDROP: u64 = 200_000_000_000_000_000;
const TOTAL_COMMUNITY_AIRDROP: u64 = 470_000_000_000_000_000;
const TOTAL_EARLY_BACKERS_AIRDROP: u64 = 100_000_000_000_000_000;
const TOTAL_CORE_CONTRIBUTORS_AIRDROP: u64 = 100_000_000_000_000_000;
const ECOSYSTEM_AIRDROP_MONTH: u64 = 4_166_666_666_666_666;
const COMMUNITY_AIRDROP_MONTH: u64 = 6_527_777_777_777_777;
const EARLY_BACKERS_AIRDROP_MONTH: u64 = 2_777_777_777_777_777;
const CORE_CONTRIBUTORS_AIRDROP_MONTH: u64 = 2_777_777_777_777_777;
const LIQUIDITY_AND_LISTING: u64 = 50_000_000_000_000_000;
const AIRDROP: u64 = 80_000_000_000_000_000;

const EInvalidState: u64 = 0;
const EInvalidAddress: u64 = 1;
const EAlreadyLiquidityAndListing: u64 = 2;
const EInvalidTime: u64 = 3;
const EInvalidLength: u64 = 4;
const EInvalidAddressAndValueLength: u64 = 5;
const EInvalidTgeTimestamp: u64 = 6;
const EOverAirdropAmount: u64 = 7;
const EAlreadyExistAdmin: u64 = 8;
const EAlreadySetTgeTimestamp: u64 = 9;
const EInvalidVersion: u64 = 10;

public struct ACL has key {
    id: UID,
    set_whitelist_admin: vector<address>,
    robot_admin: vector<address>,
}

public struct SurgeVestingState has key {
    id: UID,
    version: u64,
    surge_address_config: SurgeAddressConfig,
    vesting_config: VestingConfig,
    current_airdrop_amount: u64,
    claimed_airdrop_table: Table<address, u64>,
    airdrop_table: Table<address, u64>,
    treasury_cap: TreasuryCap<SURGE>,
}

public struct SurgeAddressConfig has store {
    //address,can_claim_timestamp
    early_backers: address,
    total_early_backers_airdrop: u64,
    early_backers_can_claim_timestamp: u64,

    total_core_contributors_airdrop: u64,
    core_contributors: address,
    core_contributors_can_claim_timestamp: u64,

    ecosystem: address,
    total_ecosystem_airdrop: u64,
    ecosystem_can_claim_timestamp: u64,

    community: address,
    total_community_airdrop: u64,
    community_can_claim_timestamp: u64,
}

public struct VestingConfig has store {
    is_liquidity_and_listing: bool,
    tge_timestamp: u64,
}

public struct TgeStartedEvent has copy, drop {
    tge_timestamp: u64,
    vesting_timestamp: u64,
}

public struct AirdropClaimedEvent has copy, drop {
    address: address,
    amount: u64,
}

public struct EarlyBackersClaimedEvent has copy, drop {
    address: address,
    amount: u64,
}

public struct CoreContributorsClaimedEvent has copy, drop {
    address: address,
    amount: u64,
}

public struct EcosystemClaimedEvent has copy, drop {
    address: address,
    amount: u64,
}

public struct CommunityClaimedEvent has copy, drop {
    address: address,
    amount: u64,
}

public struct LiquidityAndListingClaimedEvent has copy, drop {
    address: address,
    amount: u64,
}

public struct WhitelistAdminSetEvent has copy, drop {
    admin_list: vector<address>,
    amount_list: vector<u64>,
}

public struct VersionUpdatedEvent has copy, drop {
    old_version: u64,
    new_version: u64,
}

fun init(ctx: &mut TxContext) {
    let access_control = ACL {
        id: object::new(ctx),
        set_whitelist_admin: vector::empty(),
        robot_admin: vector::empty(),
    };
    transfer::share_object(access_control);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

public fun initialize_surge_vest_state(
    _: &SuperAdmin,
    treasury_cap: TreasuryCap<SURGE>,
    ctx: &mut TxContext,
) {
    let vesting_config = VestingConfig {
        is_liquidity_and_listing: false,
        tge_timestamp: 0,
    };

    let surge_vesting_state = SurgeVestingState {
        id: object::new(ctx),
        version: VERSION,
        surge_address_config: SurgeAddressConfig {
            early_backers: @0x0,
            core_contributors: @0x0,
            ecosystem: @0x0,
            community: @0x0,
            total_early_backers_airdrop: 0,
            total_core_contributors_airdrop: 0,
            total_ecosystem_airdrop: 0,
            total_community_airdrop: 0,
            early_backers_can_claim_timestamp: 0,
            core_contributors_can_claim_timestamp: 0,
            ecosystem_can_claim_timestamp: 0,
            community_can_claim_timestamp: 0,
        },
        vesting_config: vesting_config,
        airdrop_table: table::new(ctx),
        claimed_airdrop_table: table::new(ctx),
        treasury_cap: treasury_cap,
        current_airdrop_amount: 0,
    };

    transfer::share_object(surge_vesting_state);
}

public fun claim_airdrop_coin(
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SURGE> {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(
        clock::timestamp_ms(clock) >= config.vesting_config.tge_timestamp && config.vesting_config.tge_timestamp != 0,
        EInvalidTgeTimestamp,
    );
    assert!(table::contains(&config.airdrop_table, ctx.sender()), EInvalidAddress);
    let airdrop_amount = *table::borrow(&config.airdrop_table, ctx.sender());
    table::remove(&mut config.airdrop_table, ctx.sender());
    if(table::contains(&config.claimed_airdrop_table, ctx.sender())) {
        let claimed_airdrop_amount = *table::borrow(&config.claimed_airdrop_table, ctx.sender());
        *table::borrow_mut(&mut config.claimed_airdrop_table, ctx.sender()) = claimed_airdrop_amount + airdrop_amount;
    }else{
        table::add(&mut config.claimed_airdrop_table, ctx.sender(), airdrop_amount);
    };
    let coin = coin::mint(&mut config.treasury_cap, airdrop_amount, ctx);
    event::emit(AirdropClaimedEvent {
        address: ctx.sender(),
        amount: airdrop_amount,
    });
    coin
}

public fun claim_airdrop(config: &mut SurgeVestingState, clock: &Clock, ctx: &mut TxContext) {
    let coin = claim_airdrop_coin(config, clock, ctx);
    transfer::public_transfer(coin, ctx.sender());
}

public fun send_to_early_backers(
    acl: &ACL,
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(vector::contains(&acl.robot_admin, &ctx.sender()), EInvalidAddress);
    assert!(
        clock::timestamp_ms(clock) >= config.surge_address_config.early_backers_can_claim_timestamp 
        && config.surge_address_config.early_backers_can_claim_timestamp != 0,
        EInvalidTime,
    );
    config.surge_address_config.total_early_backers_airdrop = config.surge_address_config.total_early_backers_airdrop + EARLY_BACKERS_AIRDROP_MONTH;
    assert!(config.surge_address_config.total_early_backers_airdrop <= TOTAL_EARLY_BACKERS_AIRDROP, EOverAirdropAmount);
    let coin = coin::mint(&mut config.treasury_cap, EARLY_BACKERS_AIRDROP_MONTH, ctx);
    transfer::public_transfer(coin, config.surge_address_config.early_backers);
    config.surge_address_config.early_backers_can_claim_timestamp =
        config.surge_address_config.early_backers_can_claim_timestamp + MONTH_TIME_MS;
    event::emit(EarlyBackersClaimedEvent {
        address: config.surge_address_config.early_backers,
        amount: EARLY_BACKERS_AIRDROP_MONTH,
    });
}

public fun send_to_core_contributors(
    acl: &ACL,
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(vector::contains(&acl.robot_admin, &ctx.sender()), EInvalidAddress);
    assert!(
        clock::timestamp_ms(clock) >= config.surge_address_config.core_contributors_can_claim_timestamp 
        && config.surge_address_config.core_contributors_can_claim_timestamp != 0,
        EInvalidTime,
    );
    config.surge_address_config.total_core_contributors_airdrop = config.surge_address_config.total_core_contributors_airdrop + CORE_CONTRIBUTORS_AIRDROP_MONTH;
    assert!(config.surge_address_config.total_core_contributors_airdrop <= TOTAL_CORE_CONTRIBUTORS_AIRDROP, EOverAirdropAmount);
    let coin = coin::mint(&mut config.treasury_cap, CORE_CONTRIBUTORS_AIRDROP_MONTH, ctx);
    transfer::public_transfer(coin, config.surge_address_config.core_contributors);
    config.surge_address_config.core_contributors_can_claim_timestamp =
        config.surge_address_config.core_contributors_can_claim_timestamp + MONTH_TIME_MS;
    event::emit(CoreContributorsClaimedEvent {
        address: config.surge_address_config.core_contributors,
        amount: CORE_CONTRIBUTORS_AIRDROP_MONTH,
    });
}

public fun send_to_ecosystem(
    acl: &ACL,
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(vector::contains(&acl.robot_admin, &ctx.sender()), EInvalidAddress);
    assert!(
        clock::timestamp_ms(clock) >= config.surge_address_config.ecosystem_can_claim_timestamp
        && config.surge_address_config.ecosystem_can_claim_timestamp != 0,
        EInvalidTime,
    );
    config.surge_address_config.total_ecosystem_airdrop = config.surge_address_config.total_ecosystem_airdrop + ECOSYSTEM_AIRDROP_MONTH;
    assert!(config.surge_address_config.total_ecosystem_airdrop <= TOTAL_ECOSYSTEM_AIRDROP, EOverAirdropAmount);
    let coin = coin::mint(&mut config.treasury_cap, ECOSYSTEM_AIRDROP_MONTH, ctx);
    transfer::public_transfer(coin, config.surge_address_config.ecosystem);
    config.surge_address_config.ecosystem_can_claim_timestamp =
        config.surge_address_config.ecosystem_can_claim_timestamp + MONTH_TIME_MS;
    event::emit(EcosystemClaimedEvent {
        address: config.surge_address_config.ecosystem,
        amount: ECOSYSTEM_AIRDROP_MONTH,
    });
}

public fun send_to_community(
    acl: &ACL,
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(vector::contains(&acl.robot_admin, &ctx.sender()), EInvalidAddress);
    assert!(
        clock::timestamp_ms(clock) >= config.surge_address_config.community_can_claim_timestamp
        && config.surge_address_config.community_can_claim_timestamp != 0,
        EInvalidTime,
    );
    config.surge_address_config.total_community_airdrop = config.surge_address_config.total_community_airdrop + COMMUNITY_AIRDROP_MONTH;
    assert!(config.surge_address_config.total_community_airdrop <= TOTAL_COMMUNITY_AIRDROP, EOverAirdropAmount);
    let coin = coin::mint(&mut config.treasury_cap, COMMUNITY_AIRDROP_MONTH, ctx);
    transfer::public_transfer(coin, config.surge_address_config.community);
    config.surge_address_config.community_can_claim_timestamp =
        config.surge_address_config.community_can_claim_timestamp + MONTH_TIME_MS;
    event::emit(CommunityClaimedEvent {
        address: config.surge_address_config.community,
        amount: COMMUNITY_AIRDROP_MONTH,
    });
}

public fun send_liquidity_and_listing_coin(
    _: &SuperAdmin,
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SURGE> {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(
        clock::timestamp_ms(clock) >= config.vesting_config.tge_timestamp && config.vesting_config.tge_timestamp != 0,
        EInvalidTgeTimestamp,
    );
    assert!(!config.vesting_config.is_liquidity_and_listing, EAlreadyLiquidityAndListing);
    config.vesting_config.is_liquidity_and_listing = true;
    event::emit(LiquidityAndListingClaimedEvent {
        address: ctx.sender(),
        amount: LIQUIDITY_AND_LISTING,
    });
    coin::mint(&mut config.treasury_cap, LIQUIDITY_AND_LISTING, ctx)
}

public fun send_liquidity_and_listing(
    admin: &SuperAdmin,
    recipient: address,
    config: &mut SurgeVestingState,
    clock: &Clock,
    ctx: &mut TxContext,
) {
  let coin = send_liquidity_and_listing_coin(admin, config, clock, ctx);
  transfer::public_transfer(coin, recipient);
}


public fun set_whitelist_admin_list(
    config: &mut ACL,
    state: &mut SurgeVestingState,
    whitelist_address: vector<address>,
    value: vector<u64>,
    ctx: &mut TxContext,
) {
    assert!(state.version == VERSION, EInvalidVersion);
    assert!(vector::contains(&config.set_whitelist_admin, &ctx.sender()), EInvalidAddress);
    assert!(
        vector::length(&whitelist_address) == vector::length(&value),
        EInvalidAddressAndValueLength,
    );
    assert!(whitelist_address.length() <= MAX_LENGTH, EInvalidLength);
    let mut i = 0;
    while (i < whitelist_address.length()) {
        if (table::contains(&state.airdrop_table, whitelist_address[i])) {
            state.current_airdrop_amount =
                state.current_airdrop_amount + value[i];
            *table::borrow_mut(&mut state.airdrop_table, whitelist_address[i]) = value[i] + *table::borrow(&state.airdrop_table, whitelist_address[i]);
        } else {
            table::add(&mut state.airdrop_table, whitelist_address[i], value[i]);
            state.current_airdrop_amount = state.current_airdrop_amount + value[i];
        };
        i = i + 1;
    };

    assert!(state.current_airdrop_amount <= AIRDROP, EOverAirdropAmount);
    event::emit(WhitelistAdminSetEvent {
        admin_list: whitelist_address,
        amount_list: value,
    });
}

public fun remove_whitelist_admin_list(
    config: &mut ACL,
    state: &mut SurgeVestingState,
    whitelist_address: vector<address>,
    ctx: &mut TxContext,
) {
    assert!(state.version == VERSION, EInvalidVersion);
    assert!(whitelist_address.length() <= MAX_LENGTH, EInvalidLength);
    assert!(vector::contains(&config.set_whitelist_admin, &ctx.sender()), EInvalidAddress);
    let mut i = 0;
    while (i < whitelist_address.length()) {
        state.current_airdrop_amount =
            state.current_airdrop_amount - *table::borrow(&state.airdrop_table, whitelist_address[i]);
        table::remove(&mut state.airdrop_table, whitelist_address[i]);
        i = i + 1;
    };
}

public fun set_tge_timestamp(
    _: &SuperAdmin,
    config: &mut SurgeVestingState,
    tge_timestamp: u64,
    vesting_timestamp: u64,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    assert!(config.vesting_config.tge_timestamp == 0, EAlreadySetTgeTimestamp);
    assert!(vesting_timestamp > tge_timestamp, EInvalidTime);
    config.vesting_config.tge_timestamp = tge_timestamp;
    config.surge_address_config.early_backers_can_claim_timestamp =
        vesting_timestamp + YEAR_TIME_MS;
    config.surge_address_config.core_contributors_can_claim_timestamp =
        vesting_timestamp + YEAR_TIME_MS;
    config.surge_address_config.ecosystem_can_claim_timestamp = vesting_timestamp;
    config.surge_address_config.community_can_claim_timestamp = vesting_timestamp;
    event::emit(TgeStartedEvent {
        tge_timestamp: tge_timestamp,
        vesting_timestamp: vesting_timestamp,
    });
}

public fun set_robot_admin(_: &SuperAdmin, config: &mut ACL, admin: address) {
    assert!(!vector::contains(&config.robot_admin, &admin), EAlreadyExistAdmin);
    vector::push_back(&mut config.robot_admin, admin);
}

public fun set_whitelist_admin(_: &SuperAdmin, config: &mut ACL, admin: address) {
    assert!(!vector::contains(&config.set_whitelist_admin, &admin), EAlreadyExistAdmin);
    vector::push_back(&mut config.set_whitelist_admin, admin);
}

public fun set_early_backers_address(
    _: &SuperAdmin,
    config: &mut SurgeVestingState,
    addr: address,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    config.surge_address_config.early_backers = addr;
}

public fun set_core_contributors_address(
    _: &SuperAdmin,
    config: &mut SurgeVestingState,
    addr: address,
) {
    assert!(config.version == VERSION, EInvalidVersion);
    config.surge_address_config.core_contributors = addr;
}

public fun set_ecosystem_address(_: &SuperAdmin, config: &mut SurgeVestingState, addr: address) {
    assert!(config.version == VERSION, EInvalidVersion);
    config.surge_address_config.ecosystem = addr;
}

public fun set_community_address(_: &SuperAdmin, config: &mut SurgeVestingState, addr: address) {
    assert!(config.version == VERSION, EInvalidVersion);
    config.surge_address_config.community = addr;
}

public fun remove_robot_admin(_: &SuperAdmin, config: &mut ACL, admin: address) {
    let (is_found, index) = vector::index_of(&config.robot_admin, &admin);
    assert!(is_found, EInvalidAddress);
    vector::remove(&mut config.robot_admin, index);
}

public fun remove_whitelist_admin(_: &SuperAdmin, config: &mut ACL, admin: address) {
    let (is_found, index) = vector::index_of(&config.set_whitelist_admin, &admin);
    assert!(is_found, EInvalidAddress);
    vector::remove(&mut config.set_whitelist_admin, index);
}

public fun migrate_version(_: &SuperAdmin, config: &mut SurgeVestingState) {
    assert!(config.version < VERSION, EInvalidVersion);
    event::emit(VersionUpdatedEvent {
        old_version: config.version,
        new_version: VERSION,
    });
    config.version = VERSION;
}

///getter
public fun get_whitelist_admin(config: &ACL): vector<address> {
    config.set_whitelist_admin
}

public fun get_robot_admin(config: &ACL): vector<address> {
    config.robot_admin
}

public fun get_user_airdrop_amount(state: &SurgeVestingState, addr: address): u64 {
    if (table::contains(&state.airdrop_table, addr)) {
        *table::borrow(&state.airdrop_table, addr)
    } else {
        0
    }
}

public fun get_tge_timestamp(config: &SurgeVestingState): u64 {
    config.vesting_config.tge_timestamp
}

public fun get_early_backers_can_claim_timestamp(config: &SurgeVestingState): u64 {
    config.surge_address_config.early_backers_can_claim_timestamp
}

public fun get_core_contributors_can_claim_timestamp(config: &SurgeVestingState): u64 {
    config.surge_address_config.core_contributors_can_claim_timestamp
}

public fun get_ecosystem_can_claim_timestamp(config: &SurgeVestingState): u64 {
    config.surge_address_config.ecosystem_can_claim_timestamp
}

public fun get_community_can_claim_timestamp(config: &SurgeVestingState): u64 {
    config.surge_address_config.community_can_claim_timestamp
}

public fun get_is_liquidity_and_listing(config: &SurgeVestingState): bool {
    config.vesting_config.is_liquidity_and_listing
}

public fun get_claimed_airdrop_amount(state: &SurgeVestingState, addr: address): u64 {
    if (table::contains(&state.claimed_airdrop_table, addr)) {
        *table::borrow(&state.claimed_airdrop_table, addr)
    } else {
        0
    }
}

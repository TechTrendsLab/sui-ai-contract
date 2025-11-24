module surge::lock_message;

use wormhole::bytes::{Self};
use wormhole::cursor::{Self};
use wormhole::external_address::{Self, ExternalAddress};

public struct LockMessage has drop {
    payload_id: u8,
    sender: ExternalAddress,
    recipient_address: ExternalAddress,
    amount: u256,
    source_chain: u16,
    target_chain: u16,
}

public fun new_lock_message(payload_id: u8, sender: ExternalAddress, recipient_address: ExternalAddress, amount: u256, source_chain: u16, target_chain: u16): LockMessage {
    LockMessage {
        payload_id,
        sender,
        recipient_address,
        amount,
        source_chain,
        target_chain,
    }
}

public fun serialize(lock_message: LockMessage): vector<u8> {
    let mut buf = vector::empty<u8>();
    bytes::push_u8(&mut buf, lock_message.payload_id);
    vector::append(&mut buf, external_address::to_bytes(lock_message.sender));
    vector::append(&mut buf, external_address::to_bytes(lock_message.recipient_address));
    bytes::push_u256_be(&mut buf, lock_message.amount);
    bytes::push_u16_be(&mut buf, lock_message.source_chain);
    bytes::push_u16_be(&mut buf, lock_message.target_chain);
    buf
}

public fun deserialize(buf: vector<u8>): LockMessage {  
    let mut cur = cursor::new(buf);
    let payload_id = bytes::take_u8(&mut cur);
    let sender = external_address::take_bytes(&mut cur);
    let recipient_address = external_address::take_bytes(&mut cur);
    let amount = bytes::take_u256_be(&mut cur);
    let source_chain = bytes::take_u16_be(&mut cur);
    let target_chain = bytes::take_u16_be(&mut cur);
    cursor::take_rest(cur);
    LockMessage {
        payload_id,
        sender,
        recipient_address,
        amount,
        source_chain,
        target_chain,
    }
}

public fun unpack(lock_message: LockMessage): (u256, ExternalAddress, u16, ExternalAddress, u16) {
    (lock_message.amount, lock_message.sender, lock_message.source_chain, lock_message.recipient_address, lock_message.target_chain)
}

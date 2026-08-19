package main

import "core:crypto"
import "core:encoding/hex"
import "core:encoding/uuid"
import "core:time"

Uuid :: uuid.Identifier

uuid_v4 :: proc() -> (id: Uuid) {
	context.random_generator = crypto.random_generator()
	id = uuid.generate_v4()
	return
}

uuid_v7 :: proc() -> (id: Uuid) {
	context.random_generator = crypto.random_generator()
	id = uuid.generate_v7()
	return
}

uuid_to_hex :: proc(id: Uuid, allocator := context.allocator) -> string {
	id := id
	out := hex.encode(id[:], allocator)
	return transmute(string)out
}

uuid_from_hex :: proc(src: string) -> (uuid: Uuid, ok: bool) {
	hex.decode_into_buffer(transmute([]u8)src, uuid[:]) or_return

	ok = true
	return
}

// Seconds since 1 Jan 1970.
unix_time :: proc() -> i64 {
	return time.time_to_unix(time.now())
}

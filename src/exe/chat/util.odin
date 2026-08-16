package main

import "core:crypto"
import "core:encoding/hex"
import "core:encoding/uuid"

Uuid :: uuid.Identifier

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

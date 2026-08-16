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


// TODO: When https://github.com/odin-lang/Odin/pull/7347 is merged, replace with
// hex.decode_into_buffer
uuid_from_hex :: proc(src: string) -> (uuid: Uuid, ok: bool) {
	if len(src) != 32 do return

	dst := uuid[:]
	#no_bounds_check for i, j := 0, 1; j < 32; j += 2 {
		p := src[j-1]
		q := src[j]

		a := hex_digit(p) or_return
		b := hex_digit(q) or_return

		dst[i] = (a << 4) | b
		i += 1
	}
	ok = true
	return
}

hex_digit :: proc(char: byte) -> (u8, bool) {
	switch char {
	case '0' ..= '9': return char - '0', true
	case 'a' ..= 'f': return char - 'a' + 10, true
	case 'A' ..= 'F': return char - 'A' + 10, true
	case:             return 0, false
	}
}

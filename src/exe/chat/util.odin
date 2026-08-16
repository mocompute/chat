package main

import "core:crypto"
import "core:encoding/uuid"

Uuid :: uuid.Identifier

uuid_v7 :: proc() -> (id: Uuid) {
	context.random_generator = crypto.random_generator()
	id = uuid.generate_v7()
	return
}

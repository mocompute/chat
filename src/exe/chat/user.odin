package main

import "../../../../base/src/lib/sqlite3"

import "base:intrinsics"
import "core:crypto"
import "core:crypto/argon2id"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

SALT_BYTES :: argon2id.RECOMMENDED_SALT_SIZE
KEY_LENGTH :: argon2id.RECOMMENDED_TAG_SIZE

User_Role :: enum {
	Plain,
	Create_Channel,
	Create_Server,
	Super,
}

User :: struct {
	uuid: Uuid,
	server: Uuid,
	username: string,
	hashed_password: [KEY_LENGTH]u8,
	salt: [SALT_BYTES]u8,
	role: User_Role,
}

User_Create_Table :: `-- sql
	CREATE TABLE IF NOT EXISTS user(
	uuid            BLOB PRIMARY KEY,
	server          BLOB NOT NULL REFERENCES server(uuid) ON DELETE CASCADE,
	username        TEXT NOT NULL UNIQUE,
	hashed_password BLOB NOT NULL,
	salt            BLOB NOT NULL,
	role            INTEGER NOT NULL
	) WITHOUT ROWID;
	CREATE UNIQUE INDEX IF NOT EXISTS user_server_username ON user(
	server, username
	);`

user_from_row :: proc(obj: any, stmt: sqlite3.Statement) -> (err: Db_Error) {
	switch self in obj {
	case ^User:
		err = db_scan_columns(stmt, {
			{"uuid", self.uuid[:]},
			{"server", self.server[:]},
			{"username", &self.username},
			{"hashed_password", self.hashed_password[:]},
			{"salt", self.salt[:]},
			{"role", cast(^int)(&self.role)},
		})
	case:
		panic(fmt.tprintf("user_from_row: bad type %v", obj))
	}
	return
}

user_to_row :: proc(obj: any, stmt: sqlite3.Statement) -> (err: Db_Error) {
	switch self in obj {
	case User:
		uuid := self.uuid
		server := self.server
		hashed_password := self.hashed_password
		salt := self.salt
		err = db_bind(stmt, {
			{":uuid", uuid[:]},
			{":server", server[:]},
			{":username", self.username},
			{":hashed_password", hashed_password[:]},
			{":salt", salt[:]},
			{":role", int(self.role)},
		})
	case:
		panic(fmt.tprintf("user_to_row: bad type %v", obj))
	}
	return
}

// Allocates to copy username string. Argon may return allocator error.
user_init :: proc(self: ^User, server: Uuid, username, password: string, pepper: []u8) -> (err: mem.Allocator_Error) {
	crypto.rand_bytes(self.salt[:])
	argon2id.derive(&argon2id.PARAMS_OWASP, transmute([]u8)password, self.salt[:], self.hashed_password[:], pepper) or_return

	self.server = server
	self.uuid = uuid_v7()
	self.username = strings.clone(username)
	return
}

user_deinit :: proc(self: ^User) {
	delete(self.username)
}
user_deinit_rawptr :: proc(self: rawptr) {
	user_deinit(cast(^User)self)
}

user_save :: proc(self: User, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT OR REPLACE INTO user(uuid, server, username, hashed_password, salt, role)
	VALUES(:uuid, :server, :username, :hashed_password, :salt, :role);
	`
	stmt: sqlite3.Statement
	stmt = db_prepare_bind_row(db, sql, self, user_to_row) or_return
	db_step_and_finalize_default_timeout(stmt) or_return
	return
}



user_load_uuid :: proc(self: ^User, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	SELECT * FROM user WHERE uuid = :uuid;`
	return user_load_(self, db, sql)
}

user_load_username :: proc(self: ^User, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	SELECT * FROM user WHERE username = :username;`
	return user_load_(self, db, sql)
}

user_load_ :: proc(self: ^User, db: Db, sql: cstring) -> (err: Db_Error) {
	stmt: sqlite3.Statement

	// set sql params required by sql from self
	stmt = db_prepare_bind_row(db, sql, self^, user_to_row) or_return
	db_retrieve_one_and_finalize_default_timeout(stmt, self, user_from_row) or_return
	return
}

user_create :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.action.(Command).(User_Create)

	user: User
	alloc_err := user_init(&user, cmd.server, cmd.username, cmd.password, cmd.pepper[:])
	if alloc_err != nil {
		task_data.status = .Runtime_Error
		task_data.message = fmt.aprintf("%v", alloc_err)
		return
	}
	err := user_save(user, tl_db_conn)

	if !is_db_error(err, task_data, cmd.username) {
		cmd.result = new_clone(user) // transfers ownership to task

		task_data.result = cmd.result
		task_data.result_deinit = user_deinit_rawptr
	}
}


user_lookup_username :: proc(task: Task) {
	task_data := task_to_task_data(task)
	q := task_data.action.(Query).(User_Lookup_Username)

	user := User{server=q.server, username=q.username}
	err := user_load_username(&user, tl_db_conn)

	if !is_db_error(err, task_data) {
		q.result = new_clone(user)

		task_data.result = q.result
		task_data.result_deinit = user_deinit_rawptr
	}
	return
}

user_lookup_uuid :: proc(task: Task) {
	task_data := task_to_task_data(task)
	q := task_data.action.(Query).(User_Lookup_Uuid)

	user := User{uuid=q.user}
	err := user_load_uuid(&user, tl_db_conn)

	if !is_db_error(err, task_data) {
		q.result = new_clone(user)

		task_data.result = q.result
		task_data.result_deinit = user_deinit_rawptr
	}
	return
}

user_role_assign :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.action.(Command).(User_Role_Assign)

	user := User{uuid=cmd.user}
	err := user_load_uuid(&user, tl_db_conn)
	if err != nil {
		task_data.status = .Not_Found
		return
	}

	user.role = cmd.role
	err = user_save(user, tl_db_conn)
	if !is_db_error(err, task_data) {
		cmd.result = new_clone(user)

		task_data.result = cmd.result
		task_data.result_deinit = user_deinit_rawptr
	}
	return
}

user_role_to_i64 :: proc(role: User_Role) -> (result: i64, ok: bool) {
	switch role {
	case .Plain: return 0, true
	case .Create_Channel: return 1, true
	case .Create_Server: return 2, true
	case .Super: return 3, true
	}
	return
}

user_role_from_i64 :: proc(index: i64) -> (result: User_Role, ok: bool) {
	switch index {
	case 0: return .Plain, true
	case 1: return .Create_Channel, true
	case 2: return .Create_Server, true
	case 3: return .Super, true
	}
	return
}

user_role_from_string :: proc(s: string) -> (result: User_Role, ok: bool) {
	switch s {
	case "plain": return .Plain, true
	case "create-channel": return .Create_Channel, true
	case "create-server": return .Create_Server, true
	case "super": return .Super, true
	}
	return
}

user_valid_password :: proc(self: User, test_password: string, pepper: []u8) -> bool {
	hashed_password: [KEY_LENGTH]u8
	salt := self.salt
	err := argon2id.derive(&argon2id.PARAMS_OWASP, transmute([]u8)test_password, salt[:], hashed_password[:], pepper)
	if err != nil do return false
	return hashed_password == self.hashed_password
}

user_role_can_create_channel :: proc(role: User_Role) -> bool {
	switch role {
	case .Plain: return false
	case .Create_Channel: return true
	case .Create_Server: return true
	case .Super: return true
	}
	return false
}

@(test)
test_password :: proc(t: ^testing.T) {
	server := uuid_v7()
	user: User
	err := user_init(&user, server, "foo", "bar", {1,2,3,4})
	testing.expect(t, err == nil)
	defer user_deinit(&user)

	testing.expect_value(t, true, user_valid_password(user, "bar", {1,2,3,4}))
	testing.expect_value(t, false, user_valid_password(user, "barf", {1,2,3,4}))
}

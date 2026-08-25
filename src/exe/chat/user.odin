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

User_Row :: Db_Row_Spec{{"uuid", []u8}, {"server", []u8}, {"username", cstring}, {"hashed_password", []u8}, {"salt", []u8}, {"role", i64}}
User_Cols :: "uuid, server, username, hashed_password, salt, role"
User_Cols_P :: ":uuid, :server, :username, :hashed_password, :salt, :role"
User_Cols_N :: 6
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

user_from_row :: proc(stmt: sqlite3.Statement, allocator := context.allocator) -> (self: User, err: Db_Error) {
	res: [User_Cols_N]Db_Value
	db_get_columns(stmt, User_Row, res[:]) or_return

	bs: []u8
	bs = res[0].([]u8)
	copy_exact(self.uuid[:], bs)

	bs = res[1].([]u8)
	copy_exact(self.server[:], bs)

	// stmt will be finalized, so we need to clone
	self.username = strings.clone_from_cstring(res[2].(cstring), allocator)

	bs = res[3].([]u8)
	copy_exact(self.hashed_password[:], bs)

	bs = res[4].([]u8)
	copy_exact(self.salt[:], bs)

	self.role = User_Role(res[5].(i64))
	return
}

@(require_results)
user_db_prepare_statement :: proc(self: ^User, db: Db, sql: cstring) -> (stmt: sqlite3.Statement, err: Db_Error) {
	stmt, err = db_prepare_bind(db, sql, {
		{":uuid", self.uuid[:]},
		{":server", self.server[:]},
		{":username", self.username},
		{":hashed_password", self.hashed_password[:]},
		{":salt", self.salt[:]},
		{":role", i64(self.role)},
	})
	return
}

// Allocates to copy username string.
user_init :: proc(self: ^User, server: Uuid, username, password: string, pepper: []u8, allocator := context.allocator) -> (err: mem.Allocator_Error) {
	crypto.rand_bytes(self.salt[:])
	argon2id.derive(&argon2id.PARAMS_OWASP, transmute([]u8)password, self.salt[:], self.hashed_password[:], pepper) or_return

	self.server = server
	self.uuid = uuid_v7()
	self.username = strings.clone(username, allocator)
	return
}

user_deinit :: proc(self: ^User, allocator := context.allocator) {
	delete(self.username, allocator)
}
user_deinit_rawptr :: proc(self: rawptr, allocator := context.allocator) {
	user_deinit(cast(^User)self, allocator)
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
	err := user_db_create(&user, tl_db_conn)

	if !is_db_error(err, task_data, cmd.username) {
		cmd.result = new_clone(user) // transfers ownership to task

		task_data.result = cmd.result
		task_data.result_deinit = user_deinit_rawptr
	}
}

user_lookup_username :: proc(task: Task) {
	task_data := task_to_task_data(task)
	q := task_data.action.(Query).(User_Lookup_Username)

	user, err := user_db_lookup_username(tl_db_conn, q.server, q.username, context.allocator)

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

	user, err := user_db_lookup_uuid(tl_db_conn, q.user, context.allocator)

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

	user, err := user_db_lookup_uuid(tl_db_conn, cmd.user)
	if err != nil {
		task_data.status = .Not_Found
		return
	}

	user.role = cmd.role
	err = user_db_update(&user, tl_db_conn)
	if !is_db_error(err, task_data) {
		cmd.result = new_clone(user)

		task_data.result = cmd.result
		task_data.result_deinit = user_deinit_rawptr
	}
	return
}

user_db_create :: proc(self: ^User, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT INTO user (` + User_Cols + `)
	VALUES(` + User_Cols_P + `);
	`
	stmt := user_db_prepare_statement(self, db, sql) or_return
	defer db_finalize(stmt)
	return db_insert_unique(stmt)
}

user_db_update :: proc(self: ^User, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	UPDATE user SET (` + User_Cols + `) = (` + User_Cols_P + `)
	WHERE uuid = :uuid;`

	stmt := user_db_prepare_statement(self, db, sql) or_return
	defer db_finalize(stmt)
	return db_step(stmt)
}


user_db_lookup_username :: proc(db: Db, server: Uuid, username: string, allocator := context.allocator) -> (self: User, err: Db_Error) {
	server := server
	sql :: `SELECT ` + User_Cols + ` FROM user WHERE server = :server AND username = :username;`

	stmt := db_prepare_bind(db, sql, {
		{":server", server[:]},
		{":username", username},
	}) or_return
	defer db_finalize(stmt)

	self = db_retrieve_one(User, stmt, user_from_row, allocator) or_return
	return
}

user_db_lookup_uuid :: proc(db: Db, user: Uuid, allocator := context.allocator) -> (self: User, err: Db_Error) {
	user := user
	sql :: `SELECT ` + User_Cols + ` FROM user WHERE uuid = :uuid;`

	stmt := db_prepare_bind(db, sql, {
		{":uuid", user[:]},
	}) or_return
	defer db_finalize(stmt)

	self = db_retrieve_one(User, stmt, user_from_row, allocator) or_return
	return
}

user_db_get_role :: proc(db: Db, user: Uuid) -> (role: User_Role, err: Db_Error) {
	user := user
	sql :: `SELECT role FROM user WHERE uuid = :uuid`
	stmt := db_prepare_bind(db, sql, {
		{":uuid", user[:]},
	}) or_return
	defer db_finalize(stmt)

	role_from_row :: proc(stmt: sqlite3.Statement, allocator := context.allocator) -> (role: User_Role, err: Db_Error) {
		res: [1]Db_Value
		db_get_columns(stmt, {{"role", i64}}, res[:]) or_return

		ok: bool
		role, ok = user_role_from_i64(res[0].(i64))
		if !ok {
			err = .Out_Of_Range
		}
		return
	}

	role = db_retrieve_one(User_Role, stmt, role_from_row) or_return
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

user_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	err = db_exec(db, User_Create_Table)
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

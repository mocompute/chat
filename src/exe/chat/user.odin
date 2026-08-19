package main

import "../../../../base/src/lib/sqlite3"

import "base:intrinsics"
import "core:crypto"
import "core:crypto/argon2id"
import "core:testing"

SALT_BYTES :: argon2id.RECOMMENDED_SALT_SIZE
KEY_LENGTH :: argon2id.RECOMMENDED_TAG_SIZE

User :: struct {
	uuid: Uuid,
	server: Uuid,
	username: string,
	hashed_password: [KEY_LENGTH]u8,
	salt: [SALT_BYTES]u8,
}

User_Row :: Db_Row_Spec{{"uuid", []u8}, {"server", []u8}, {"username", cstring}, {"hashed_password", []u8}, {"salt", []u8}}
User_Cols :: "uuid, server, username, hashed_password, salt"
User_Cols_N :: 5

user_from_row :: proc(stmt: sqlite3.Statement) -> (self: User, err: Db_Error) {
	res: [User_Cols_N]Db_Value
	db_columns(stmt, User_Row, res[:]) or_return

	bs: []u8
	bs = res[0].([]u8)
	copy(self.uuid[:], bs)

	bs = res[1].([]u8)
	copy(self.server[:], bs)

	self.username = string(res[2].(cstring))

	bs = res[3].([]u8)
	copy(self.hashed_password[:], bs)

	bs = res[4].([]u8)
	copy(self.salt[:], bs)

	return
}

user_create :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.command.(User_Create)

	user, err := user_hash_create(cmd.username, cmd.password, cmd.pepper[:])
	if err != nil {
		task_data.status = .Runtime_Error
		return
	}
	err = user_db_create(&user, db_conn)

	if !is_db_error(err, task_data) {
		cmd.result = new_clone(user)
		task_data.result = cmd.result
	}
}

user_hash_create :: proc(username, password: string, pepper: []u8) -> (user: User, err: Db_Error) {
	user.username = username
	crypto.rand_bytes(user.salt[:])

	argon2id.derive(&argon2id.PARAMS_OWASP, transmute([]u8)password, user.salt[:], user.hashed_password[:], pepper) or_return
	return
}

user_db_create :: proc(self: ^User, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT INTO user (uuid, server, username, password, salt)
	VALUES(:uuid, :server, :username, :password, :salt);
	`
	stmt := db_prepare_bind(db, sql, {
		{":uuid", self.uuid[:]},
		{":server", self.server[:]},
		{":username", self.username},
		{":password", self.hashed_password[:]},
		{":salt", self.salt[:]},
	}) or_return
	defer db_finalize(stmt)
	return db_insert_unique(stmt)
}

user_db_lookup_username :: proc(db: Db, username: string) -> (self: User, err: Db_Error) {
	sql :: `SELECT ` + User_Cols + ` FROM user WHERE username = :username;`

	stmt := db_prepare_bind(db, sql, {{":username", username}}) or_return
	defer db_finalize(stmt)
	self = db_retrieve_one(User, stmt, user_from_row) or_return
	return
}

user_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	CREATE TABLE IF NOT EXISTS user(
	uuid BLOB PRIMARY KEY,
	server BLOB NOT NULL,
	username TEXT NOT NULL UNIQUE,
	password BLOB NOT NULL,
	salt BLOB NOT NULL
	) WITHOUT ROWID;
	`
	err = db_exec_multi_null(db, sql)
	return
}

user_valid_password :: proc(self: User, test_password: string, pepper: []u8) -> bool {
	hashed_password: [KEY_LENGTH]u8
	salt := self.salt
	err := argon2id.derive(&argon2id.PARAMS_OWASP, transmute([]u8)test_password, salt[:], hashed_password[:], pepper)
	if err != nil do return false
	return hashed_password == self.hashed_password
}

@(test)
test_password :: proc(t: ^testing.T) {
	user, err := user_hash_create("foo", "bar", {1,2,3,4})
	testing.expect(t, err == nil)

	testing.expect_value(t, true, user_valid_password(user, "bar", {1,2,3,4}))
	testing.expect_value(t, false, user_valid_password(user, "barf", {1,2,3,4}))
}

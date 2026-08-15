package main

import "../../lib/sqlite3"

import "base:intrinsics"
import "core:crypto"
import "core:crypto/argon2id"
import "core:encoding/hex"
import "core:fmt"
import "core:testing"


@(private="file")
SALT_BYTES :: argon2id.RECOMMENDED_SALT_SIZE
@(private="file")
KEY_LENGTH :: argon2id.RECOMMENDED_TAG_SIZE

User :: struct {
	id: i64,
	username: string,
	hashed_password: [KEY_LENGTH]u8,
	salt: [SALT_BYTES]u8,
}

User_Create :: struct {
	username: string,
	password: string,
	pepper: []u8,
}

user_create :: proc(uc: User_Create) -> (user: User, err: Db_Error) {
	user.username = uc.username
	crypto.rand_bytes(user.salt[:])

	argon2id.derive(&argon2id.PARAMS_OWASP, transmute([]u8)uc.password, user.salt[:], user.hashed_password[:], uc.pepper) or_return

	fmt.eprintln("user_create:")
	fmt.eprintfln("    salt = %s", hex.encode(user.salt[:], context.temp_allocator))
	fmt.eprintfln("    hash = %s", hex.encode(user.hashed_password[:], context.temp_allocator))
	return
}

user_db_create :: proc(self: ^User, db: Db) -> (err: Db_Error) {

	sql :: `-- sql
	INSERT INTO user (username, password, salt)
	VALUES(:username, :password, :salt);
	`
	stmt := db_prepare(db, sql) or_return
	defer db_finalize(stmt)

	db_bind(stmt, {
		{":username", self.username},
		{":password", self.hashed_password[:]},
		{":salt", self.salt[:]},
	}) or_return

	err = sqlite3.step(stmt)

	if err == sqlite3.Result.Done {
		self.id = sqlite3.last_insert_rowid(db)
	} else if err == sqlite3.Result.Constraint {
		err = .Exists
	}
	return
}

user_db_retrieve :: proc(db: Db, username: string) -> (self: User, err: Db_Error) {
	sql :: `-- sql
	SELECT id, password, salt FROM user WHERE username = :username;
	`
	row := Db_Row_Spec{{"id", i64}, {"password", []u8}, {"salt", []u8}}
	res :  [3]Db_Value

	stmt := db_prepare(db, sql) or_return
	defer db_finalize(stmt)

	db_bind(stmt, {{":username", username}}) or_return

	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Row {

		ensure(KEY_LENGTH == sqlite3.column_bytes(stmt, 1))
		ensure(SALT_BYTES == sqlite3.column_bytes(stmt, 2))

		db_columns(stmt, row, res[:])

		id := res[0].(i64)
		hashed := res[1].([]u8)
		salt := res[2].([]u8)

		ensure(len(hashed) == KEY_LENGTH)
		ensure(len(salt) == SALT_BYTES)

		self.id = id
		self.username = username
		copy(self.hashed_password[:], hashed)
		copy(self.salt[:], salt)

		fmt.eprintln("user_db_retrieve:")
		fmt.eprintfln("    salt = %s", hex.encode(self.salt[:], context.temp_allocator))
		fmt.eprintfln("    hash = %s", hex.encode(self.hashed_password[:], context.temp_allocator))

		err = nil
	} else {
		err = Runtime_Error.Not_Found
	}

	return
}

user_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	CREATE TABLE IF NOT EXISTS user(
	id INTEGER PRIMARY KEY,
	username TEXT NOT NULL UNIQUE,
	password BLOB NOT NULL,
	salt BLOB NOT NULL
	);
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
	user, err := user_create({"foo", "bar", {1,2,3,4}})
	testing.expect(t, err == nil)

	testing.expect_value(t, true, user_valid_password(user, "bar", {1,2,3,4}))
	testing.expect_value(t, false, user_valid_password(user, "barf", {1,2,3,4}))
}

package main

import "core:crypto"
import "../../../../base/src/lib/sqlite3"
@(require) import "core:fmt"

PEPPER_BYTES :: 8
CONFIG_VERSION :: i32(1)

Config :: struct {
	id: i64,
	version: i32,
	pepper: [PEPPER_BYTES]u8,
}
Config_Row :: Db_Row_Spec{{"version", i64}, {"pepper", []u8}}
Config_Cols :: "version, pepper"
Config_Cols_N :: 2
Config_Create_Table :: `-- sql
	CREATE TABLE IF NOT EXISTS config(
	id INTEGER PRIMARY KEY,
	version INTEGER,
	pepper BLOB);`

config_from_row :: proc(stmt: sqlite3.Statement, allocator := context.allocator) -> (self: Config, err: Db_Error) {
	res: [Config_Cols_N]Db_Value
	db_get_columns(stmt, Config_Row, res[:]) or_return
	self.version = i32(res[0].(i64))

	bs: []u8
	bs = res[1].([]u8)
	copy_exact(self.pepper[:], bs)
	return
}

config_create :: proc() -> (self: Config) {
	self.id = 1
	self.version = CONFIG_VERSION
	crypto.rand_bytes(self.pepper[:])
	return
}

version_get :: proc(task: Task) {
	task_data := task_to_task_data(task)
	query := task_data.query.(Version_Get)

	config, err := config_db_retrieve(tl_db_conn)
	if !is_db_error(err, task_data) {
		query.result = config.version
		task_data.result = i64(query.result)
	}
}

config_db_create :: proc(self: ^Config, db: Db) -> (err: Db_Error) {
	_, err = config_db_retrieve(db)
	if err == nil do return

	sql :: `-- sql
	INSERT OR IGNORE INTO config(id, version, pepper)
	VALUES(:id, :version, :pepper);
	`
	stmt := db_prepare_bind(db, sql, {
		{":id", self.id},
		{":version", CONFIG_VERSION},
		{":pepper", self.pepper[:]},
	}) or_return
	defer db_finalize(stmt)

	err = db_step(stmt)
	if err == sqlite3.Result.Done do err = nil

	return
}

config_db_retrieve :: proc(db: Db, allocator := context.allocator) -> (self: Config, err: Db_Error) {
	sql :: `SELECT ` + Config_Cols + ` FROM config WHERE id = 1;`

	stmt := db_prepare_bind(db, sql, {}) or_return
	defer db_finalize(stmt)

	self = db_retrieve_one(Config, stmt, config_from_row, allocator) or_return
	return
}

config_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	err = db_exec(db, Config_Create_Table)
	return
}

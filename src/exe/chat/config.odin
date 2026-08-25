package main

import "base:intrinsics"
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

Config_Create_Table :: `-- sql
	CREATE TABLE IF NOT EXISTS config(
	id INTEGER PRIMARY KEY,
	version INTEGER,
	pepper BLOB);`

config_from_row :: proc(self: ^Config, stmt: sqlite3.Statement) -> (err: Db_Error) {
	err = db_scan_columns(stmt, {
		{"id", &self.id},
		{"version", &self.version},
		{"pepper", self.pepper[:]},
	})
	return
}

config_to_row :: proc(self: Config, stmt: sqlite3.Statement) -> (err: Db_Error) {
	pepper := self.pepper
	err = db_bind(stmt, {
		{":id", self.id},
		{":version", self.version},
		{":pepper", pepper[:]},
	})
	return
}

config_init :: proc(self: ^Config) {
	self.id = 1
	self.version = CONFIG_VERSION
	crypto.rand_bytes(self.pepper[:])
}

config_save :: proc(self: Config, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT OR REPLACE INTO config(id, version, pepper)
	VALUES(:id, :version, :pepper);
	`
	stmt: sqlite3.Statement
	stmt = db_prepare_bind_row(db, sql, self, config_to_row) or_return
	err = db_step_and_finalize_default_timeout(stmt)
	return
}

config_load :: proc(self: ^Config, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	SELECT * FROM config WHERE id = :id;
	`
	stmt: sqlite3.Statement
	stmt = db_prepare_bind_row(db, sql, self^, config_to_row) or_return // set sql params from self
	db_retrieve_one_and_finalize_default_timeout(stmt, self, config_from_row) or_return
	return
}


version_get :: proc(task: Task) {
	task_data := task_to_task_data(task)
	query := task_data.action.(Query).(Version_Get)

	config := Config{id=1}
	err := config_load(&config, tl_db_conn)
	if !is_db_error(err, task_data) {
		query.result = config.version
		task_data.result = i64(query.result)
	}
}

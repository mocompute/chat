package main

import "core:crypto"
import "../../lib/sqlite3"
@(require) import "core:fmt"

PEPPER_BYTES :: 8
CONFIG_VERSION :: i32(1)

Config :: struct {
	id: i64,
	version: i32,
	pepper: [PEPPER_BYTES]u8,
}

config_create :: proc() -> (self: Config) {
	self.id = 1
	self.version = CONFIG_VERSION
	crypto.rand_bytes(self.pepper[:])
	return
}

version_get :: proc(task: Task) {
	task_data := cast(^Task_Data) task.data
	// query := task_data.query.(Version_Get)
	defer if task_data.callback != nil do task_data.callback(task_data, task_data.callback_data)

	db := task_data.app.db

	config, err := config_db_retrieve(db)
	if err != nil {
		task_data.status = .Runtime_Error
		task_data.message = fmt.aprintf("failed to retrieve configuration: %s", err)
	} else {
		task_data.status = .Ok
		task_data.result = i64(config.version)
	}
}

config_db_create :: proc(self: ^Config, db: Db) -> (err: Db_Error) {
	_, err = config_db_retrieve(db)
	if err == nil do return

	sql: cstring: `-- sql
	INSERT OR IGNORE INTO config(id, version, pepper)
	VALUES(:id, :version, :pepper);
	`
	stmt := db_prepare(db, sql) or_return
	defer db_finalize(stmt)

	db_bind(stmt, {
		{":id", self.id},
		{":version", CONFIG_VERSION},
		{":pepper", self.pepper[:]},
	}) or_return

	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Done do err = nil

	return
}

config_db_retrieve :: proc(db: Db) -> (self: Config, err: Db_Error) {
	sql: cstring: `-- sql
	SELECT version, pepper FROM config WHERE id = 1;
	`
	row := Db_Row_Spec{{"version", i64}, {"pepper", []u8},}
	res : [2]Db_Value

	stmt := db_prepare(db, sql) or_return
	defer db_finalize(stmt)

	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Row {
		db_columns(stmt, row, res[:]) or_return

		self.version = cast(i32) res[0].(i64)
		copy(self.pepper[:], res[1].([]u8))
		err = nil
	}
	return
}

config_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	sql: cstring: `-- sql
	CREATE TABLE IF NOT EXISTS config(
	id INTEGER PRIMARY KEY,
	version INTEGER,
	pepper BLOB
	);
	`
	err = db_exec_multi_null(db, sql)
	return
}

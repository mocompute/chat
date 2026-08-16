#+feature using-stmt
package main

import "../../lib/sqlite3"

import "core:c"
import "core:mem"
@(require) import "core:fmt"

Logic_Error :: enum {
	Ok,
	Expected_Row,
	Unexpected_Row,
	Expected_Null_Return,
	Field_Name_Not_Found,
}

Runtime_Error :: enum {
	None,
	Exists,
	Not_Found,
	Bad_Argument,
}

Db_Error :: union #shared_nil {
	Logic_Error,
	Runtime_Error,
	sqlite3.Result,
	mem.Allocator_Error,
}

Db :: sqlite3.Connection
Db_Statement_Callback :: proc(sqlite3.Statement)

db_open_flags :: proc(filename: cstring, flags: c.int) -> (db: Db, err: Db_Error) {
	using sqlite3

	open_v2(filename, &db, flags, transmute(cstring)c.NULL) or_return
	sql: cstring: `-- sql
	PRAGMA foreign_keys = ON;
	PRAGMA journal_mode = WAL;
	`
	err = db_exec_multi(db, sql)
	return
}

db_open :: proc(filename: cstring) -> (db: Db, err: Db_Error) {
	using sqlite3
	return db_open_flags(filename, cast(c.int)(Open_Flags.READWRITE | Open_Flags.CREATE))
}

db_open_multi_threaded :: proc(filename: cstring) -> (db: Db, err: Db_Error) {
	using sqlite3
	db, err = db_open_flags(filename, cast(c.int)(Open_Flags.READWRITE | Open_Flags.CREATE | Open_Flags.NOMUTEX))
	if err != nil do return
	sql: cstring: `-- sql
	PRAGMA synchronous = NORMAL;
	PRAGMA busy_timeout = 5000;
	`
	err = db_exec_multi(db, sql)
	return
}

// For testing: the main difference is that :memory: databases do not support WAL mode.
db_open_memory :: proc() -> (db: Db, err: Db_Error) {
	using sqlite3
	path: cstring: ":memory:"

	open(path, &db) or_return
	sql: cstring: `-- sql
	PRAGMA foreign_keys = ON;
	`
	err = db_exec_multi(db, sql)
	return
}

db_close :: proc(db: Db) -> (err: Db_Error) {
	sql: cstring: `-- sql
	PRAGMA analysis_limit = 500;
	PRAGMA optimize;
	`
	err = db_exec_multi(db, sql)
	if err != nil {
		fmt.eprintfln("error: error before closing database: %s", err)
	}
	sqlite3.close(db) or_return
	return
}

db_config :: proc(db: Db) -> (err: Db_Error) {
	return
}

db_prepare :: proc(db: Db, sql: cstring) -> (stmt: sqlite3.Statement, err: Db_Error) {
	err = sqlite3.prepare_v2(db, sql, -1, &stmt, cast(^cstring)c.NULL)
	return
}

db_finalize :: proc(stmt: sqlite3.Statement) {
	sqlite3.finalize(stmt)
}

db_exec_null :: proc(db: Db, sql: cstring) -> (err: Db_Error) {
	using sqlite3

	stmt: Statement
	stmt, err = db_prepare(db, sql)
	if stmt == nil do return err // e.g. empty string returns ok but nil stmt
	defer finalize(stmt)

	err = step(stmt)
	if err != .Done do return .Expected_Null_Return
	return
}

db_exec_multi_null :: proc(db: Db, sql: cstring) -> (err: Db_Error) {
	using sqlite3

	tail := sql

	for (cast([^]u8) tail)[0] != 0 {
		stmt: Statement
		err = prepare_v2(db, tail, -1, &stmt, &tail)
		if stmt == nil do return err // e.g. empty string returns ok but nil stmt
		defer finalize(stmt)

		err = step(stmt)
		if err != .Done {
			fmt.eprintfln("error: expected null: '%s', got %s", sql, err)
			return .Expected_Null_Return
		}
	}
	return
}

db_exec_multi :: proc(db: Db, sql: cstring) -> (err: Db_Error) {
	using sqlite3

	tail := sql

	for (cast([^]u8) tail)[0] != 0 {
		stmt: Statement
		err = prepare_v2(db, tail, -1, &stmt, &tail)
		if stmt == nil do return err // e.g. empty string returns ok but nil stmt
		defer finalize(stmt)

		err = step(stmt)
		if err != .Done && err != .Row {
			fmt.eprintfln("error: '%s', got %s", sql, err)
			return
		}
	}
	return
}

db_exec_one_row :: proc(db: Db, sql: cstring, cb: Db_Statement_Callback) -> (err: Db_Error) {
	using sqlite3

	stmt: Statement
	stmt, err = db_prepare(db, sql)
	defer finalize(stmt)

	err = step(stmt)
	if err != .Row do return .Expected_Row

	cb(stmt)

	err = step(stmt)
	if err != .Done do return .Unexpected_Row

	return
}

db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	config_db_create_tables(db)
	server_db_create_tables(db)
	user_db_create_tables(db)
	return
}

#+feature using-stmt
package main

import sqlite3 "../../vendor/sqlite"

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
	Out_Of_Range,
	Timeout,
}

Db_Error :: union #shared_nil {
	Logic_Error,
	Runtime_Error,
	sqlite3.Result,
	mem.Allocator_Error,
}

Db :: sqlite3.Connection
Db_Statement_Callback :: proc(sqlite3.Statement)

@(require_results)
db_open_flags :: proc(filename: cstring, flags: c.int) -> (db: Db, err: Db_Error) {
	rc := sqlite3.initialize()
	if rc != .Ok {
		return nil, rc
	}

	rc = sqlite3.open_v2(filename, &db, flags, transmute(cstring)c.NULL)
	if rc != .Ok {
		return nil, rc
	}

	sql :: `-- sql
	PRAGMA foreign_keys = ON;
	PRAGMA journal_mode = WAL;`
	err = db_exec(db, sql)

	return
}

@(require_results)
db_open :: proc(filename: cstring) -> (db: Db, err: Db_Error) {
	using sqlite3
	return db_open_flags(filename, cast(c.int)(Open_Flags.READWRITE | Open_Flags.CREATE))
}

@(require_results)
db_open_multi_threaded :: proc(filename: cstring) -> (db: Db, err: Db_Error) {
	using sqlite3
	db, err = db_open_flags(filename, cast(c.int)(Open_Flags.READWRITE | Open_Flags.CREATE | Open_Flags.NOMUTEX))
	if err != nil do return
	sql :: `-- sql
	PRAGMA synchronous = NORMAL;
	PRAGMA busy_timeout = 5000;`
	err = db_exec(db, sql)
	return
}

// For testing: the main difference is that :memory: databases do not support WAL mode.
@(require_results)
db_open_memory :: proc() -> (db: Db, err: Db_Error) {
	path: cstring: ":memory:"

	rc := sqlite3.initialize()
	if rc != .Ok {
		return nil, rc
	}
	rc = sqlite3.open(path, &db)
	if rc != .Ok {
		return nil, rc
	}
	sql :: `-- sql
	PRAGMA foreign_keys = ON;`
	err = db_exec(db, sql)
	return
}

db_close :: proc(db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	PRAGMA analysis_limit = 500;
	PRAGMA optimize;`
	err = db_exec(db, sql)

	rc := sqlite3.close(db)
	if rc != .Ok {
		return rc
	}
	return
}


@(require_results)
db_prepare :: proc(db: Db, sql: cstring) -> (stmt: sqlite3.Statement, err: Db_Error) {
	err = sqlite3.prepare_v2(db, sql, -1, &stmt, cast(^cstring)c.NULL)
	return
}

db_finalize :: proc(stmt: sqlite3.Statement) {
	sqlite3.finalize(stmt)
}


@(require_results)
db_exec :: proc(db: Db, sql: cstring) -> (err: Db_Error) {
	err_msg: cstring
	err = sqlite3.exec(db, sql, nil, nil, &err_msg)
	defer sqlite3.free(cast(rawptr) err_msg)
	if err != nil {
		fmt.eprintfln("error: SQLite3: %s", err_msg)
	}
	return
}

@(require_results)
db_exec_one_row :: proc(db: Db, sql: cstring, cb: Db_Statement_Callback, loc := #caller_location) -> (err: Db_Error) {
	stmt: sqlite3.Statement
	stmt, err = db_prepare(db, sql)
	if stmt == nil || err != nil {
		fmt.eprintfln("error: expected sql: '%s'", sql)
	}
	ensure(stmt != nil, loc=loc)
	defer sqlite3.finalize(stmt)

	ensure(err == nil, loc=loc)

	err = db_step(stmt)
	if err != .Row do return .Expected_Row

	cb(stmt)

	err = db_step(stmt)
	if err != .Done do return .Unexpected_Row
	err = nil

	return
}

db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	db_exec(db, Config_Create_Table) or_return
	db_exec(db, Server_Create_Table) or_return
	db_exec(db, User_Create_Table) or_return
	db_exec(db, Channel_Create_Table) or_return
	return
}

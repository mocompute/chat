package main

import "../../lib/sqlite3"
import "core:fmt"

Server :: struct {
	uuid: Uuid,
	name: string,
}

Server_Row  :: Db_Row_Spec{{"uuid", []u8}, {"name", cstring}}
Server_Cols :: "uuid, name"
Server_Cols_N :: 2

server_from_row :: proc(stmt: sqlite3.Statement) -> (self: Server, err: Db_Error) {
	res: [Server_Cols_N]Db_Value

	db_columns(stmt, Server_Row, res[:]) or_return

	uuid := res[0].([]u8)
	copy(self.uuid[:], uuid[:])

	self.name = string(res[1].(cstring))
	return
}

is_db_error :: proc(err: Db_Error, task_data: ^Task_Data, key: string = "") -> (is_error: bool) {
	if err == .Exists {
		is_error = true
		task_data.status = .Conflict
		if key != "" {
			task_data.message = fmt.aprintf("'%s' exists", key)
		}
	} else if err == .Not_Found {
		is_error = true
		task_data.status = .Not_Found
	} else if err != nil {
		is_error = true
		task_data.status = .Database_Error
		task_data.message = fmt.aprintf("database error: %s", err)
	} else {
		task_data.status = .Ok
	}
	return
}

server_create :: proc(task: Task) {
	task_data := cast(^Task_Data) task.data
	cmd := task_data.command.(Server_Create)
	defer if task_data.callback != nil do task_data.callback(task_data, task_data.callback_data)

	server := Server{name=cmd.name, uuid=uuid_v7()}
	err := server_db_create(&server, db_conn)
	if !is_db_error(err, task_data) {
		task_data.result = new_clone(server)
	}
}

server_lookup_name :: proc(task: Task) {
	task_data := cast(^Task_Data) task.data
	q := task_data.query.(Server_Lookup_Name)
	defer if task_data.callback != nil do task_data.callback(task_data, task_data.callback_data)

	server, err := server_db_lookup_name(db_conn, q.name)
	if !is_db_error(err, task_data) {
		task_data.result = new_clone(server)
	}
}

server_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	// Although UUIDs must be unique, we assume generation will never generate a
	// duplicate, so we avoid a SQL index.
	sql: cstring: `-- sql
	CREATE TABLE IF NOT EXISTS server(
	uuid BLOB PRIMARY KEY,
	name TEXT NOT NULL UNIQUE
	) WITHOUT ROWID;
	`
	err = db_exec_null(db, sql)
	return
}

server_db_create :: proc(self: ^Server, db: Db) -> (err: Db_Error) {
	sql: cstring: `-- sql
	INSERT INTO server (uuid, name)
	VALUES (:uuid, :name);
	`
	stmt := db_prepare_bind(db, sql, {
		{":uuid", self.uuid[:]},
		{":name", self.name},
	}) or_return
	defer db_finalize(stmt)

	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Done {
		err = nil
	} else if err == sqlite3.Result.Constraint {
		err = .Exists
	}
	return
}

server_db_lookup_name :: proc(db: Db, name: string) -> (self: Server, err: Db_Error) {
	sql: cstring: `SELECT ` + Server_Cols + ` FROM server WHERE name = :name`
	stmt := db_prepare_bind(db, sql, {
		{":name", name},
	}) or_return
	defer db_finalize(stmt)
	self = db_retrieve_one(Server, stmt, server_from_row) or_return
	return
}

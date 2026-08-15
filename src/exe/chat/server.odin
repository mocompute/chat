package main

import "../../lib/sqlite3"
import "core:fmt"

Server :: struct {
	id: i64,
	name: string,
}

server_create :: proc(task: Task) {
	task_data := cast(^Task_Data) task.data
	cmd := task_data.command.(Server_Create)
	defer if task_data.callback != nil do task_data.callback(task_data, task_data.callback_data)

	db := task_data.app.db
	server := Server{name=cmd.name}
	err := server_db_create(&server, db)
	if err == .Exists {
		task_data.status = .Conflict
		task_data.message = fmt.aprintf("server '%s' exists", server.name)
	} else if err != nil {
		task_data.status = .Database_Error
		task_data.message = fmt.aprintf("database error: %s", err)
		return
	} else {
		task_data.status = .Ok
		task_data.result = server.id
	}
}

server_get :: proc(task: Task) {
	task_data := cast(^Task_Data) task.data
	q := task_data.query.(Server_Get)
	defer if task_data.callback != nil do task_data.callback(task_data, task_data.callback_data)

	db := task_data.app.db
	server, err := server_db_retrieve(db, q.name)
	if err == .Not_Found {
		task_data.status = .Not_Found
	} else if err != nil {
		task_data.status = .Database_Error
		task_data.message = fmt.aprintf("database error: %s", err)
	} else {
		task_data.status = .Ok
		task_data.result = server.id
	}
}

server_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	sql: cstring: `-- sql
	CREATE TABLE IF NOT EXISTS server(
	id INTEGER PRIMARY KEY,
	name TEXT NOT NULL UNIQUE
	);
	`
	err = db_exec_null(db, sql)
	return
}

server_db_create :: proc(self: ^Server, db: Db) -> (err: Db_Error) {
	sql: cstring: `-- sql
	INSERT INTO server (name)
	VALUES (:name);
	`
	stmt := db_prepare_bind(db, sql, {
		{":name", self.name},
	}) or_return
	defer db_finalize(stmt)

	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Done {
		err = nil
		self.id = sqlite3.last_insert_rowid(db)
	} else if err == sqlite3.Result.Constraint {
		err = .Exists
	}
	return
}

server_db_retrieve :: proc(db: Db, name: string) -> (self: Server, err: Db_Error) {
	sql: cstring: `-- sql
	SELECT id FROM server WHERE name = :name
	`
	row := Db_Row_Spec{{"id", i64}}
	res: [1]Db_Value

	stmt := db_prepare_bind(db, sql, {
		{":name", name},
	}) or_return
	defer db_finalize(stmt)

	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Row {
		db_columns(stmt, row, res[:]) or_return
		self.id = res[0].(i64)
		self.name = name
		err = nil
	} else if err == sqlite3.Result.Done {
		err = .Not_Found
	}
	return
}

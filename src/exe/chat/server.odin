package main

import "../../../../base/src/lib/sqlite3"
import "core:fmt"
import "core:strings"

Server :: struct {
	uuid: Uuid,
	name: string,
}

Server_Create_Table :: `-- sql
	CREATE TABLE IF NOT EXISTS server(
	uuid BLOB PRIMARY KEY,
	name TEXT NOT NULL UNIQUE
	) WITHOUT ROWID;
	INSERT INTO server (uuid, name) VALUES (X'00000000000000000000000000000000', 'null');`


server_from_row :: proc(obj: any, stmt: sqlite3.Statement) -> (err: Db_Error) {
	switch self in obj {
	case ^Server:
		err = db_scan_columns(stmt, {
			{"uuid", self.uuid[:]},
			{"name", &self.name},
		})
	case:
		panic(fmt.tprintf("server_from_row: bad type %v", obj))
	}
	return
}

server_to_row :: proc(obj: any, stmt: sqlite3.Statement) -> (err: Db_Error) {
	switch self in obj {
	case Server:
		uuid := self.uuid
		err = db_bind(stmt, {
			{":uuid", uuid[:]},
			{":name", self.name},
		})
	case:
		panic(fmt.tprintf("server_to_row: bad type %v", obj))
	}
	return
}

server_init :: proc(self: ^Server) {
	self.name = strings.clone(self.name)
}

server_deinit :: proc(self: ^Server) {
	delete(self.name)
}
server_deinit_rawptr :: proc(self: rawptr) {
	server_deinit(cast(^Server)self)
}

server_save :: proc(self: Server, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT OR REPLACE INTO server(uuid, name)
	VALUES(:uuid, :name);`
	return server_save_(self, db, sql)
}

server_insert_unique :: proc(self: Server, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT INTO server(uuid, name)
	VALUES(:uuid, :name);`
	return server_save_(self, db, sql)
}

server_save_ :: proc(self: Server, db: Db, sql: cstring) -> (err: Db_Error) {
	stmt: sqlite3.Statement
	stmt = db_prepare_bind_row(db, sql, self, server_to_row) or_return
	db_step_and_finalize_default_timeout(stmt) or_return
	return
}

server_load :: proc(self: ^Server, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	SELECT * FROM server WHERE uuid = :uuid;`
	return server_load_(self, db, sql)
}

server_load_name :: proc(self: ^Server, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	SELECT * FROM server WHERE name = :name;`
	return server_load_(self, db, sql)
}

server_load_ :: proc(self: ^Server, db: Db, sql: cstring) -> (err: Db_Error) {
	stmt: sqlite3.Statement

	// set sql params required by sql from self
	stmt = db_prepare_bind_row(db, sql, self^, server_to_row) or_return
	db_retrieve_one_and_finalize_default_timeout(stmt, self, server_from_row) or_return
	return
}

server_create :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.action.(Command).(Server_Create)

	server := Server{name=cmd.name, uuid=uuid_v7()}
	err := server_insert_unique(server, tl_db_conn)

	if !is_db_error(err, task_data, cmd.name) {
		server_copy := new_clone(server)
		server_init(server_copy)
		cmd.result = server_copy

		task_data.result = cmd.result
		task_data.result_deinit = server_deinit_rawptr
	}
}

server_lookup_uuid :: proc(task: Task) {
	task_data := task_to_task_data(task)
	q := task_data.action.(Query).(Server_Lookup_Uuid)

	server: Server
	server.uuid = q.uuid
	err := server_load(&server, tl_db_conn)

	if !is_db_error(err, task_data) {
		q.result = new_clone(server)
		task_data.result = q.result
		task_data.result_deinit = server_deinit_rawptr
	}
}

server_lookup_name :: proc(task: Task) {
	task_data := task_to_task_data(task)
	q := task_data.action.(Query).(Server_Lookup_Name)

	server: Server
	server.name = q.name
	err := server_load_name(&server, tl_db_conn)

	if !is_db_error(err, task_data) {
		q.result = new_clone(server)
		task_data.result = q.result
		task_data.result_deinit = server_deinit_rawptr
	}
}

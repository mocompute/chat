package main

import sqlite3 "../../vendor/sqlite"

import "core:strings"

Channel :: struct {
	uuid: Uuid,
	server: Uuid,
	name: string,
}
Channel_Create_Table :: `-- sql
	CREATE TABLE IF NOT EXISTS channel(
	uuid            BLOB PRIMARY KEY,
	server          BLOB NOT NULL REFERENCES server(uuid) ON DELETE CASCADE,
	name     TEXT NOT NULL UNIQUE
	) WITHOUT ROWID;
	CREATE UNIQUE INDEX IF NOT EXISTS channel_server_name ON channel(
	server, name
	);`

channel_from_row :: proc(self: ^Channel, stmt: sqlite3.Statement) -> (err: Db_Error) {
	err = db_scan_columns(stmt, {
		{"uuid", self.uuid[:]},
		{"server", self.server[:]},
		{"name", &self.name},
	})
	return
}

channel_to_row :: proc(self: Channel, stmt: sqlite3.Statement) -> (err: Db_Error) {
	uuid := self.uuid
	server := self.server
	err = db_bind(stmt, {
		{":uuid", uuid[:]},
		{":server", server[:]},
		{":name", self.name},
	})
	return
}

channel_save :: proc(self: Channel, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT OR REPLACE INTO channel(uuid, server, name)
	VALUES(:uuid, :server, :name);
	`
	stmt: sqlite3.Statement
	stmt = db_prepare_bind_row(db, sql, self, channel_to_row) or_return
	err = db_step_and_finalize_default_timeout(stmt)
	return
}

channel_load_uuid :: proc(self: ^Channel, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	SELECT * FROM channel WHERE uuid = :uuid;`
	return channel_load_(self, db, sql)
}

channel_load_ :: proc(self: ^Channel, db: Db, sql: cstring) -> (err: Db_Error) {
	stmt: sqlite3.Statement

	// set sql params required by sql from self
	stmt = db_prepare_bind_row(db, sql, self^, channel_to_row) or_return
	db_retrieve_one_and_finalize_default_timeout(stmt, self, channel_from_row) or_return
	return
}

// Allocates to copy name string
channel_init :: proc(self: ^Channel) {
	self.name = strings.clone(self.name)
}

channel_deinit :: proc(self: ^Channel) {
	delete(self.name)
}
channel_deinit_rawptr :: proc(self: rawptr) {
	channel_deinit(cast(^Channel)self)
}

channel_create :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.action.(Command).(Channel_Create)

	session, ok := session_manager_lookup(cmd.session_manager, cmd.session)
	if !ok {
		task_data.status = .Not_Authorized
		return
	}

	if !user_role_can_create_channel(session.user_role) {
		task_data.status = .Conflict
		return
	}

	channel := Channel{uuid=uuid_v7(), server=cmd.server, name=cmd.name}
	err := channel_save(channel, tl_db_conn)

	if !is_db_error(err, task_data) {
		channel_copy := new_clone(channel)
		channel_init(channel_copy)
		cmd.result = channel_copy

		task_data.result = cmd.result
		task_data.result_deinit = channel_deinit_rawptr
	}
}

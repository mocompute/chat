package main

import "../../../../base/src/lib/sqlite3"

import "core:strings"

Channel :: struct {
	uuid: Uuid,
	server: Uuid,
	name: string,
}

Channel_Row :: Db_Row_Spec{{"uuid", []u8}, {"server", []u8}, {"name", cstring}}
Channel_Cols :: "uuid, server, name"
Channel_Cols_N :: 3
Channel_Create_Table :: `-- sql
	CREATE TABLE IF NOT EXISTS channel(
	uuid            BLOB PRIMARY KEY,
	server          BLOB NOT NULL REFERENCES server(uuid) ON DELETE CASCADE,
	name     TEXT NOT NULL UNIQUE
	) WITHOUT ROWID;
	CREATE UNIQUE INDEX IF NOT EXISTS channel_server_name ON channel(
	server, name
	);`

channel_from_row :: proc(stmt: sqlite3.Statement, allocator := context.allocator) -> (self: Channel, err: Db_Error) {
	res: [Channel_Cols_N]Db_Value
	db_get_columns(stmt, Channel_Row, res[:]) or_return

	bs: []u8
	bs = res[0].([]u8)
	copy_exact(self.uuid[:], bs)

	bs = res[1].([]u8)
	copy_exact(self.server[:], bs)

	self.name = strings.clone_from_cstring(res[2].(cstring), allocator)
	return
}

// Allocates to copy name string
channel_init :: proc(self: ^Channel, uuid, server: Uuid, name: string, allocator := context.allocator) {
	self.uuid = uuid
	self.server = server
	self.name = strings.clone(name, allocator)
}

channel_deinit :: proc(self: ^Channel, allocator := context.allocator) {
	delete(self.name, allocator)
}
channel_deinit_rawptr :: proc(self: rawptr, allocator := context.allocator) {
	channel_deinit(cast(^Channel)self, allocator)
}

channel_create :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.command.(Channel_Create)

	session, ok := session_manager_lookup(cmd.session_manager, cmd.session)
	if !ok {
		task_data.status = .Not_Authorized
		return
	}

	if !user_role_can_create_channel(session.user_role) {
		task_data.status = .Conflict
		return
	}

	channel: Channel
	channel_init(&channel, uuid=uuid_v7(), server=cmd.server, name=cmd.name)
	err := channel_db_create(&channel, tl_db_conn)

	if !is_db_error(err, task_data) {
		cmd.result = new_clone(channel)

		task_data.result = cmd.result
		task_data.result_deinit = channel_deinit_rawptr
	}
}

channel_db_create_tables :: proc(db: Db) -> (err: Db_Error) {
	err = db_exec(db, Channel_Create_Table)
	assert(err == nil)
	return
}

channel_db_create :: proc(self: ^Channel, db: Db) -> (err: Db_Error) {
	sql :: `-- sql
	INSERT INTO channel (uuid, server, name)
	VALUES(:uuid, :server, :name);
	`
	stmt := db_prepare_bind(db, sql, {
		{":uuid", self.uuid[:]},
		{":server", self.server[:]},
		{":name", self.name},
	}) or_return
	defer db_finalize(stmt)
	return db_insert_unique(stmt)
}

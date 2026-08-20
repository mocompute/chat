package main

import "core:fmt"

/*

Commands and Queries

Commands are processed by a single worker thread to write to the database. Queries are
processed by a worker pool. All Commands and Queries return a result code in
Task_Data.status which should be checked by the client before attempting to use the
optional result value.

Commands and Queries are collectively called 'Actions'. Actions may be cast or called.
cast returns immediately. The Action will invoke a callback, if any was configured.
call will queue the Action to the worker pool (or single thread for Command) and will
busy-wait until the action is complete, then return to the caller.

The APIs for Actions are defined as structs. Fields listed before the optional `result`
field must be supplied when invoking the Action. The `result` field will hold the
result. If there is no result, no `result` field appears in the struct. Fields appearing
after `result` are context required by the Action and are inserted by the action
constructor functions.

Lifetimes: task results which are placed in Task_Data.result.(rawptr) will be freed by
the command processor. An optional deinit proc can be placed in Task_Data.result_deinit
to release internal buffers.

*/

Channel_Create :: struct {
	server: Uuid,
	name: string,
	result: ^Channel,
}

Database_Create :: struct {
	path: string,
}



Server_Create :: struct {
	name: string,
	result: ^Server,
}
Server_Lookup_Uuid :: struct {
	uuid: Uuid,
	result: ^Server,
}
Server_Lookup_Name :: struct {
	name: string,
	result: ^Server,
}



Session_Create :: struct {
	server: Uuid,
	username: string,
	password: string,
	result: ^Session,

	pepper: [PEPPER_BYTES]u8,
	session_manager: ^Session_Manager,
}
Session_Destroy :: struct {
	uuid: Uuid,
	session_manager: ^Session_Manager,
}
Session_Refresh :: struct {
	uuid: Uuid,
	result: ^Session,

	session_manager: ^Session_Manager,
}



User_Create :: struct {
	server: Uuid,
	username: string,
	password: string,
	pepper: [PEPPER_BYTES]u8,
	result: ^User,
}
User_Lookup_Username :: struct {
	server: Uuid,
	username: string,
	result: ^User,
}
User_Lookup_Uuid :: struct {
	server: Uuid,
	user: Uuid,
	result: ^User,
}



Version_Get :: struct {
	result: i32,
}



Command :: union {
	Channel_Create,
	Database_Create,
	Server_Create,
	Session_Create,
	Session_Refresh,
	User_Create,
}
Query :: union {
	Server_Lookup_Name,
	Server_Lookup_Uuid,
	User_Lookup_Username,
	User_Lookup_Uuid,
	Version_Get,
}
Action_Error :: enum {
	None,
	Not_Found,
	Empty,
	Bad_Arity,
	Bad_Argument,
}

API_Item :: struct {
	command_word: string,
	arity: int,
	constructor: proc([]string, ^App) -> (Command, Query, Action_Error),
}

DB_CREATE_COMMAND :: "db-create"
API :: [?]API_Item{
	{DB_CREATE_COMMAND, 1, mk_database_create},
	{"channel-create", 2, mk_channel_create},
	{"server-create", 1, mk_server_create},
	{"server-lookup-name", 1, mk_server_lookup_name},
	{"server-lookup-uuid", 1, mk_server_lookup_uuid},
	{"session-create", 3, mk_session_create},
	{"session-refresh", 1, mk_session_refresh},
	{"user-create", 3, mk_user_create},
	{"user-lookup-username", 2, mk_user_lookup_username},
	{"user-lookup-uuid", 2, mk_user_lookup_uuid},
	{"version", 0, mk_version_get},
}

api_index: map[string]API_Item
api_index_init :: proc() {
	if api_index == nil {
		api_index = make(map[string]API_Item)
		reserve(&api_index, len(API))
		for item in API {
			api_index[item.command_word] = item
		}
	}
}
api_index_deinit :: proc() {
	delete(api_index)
	api_index = nil
}
mk_version_get :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	query = Version_Get{}
	return
}
mk_channel_create :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	server := _get_uuid(words[1]) or_return
	name := words[2]
	command = Channel_Create{server=server, name=name}
	return
}
mk_database_create :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	command = Database_Create{path=words[1]}
	return
}
mk_server_create :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	command = Server_Create{name=words[1]}
	return
}
mk_server_lookup_name :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	query = Server_Lookup_Name{name=words[1]}
	return
}
mk_server_lookup_uuid :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	uuid := _get_uuid(words[1]) or_return
	query = Server_Lookup_Uuid{uuid=uuid}
	return
}
mk_session_create :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	server := words[1]
	username := words[2]
	password := words[3]

	sc := Session_Create{username=username, password=password}
	sc.pepper = app.config.pepper
	sc.session_manager = &app.session_manager
	sc.server = _get_uuid(server) or_return

	command = sc
	return
}
mk_session_refresh :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	session := words[1]

	sr: Session_Refresh
	sr.session_manager = &app.session_manager
	sr.uuid = _get_uuid(session) or_return

	command = sr
	return
}
mk_user_create :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	server := words[1]
	username := words[2]
	password := words[3]

	uc := User_Create{username=username, password=password}
	uc.server = _get_uuid(server) or_return
	uc.pepper = app.config.pepper

	command = uc
	return
}
mk_user_lookup_username :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	server := words[1]
	username := words[2]
	ulu := User_Lookup_Username{username=username}
	ulu.server = _get_uuid(server) or_return
	query = ulu
	return
}
mk_user_lookup_uuid :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	server := words[1]
	user := words[2]

	ulu: User_Lookup_Uuid
	ulu.server = _get_uuid(server) or_return
	ulu.user = _get_uuid(user) or_return
	query = ulu
	return
}

_get_uuid :: proc(s: string) -> (uuid: Uuid, err: Action_Error) {
	ok: bool
	if uuid, ok = uuid_from_hex(s); ok {
		return uuid, nil
	} else {
		return {}, .Bad_Argument
	}
}

words_to_action :: proc(words: []string, app: ^App) -> (command: Command, query: Query, err: Action_Error) {
	if len(words) == 0 do return nil, nil, .Empty
	assert(api_index != nil)

	api_item, ok := api_index[words[0]]
	if !ok {
		fmt.eprintfln("error: words_to_action: not found: %s", words[0])
		fmt.eprintfln("error: words_to_action: len = %d", len(api_index))
	}
	if !ok do return nil, nil, .Not_Found

	if api_item.arity != len(words) - 1 do return nil, nil, .Bad_Arity

	return api_item.constructor(words, app)
}

action_error_to_string :: proc(error: Action_Error) -> (msg: string) {
	switch error {
	case .None:
		msg = ""
	case .Not_Found:
		msg = "command unknown"
	case .Empty:
		msg = "command missing"
	case .Bad_Arity:
		msg = "wrong number of arguments to command"
	case .Bad_Argument:
		msg = "bad argument"
	}
	return
}

action_to_procedure :: proc(command: Command, query: Query) -> (p: Task_Proc) {
	if command != nil {
		switch _ in command {
		case Channel_Create:  p = channel_create
		case Database_Create: p = nil
		case Server_Create:   p = server_create
		case Session_Create:  p = session_create
		case Session_Refresh: p = session_refresh
		case User_Create:     p = user_create
		}

	} else if query != nil {
		switch _ in query {
		case Server_Lookup_Name:    p = server_lookup_name
		case Server_Lookup_Uuid:    p = server_lookup_uuid
		case User_Lookup_Username:  p = user_lookup_username
		case User_Lookup_Uuid:      p = user_lookup_uuid
		case Version_Get:           p = version_get
		}

	}
	return
}

// Callback must free task_data AND task_data.message
action_cast :: proc(task_manager: ^Task_Manager, command: Command, query: Query, app: ^App, callback: Task_Callback ) {
	task_data, procedure := _create_task(command, query)
	if !handled_immediate_task(task_data, procedure, command, query) {
		task_manager_cast(task_manager, procedure, task_data, app, callback)
	}
}

// Caller must free task_data AND task_data.message
action_call :: proc(task_manager: ^Task_Manager, command: Command, query: Query, app: ^App) -> (task_data: ^Task_Data) {
	procedure: Task_Proc
	task_data, procedure = _create_task(command, query)
	if !handled_immediate_task(task_data, procedure, command, query) {
		task_manager_call(task_manager, procedure, task_data, app)
	}
	return
}

_create_task :: proc(command: Command, query: Query) -> (task_data: ^Task_Data, procedure: Task_Proc) {
	ensure( (command != nil && query == nil) || (command == nil && query != nil) )
	task_data = new(Task_Data)

	task_data.command = command
	task_data.query = query

	procedure = action_to_procedure(command, query)
	return
}

handled_immediate_task :: proc(task_data: ^Task_Data, procedure: Task_Proc, command: Command, query: Query) -> (handled: bool) {
	if procedure == nil {
		if command != nil {
			if dc, ok := command.(Database_Create); ok {
				// Database_Create cannot use worker pool, since pool
				// requires existing open database connections.
				err := create_db(dc.path)
				if err == nil {
					task_data.status = .Ok
				} else {
					task_data.status = .Runtime_Error
					task_data.message = fmt.aprintf("%v", err)
				}
				return true
			}
		}

		ensure(false, "nil procedure and no valid command")
	}

	return
}

#+feature dynamic-literals
package main

import "core:fmt"
import "core:strconv"

/*

Actions: Commands and Queries

Commands are processed by a single worker thread to write to the database. Queries are
processed by a worker pool. All Commands and Queries return a result code in
Task_Data.status which should be checked by the client before attempting to use the
optional result value.

Commands and Queries are collectively called 'Actions'. Actions may be cast or called.
cast returns immediately. The Action will invoke a callback, if any was provided.
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

Authentication

Many Actions require correct privileges to be executed. We use a Session system: clients
provide authentication and are issued an expiring token (a Uuid). The token caches the
user's privileges. Actions which require privileges require a session Uuid.

*/

Action :: union {
	Command,
	Query,
}

Command :: union {
	Channel_Create,
	Database_Create,
	Server_Create,
	Session_Create,
	Session_Refresh,
	User_Create,
	User_Role_Assign,
}

Query :: union {
	Server_Lookup_Name,
	Server_Lookup_Uuid,
	User_Lookup_Username,
	User_Lookup_Uuid,
	Version_Get,
}

Channel_Create :: struct {
	session: Uuid,
	server: Uuid,
	name: string,
	result: ^Channel,

	session_manager: ^Session_Manager,
}

Database_Create :: struct {
	path: string,
}



Server_Create :: struct {
	session: Uuid,
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
	user: Uuid,
	result: ^User,
}
User_Role_Assign :: struct {
	user: Uuid,
	role: User_Role,
	result: ^User,
}



Version_Get :: struct {
	result: i32,
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

Action_Constructor :: struct {
	arity: int,
	constructor: proc([]string, ^App) -> (Action, Action_Error),
}

API := map[string]Action_Constructor{
	"database-create"      = {1, mk_database_create},
	"channel-create"       = {3, mk_channel_create},
	"server-create"        = {2, mk_server_create},
	"server-lookup-name"   = {1, mk_server_lookup_name},
	"server-lookup-uuid"   = {1, mk_server_lookup_uuid},
	"session-create"       = {3, mk_session_create},
	"session-refresh"      = {1, mk_session_refresh},
	"user-create"          = {3, mk_user_create},
	"user-lookup-username" = {2, mk_user_lookup_username},
	"user-lookup-uuid"     = {1, mk_user_lookup_uuid},
	"user-role-assign"     = {2, mk_user_role_assign},
	"version"              = {0, mk_version_get},
}

mk_version_get :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	action = Query(Version_Get{})
	return
}
mk_channel_create :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	server := _get_uuid(words[1]) or_return
	session := _get_uuid(words[2]) or_return
	name := words[3]

	action = Command(Channel_Create{server=server, session=session, name=name, session_manager=&app.session_manager})
	return
}
mk_database_create :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	action = Command(Database_Create{path=words[1]})
	return
}
mk_server_create :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	sc: Server_Create
	sc.session = _get_uuid(words[1]) or_return
	sc.name = words[2]
	action = Command(sc)
	return
}
mk_server_lookup_name :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	action = Query(Server_Lookup_Name{name=words[1]})
	return
}
mk_server_lookup_uuid :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	uuid := _get_uuid(words[1]) or_return
	action = Query(Server_Lookup_Uuid{uuid=uuid})
	return
}
mk_session_create :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	server := words[1]
	username := words[2]
	password := words[3]

	sc := Session_Create{username=username, password=password}
	sc.pepper = app.config.pepper
	sc.session_manager = &app.session_manager
	sc.server = _get_uuid(server) or_return

	action = Command(sc)
	return
}
mk_session_refresh :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	session := words[1]

	sr: Session_Refresh
	sr.session_manager = &app.session_manager
	sr.uuid = _get_uuid(session) or_return

	action = Command(sr)
	return
}
mk_user_create :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	server := words[1]
	username := words[2]
	password := words[3]

	uc := User_Create{username=username, password=password}
	uc.server = _get_uuid(server) or_return
	uc.pepper = app.config.pepper

	action = Command(uc)
	return
}
mk_user_lookup_username :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	server := words[1]
	username := words[2]
	ulu := User_Lookup_Username{username=username}
	ulu.server = _get_uuid(server) or_return
	action = Query(ulu)
	return
}
mk_user_lookup_uuid :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	user := words[1]

	ulu: User_Lookup_Uuid
	ulu.user = _get_uuid(user) or_return
	action = Query(ulu)
	return
}
mk_user_role_assign :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	user := words[1]
	role, ok := user_role_from_string(words[2])
	if !ok {
		err = .Bad_Argument
		return
	}

	cmd: User_Role_Assign
	cmd.user = _get_uuid(user) or_return
	cmd.role = User_Role(role)
	action = Command(cmd)
	return
}

_get_uuid :: proc(s: string) -> (uuid: Uuid, err: Action_Error) {
	if s == "" {
		// null uuid
		return {}, nil
	}

	ok: bool
	if uuid, ok = uuid_from_hex(s); ok {
		return uuid, nil
	} else {
		return {}, .Bad_Argument
	}
}

_get_integer :: proc(s: string) -> (i64, Action_Error) {
	integer, ok := strconv.parse_i64(s)
	if !ok {
		return 0, .Bad_Argument
	}
	return integer, nil
}

words_to_action :: proc(words: []string, app: ^App) -> (action: Action, err: Action_Error) {
	if len(words) == 0 do return nil, .Empty

	api_item, ok := API[words[0]]
	if !ok {
		fmt.eprintfln("error: words_to_action: not found: %s", words[0])
	}
	if !ok do return nil, .Not_Found

	if api_item.arity != len(words) - 1 do return nil, .Bad_Arity

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

action_to_procedure :: proc(action: Action) -> (p: Task_Proc) {
	switch v in action {
	case Command:
		switch _ in v {
		case Channel_Create:    p = channel_create
		case Database_Create:   p = nil
		case Server_Create:     p = server_create
		case Session_Create:    p = session_create
		case Session_Refresh:   p = session_refresh
		case User_Create:       p = user_create
		case User_Role_Assign:  p = user_role_assign
		}
	case Query:
		switch _ in v {
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
action_cast :: proc(task_manager: ^Task_Manager, action: Action, app: ^App, callback: Task_Callback, callback_data: rawptr) -> (id: Uuid) {
	task_data, procedure := _create_task(action)
	if !handled_immediate_task(task_data, procedure, action) {
		id = task_manager_cast(task_manager, procedure, task_data, app, callback, callback_data)
	}
	return
}

// Caller must free task_data AND task_data.message
action_call :: proc(task_manager: ^Task_Manager, action: Action, app: ^App) -> (task_data: ^Task_Data) {
	procedure: Task_Proc
	task_data, procedure = _create_task(action)
	if !handled_immediate_task(task_data, procedure, action) {
		task_manager_call(task_manager, procedure, task_data, app)
	}
	return
}

_create_task :: proc(action: Action) -> (task_data: ^Task_Data, procedure: Task_Proc) {
	task_data = new(Task_Data)

	task_data.action = action

	procedure = action_to_procedure(action)
	return
}

handled_immediate_task :: proc(task_data: ^Task_Data, procedure: Task_Proc, action: Action) -> (handled: bool) {
	if procedure == nil {
		switch command in action {
		case Command:
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
		case Query:
		}

		ensure(false, "nil procedure and no valid command")
	}

	return
}

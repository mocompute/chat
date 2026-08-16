package main

import "core:fmt"

Version_Get :: struct {}

Database_Create :: struct {
	path: string,
}

Server_Create :: struct {
	name: string,
}

Server_Lookup_Uuid :: struct {
	uuid: Uuid,
}
Server_Lookup_Name :: struct {
	name: string,
}

Command :: union {
	Database_Create,
	Server_Create,
}

Query :: union {
	Server_Lookup_Name,
	Server_Lookup_Uuid,
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
	constructor: proc([]string) -> (Command, Query, Action_Error),
}

API :: [?]API_Item{
	{"db-create", 1, mk_database_create},
	{"server-create", 1, mk_server_create},
	{"server-lookup-name", 1, mk_server_lookup_name},
	{"server-lookup-uuid", 1, mk_server_lookup_uuid},
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
mk_version_get :: proc(words: []string)  -> (command: Command, query: Query, err: Action_Error) {
	query = Version_Get{}
	return
}
mk_database_create :: proc(words: []string)  -> (command: Command, query: Query, err: Action_Error) {
	command = Database_Create{path=words[1]}
	return
}
mk_server_create :: proc(words: []string)  -> (command: Command, query: Query, err: Action_Error) {
	command = Server_Create{name=words[1]}
	return
}
mk_server_lookup_name :: proc(words: []string)  -> (command: Command, query: Query, err: Action_Error) {
	query = Server_Lookup_Name{name=words[1]}
	return
}
mk_server_lookup_uuid :: proc(words: []string)  -> (command: Command, query: Query, err: Action_Error) {
	if uuid, ok := uuid_from_hex(words[1]); ok {
		query = Server_Lookup_Uuid{uuid=uuid}
	} else {
		err = .Bad_Argument
	}
	return
}
words_to_action :: proc(words: []string) -> (command: Command, query: Query, err: Action_Error) {
	if len(words) == 0 do return nil, nil, .Empty
	assert(api_index != nil)

	api_item, ok := api_index[words[0]]
	if !ok {
		fmt.eprintfln("error: words_to_action: not found: %s", words[0])
		fmt.eprintfln("error: words_to_action: len = %d", len(api_index))
	}
	if !ok do return nil, nil, .Not_Found

	if api_item.arity != len(words) - 1 do return nil, nil, .Bad_Arity

	return api_item.constructor(words)
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
		case Database_Create: p = nil
		case Server_Create:   p = server_create
		}

	} else if query != nil {
		switch _ in query {
		case Server_Lookup_Name:  p = server_lookup_name
		case Server_Lookup_Uuid:  p = server_lookup_uuid
		case Version_Get:         p = version_get
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

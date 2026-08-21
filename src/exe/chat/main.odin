package main

import "core:flags"
@(require) import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"

DEFAULT_DB_PATH :: "chat.db"
MAX_SESSIONS :: 1_000_000

Options :: struct {
	db: string `usage:"Path to db file (default: ./chat.db)"`,
	verbose: bool `usage:"Enable verbose output"`,
	v: bool `usage:"Enable verbose output"`,
	overflow: [dynamic]string `usage:"Command and arguments"`,
}

App :: struct {
	command_pool: Task_Manager,
	query_pool: Task_Manager,
	session_manager: Session_Manager,

	config: Config,

	task_thread_init: Task_Thread_Init,
	tmp_dir: string,	// only used by tests
}

app_init :: proc(^App) {
	api_index_init()
}
app_deinit :: proc(^App) {
	api_index_deinit()
}

app_open_db :: proc(self: ^App, db_path: string) {
	db_path_c := strings.clone_to_cstring(db_path)
	self.task_thread_init = {db_path=db_path_c}

	{
		conn, err := db_open_multi_threaded(db_path_c)
		defer db_close(conn)

		self.config, err = config_db_retrieve(conn)
		if err != nil {
			panic("fatal: unable to read configuration. Does the database exist?")
		}
	}

	session_manager_init(&self.session_manager, MAX_SESSIONS, context.allocator)

	task_manager_init(&self.command_pool, 1, &self.task_thread_init)
	task_manager_start(&self.command_pool)

	task_manager_init(&self.query_pool, 4, &self.task_thread_init) // FIXME hardcoded
	task_manager_start(&self.query_pool)
}

app_close_db :: proc(self: ^App) {
	task_manager_drain(&self.command_pool)
	task_manager_drain(&self.query_pool)

	task_manager_deinit(&self.command_pool)
	task_manager_deinit(&self.query_pool)

	session_manager_deinit(&self.session_manager)

	delete(self.task_thread_init.db_path)
}

create_db :: proc(path: string) -> (err: Db_Error) {
	if os.exists(path) {
		err = Runtime_Error.Exists
		return
	}
	path_c := strings.clone_to_cstring(path, allocator = context.temp_allocator)
	db := db_open(path_c) or_return
	defer db_close(db)

	db_config(db) or_return
	db_create_tables(db) or_return
	config := config_create()
	config_db_create(&config, db) or_return
	return
}

fatal :: proc(message: string, exit := true) {
	fmt.eprintln(message)
	if exit {
		os.exit(1)
	}
}

// Caller must task_data_destroy the return value.
@(require_results)
_dispatch :: proc(self: ^App, words: []string, exit_on_error: bool) -> (td: ^Task_Data) {
	command, query, err := words_to_action(words, self)
	if err == nil {
		// TODO: everything is serialized at the moment, which makes sense for
		// the CLI but not the server.
		td = action_call(&self.command_pool, command, query, self)
	} else {
		fatal(fmt.tprintfln("error: %s: '%s'", action_error_to_string(err), words[0]), exit_on_error)
		return
	}

	if td.status != .Ok {
		if td.command != nil {
			fmt.eprintfln("error: %v failed: %s", reflect.union_variant_typeid(td.command), td.message)
		} else if td.query != nil {
			fmt.eprintfln("error: %v failed: %s", reflect.union_variant_typeid(td.query), td.message)
		}
		if exit_on_error {
			os.exit(1)
		} else {
			return
		}
	}

	return
}


// Caller must task_data_destroy the return value.
@(require_results)
dispatch :: proc(self: ^App, words: []string) -> ^Task_Data {
	return _dispatch(self, words, exit_on_error=false)
}

main_dispatch :: proc(self: ^App, words: []string) {
	assert(len(words) > 0)
	td := _dispatch(self, words, exit_on_error=true)
	task_data_destroy(td)
}



main :: proc () {
	app: App
	app_init(&app)
	defer app_deinit(&app)

	opts: Options
	flags.parse_or_exit(&opts, os.args)
	if opts.v do opts.verbose = true
	if opts.db == "" do opts.db = DEFAULT_DB_PATH


	if len(opts.overflow) == 0 {
		stderr := os.to_stream(os.stderr)
		flags.write_usage(stderr, Options, os.args[0])
		os.exit(1)
	}

	if opts.overflow[0] != DB_CREATE_COMMAND {
		app_open_db(&app, opts.db)
		defer app_close_db(&app)
		main_dispatch(&app, opts.overflow[:])
	} else {
		main_dispatch(&app, opts.overflow[:])
	}
}

package main

import "core:flags"
@(require) import "core:fmt"
import "core:os"
import "core:reflect"

DEFAULT_DB_PATH :: "chat.db"

Options :: struct {
	db: string `usage:"Path to db file (default: ./chat.db)"`,
	verbose: bool `usage:"Enable verbose output"`,
	v: bool `usage:"Enable verbose output"`,
	overflow: [dynamic]string `usage:"Command and arguments"`,
}

App :: struct {
	db: Db,

	command_pool: Task_Manager,
	query_pool: Task_Manager,
}

app_init :: proc(self: ^App) {
	task_manager_init(&self.command_pool, 1)
	task_manager_start(&self.command_pool)

	task_manager_init(&self.query_pool, 4) // FIXME hardcoded
	task_manager_start(&self.query_pool)
}

app_deinit :: proc(self: ^App) {
	app_join(self)
	task_manager_deinit(&self.query_pool)
	task_manager_deinit(&self.command_pool)

	if self.db != nil {
		db_close(self.db)
		self.db = nil
	}
}

app_join :: proc(self: ^App) {
	task_manager_join(&self.query_pool)
	task_manager_join(&self.command_pool)
}

app_open_db :: proc(self: ^App, path: string) -> (err: Db_Error) {
	self.db, err = _open_db(path)
	return
}

// Mostly intended for tests.
app_adopt_db :: proc(self: ^App, db: Db) {
	ensure(self.db == nil)
	self.db = db
}

// Caller must retrieve Db handle from task_data.result and close it.
create_db :: proc(task: Task) {
	task_data := cast(^Task_Data) task.data
	cmd := task_data.command.(Database_Create)
	defer if task_data.callback != nil do task_data.callback(task_data, task_data.callback_data)

	if cmd.path != ":memory:" && os.exists(cmd.path) {
		task_data.message = fmt.aprintfln("file exists: %s", cmd.path)
		task_data.status = .Conflict
		return
	}

	db: Db
	err: Db_Error
	if cmd.path == ":memory:" {
		db, err = db_open_memory()

	} else {
		db, err = _open_db(cmd.path)
	}

	if err != nil {
		task_data.message = fmt.aprintfln("db_open failed with error: %s", err)
		task_data.status = .Runtime_Error
		return
	}

	task_data.result = db

	err = db_config(db)
	if err != nil {
		task_data.message = fmt.aprintfln("db_config failed with error: %s", err)
		task_data.status = .Runtime_Error
		return
	}

	err = db_create_tables(db)
	if err != nil {
		task_data.message = fmt.aprintfln("db_create_tables failed with error: %s", err)
		task_data.status = .Runtime_Error
		return
	}

	config := config_create()
	err = config_db_create(&config, db)
	if err != nil {
		task_data.message = fmt.aprintfln("config_create failed with error: %s", err)
		task_data.status = .Runtime_Error
		return
	}

	return
}

_open_db :: proc(path: string) -> (db: Db, err: Db_Error) {
	buf: [1024]u8 = ---
	if len(path) + 1 > size_of(buf) {
		return nil, .Bad_Argument
	}
	copy(buf[:], path)
	buf[len(path)] = 0
	path_c := cstring(&buf[0])
	db, err = db_open(path_c)
	return
}

fatal :: proc(message: string, exit := true) {
	fmt.eprintln(message)
	if exit {
		os.exit(1)
	}
}

// Caller must task_data_destroy the return value.
_dispatch :: proc(self: ^App, words: []string, exit_on_error: bool) -> (td: ^Task_Data) {
	command, query, err := words_to_action(words)
	if err == nil {
		td = action_call(&self.command_pool, command, query, self)
	} else {
		fatal(action_error_to_string(err), exit_on_error)
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
dispatch :: proc(self: ^App, words: []string) -> ^Task_Data {
	return _dispatch(self, words, exit_on_error=false)
}

main_dispatch :: proc(self: ^App, words: []string) {
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

	app_open_db(&app, opts.db)
	main_dispatch(&app, opts.overflow[:])
}

#+test
package main

import "core:os"
import "core:path/filepath"
import "core:testing"
@(require) import "core:fmt"

@(test)
test_version :: proc(t: ^testing.T) {
	app := test_db_init()

	input: []string : {"version"}
	_, query, err := words_to_action(input, app)
	testing.expect_value(t, err, nil)

	td := action_call(&app.query_pool, nil, query, app)
	defer free(td)
	testing.expect(t, td.status == .Ok)

	result_version := td.result.(i64)
	expect_version := i64(1)
	testing.expect_value(t, result_version, expect_version)
}

@(test)
test_server_create_get :: proc(t: ^testing.T) {
	app := test_db_init()
	input: []string = {"server-create", "foo"}
	server_uuid: Uuid
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)

		server := cast(^Server)td.result.(rawptr)
		server_uuid = server.uuid
		free(td.result.(rawptr))
	}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Conflict)
	}

	input = {"server-lookup-name", "foo"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)

		testing.expect(t, td.status == .Ok)
		server := cast(^Server)td.result.(rawptr)
		testing.expect_value(t, server.uuid, server_uuid)
		free(td.result.(rawptr))
	}
	input = {"server-lookup-name", "nonexistent"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Not_Found)
	}

	uuid_hex := uuid_to_hex(server_uuid, context.temp_allocator)
	input = {"server-lookup-uuid", uuid_hex}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		server := cast(^Server)td.result.(rawptr)
		testing.expect_value(t, server.uuid, server_uuid)
		free(td.result.(rawptr))
	}
}

@(test)
test_user_create :: proc(t: ^testing.T) {
	app := test_db_init()
	input: []string = {"server-create", "foo"}
	server_uuid: Uuid
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)

		server := cast(^Server)td.result.(rawptr)
		server_uuid = server.uuid
		free(td.result.(rawptr))
	}

	input = {"user-create", uuid_to_hex(server_uuid, context.temp_allocator), "bar", "baz"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		free(td.result.(rawptr))
	}
}



@(deferred_out=test_db_deinit)
test_db_init :: proc() -> (app: ^App) {
	app = new(App)
	app_init(app)

	app.tmp_dir = os.make_directory_temp("", "chat_*", allocator = context.temp_allocator) or_else panic("failed to make temp dir")
	path := filepath.join({app.tmp_dir, "test.db"}, allocator = context.temp_allocator) or_else panic("oom")

	err := create_db(path)
	if err != nil {
		fmt.eprintfln("error: failed to create database '%s': %s", path, err)
		panic("create failed")
	}

	app_open_db(app, path)
	free_all(context.temp_allocator)
	return
}

test_db_deinit :: proc(app: ^App) {
	app_close_db(app)
	os.remove_all(app.tmp_dir)

	app_deinit(app)
	free(app)
}

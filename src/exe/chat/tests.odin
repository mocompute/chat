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

	Ctx :: struct {
		t: ^testing.T,
		server_uuid: Uuid,
	}
	ctx := Ctx{t=t}
	ctx_ := cast(rawptr)&ctx


	session_uuid: string
	input: []string = {"user-create", "", "super", "pass"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
	}
	input = {"session-create", "", "super", "pass"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		session := cast(^Uuid)td.result.(rawptr)
		session_uuid = uuid_to_hex(session^, context.temp_allocator)
	}

	input = {"server-create", session_uuid, "foo"}
	{
		tm: ^Task_Manager
		id: Uuid
		{
			f :: proc(td: ^Task_Data, ctx: rawptr) {
				ctx := cast(^Ctx) ctx
				t := ctx.t
				defer task_data_destroy(td)

				testing.expect(t, td.status == .Ok)
				server := cast(^Server)td.result.(rawptr)
				ctx.server_uuid = server.uuid
			}
			err: Task_Proc_Status
			tm, id, err = dispatch_async(app, input, f, ctx_)
			testing.expect(t, err == nil)

		}

		// even though this synchronous task is immediately invoked before the async
		// create above has (probably) had a chance to complete, it should still fail
		// due to command serialization.
		{
			td := dispatch(app, input)
			defer task_data_destroy(td)
			testing.expect(t, td.status == .Conflict)
		}

		// busy-wait before proceeding to next test
		task_manager_busy_wait(tm, id)
	}

	input = {"server-lookup-name", "foo"}
	{
		f :: proc(td: ^Task_Data, ctx: rawptr) {
			ctx := cast(^Ctx) ctx
			t := ctx.t
			defer task_data_destroy(td)

			testing.expect(t, td.status == .Ok)
			server := cast(^Server)td.result.(rawptr)
			testing.expect_value(t, server.uuid, ctx.server_uuid)
		}
		dispatch_async(app, input, f, ctx_)
	}
	input = {"server-lookup-name", "nonexistent"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Not_Found)
	}

	uuid_hex := uuid_to_hex(ctx.server_uuid, context.temp_allocator)
	input = {"server-lookup-uuid", uuid_hex}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		server := cast(^Server)td.result.(rawptr)
		testing.expect_value(t, server.uuid, ctx.server_uuid)
	}
}

@(test)
test_user_session_and_channel_create :: proc(t: ^testing.T) {
	app := test_db_init()

	session_uuid: string
	input: []string = {"user-create", "", "super", "pass"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
	}
	input = {"session-create", "", "super", "pass"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		session := cast(^Uuid)td.result.(rawptr)
		session_uuid = uuid_to_hex(session^, context.temp_allocator)
	}

	input = {"server-create", session_uuid, "foo"}
	server_uuid: string
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)

		server := cast(^Server)td.result.(rawptr)
		server_uuid = uuid_to_hex(server.uuid, context.temp_allocator)
	}

	user_uuid: string
	input = {"user-create", server_uuid, "bar", "baz"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		user_uuid = uuid_to_hex(user.uuid, context.temp_allocator)
	}
	input = {"user-lookup-username", server_uuid, "bar"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		testing.expect_value(t, user.role, User_Role.Plain)
	}
	input = {"user-lookup-uuid", user_uuid}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		testing.expect_value(t, user.role, User_Role.Plain)
	}

	input = {"user-role-assign", user_uuid, "create-channel"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		testing.expect_value(t, user.role, User_Role.Create_Channel)
	}
	input = {"user-role-assign", user_uuid, "create-server"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		testing.expect_value(t, user.role, User_Role.Create_Server)
	}

	input = {"user-role-assign", user_uuid, "plain"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		testing.expect_value(t, user.role, User_Role.Plain)
	}

	input = {"session-create", server_uuid, "bar", "baz"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		session := cast(^Uuid)td.result.(rawptr)
		session_uuid = uuid_to_hex(session^, context.temp_allocator)
	}
	input = {"session-refresh", session_uuid}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		refreshed := cast(^Uuid)td.result.(rawptr)
		refreshed_uuid := uuid_to_hex(refreshed^, context.temp_allocator)
		testing.expect(t, refreshed_uuid != session_uuid)

		session_uuid = refreshed_uuid // for following tests
	}
	// expect failure, user has wrong role
	input = {"channel-create", server_uuid, session_uuid, "dazzle"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Conflict)
	}
	// assign create-channel role
	input = {"user-role-assign", user_uuid, "create-channel"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		user := cast(^User)td.result.(rawptr)
		testing.expect_value(t, user.username, "bar")
		testing.expect_value(t, user.role, User_Role.Create_Channel)
	}
	// refresh session so new role takes effect
	input = {"session-refresh", session_uuid}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		refreshed := cast(^Uuid)td.result.(rawptr)
		refreshed_uuid := uuid_to_hex(refreshed^, context.temp_allocator)
		testing.expect(t, refreshed_uuid != session_uuid)

		session_uuid = refreshed_uuid // for following tests
	}
	// expect success
	input = {"channel-create", server_uuid, session_uuid, "dazzle"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
		channel := cast(^Channel)td.result.(rawptr)
		testing.expect_value(t, channel.name, "dazzle")
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

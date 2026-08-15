#+test
package main

import "core:testing"
@(require) import "core:fmt"

@(test)
test_version :: proc(t: ^testing.T) {
	app := test_db_init()

	input: []string : {"version"}
	_, query, err := words_to_action(input)
	testing.expect_value(t, err, nil)

	td := action_call(&app.query_pool, nil, query, app)
	defer free(td)
	testing.expect(t, td.status == .Ok)

	result_version := transmute(i64)td.result
	expect_version := i64(1)
	testing.expect_value(t, result_version, expect_version)
}

@(test)
test_server_create :: proc(t: ^testing.T) {
	app := test_db_init()
	input: []string : {"server-create", "foo"}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Ok)
	}
	{
		td := dispatch(app, input)
		defer task_data_destroy(td)
		testing.expect(t, td.status == .Conflict)
	}
}



@(deferred_out=test_db_deinit)
test_db_init :: proc() -> (app: ^App) {
	path :: ":memory:"
	app = new(App)
	app_init(app)

	td := action_call(&app.command_pool, Database_Create{path=path}, nil, app)
	defer free(td)

	// 'Adopt' db -- this is normally just for testing purposes. The :memory: db
	// forgets everything when it's closed (it's in the name), so the usual workflow
	// of create/close/open doesn't work.
	app_adopt_db(app, td.result)
	return
}

test_db_deinit :: proc(app: ^App) {
	app_deinit(app)
	free(app)
}

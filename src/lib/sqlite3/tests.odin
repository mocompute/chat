#+test
package sqlite3

import "core:c"
import "core:testing"

@(test)
test_open_close :: proc(t: ^testing.T) {
	rc: Result

	db: Connection
	rc = open(":memory:", &db)
	testing.expect_value(t, rc, Result.Ok)

	rc = close(db)
	testing.expect_value(t, rc, Result.Ok)
}

@(test)
test_prepare :: proc(t: ^testing.T) {
	rc: Result

	db: Connection
	rc = open(":memory:", &db)
	testing.expect_value(t, rc, Result.Ok)
	defer close(db)

	stmt: Statement
	rc = prepare_v2(db, "SELECT 42", -1, &stmt, transmute(^cstring)c.NULL)
	testing.expect_value(t, rc, Result.Ok)
	defer finalize(stmt)

	rc = step(stmt)
	testing.expect_value(t, rc, Result.Row)

	result := column_int(stmt, 0)
	testing.expect_value(t, result, 42)

	rc = step(stmt)
	testing.expect_value(t, rc, Result.Done)
}

@(test)
test_bind_reset :: proc(t: ^testing.T) {
	rc: Result

	db: Connection
	rc = open(":memory:", &db)
	testing.expect_value(t, rc, Result.Ok)
	defer close(db)

	stmt: Statement
	rc = prepare_v2(db, "SELECT ?", -1, &stmt, transmute(^cstring)c.NULL)
	testing.expect_value(t, rc, Result.Ok)
	defer finalize(stmt)

	rc = bind_int(stmt, 1, 42)
	rc = step(stmt)
	testing.expect_value(t, rc, Result.Row)

	result := column_int(stmt, 0)
	testing.expect_value(t, result, 42)

	rc = step(stmt)
	testing.expect_value(t, rc, Result.Done)

	// reset and rebind with int64
	rc = reset(stmt)
	testing.expect_value(t, rc, Result.Ok)

	rc = bind_int64(stmt, 1, 67)
	rc = step(stmt)
	testing.expect_value(t, rc, Result.Row)

	resulti64 := column_int64(stmt, 0)
	testing.expect_value(t, resulti64, 67)

	rc = step(stmt)
	testing.expect_value(t, rc, Result.Done)
}

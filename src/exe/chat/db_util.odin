#+feature using-stmt
package main

import "../../../../base/src/lib/sqlite3"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:thread"
import "core:time"

Db_Bind_Spec :: struct {
	name: cstring,
	value: any,
}

Db_Scan_Spec :: struct {
	name: cstring,
	dest: any,
}

MAX_COLUMNS :: 32
DEFAULT_TIMEOUT :: 5000

db_prepare_bind :: proc(db: Db, sql: cstring, specs: []Db_Bind_Spec) -> (stmt: sqlite3.Statement, err: Db_Error) {
	stmt = db_prepare(db, sql) or_return
	db_bind(stmt, specs) or_return
	return
}

db_prepare_bind_row :: proc(db: Db, sql: cstring, source: $T, to_row_proc: proc(T, sqlite3.Statement) -> Db_Error) -> (stmt: sqlite3.Statement, err: Db_Error) {
	stmt = db_prepare(db, sql) or_return
	to_row_proc(source, stmt) or_return
	return
}

db_retrieve_one_scan :: proc(stmt: sqlite3.Statement, destination: $T, from_row_proc: proc(T, sqlite3.Statement) -> Db_Error, timeout: uint) -> (err: Db_Error) {
	err = db_step(stmt, timeout)

	if err == sqlite3.Result.Row {
		from_row_proc(destination, stmt) or_return
		err = nil
	} else if err == sqlite3.Result.Done {
		err = .Not_Found
	} else {
		panic("unreachable")
	}
	return
}

db_retrieve_one_and_finalize_default_timeout :: proc(stmt: sqlite3.Statement, dest: $T, from_row_proc: proc(T, sqlite3.Statement) -> Db_Error) -> (err: Db_Error) {
	err = db_retrieve_one_scan(stmt, dest, from_row_proc, 0)
	sqlite3.finalize(stmt)
	return
}

db_bind :: proc(stmt: sqlite3.Statement, specs: []Db_Bind_Spec) -> (err: Db_Error) {
	using sqlite3
	clear_bindings(stmt)

	for s in specs {
		i := bind_parameter_index(stmt, s.name)
		if i == 0 do continue

		switch v in s.value {
		case i64:
			err = bind_int64(stmt, i, v)
		case i32:
			err = bind_int64(stmt, i, i64(v))
		case i16:
			err = bind_int64(stmt, i, i64(v))
		case i8:
			err = bind_int64(stmt, i, i64(v))
		case int:
			err = bind_int64(stmt, i, i64(v))
		case u64:
			if v > u64(max(i64)) {
				fmt.eprintfln("warning: i64 truncation")
			}
			err = bind_int64(stmt, i, i64(v))
		case u32:
			err = bind_int64(stmt, i, i64(v))
		case u16:
			err = bind_int64(stmt, i, i64(v))
		case u8:
			err = bind_int64(stmt, i, i64(v))
		case uint:
			err = bind_int64(stmt, i, i64(v))

		case string:
			err = bind_text(stmt, i, cast(cstring)raw_data(v), i32(len(v)), TRANSIENT)
		case cstring:
			err = bind_text(stmt, i, v, i32(len(v)), TRANSIENT)
		case []u8:
			err = bind_blob(stmt, i, raw_data(v), i32(len(v)), TRANSIENT)
		case:
			fatal(fmt.tprintf("db_bind: field '%s' unknown type %v", s.name, v))
		}

		if err != nil do return
	}

	return
}

// Allocates to copy strings out of Statement. For blobs, caller must provide a slice
// large enough to hold the column data.
db_scan_columns :: proc(stmt: sqlite3.Statement, specs: []Db_Scan_Spec) -> (err: Db_Error) {
	column_names: [MAX_COLUMNS]cstring
	n_cols := sqlite3.column_count(stmt)
	if n_cols > MAX_COLUMNS {
		panic("too many columns")
	}
	for i in 0..<n_cols {
		column_names[i] = sqlite3.column_name(stmt, i)
	}

	for s, _ in specs {
		col_idx: c.int = -1
	inner:
		for i in 0..<n_cols {
			if column_names[i] == s.name {
				col_idx = i
				break inner
			}
		}
		if col_idx == -1 {
			return Logic_Error.Field_Name_Not_Found
		}

		switch p in s.dest {
		case ^i64:
			p^ = i64(sqlite3.column_int64(stmt, col_idx))
		case ^i32:
			p^ = i32(sqlite3.column_int64(stmt, col_idx))
		case ^i16:
			p^ = i16(sqlite3.column_int64(stmt, col_idx))
		case ^i8:
			p^ = i8(sqlite3.column_int64(stmt, col_idx))
		case ^int:
			p^ = int(sqlite3.column_int64(stmt, col_idx))
		case ^u32:
			p^ = u32(sqlite3.column_int64(stmt, col_idx))
		case ^u16:
			p^ = u16(sqlite3.column_int64(stmt, col_idx))
		case ^u8:
			p^ = u8(sqlite3.column_int64(stmt, col_idx))
		case ^string:
			p^ = strings.clone_from_cstring(sqlite3.column_text(stmt, col_idx))
		case []byte:
			n: int = int(sqlite3.column_bytes(stmt, col_idx))
			if len(p) < n {
				return Runtime_Error.Out_Of_Range
			}
			mem.copy(raw_data(p), sqlite3.column_blob(stmt, col_idx), n)
		case:
			fatal(fmt.tprintf("fatal: unknown result column type: %v", p))
		}
	}
	return
}

db_retrieve_one :: proc($T: typeid, stmt: sqlite3.Statement, construct: proc(sqlite3.Statement, mem.Allocator) -> (T, Db_Error), allocator := context.allocator) -> (result: T, err: Db_Error) {
	for {
		err = sqlite3.step(stmt)
		if err == sqlite3.Result.Row {
			result = construct(stmt, allocator) or_return
			err = nil
			break
		} else if err == sqlite3.Result.Done {
			err = .Not_Found
			break
		} else if err == sqlite3.Result.Busy {
			thread.yield()
		}
	}
	return
}

// Loops in case of BUSY response from SQLite3. When used in conjunction with PRAGMA
// busy_timeout, BUSY will only be returned if the database is still locked after the
// busy_timeout value has elapsed. Timeout is in milliseconds.
db_step :: proc(stmt: sqlite3.Statement, timeout: uint = 0) -> (err: Db_Error) {
	timeout := timeout
	if timeout == 0 {
		timeout = DEFAULT_TIMEOUT
	}
	start_time := time.now()

	for {
		err = sqlite3.step(stmt)

		if err == sqlite3.Result.Busy {
			now := time.now()
			elapsed := time.duration_milliseconds(time.diff(start_time, now))
			if i64(elapsed) > i64(timeout) {
				return Runtime_Error.Timeout
			}
			thread.yield()
		} else {
			break
		}
	}
	return
}

db_step_and_finalize :: proc(stmt: sqlite3.Statement, timeout: uint = 0) -> (err: Db_Error) {
	err = db_step(stmt, timeout)
	if err == .Done {
		err = nil
	} else {
		msg := sqlite3.errmsg(sqlite3.db_handle(stmt))
		fmt.eprintfln("db_step_and_finalize: error: %v: %s", err, msg)
	}
	sqlite3.finalize(stmt)
	return
}

db_step_and_finalize_default_timeout :: proc (stmt: sqlite3.Statement) -> (err: Db_Error) {
	return db_step_and_finalize(stmt, 0)
}

#+feature using-stmt
package main

import "../../lib/sqlite3"
import "core:c"
import "core:fmt"
import "core:slice"

Db_Value :: union {
	i32,
	i64,
	string,
	cstring,
	[]u8,
}

Db_Bind_Spec :: struct {
	name: cstring,
	value: Db_Value,
}

Db_Column_Spec :: struct  {
	name: cstring,
	type: typeid,
}

Db_Row_Spec :: []Db_Column_Spec

MAX_COLUMNS :: 32

db_prepare_bind :: proc(db: Db, sql: cstring, specs: []Db_Bind_Spec) -> (stmt: sqlite3.Statement, err: Db_Error) {
	stmt = db_prepare(db, sql) or_return
	db_bind(stmt, specs) or_return
	return
}

db_bind :: proc(stmt: sqlite3.Statement, specs: []Db_Bind_Spec) -> (err: Db_Error) {
	using sqlite3
	clear_bindings(stmt)

	for s in specs {
		i := bind_parameter_index(stmt, s.name)
		if i == 0 do return Logic_Error.Field_Name_Not_Found

		switch v in s.value {
		case i32:
			err = bind_int(stmt, i, v)
		case i64:
			err = bind_int64(stmt, i, v)
		case string:
			err = bind_text(stmt, i, cast(cstring)raw_data(v), i32(len(v)), TRANSIENT)
		case cstring:
			err = bind_text(stmt, i, v, i32(len(v)), TRANSIENT)
		case []u8:
			err = bind_blob(stmt, i, raw_data(v), i32(len(v)), TRANSIENT)
		}

		if err != nil do return
	}

	return
}

db_columns :: proc(stmt: sqlite3.Statement, specs: []Db_Column_Spec, out: []Db_Value) -> (err: Db_Error) {
	using sqlite3

	ensure(len(specs) == len(out))

	column_names: [MAX_COLUMNS]cstring
	n_cols := column_count(stmt)
	ensure(n_cols <= MAX_COLUMNS)
	for i in 0..<n_cols {
		column_names[i] = column_name(stmt, i)
	}

	for s, i_specs in specs {
		col_idx: c.int = -1
		inner: for i in 0..<n_cols {
			if (column_names[i] == s.name) {
				col_idx = i
				break inner
			}
		}
		if col_idx == -1 do return Logic_Error.Field_Name_Not_Found

		switch s.type {
		case i64:
			out[i_specs] = column_int64(stmt, col_idx)
		case cstring:
			out[i_specs] = column_text(stmt, col_idx)
		case []u8:
			data_size := column_bytes(stmt, col_idx)
			out[i_specs] = slice.bytes_from_ptr(column_blob(stmt, col_idx), int(data_size))
		case:
			fatal(fmt.tprintf("fatal: unknown result column type: %v", s.type))
		}
	}
	return
}

db_retrieve_one :: proc($T: typeid, stmt: sqlite3.Statement, construct: proc(sqlite3.Statement) -> (T, Db_Error)) -> (result: T, err: Db_Error) {
	err = sqlite3.step(stmt)
	if err == sqlite3.Result.Row {
		result = construct(stmt) or_return
		err = nil
	} else if err == sqlite3.Result.Done {
		err = .Not_Found
	}
	return
}

db_insert_unique :: proc(stmt: sqlite3.Statement) -> (err: Db_Error) {
	err = sqlite3.step(stmt)

	if err == sqlite3.Result.Done {
		err = nil
	} else if err == sqlite3.Result.Constraint {
		err = .Exists
	}
	return
}

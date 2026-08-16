package sqlite3

import "core:c"

when ODIN_OS == .Linux || ODIN_OS == .Darwin {
	foreign import sqlite3 "../../vendor/sqlite3/sqlite-amalgamation-3530400/sqlite3.a"
}
when ODIN_OS == .Windows {
	foreign import sqlite3 "../../vendor/sqlite3/sqlite-amalgamation-3530400/sqlite3.lib"
}

// Database Connection Handle
Connection :: rawptr

// Statement handle
Statement :: rawptr

// Dynamically Typed Value Object
Value :: rawptr

/*
Subset of interesting error codes.

Copied from MIT licensed https://github.com/saenai255/odin-sqlite3/
with gratitude to save some typing.

Verified by eye against sqlite3.h.
*/
Result :: enum (c.int) {
	Ok                      = 0,
	Error                   = 1,
	Internal                = 2,
	Perm                    = 3,
	Abort                   = 4,
	Busy                    = 5,
	Locked                  = 6,
	NoMem                   = 7,
	ReadOnly                = 8,
	Interrupt               = 9,
	IoErr                   = 10,
	Corrupt                 = 11,
	NotFound                = 12,
	Full                    = 13,
	CantOpen                = 14,
	Protocol                = 15,
	Empty                   = 16,
	Schema                  = 17,
	TooBig                  = 18,
	Constraint              = 19,
	Mismatch                = 20,
	Misuse                  = 21,
	NoLfs                   = 22,
	Auth                    = 23,
	Format                  = 24,
	Range                   = 25,
	NotADb                  = 26,
	Notice                  = 27,
	Warning                 = 28,
	Row                     = 100,
	Done                    = 101,
}

/*
Configuration options for use with `config()`, which is a varargs C
function. Refer to sqlite3.h for documentation of the required
parameters.

Copied from MIT licensed https://github.com/saenai255/odin-sqlite3/
with gratitude to save some typing.

Verified by eye against sqlite3.h.
*/
Config :: enum (c.int) {
	Single_Thread       = 1,
	Multi_Thread        = 2,
	Serialized          = 3,
	Malloc              = 4,
	Get_Malloc          = 5,
	Scratch             = 6,
	Page_Cache          = 7,
	Heap                = 8,
	Mem_Status          = 9,
	Mutex               = 10,
	Get_Mutex           = 11,
/* previously SQLITE_CONFIG_CHUNKALLOC    12 which is now unused. */
	Lookaside           = 13,
	PCache              = 14,
	Get_PCache          = 15,
	Log                 = 16,
	Uri                 = 17,
	PCache2             = 18,
	Get_PCache2         = 19,
	Covering_Index_Scan = 20,
	SqlLog              = 21,
	Mmap_Size           = 22,
	Win32_Heapsize      = 23,
	PCache_Hdrsz        = 24,
	Pmasz               = 25,
	StmtJrnl_Spill      = 26,
	Small_Malloc        = 27,
	SorterRef_Size      = 28,
	Memdb_Maxsize       = 29,
	Rowid_In_View       = 30,
}

Open_Flags :: enum (c.int) {
	// From sqlite3.h
	READONLY       =  0x00000001,  /* Ok for sqlite3_open_v2() */
	READWRITE      =  0x00000002,  /* Ok for sqlite3_open_v2() */
	CREATE         =  0x00000004,  /* Ok for sqlite3_open_v2() */
	DELETEONCLOSE  =  0x00000008,  /* VFS only */
	EXCLUSIVE      =  0x00000010,  /* VFS only */
	AUTOPROXY      =  0x00000020,  /* VFS only */
	URI            =  0x00000040,  /* Ok for sqlite3_open_v2() */
	MEMORY         =  0x00000080,  /* Ok for sqlite3_open_v2() */
	MAIN_DB        =  0x00000100,  /* VFS only */
	TEMP_DB        =  0x00000200,  /* VFS only */
	TRANSIENT_DB   =  0x00000400,  /* VFS only */
	MAIN_JOURNAL   =  0x00000800,  /* VFS only */
	TEMP_JOURNAL   =  0x00001000,  /* VFS only */
	SUBJOURNAL     =  0x00002000,  /* VFS only */
	SUPER_JOURNAL  =  0x00004000,  /* VFS only */
	NOMUTEX        =  0x00008000,  /* Ok for sqlite3_open_v2() */
	FULLMUTEX      =  0x00010000,  /* Ok for sqlite3_open_v2() */
	SHAREDCACHE    =  0x00020000,  /* Ok for sqlite3_open_v2() */
	PRIVATECACHE   =  0x00040000,  /* Ok for sqlite3_open_v2() */
	WAL            =  0x00080000,  /* VFS only */
	NOFOLLOW       =  0x01000000,  /* Ok for sqlite3_open_v2() */
	EXRESCODE      =  0x02000000,  /* Extended result codes */
}


Bind_Callback :: proc "c" (rawptr) -> rawptr
STATIC := transmute(Bind_Callback)i64(0)
TRANSIENT := transmute(Bind_Callback) i64(-1)

@(link_prefix="sqlite3_", default_calling_convention="c")
foreign sqlite3 {
	threadsafe :: proc() -> c.int ---

	initialize :: proc() -> Result ---
	config :: proc(option: Config, #c_vararg args: ..any) -> Result ---

	open :: proc(filename: cstring, ppDb: ^Connection) -> Result ---
	open_v2 :: proc(filename: cstring, ppDb: ^Connection, flags: c.int, zVfs: cstring) -> Result ---
	close :: proc(db: Connection) -> Result ---

	prepare_v2 :: proc(db: Connection, zSql: cstring, nByte: c.int, ppStmt: ^Statement, pzTail: ^cstring) -> Result ---
	step :: proc(stmt: Statement) -> Result ---
	reset :: proc(stmt: Statement) -> Result ---
	finalize :: proc(stmt: Statement) -> Result ---

	// bind_* use 1-based parameter indices from left to right
	bind_blob:: proc(stmt: Statement, i_1: c.int, p: rawptr, n: c.int, cb: Bind_Callback) -> Result ---
	bind_blob64:: proc(stmt: Statement, i_1: c.int, p: rawptr, n: u64, cb: Bind_Callback) -> Result ---
	bind_double:: proc(stmt: Statement, i_1: c.int, d: c.double) -> Result ---
	bind_int :: proc(stmt: Statement, i_1: c.int, val: c.int) -> Result ---
	bind_int64 :: proc(stmt: Statement, i_1: c.int, val: i64) -> Result ---
	bind_null :: proc(stmt: Statement, i_1: c.int) -> Result ---
	bind_text :: proc(stmt: Statement, i_1: c.int, s: cstring, n: c.int, cb: Bind_Callback) -> Result ---
	bind_text16 :: proc(stmt: Statement, i_1: c.int, s: cstring, n: c.int, cb: Bind_Callback) -> Result ---
	bind_text64 :: proc(stmt: Statement, i_1: c.int, s: cstring, n: u64, cb: Bind_Callback, encoding: u8) -> Result ---
	bind_value :: proc(stmt: Statement, i_1: c.int, value: Value) -> Result ---
	bind_pointer :: proc(stmt: Statement, i_1: c.int, p: rawptr, s: cstring, cb: Bind_Callback) -> Result ---
	bind_zeroblob :: proc(stmt: Statement, i_1: c.int, n: c.int) -> Result ---
	bind_zeroblob64 :: proc(stmt: Statement, i_1: c.int, n: u64) -> Result ---
	clear_bindings :: proc(stmt: Statement) -> c.int ---


	column_blob :: proc(stmt: Statement, i: c.int) -> rawptr ---
	column_double :: proc(stmt: Statement, i: c.int) -> c.double ---
	column_int :: proc(stmt: Statement, i: c.int) -> c.int ---
	column_int64 :: proc(stmt: Statement, i: c.int) -> i64 ---
	column_text :: proc(stmt: Statement, i: c.int) -> cstring ---
	column_text16 :: proc(stmt: Statement, i: c.int) -> rawptr ---
	column_value :: proc(stmt: Statement, i: c.int) -> Value ---
	column_bytes :: proc(stmt: Statement, i: c.int) -> c.int ---
	column_bytes16 :: proc(stmt: Statement, i: c.int) -> c.int ---
	column_type :: proc(stmt: Statement, i: c.int) -> c.int ---

	column_count :: proc(stmt: Statement) -> c.int ---
	column_name :: proc(stmt: Statement, n: c.int) -> cstring ---
	column_name16 :: proc (stmt:Statement, n: c.int) -> rawptr ---

	last_insert_rowid :: proc(db: Connection) -> i64 ---

	bind_parameter_count :: proc(stmt: Statement) -> c.int ---
	bind_parameter_index :: proc(stmt: Statement, zName: cstring) -> c.int ---
	bind_parameter_name :: proc(stmt: Statement, param: c.int) -> cstring ---

}

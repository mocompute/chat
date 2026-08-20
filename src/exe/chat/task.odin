package main

import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"

import "../../../../base/src/lib/sqlite3"

Task_Manager :: struct {
	tickets: map[Uuid]Ticket,
	tickets_mutex: sync.RW_Mutex,

	pool: thread.Pool,
}

Ticket :: struct {
	task_data: ^Task_Data,
	status: Task_Status,
}

Task_Proc_Status :: enum {
	Ok,
	Runtime_Error,
	Conflict,
	Not_Found,
	Database_Error,
}

Task_Data :: struct {
	id: Uuid,
	app: ^App,
	command: Command,
	query: Query,

	result: union {
		rawptr,		// will be freed by task_data_destroy
		i64,
	},
	result_deinit: proc(rawptr, mem.Allocator), // called before free of result.rawptr

	message: string,
	status: Task_Proc_Status,

	// set by cast/call, do not set directly
	callback: Task_Callback,
	callback_data: rawptr,
}

Task_Status :: enum {
	In_Flight,
	Done,
}

Task :: thread.Task
Task_Proc :: thread.Task_Proc
Task_Callback :: #type proc(^Task_Data, rawptr)

// SQLite3 per-thread connection
@(thread_local) tl_db_conn: sqlite3.Connection

Task_Thread_Init :: struct {
	db_path: cstring,
}

task_thread_init :: proc(thread: ^thread.Thread, user_data: rawptr) {
	ctx := cast(^Task_Thread_Init) user_data
	db, err := db_open_multi_threaded(ctx.db_path)
	if err == nil {
		tl_db_conn = db
	}
}

task_thread_fini :: proc(thread: ^thread.Thread, user_data: rawptr) {
	if tl_db_conn != nil {
		db_close(tl_db_conn)
	}
}

task_data_destroy :: proc(self: ^Task_Data) {
	delete(self.message)
	if v, ok := self.result.(rawptr); ok {
		if self.result_deinit != nil {
			self.result_deinit(v, context.allocator)
		}
		free(v)
	}
	free(self)
}

task_manager_init :: proc(self: ^Task_Manager, thread_count: int, task_thread_init_data: ^Task_Thread_Init) {
	self.tickets = make(map[Uuid]Ticket)

	ud := cast(rawptr)task_thread_init_data

	// thread-safe allocator is required.
	thread.pool_init(&self.pool, os.heap_allocator(), thread_count, task_thread_init, ud, task_thread_fini, nil)
}

task_manager_start :: proc(self: ^Task_Manager) {
	thread.pool_start(&self.pool)
}

task_manager_drain :: proc(self: ^Task_Manager) {
	for thread.pool_num_outstanding(&self.pool) > 0 {
		thread.yield()
	}
	thread.pool_join(&self.pool)
}

task_manager_deinit :: proc(self: ^Task_Manager) {
	thread.pool_destroy(&self.pool)
	delete(self.tickets)
	self.tickets = nil
}


// `procedure` MUST use `task_to_task_data` because it queues a required defer statement
//
//	foo :: proc(task: Task) {
//		task_data := task_to_task_data(task)
//		// ...
//	}
task_manager_cast :: proc(self: ^Task_Manager, procedure: thread.Task_Proc, data: ^Task_Data, app: ^App, cb: Task_Callback = nil, cb_data: rawptr = nil) -> (id: Uuid) {
	id = uuid_v7()
	if sync.rw_mutex_guard(&self.tickets_mutex) {
		self.tickets[id] = {task_data=data, status=.In_Flight}
	}
	data.id = id
	data.app = app
	data.callback = cb
	data.callback_data = cb_data
	thread.pool_add_task(&self.pool, context.allocator, procedure, data)
	return
}

// `procedure` MAY check the callback, as in procedures used with `task_manager_cast`, but
// it isn't necessary.
task_manager_call :: proc(self: ^Task_Manager, procedure: thread.Task_Proc, data: ^Task_Data, app: ^App) {
	id := task_manager_cast(self, procedure, data, app)
	result := task_manager_busy_wait(self, id)
	ensure(data == result)
}

task_manager_ticket_status :: proc(self: ^Task_Manager, id: Uuid) -> (status: Task_Status, ok: bool) {
	if sync.rw_mutex_shared_guard(&self.tickets_mutex) {
		ticket, found := self.tickets[id]
		if found {
			return ticket.status, true
		} else {
			return nil, false
		}
	}
	return
}

task_manager_busy_wait :: proc(self: ^Task_Manager, id: Uuid) -> (result: ^Task_Data) {
	ticket: Ticket
	if sync.rw_mutex_shared_guard(&self.tickets_mutex) {
		ticket = self.tickets[id]
	}

	if ticket.status == .Done {
		result = ticket.task_data
		task_manager_remove_task(self, id)
		return
	}

	for {
		task: Task
		got_task := false
		for got_task == false {
			task, got_task = thread.pool_pop_done(&self.pool)
		}

		task_data := cast(^Task_Data) task.data

		if task_data.id == id {
			result = task_data
			task_manager_remove_task(self, id)
			return
		} else {
			if sync.rw_mutex_guard(&self.tickets_mutex) {
				ticket = self.tickets[task_data.id]
				ticket.status = .Done
				self.tickets[task_data.id] = ticket
			}

		}

		thread.yield()
	}
}

task_manager_remove_task :: proc(self: ^Task_Manager, id: Uuid) {
	if sync.rw_mutex_guard(&self.tickets_mutex) {
		delete_key(&self.tickets, id)
	}
}


@(deferred_out=deferred_task_data_callback)
task_to_task_data :: proc(task: Task) -> (td: ^Task_Data) {
	td = cast(^Task_Data) task.data
	return
}

deferred_task_data_callback :: proc(td: ^Task_Data) {
	if td.callback != nil do td.callback(td, td.callback_data)
}

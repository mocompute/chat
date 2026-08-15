package main

import "core:encoding/uuid"
import "core:crypto"
import "core:os"
import "core:sync"
import "core:thread"
@(require) import "core:fmt"

Task_Manager :: struct {
	tickets: map[uuid.Identifier]Ticket,
	tickets_mutex: sync.RW_Mutex,

	pool: thread.Pool,
}

Ticket :: struct {
	task_data: ^Task_Data,
	status: Task_Status,
}

Task_Data :: struct {
	id: uuid.Identifier,
	app: ^App,
	command: Command,
	query: Query,
	result: rawptr,
	message: string,
	status: enum {
		Runtime_Error,
		Ok,
		Conflict,
		Database_Error,
	},

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

task_data_destroy :: proc(self: ^Task_Data) {
	delete(self.message)
	free(self)
}

task_manager_init :: proc(self: ^Task_Manager, thread_count: int) {
	self.tickets = make(map[uuid.Identifier]Ticket)
	thread.pool_init(&self.pool, os.heap_allocator(), thread_count)
}

task_manager_start :: proc(self: ^Task_Manager) {
	thread.pool_start(&self.pool)
}

task_manager_join :: proc(self: ^Task_Manager) {
	thread.pool_join(&self.pool)
}

task_manager_deinit :: proc(self: ^Task_Manager) {
	thread.pool_destroy(&self.pool)
	delete(self.tickets)
	self.tickets = nil
}


// `procedure` MUST check the callback, like this:
//
//	foo :: proc(task: Task) {
//		task_data := cast(^Task_Data) task.data
//		defer if task_data.callback != nil do task_data.callback(task_data)
//		// ...
//	}
task_manager_cast :: proc(self: ^Task_Manager, procedure: thread.Task_Proc, data: ^Task_Data, app: ^App, cb: Task_Callback = nil, cb_data: rawptr = nil) -> (id: uuid.Identifier) {
	{
		context.random_generator = crypto.random_generator()
		id = uuid.generate_v7()
	}
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

task_manager_ticket_status :: proc(self: ^Task_Manager, id: uuid.Identifier) -> (status: Task_Status, ok: bool) {
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

task_manager_busy_wait :: proc(self: ^Task_Manager, id: uuid.Identifier) -> (result: ^Task_Data) {
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

task_manager_remove_task :: proc(self: ^Task_Manager, id: uuid.Identifier) {
	if sync.rw_mutex_guard(&self.tickets_mutex) {
		delete_key(&self.tickets, id)
	}
}

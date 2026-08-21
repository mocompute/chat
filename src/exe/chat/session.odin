package main

import "core:container/lru"
import "core:mem"
import "core:sync"

/*

Session Management

A Session represents an authenticated user. Any bearer of the session token (a Uuid) is
considered acting on behalf of the authenticated user. This means the transport layer
must be secure, and the token must be stored by the client securely, e.g. in a Secure
cookie, not localStorage.

A Session token is invalid after a certain time.

The Session Manager is an LRU cache, configured with a maximum number of sessions to
store in memory.

*/

SESSION_MAX_AGE :: 900		// 15 minutes

Session :: struct {
	user: Uuid,
	user_role: User_Role,
	expires: i64,
}

Session_Manager :: struct {
	cache: lru.Cache(Uuid, Session),
	mutex: sync.Mutex,
}

session_manager_init :: proc(self: ^Session_Manager, max_sessions: int, allocator: mem.Allocator) {
	sync.mutex_guard(&self.mutex)
	lru.init(&self.cache, max_sessions, allocator, allocator)
}

session_manager_deinit :: proc(self: ^Session_Manager) {
	sync.mutex_guard(&self.mutex)
	lru.destroy(&self.cache, false)
}

session_manager_insert :: proc(self: ^Session_Manager, uuid: Uuid, session: Session) {
	sync.mutex_guard(&self.mutex)
	lru.set(&self.cache, uuid, session)
}

session_manager_lookup :: proc(self: ^Session_Manager, uuid: Uuid) -> (session: Session, ok: bool) {
	sync.mutex_guard(&self.mutex)
	session, ok = lru.get(&self.cache, uuid)
	return
}

session_manager_remove :: proc(self: ^Session_Manager, uuid: Uuid) -> (ok: bool) {
	sync.mutex_guard(&self.mutex)
	ok = lru.remove(&self.cache, uuid)
	return
}

session_manager_refresh :: proc(self: ^Session_Manager, uuid: Uuid, db: Db) -> (refreshed: Uuid, status: Task_Proc_Status) {
	session: Session
	ok: bool

	// outside of mutex
	now := unix_time()
	refreshed = uuid_v4()

	// load current session and user, without holding lock
	session, ok = session_manager_lookup(self, uuid)
	if !ok {
		return {}, .Not_Found
	}
	user, err := user_db_lookup_uuid(tl_db_conn, session.user)
	defer user_deinit(&user)
	if err != nil {
		return {}, .Not_Found
	}

	// update session from current user role
	session.user_role = user.role

	// refresh token and update session
	sync.mutex_guard(&self.mutex)

	if session.expires < now {
		// Refuse to refresh an expired token. Instead, delete it and return error.
		lru.remove(&self.cache, uuid)
		return {}, .Conflict
	}

	lru.remove(&self.cache, uuid)
	lru.set(&self.cache, refreshed, session)
	return refreshed, .Ok
}

session_create :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.command.(Session_Create)

	user, err := user_db_lookup_username(tl_db_conn, cmd.server, cmd.username)
	defer user_deinit(&user)
	if err != nil {
		task_data.status = .Not_Found
		return
	}

	if user_valid_password(user, cmd.password, cmd.pepper[:]) {
		task_data.status = .Ok

		session := Session{user=user.uuid, user_role=user.role, expires=unix_time() + SESSION_MAX_AGE}
		uuid := uuid_v4()
		session_manager_insert(cmd.session_manager, uuid, session)
		task_data.result = cast(rawptr) new_clone(uuid)
	} else {
		task_data.status = .Conflict
	}
	return
}

session_refresh :: proc(task: Task) {
	task_data := task_to_task_data(task)
	cmd := task_data.command.(Session_Refresh)

	refreshed: Uuid
	refreshed, task_data.status = session_manager_refresh(cmd.session_manager, cmd.uuid, tl_db_conn)
	if task_data.status == .Ok {
		task_data.result = cast(rawptr) new_clone(refreshed)
	}
}

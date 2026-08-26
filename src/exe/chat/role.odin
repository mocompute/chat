package main

// Roles/capabilities which apply to the entire node.
Node_Role :: enum {
	Create_Server,
	Create_User,
}

Node_Role_Set :: bit_set[Node_Role; u32]

// Roles/capabilities which apply to a particular server.
Server_Role :: enum {
	Create_Channel,		// create new channels in the server
	Assign_Role,		// assign server role to user
}

Server_Role_Set :: bit_set[Server_Role; u32]

// Roles assigned to the node's superuser.
Role_Super :: Node_Role_Set{
	.Create_Server,
	.Create_User,
}

// Roles assigned to a server owner.
Role_Server_Owner :: Server_Role_Set{
	.Create_Channel,
	.Assign_Role,
}

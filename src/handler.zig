const std = @import("std");
const pg = @import("pg");

pub const Role = enum {
    admin,
    customer,
    developer,
    guest,
};
pub const RoleSet = std.EnumSet(Role);

pg_pool: *pg.Pool,
user: struct {
    role: Role,
    id: []const u8,
},

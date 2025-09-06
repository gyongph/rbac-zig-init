const std = @import("std");
const pg = @import("pg");

pub const Role = enum {
    admin,
    customer,
    developer,
    guest,
};
pub const RoleSet = std.EnumSet(Role);
pub const string = []const u8;
pub const TokenPayload = union(Role) {
    admin: void,
    /// client account id
    customer: string,
    developer: struct {
        client_account_id: string,
        profile_id: string,
    },
    guest: void,
};
user: TokenPayload,
pg_pool: *pg.Pool,

const std = @import("std");
const Handler = @import("../../handler.zig");
const httpz = @import("httpz");
const TypeUtils = @import("type-utils");
pub const Schema = struct {
    id: []const u8,
    xa_id: []const u8,
    xa_perm_refresh_token: []const u8,
    xa_perm_rt_created_at: i64,
    xa_perm_rt_expires_at: i64,
};
pub const SchemaField = TypeUtils.MatchStructFields(Schema, enum {
    id,
    xa_id,
    xa_perm_refresh_token,
    xa_perm_rt_created_at,
    xa_perm_rt_expires_at,
});
pub const SchemaFieldSet = std.EnumSet(SchemaField);
pub const Accessor = enum {
    admin,
    owner,
    public,
    pub fn get(_: Handler, _: *httpz.Request, _: *httpz.Response) !Accessor {
        return .public;
    }
};

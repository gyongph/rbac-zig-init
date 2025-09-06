const std = @import("std");
const RBAC = @import("rbac");
const String = @import("utils").String;
const AccountModule = @import("modules/account/main.zig");
const Handler = @import("handler.zig");
const env = @import("env.zig");
const pb_db = @import("db/conn.zig");
pub fn main() !void {
    try env.init();
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();
    var app = try RBAC.init(
        Handler{
            .user = .{
                .guest = {},
            },
            .pg_pool = try pb_db.init(gpa_alloc, 69),
        },
        gpa_alloc,
        .{
            .address = "0.0.0.0",
            .port = 8080,
        },
        .{
            .allow_creds = true,
            .origins = "https://example.com",
            .headers = "Content-Type, Authorization",
            .methods = "GET, PATCH, POST, DELETE, PUT",
        },
    );
    try app.register(AccountModule);
    try app.listen();
}

const std = @import("std");
const RBAC = @import("rbac");
const String = @import("utils").String;
const AccountModule = @import("modules/account/main.zig");
const Handler = @import("handler.zig");
const env = @import("env.zig");
const pb_db = @import("db/conn.zig");
pub fn main() !void {
    try env.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_alloc = gpa.allocator();
    var app = try RBAC.init(
        Handler{
            .user = .{
                .role = .guest,
                .id = &String.random(10),
            },
            .pg_pool = try pb_db.init(gpa_alloc, 69),
        },
        gpa_alloc,
        .{ .port = 5454 },
    );
    try app.registerModule(AccountModule);
    try app.listen();
}

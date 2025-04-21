const std = @import("std");
const httpz = @import("httpz");
const Handler = @import("../../handler.zig");
const Utils = @import("utils");

pub const @"GET: /alive/:status" = struct {
    pub const allowed_role: Handler.RoleSet = .initEmpty();
    pub fn action(_: Handler, req: *httpz.Request, res: *httpz.Response) anyerror!void {
        const status = req.param("status").?;
        std.log.info("{s}", .{status});
        std.log.info("{s}", .{Utils.String.random(100)});
        res.status = 200;
    }
};

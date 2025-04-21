const std = @import("std");
const httpz = @import("httpz");
const Handler = @import("../../handler.zig");
const Accessor = @import("main.zig").Accessor;
const SchemaFieldSet = @import("main.zig").SchemaFieldSet;
const ListOptions = @import("rbac").ListOptions;

pub const list = struct {
    pub const role = Handler.RoleSet.initOne(.guest);
    pub const action = struct {
        pub const select = SchemaFieldSet.initOne(.xa_id);
        pub const where = "true";
    };
};

pub const create = struct {
    pub const role = Handler.RoleSet.initMany(&.{ .admin, .guest });
    pub fn action(handler: Handler, req: *httpz.Request, res: *httpz.Response) !void {
        _ = handler;
        _ = req;
        _ = res;
    }
};

pub const delete = struct {
    pub const accessor = std.EnumSet(Accessor).initEmpty();
    pub fn action(handler: Handler, req: *httpz.Request, res: *httpz.Response) !void {
        _ = handler;
        _ = req;
        _ = res;
    }
};

pub usingnamespace @import("types.zig");
const std = @import("std");
const TypeUtils = @import("type-utils");
const RBAC = @import("rbac");
const httpz = @import("httpz");
const Handler = @import("../../handler.zig");
const Types = @import("types.zig");

pub const name = "account";
pub const path = "/account";

pub const other_routes = @import("other-routes.zig");
pub const field_access = @import("field-access.zig");
pub const record_access = @import("record-access.zig");

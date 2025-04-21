const std = @import("std");
const Utils = @import("utils");
const EnvVar = Utils.EnvVar;

const Self = @This();

const env = enum {
    APP_ENV,
    DB_NAME,
    DB_USERNAME,
    DB_PASSWORD,
    ACCESS_TOKEN_SECRET,
    REFRESH_TOKEN_SECRET,
    XA_APP_SECRET_KEY,
    XA_APP_ID,
    SERVER_PORT,
};

pub fn init() !void {
    inline for (std.meta.fields(env)) |f| {
        const found = EnvVar.get(f.name) catch null;
        if (found == null) {
            @panic("Environment not found: " ++ f.name);
        }
    }
}

pub fn get(tag: env) []const u8 {
    const result = EnvVar.get(@tagName(tag)) catch null;
    return result.?;
}

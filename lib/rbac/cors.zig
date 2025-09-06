const std = @import("std");
const httpz = @import("httpz");

pub const Config = struct {
    origins: []const u8 = "",
    allow_creds: bool = false,
    headers: ?[]const u8 = null,
    methods: ?[]const u8 = null,
    max_age: ?[]const u8 = null,
};

origins: []const u8,
allow_creds: bool = false,
headers: ?[]const u8 = null,
methods: ?[]const u8 = null,
max_age: ?[]const u8 = null,

const Cors = @This();

pub fn init(config: Config) !Cors {
    // origins must have scheme and domain
    return .{
        .origins = config.origins,
        .allow_creds = config.allow_creds,
        .headers = config.headers,
        .methods = config.methods,
        .max_age = config.max_age,
    };
}

pub fn execute(self: *const Cors, req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
    const client_origin = req.header("origin") orelse req.header("referer");
    var found: ?[]const u8 = null;

    if (client_origin != null) {
        var itr = std.mem.splitAny(u8, self.origins, ", ");
        while (itr.next()) |origin| {
            const allowed_origin_uri = try std.Uri.parse(origin);
            const client_origin_uri = try std.Uri.parse(client_origin.?);
            if (client_origin_uri.host == null) continue;
            if (!std.ascii.eqlIgnoreCase(client_origin_uri.host.?.percent_encoded, allowed_origin_uri.host.?.percent_encoded)) continue;
            if (!std.ascii.eqlIgnoreCase(allowed_origin_uri.scheme, client_origin_uri.scheme)) continue;
            if (allowed_origin_uri.port != client_origin_uri.port) continue;
            found = client_origin;
            break;
        }
    }

    if (found != null) res.header("Access-Control-Allow-Origin", found.?);
    if (self.allow_creds) res.header("Access-Control-Allow-Credentials", "true");
    res.header("Access-Control-Allow-Private-Network", "true");

    if (self.headers) |headers| {
        res.header("Access-Control-Allow-Headers", headers);
    }
    if (self.methods) |methods| {
        res.header("Access-Control-Allow-Methods", methods);
    }
    if (self.max_age) |max_age| {
        res.header("Access-Control-Max-Age", max_age);
    }
    res.status = 204;
    if (req.method != .OPTIONS) {
        return executor.next();
    }

    const mode = req.header("sec-fetch-mode") orelse {
        return executor.next();
    };

    if (std.mem.eql(u8, mode, "cors") == false) {
        return executor.next();
    }
}

test Cors {
    @panic("TODO: Cors middleware");
    // Specs
    // All origins must have a protocol and domain
}

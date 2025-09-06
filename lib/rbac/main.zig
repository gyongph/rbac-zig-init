const std = @import("std");
const pg = @import("pg");
const httpz = @import("httpz");
const Utils = @import("utils");
const TypeUtils = @import("type-utils");
const Cors = @import("cors.zig");
const AppConfig = struct {
    port: u64,
    cors: Cors.Config,
};
pub fn App(comptime H: type) type {
    if (!@hasDecl(H, "Role")) @compileError("Handler missing declaration: Role");
    if (!@hasField(H, "pg_pool")) @compileError("Handler missing field: pg_pool");

    return struct {
        _server: httpz.Server(H),
        cors: ?Cors.Config,
        pub fn listen(self: *@This()) !void {
            defer {
                // clean shutdown, finishes serving any live request
                self._server.stop();
                self._server.deinit();
            }
            std.log.info("Server is listening on port {?}", .{self._server.config.port});
            try self._server.listen();
        }
        pub fn register(self: *@This(), module: type) !void {
            try self._register(module, "");
        }
        fn _register(self: *@This(), module: type, comptime parent_path: []const u8) !void {
            if (!@hasDecl(module, "name")) @compileError("Module missing declaration: name");
            if (!@hasDecl(module, "path")) @compileError("Module missing declaration: path");
            if (!@hasDecl(module, "field_access")) @compileError("Module missing declaration: field_access");
            if (!@hasDecl(module, "Schema")) @compileError("Module missing declaration: Schema");
            if (!@hasDecl(module, "SchemaField")) @compileError("Module missing declaration: SchemaField");
            if (!@hasDecl(module, "Accessor")) @compileError("Module missing declaration: Accessor");
            if (!@hasDecl(module.Accessor, "get")) @compileError("Module missing declaration: Accessor.get");
            if (!@hasDecl(module, "record_access")) @compileError("Module missing declaration: record_access");
            const OptionalFieldsSchema = TypeUtils.Partial(module.Schema);
            const path = parent_path ++ @as([]const u8, module.path);
            const router = try self._server.router(.{ .middlewares = if (self.cors != null) &.{try self._server.middleware(Cors, self.cors.?)} else &.{} });
            var group = router.group(path, .{});

            const getByIdHandler = struct {
                pub fn action(handler: H, req: *httpz.Request, res: *httpz.Response) !void {
                    const req_query = try req.query();
                    const id = req.param(module.name ++ "_id").?;
                    const return_fields = req_query.get("return_fields");
                    const accessor = try module.Accessor.get(handler, req, res);
                    const field_access = module.field_access;
                    const field_acccess_member = @typeInfo(field_access).@"struct".decls;
                    const read_access: std.EnumSet(module.SchemaField) = blk: {
                        inline for (field_acccess_member) |member| {
                            if (std.mem.eql(u8, member.name, @tagName(accessor))) {
                                const policy = @field(field_access, member.name);
                                if (!@hasDecl(policy, "read")) @compileError(module.name ++ " module's field access policy for " ++ member.name ++ " accessor doesn't have read declaration");
                                if (@TypeOf(policy.read) == std.EnumSet(module.SchemaField))
                                    break :blk policy.read
                                else {
                                    const getReadPolicy: *const fn (H, *httpz.Request, *httpz.Response) anyerror!std.EnumSet(module.SchemaField) = policy.read;
                                    break :blk try getReadPolicy(handler, req);
                                }
                            }
                        }
                        break :blk std.EnumSet(module.SchemaField).initEmpty();
                    };
                    const no_allowed_fields = read_access.bits.mask == 0;
                    if (no_allowed_fields) {
                        res.status = HTTPStatus.code(.unauthorized);
                        return;
                    }

                    const query = blk: {
                        var columns = std.ArrayList([]const u8).init(req.arena);
                        defer columns.deinit();
                        inline for (std.meta.fields(module.Schema)) |f| {
                            const selected = field_check: {
                                if (return_fields) |rf| {
                                    var itr = std.mem.splitSequence(u8, rf, ",");
                                    while (itr.next()) |field_name| {
                                        if (std.mem.eql(u8, field_name, "")) continue;
                                        const tag = std.meta.stringToEnum(module.SchemaField, field_name) orelse {
                                            res.status = HTTPStatus.code(.bad_request);
                                            try res.json(.{ .@"error" = try std.fmt.allocPrint(req.arena, "Unknown field: {s}", .{field_name}) }, .{});
                                            return;
                                        };
                                        if (std.mem.eql(u8, field_name, f.name)) {
                                            if (read_access.contains(tag))
                                                break :field_check true;
                                            res.status = HTTPStatus.code(.unauthorized);
                                            try res.json(.{ .@"error" = "No read access for field: " ++ f.name }, .{});
                                            return;
                                        }
                                    }
                                    break :field_check false;
                                }
                                break :field_check true;
                            };

                            if (selected) {
                                const tag = std.meta.stringToEnum(module.SchemaField, f.name).?;
                                if (read_access.contains(tag)) {
                                    const base_type = Utils.BaseType.get(f.type);
                                    switch (base_type) {
                                        []u8, []const u8 => try columns.append(f.name ++ "::TEXT"),
                                        [][]u8, [][]const u8 => try columns.append(f.name ++ "::TEXT[]"),
                                        else => try columns.append(f.name),
                                    }
                                }
                            }
                        }
                        const stringed_columns = try std.mem.join(req.arena, ", ", columns.items);
                        defer req.arena.free(stringed_columns);
                        break :blk try std.fmt.allocPrint(req.arena, "SELECT {s} FROM \"{s}\" WHERE id = $1", .{ stringed_columns, module.name });
                    };

                    const pg_pool: *pg.Pool = handler.pg_pool;
                    var conn = try pg_pool.acquire();
                    defer conn.release();
                    const result = conn.queryOpts(
                        query,
                        .{id},
                        .{ .column_names = true },
                    ) catch |err| {
                        if (conn.err) |pg_err| {
                            std.log.warn("get failure: {s}", .{pg_err.message});
                        }
                        return err;
                    };
                    defer result.deinit();
                    var mapper = result.mapper(OptionalFieldsSchema, .{ .allocator = req.arena });
                    res.status = 404;
                    if (try mapper.next()) |data| {
                        res.status = 200;
                        try res.json(data, .{ .emit_null_optional_fields = false });
                    }
                    std.log.info("{s}", .{query});
                }
            };

            const updateByIdHandler = struct {
                pub fn action(handler: H, req: *httpz.Request, res: *httpz.Response) !void {
                    const id = req.param(module.name ++ "_id").?;
                    const accessor = try module.Accessor.get(handler, req, res);
                    const field_access = module.field_access;
                    const field_acccess_member = @typeInfo(field_access).@"struct".decls;
                    const update_access: ?std.EnumSet(module.SchemaField) = blk: {
                        inline for (field_acccess_member) |member| {
                            if (std.mem.eql(u8, member.name, @tagName(accessor))) {
                                const policy = @field(field_access, member.name);
                                if (!@hasDecl(policy, "update")) @compileError(module.name ++ " module's field access policy for " ++ member.name ++ " accessor doesn't have update declaration");
                                if (@TypeOf(policy.update) == std.EnumSet(module.SchemaField))
                                    break :blk policy.update
                                else {
                                    const getUpdatePolicy: *const fn (H, *httpz.Request) anyerror!std.EnumSet(module.SchemaField) = policy.update;
                                    break :blk try getUpdatePolicy(handler, req);
                                }
                            }
                        }
                        break :blk null;
                    };
                    const no_update_access = update_access == null;
                    const no_allowed_fields = if (no_update_access) true else update_access.?.bits.mask == 0;
                    if (no_update_access or no_allowed_fields) {
                        res.status = HTTPStatus.code(.unauthorized);
                        return error.unauthorized;
                    }

                    const maybe_payload = try req.jsonObject();
                    if (maybe_payload == null) return;

                    const selected_fields = maybe_payload.?;
                    const selected_fields_count = selected_fields.count();
                    const keys = selected_fields.keys();
                    const values = selected_fields.values();
                    var args_list = std.ArrayList(u8).init(req.arena);
                    const arg_writer = args_list.writer();
                    var col_list = std.ArrayList(u8).init(req.arena);
                    defer col_list.deinit();
                    const col_writer = col_list.writer();
                    var arg_count: u64 = 1;
                    defer args_list.deinit();

                    // check if the field with an enum type or a slice of an enum type
                    // has a valid value
                    inline for (std.meta.fields(module.Schema)) |sf| {
                        const field_name = sf.name;
                        const field_type = sf.type;
                        const field_info = @typeInfo(Utils.BaseType.get(field_type));
                        const val = selected_fields.get(field_name);
                        if (val != null) {
                            if (field_info == .@"enum" and val.? == .string) {
                                const tag = std.meta.stringToEnum(field_type, val.?.string);
                                if (tag == null) {
                                    return error.unmet_enum;
                                }
                            } else if (field_info == .pointer and field_info.pointer.size == .slice and @typeInfo(field_info.pointer.child) == .@"enum") {
                                if (val.? != .array) return error.invalid_type;
                                if (val.?.array.items.len > 0) {
                                    for (val.?.array.items) |av| {
                                        if (av != .string) return error.invalid_type;
                                        const tag = std.meta.stringToEnum(field_info.pointer.child, av.string);
                                        if (tag == null) {
                                            return error.unmet_enum;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    for (keys, 0..) |field_name, i| {
                        const payload_value = values[i];
                        const field_tag = std.meta.stringToEnum(module.SchemaField, field_name);
                        if (field_tag == null) {
                            res.status = 500;
                            std.log.info("{s}", .{field_name});
                            try res.json(.{
                                .message = "Bad Request",
                                .details = try std.fmt.allocPrint(req.arena, "Unknown field: {s}", .{field_name}),
                            }, .{});
                            return error.unknown_field;
                        }
                        const last_item = i == selected_fields_count - 1;
                        if (!update_access.?.contains(field_tag.?)) return error.unauthorized;
                        _ = try arg_writer.write(field_name);
                        _ = try arg_writer.write("=");
                        switch (payload_value) {
                            .array => |v| {
                                if (v.items.len == 0) {
                                    try std.fmt.format(arg_writer, "'{{}}'", .{});
                                    arg_count = arg_count - 1; // we already provided the value and no need for binding;
                                } else switch (v.items[0]) {
                                    .string => try std.fmt.format(arg_writer, "${d}::TEXT[]", .{arg_count}),
                                    .bool => try std.fmt.format(arg_writer, "${d}::BOOL[]", .{arg_count}),
                                    .float => try std.fmt.format(arg_writer, "${d}::FLOAT[]", .{arg_count}),
                                    .integer => try std.fmt.format(arg_writer, "${d}::BIGINT[]", .{arg_count}),
                                    else => {},
                                }
                                _ = try col_writer.write(field_name);
                            },
                            .string => {
                                try std.fmt.format(arg_writer, "${d}", .{arg_count});
                                _ = try col_writer.write(field_name);
                                _ = try col_writer.write("::TEXT");
                            },
                            else => {
                                try std.fmt.format(arg_writer, "${d}", .{arg_count});
                                _ = try col_writer.write(field_name);
                            },
                        }

                        if (!last_item) {
                            _ = try arg_writer.write(", ");
                            _ = try col_writer.write(", ");
                        }
                        arg_count = arg_count + 1;
                    }

                    var query = std.ArrayList(u8).init(req.arena);
                    defer query.deinit();

                    const query_writer = query.writer();
                    try query_writer.print("update \"{s}\" set {s} where id = ${d}::TEXT returning {s}", .{ module.name, args_list.items, arg_count, col_list.items });

                    const conn = try handler.pg_pool.acquire();
                    defer conn.release();
                    var stmt = try pg.Stmt.init(conn, .{
                        .allocator = req.arena,
                        .column_names = true,
                    });

                    errdefer stmt.deinit();
                    stmt.prepare(query.items, req.arena) catch |err| {
                        if (conn.err) |pg_err| {
                            res.status = 400;
                            try res.json(.{
                                .code = pg_err.code,
                                .message = pg_err.message,
                                .detail = pg_err.detail,
                                .constraint = pg_err.constraint,
                            }, .{});
                            std.log.warn("Failed stmt preparation: {s}", .{pg_err.message});
                        }
                        std.log.info("{}\n", .{err});
                        return;
                    };

                    for (keys, 0..) |field_name, i| {
                        const payload_value = values[i];

                        switch (payload_value) {
                            .array => |array| {
                                // dont deinit until stmt is executed

                                const items = array.items;
                                if (items.len > 0) {
                                    switch (items[0]) {
                                        .string => {
                                            var list = std.ArrayList([]const u8).init(req.arena);
                                            for (items) |val| {
                                                if (val == .string) try list.append(val.string);
                                            }
                                            try stmt.bind(try list.toOwnedSlice());
                                            std.log.info("binded: {s}", .{field_name});
                                        },
                                        .bool => {
                                            var list = std.ArrayList(bool).init(req.arena);
                                            for (items) |val| {
                                                if (val == .bool) try list.append(val.bool);
                                            }
                                            try stmt.bind(try list.toOwnedSlice());
                                        },
                                        .float => {
                                            var list = std.ArrayList(f64).init(req.arena);
                                            for (items) |val| {
                                                if (val == .bool) try list.append(val.float);
                                            }
                                            try stmt.bind(try list.toOwnedSlice());
                                        },
                                        .integer => {
                                            var list = std.ArrayList(i64).init(req.arena);
                                            for (items) |val| {
                                                if (val == .integer) try list.append(val.integer);
                                            }
                                            try stmt.bind(try list.toOwnedSlice());
                                        },
                                        else => unreachable,
                                    }
                                }
                            },
                            .string => try stmt.bind(payload_value.string),
                            .bool => try stmt.bind(payload_value.bool),
                            .float => try stmt.bind(payload_value.float),
                            .integer => try stmt.bind(payload_value.integer),
                            .null => try stmt.bind(null),
                            else => unreachable,
                        }
                    }

                    try stmt.bind(id);

                    const result = stmt.execute() catch |err| {
                        if (conn.err) |pg_err| {
                            res.status = 400;
                            try res.json(.{
                                .code = pg_err.code,
                                .message = pg_err.message,
                                .detail = pg_err.detail,
                                .constraint = pg_err.constraint,
                            }, .{});
                            std.log.warn("update failure: {s}", .{pg_err.message});
                        }
                        std.log.info("{}\n", .{err});
                        return;
                    };
                    var mapper = result.mapper(OptionalFieldsSchema, .{ .allocator = req.arena });
                    res.status = 404; // set default

                    while (try mapper.next()) |data| {
                        res.status = 200;
                        try res.json(data, .{ .emit_null_optional_fields = false });
                    }
                }
            };

            if (@hasDecl(module.record_access, "list")) {
                const listHandler = struct {
                    pub fn action(handler: H, req: *httpz.Request, res: *httpz.Response) anyerror!void {
                        if (!@hasDecl(module.record_access, "list")) return error.not_found;
                        const list_decl = module.record_access.list;
                        if (!list_decl.role.contains(std.meta.activeTag(handler.user))) return error.unauthorized;
                        const action_info = @typeInfo(@TypeOf(list_decl.action));
                        switch (action_info) {
                            .type => {
                                if (!@hasDecl(list_decl.action, "select")) @compileError("Invalid module list handler");
                                if (!@hasDecl(list_decl.action, "where")) @compileError("Invalid module list handler");
                                const query = try req.query();
                                const page = try std.fmt.parseInt(usize, if (query.get("page")) |page| page else "1", 10);
                                const limit = try std.fmt.parseInt(usize, if (query.get("limit")) |limit| limit else "10", 10);

                                try listAction(
                                    handler,
                                    module,
                                    .{
                                        .select = if (@TypeOf(list_decl.action.select) == std.EnumSet(module.SchemaField)) .{
                                            .fields = list_decl.action.select,
                                        } else .{
                                            .raw = list_decl.action.select,
                                        },
                                        .where = list_decl.action.where,
                                        .page = page,
                                        .limit = limit,
                                    },
                                    req,
                                    res,
                                );
                            },
                            .@"fn" => |func| {
                                const payload = @typeInfo(func.return_type.?).error_union.payload;
                                if (payload == ListOptions(module.SchemaField)) {
                                    try listAction(handler, module, try list_decl.action(handler, req), req, res);
                                } else try list_decl.action(handler, req, res);
                            },
                            else => |info| {
                                @compileLog(info);
                                @compileError(module.name ++ " module invalid list handler");
                            },
                        }
                    }
                };
                group.get("", listHandler.action, .{});
                std.log.info("\x1b[32mRoute added:\x1b[m GET " ++ module.path, .{});
            }

            if (@hasDecl(module.record_access, "create")) {
                const createHandler = struct {
                    pub fn action(handler: H, req: *httpz.Request, res: *httpz.Response) !void {
                        if (!@hasDecl(module.record_access, "create")) {
                            res.status = HTTPStatus.code(.not_found);
                            return error.not_found;
                        }
                        if (!module.record_access.create.role.contains(std.meta.activeTag(handler.user)))
                            return error.unauthorized;
                        try module.record_access.create.action(handler, req, res);
                    }
                };
                group.post("", createHandler.action, .{});
                std.log.info("\x1b[32mRoute added:\x1b[m POST " ++ module.path, .{});
            }

            if (@hasDecl(module.record_access, "delete")) {
                const deleteHandler = struct {
                    pub fn action(handler: H, req: *httpz.Request, res: *httpz.Response) !void {
                        if (!@hasDecl(module.record_access, "delete")) {
                            res.status = HTTPStatus.code(.not_found);
                            return error.not_found;
                        }
                        const accessor = try module.Accessor.get(handler, req, res);
                        if (!module.record_access.delete.accessor.contains(accessor))
                            return error.unauthorized;
                        try module.record_access.delete.action(handler, req, res);
                    }
                };
                group.delete("", deleteHandler.action, .{});
                std.log.info("\x1b[32mRoute added:\x1b[m DELETE " ++ module.path, .{});
            }

            // REGISTER CRUD ROUTES
            group.get("/:" ++ module.name ++ "_id", getByIdHandler.action, .{});
            std.log.info("\x1b[32mRoute added:\x1b[m GET " ++ path ++ "/:" ++ module.name ++ "_id", .{});
            group.patch("/:" ++ module.name ++ "_id", updateByIdHandler.action, .{});
            std.log.info("\x1b[32mRoute added:\x1b[m PATCH " ++ path ++ "/:" ++ module.name ++ "_id", .{});

            if (@hasDecl(module, "other_routes")) {
                std.log.info("Adding module's other routes..", .{});
                const other_routes = comptime parseOtherRoutes(H, module.other_routes);
                inline for (other_routes) |route| {
                    switch (route.method) {
                        .GET => group.get(route.path, route.createAction().action, .{}),
                        .PATCH => group.patch(route.path, route.createAction().action, .{}),
                        .POST => group.post(route.path, route.createAction().action, .{}),
                        .PUT => group.put(route.path, route.createAction().action, .{}),
                        .DELETE => group.delete(route.path, route.createAction().action, .{}),
                        .OPTIONS => group.options(route.path, route.createAction().action, .{}),
                        .CONNECT => group.connect(route.path, route.createAction().action, .{}),
                        else => {},
                    }
                    std.log.info("\x1b[32mRoute added:\x1b[m {s} {s}{s}", .{ @tagName(route.method), path, route.path });
                }
            }
            if (@hasDecl(module, "sub_modules")) {
                const sub_modules: []const type = module.sub_modules;
                inline for (sub_modules) |sub_mod| {
                    const parent_mod_path = module.path ++ "/:" ++ module.name ++ "_id";
                    try self._register(sub_mod, parent_mod_path);
                }
            }
            std.log.info("\x1b[1m\x1b[38;2;107;217;255m{s} module registered.\x1b[m", .{module.name});
        }
    };
}
pub fn init(handler: anytype, alloc: std.mem.Allocator, server_config: httpz.Config, cors_config: ?Cors.Config) !App(@TypeOf(handler)) {
    return .{
        ._server = try .init(alloc, server_config, handler),
        .cors = cors_config,
    };
}

pub fn Route(H: type) type {
    return struct {
        method: httpz.Method,
        allowed_role: std.EnumSet(H.Role),
        action: httpz.Action(H),
        path: []const u8,
        pub fn createAction(comptime self: @This()) type {
            const wrapper = struct {
                const role = self.allowed_role;
                const _action = self.action;
                pub fn action(handler: H, req: *httpz.Request, res: *httpz.Response) anyerror!void {
                    if (role.contains(std.meta.activeTag(handler.user))) {
                        try _action(handler, req, res);
                    } else {
                        res.status = HTTPStatus.unauthorized.code();
                        return;
                    }
                }
            };
            return wrapper;
        }
    };
}

fn parseOtherRoutes(H: type, routes_module: type) [countValidRoutes(H, routes_module)]Route(H) {
    var routes: [countValidRoutes(H, routes_module)]Route(H) = undefined;
    var count: usize = 0;
    for (std.meta.declarations(routes_module)) |decls| {
        const field = @field(routes_module, decls.name);
        if (!@hasDecl(field, "action")) continue;
        var itr = std.mem.splitSequence(u8, decls.name, ": ");
        const method_string = itr.next() orelse @compileError("Invalid path: " ++ decls.name);
        const method = std.meta.stringToEnum(httpz.Method, method_string) orelse @compileError("Unknown http method: \"" ++ method_string);
        const path = itr.next() orelse @compileError("Missing route's path");
        if (!@hasDecl(field, "allowed_role")) @compileError("Route [" ++ path ++ "] has a missing allowed_role declaration.");
        routes[count] = .{
            .method = method,
            .path = path,
            .allowed_role = field.allowed_role,
            .action = field.action,
        };
        count += 1;
    }
    return routes;
}

fn countValidRoutes(H: type, routes_module: type) usize {
    var count: usize = 0;
    for (std.meta.declarations(routes_module)) |decls| {
        const field = @field(routes_module, decls.name);
        if (!@hasDecl(field, "action")) continue;
        _ = @as(httpz.Action(H), field.action); // check type;
        count += 1;
    }
    return count;
}

pub fn ListOptions(field_enum: type) type {
    return struct {
        pub const SelectOption = enum { fields, raw };
        pub const Select = union(SelectOption) {
            fields: std.EnumSet(field_enum),
            raw: []const u8,
        };
        select: Select,
        from: ?[]const u8 = null,
        where: []const u8,
        page: u64 = 1,
        limit: u64 = 10,
    };
}

pub fn listAction(
    handler: anytype,
    module: type,
    options: ListOptions(module.SchemaField),
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    const allocator = req.arena;
    if (options.where.len == 0) @panic("[where] field is empty");
    const select = switch (options.select) {
        .fields => |f| blk: {
            if (f.bits.mask == 0) @panic("Empty selected_fields, must have at least one");
            var fields = std.ArrayList([]const u8).init(allocator);
            defer fields.deinit();
            inline for (std.meta.fields(module.Schema)) |sch_field| {
                const tag = std.meta.stringToEnum(module.SchemaField, sch_field.name).?;
                if (f.contains(tag)) {
                    const base_type = Utils.BaseType.get(sch_field.type);
                    switch (base_type) {
                        []u8, []const u8 => try fields.append(sch_field.name ++ "::TEXT"),
                        [][]u8, [][]const u8 => try fields.append(sch_field.name ++ "::TEXT[]"),
                        else => try fields.append(sch_field.name),
                    }
                }
            }
            break :blk try std.mem.join(allocator, ",", fields.items);
        },
        .raw => |f| blk: {
            if (f.len == 0) @panic("[select.raw] field is empty");
            break :blk f;
        },
    };

    const page = if (options.page < 1) 1 else options.page;
    const limit = if (options.limit < 1) 10 else options.limit;

    const conn = try handler.pg_pool.acquire();
    defer conn.release();
    const total_count = blk: {
        const row = conn.query(
            try std.fmt.allocPrint(req.arena, "SELECT COUNT(*)::BIGINT FROM \"{s}\" where {s}", .{ options.from orelse module.name, options.where }),
            .{},
        ) catch {
            if (conn.err) |pg_err| {
                res.status = 400;

                try res.json(.{
                    .code = pg_err.code,
                    .message = pg_err.message,
                    .detail = pg_err.detail,
                    .constraint = pg_err.constraint,
                }, .{});
            }
            return; // end request
        };
        defer row.deinit();
        const row_1 = try row.next();
        try row.drain();
        break :blk row_1.?.get(i64, 0);
    };

    const results = conn.queryOpts(
        try std.fmt.allocPrint(req.arena, "SELECT {s} from \"{s}\" WHERE {s} limit $1 OFFSET ($2 - 1) * $1", .{ select, options.from orelse module.name, options.where }),
        .{ limit, page },
        .{ .column_names = true },
    ) catch {
        if (conn.err) |pg_err| {
            res.status = 400;

            try res.json(.{
                .code = pg_err.code,
                .message = pg_err.message,
                .detail = pg_err.detail,
                .constraint = pg_err.constraint,
            }, .{});
        }
        return; // end request
    };
    defer results.deinit();

    var mapper = results.mapper(TypeUtils.Partial(module.Schema), .{ .allocator = allocator, .dupe = true });
    var list = std.ArrayList(TypeUtils.Partial(module.Schema)).init(req.arena);
    defer list.deinit();
    while (try mapper.next()) |item| {
        try list.append(item);
    }

    res.status = 200;
    try res.json(.{
        .page = page,
        .total_pages = try std.math.divCeil(u64, @as(u64, @intCast(total_count)), limit),
        .limit = limit,
        .total_count = total_count,
        .items = list.items,
    }, .{ .emit_null_optional_fields = false });
}

pub const HTTPStatus = enum(u16) {
    pub fn code(status: HTTPStatus) u16 {
        return @intFromEnum(status);
    }
    invalid_http_code,
    continue_ = 100,
    switching_protocols = 101,
    processing = 102,
    early_hints = 103,

    ok = 200,
    created = 201,
    accepted = 202,
    non_authoritative_information = 203,
    no_content = 204,
    reset_content = 205,
    partial_content = 206,
    multi_status = 207,
    already_reported = 208,
    im_used = 226,

    multiple_choices = 300,
    moved_permanently = 301,
    found = 302,
    see_other = 303,
    not_modified = 304,
    use_proxy = 305,
    temporary_redirect = 307,
    permanent_redirect = 308,

    bad_request = 400,
    unauthorized = 401,
    payment_required = 402,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    not_acceptable = 406,
    proxy_authentication_required = 407,
    request_timeout = 408,
    conflict = 409,
    gone = 410,
    length_required = 411,
    precondition_failed = 412,
    payload_too_large = 413,
    uri_too_long = 414,
    unsupported_media_type = 415,
    range_not_satisfiable = 416,
    expectation_failed = 417,
    im_a_teapot = 418,
    misdirected_request = 421,
    unprocessable_entity = 422,
    locked = 423,
    failed_dependency = 424,
    too_early = 425,
    upgrade_required = 426,
    precondition_required = 428,
    too_many_requests = 429,
    request_header_fields_too_large = 431,
    unavailable_for_legal_reasons = 451,

    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,
    http_version_not_supported = 505,
    variant_also_negotiates = 506,
    insufficient_storage = 507,
    loop_detected = 508,
    not_extended = 510,
    network_authentication_required = 511,
};

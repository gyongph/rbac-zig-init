const std = @import("std");

const FieldType = enum { string, numeric, boolean, enum_set, array, object };

fn EnumSetConfig(t: type) type {
    return struct {
        set: std.EnumSet(t),
        default: ?t = null,
        optional: bool = false,
    };
}
pub fn EnumSet(t: type, config: EnumSetConfig(t)) type {
    return struct {
        const tag = FieldType.enum_set;
        const field_type = if (config.optional) ?t else t;
        const set = config.set;
        const default = config.default;
        const optional = config.optional;
    };
}

const StringConfig = struct {
    min: ?usize = null,
    max: ?usize = null,
    min_err_msg: ?[]const u8 = null,
    max_err_msg: ?[]const u8 = null,
    default: ?[]const u8 = null,
    optional: bool = false,
};

pub fn String(config: StringConfig) type {
    return struct {
        const tag = FieldType.string;
        const field_type = if (config.optional or config.default != null) ?[]const u8 else []const u8;
        const min = config.min;
        const max = config.max;
        const min_err_msg = config.min_err_msg;
        const max_err_msg = config.max_err_msg;
        const default = config.default;
    };
}

fn NumericConfig(num_type: type) type {
    const optional_type = if (@typeInfo(num_type) == .optional) num_type else ?num_type;
    return struct {
        min: optional_type = null,
        max: optional_type = null,
        min_err_msg: ?[]const u8 = null,
        max_err_msg: ?[]const u8 = null,
        default: optional_type = null,
    };
}

pub fn Numeric(num_type: type, config: NumericConfig(num_type)) type {
    return struct {
        const tag = FieldType.numeric;
        const field_type = if (@typeInfo(num_type) == .optional and config.default != null) std.meta.Child(num_type) else num_type;
        const min = config.min;
        const max = config.max;
        const min_err_msg = config.min_err_msg;
        const max_err_msg = config.max_err_msg;
        const default = config.default;
    };
}

const BooleanConfig = struct {
    default: ?bool = null,
    optional: bool = false,
};

pub fn Boolean(config: BooleanConfig) type {
    return struct {
        const tag = FieldType.boolean;
        const field_type = if (config.optional or config.default != null) ?bool else bool;
        const default = config.default;
    };
}

fn ArrayConfig(item_type: type) type {
    return struct {
        min: ?usize = null,
        max: ?usize = null,
        min_err_msg: ?[]const u8 = null,
        max_err_msg: ?[]const u8 = null,
        default: ?[]const item_type.field_type = null,
        optional: ?bool = false,
    };
}

pub fn Array(child: type, config: ArrayConfig(child)) type {
    return struct {
        const tag = FieldType.array;
        const field_type = if (config.optional == true) ?[]const child.field_type else []const child.field_type;
        const child_schema = child;
        const min = config.min;
        const max = config.max;
        const min_err_msg = config.min_err_msg;
        const max_err_msg = config.max_err_msg;
        const default = config.default;
    };
}

fn Validation(comptime schema_type: type) type {
    return struct {
        pub const inferred_type = _infer(schema_type);
        const FieldError = struct {
            name: []const u8,
            message: []const u8,
        };
        const Self = @This();
        field_error: ?FieldError = null,

        pub fn validate(self: *Self, payload: inferred_type, alloc: ?std.mem.Allocator) anyerror!inferred_type {
            var new: inferred_type = undefined;
            const schema_fields = std.meta.fields(schema_type);
            inline for (schema_fields) |f| {
                @field(new, f.name) = try checkField(self, @field(payload, f.name), f.type, f.name, alloc);
            }
            return new;
        }

        fn checkField(self: *Self, field_val: anytype, comptime schema_field: type, field_name: []const u8, alloc: ?std.mem.Allocator) !schema_field.field_type {
            const schema_field_type = schema_field.field_type;
            const is_optional = @typeInfo(schema_field_type) == .optional;
            switch (schema_field.tag) {
                .array, .string => {
                    if ((!is_optional or is_optional and field_val != null) and (schema_field.min != null or schema_field.max != null)) {
                        try checkArrayLength(
                            self,
                            field_val,
                            schema_field,
                            field_name,
                            is_optional,
                        );
                    }
                    if (schema_field.tag == .array and (!is_optional or field_val != null)) {
                        const non_null_val = if (is_optional) field_val.? else field_val;
                        const new_items = try checkArrayItems(self, non_null_val, schema_field.child_schema, field_name, alloc);
                        return new_items orelse field_val;
                    } else return field_val;
                },
                .numeric => {
                    if ((is_optional and field_val == null) or (schema_field.min == null and schema_field.max == null)) {
                        return field_val;
                    } else if (schema_field.min != null) {
                        const value = if (is_optional) field_val.? else field_val;
                        if (value < schema_field.min.?) {
                            self.field_error = .{
                                .name = field_name,
                                .message = schema_field.min_err_msg orelse "Falls below the minimum of " ++ std.fmt.comptimePrint("{d}", .{schema_field.min.?}),
                            };
                            return error.invalid_payload;
                        }
                    } else if (schema_field.max != null) {
                        const value = if (is_optional) field_val.? else field_val;
                        if (value > schema_field.max.?) {
                            self.field_error = .{
                                .name = field_name,
                                .message = schema_field.max_err_msg orelse "Exceeds the maximum of " ++ std.fmt.comptimePrint("{d}", .{schema_field.max.?}),
                            };
                            return error.invalid_payload;
                        }
                    }
                    return field_val;
                },
                .enum_set => {
                    const set = schema_field.set;
                    if (is_optional and (field_val == null or set.contains(field_val.?))) return field_val;
                    if (!is_optional and set.contains(field_val)) return field_val;
                    self.field_error = .{ .name = field_name, .message = "Enum set didn't contain provided value" };
                    return error.invalid_payload;
                },
                .object => {
                    var validator = schema_field.validator();
                    const validated = validator.validate(field_val, alloc) catch {
                        self.field_error = validator.field_error;
                        return error.invalid_payload;
                    };
                    return validated;
                },
                .boolean => return field_val,
            }
        }

        fn checkArrayItems(self: *Self, items: anytype, item_schema: type, field_name: []const u8, alloc: ?std.mem.Allocator) !?[]const item_schema.field_type {
            var new_items = if (alloc != null) std.ArrayList(item_schema.field_type).init(alloc.?) else null;
            for (items) |item| {
                const new_value = try checkField(self, item, item_schema, field_name, alloc);
                if (new_items != null) {
                    if ((@typeInfo(item_schema.field_type) != .optional or new_value != null) and item_schema.default != null) {
                        try new_items.?.append(item_schema.default.?);
                    } else {
                        try new_items.?.append(new_value);
                    }
                }
            }
            if (new_items != null) return try new_items.?.toOwnedSlice() else return items;
        }

        fn checkArrayLength(
            self: *Self,
            val: anytype,
            field_schema: anytype,
            field_name: []const u8,
            comptime is_optional: bool,
        ) !void {
            if (field_schema.min != null) {
                const length = if (is_optional) val.?.len else val.len;
                if (length < field_schema.min.?) {
                    self.field_error = .{
                        .name = field_name,
                        .message = field_schema.min_err_msg orelse "Falls below the minimum length of " ++ std.fmt.comptimePrint("{d}", .{field_schema.min.?}),
                    };
                    return error.invalid_payload;
                }
            }
            if (field_schema.max != null) {
                const length = if (is_optional) val.?.len else val.len;
                if (length > field_schema.max.?) {
                    self.field_error = .{
                        .name = field_name,
                        .message = field_schema.max_err_msg orelse "Exceeds maximum length of " ++ std.fmt.comptimePrint("{d}", .{field_schema.max.?}),
                    };
                    return error.invalid_payload;
                }
            }
        }
    };
}

fn _infer(schema_type: type) type {
    const st_fields = std.meta.fields(schema_type);
    var fields: [st_fields.len]std.builtin.Type.StructField = undefined;
    inline for (st_fields, 0..) |f, i| {
        const field_type = f.type.field_type;
        const default = f.type.default;
        fields[i] = .{
            .name = f.name,
            .type = field_type,
            .default_value_ptr = if (@typeInfo(field_type) == .optional) @as(*const anyopaque, @ptrCast(&default)) else if (@typeInfo(field_type) == .optional and default != null) @as(*const anyopaque, @ptrCast(&default.?)) else null,
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}
fn ObjectConfig(t: type) type {
    return struct {
        default: ?_infer(t) = null,
    };
}
pub fn Object(t: type, config: ObjectConfig(t)) type {
    return struct {
        const tag = FieldType.object;
        const field_type = _infer(t);
        const default: ?field_type = config.default;
        pub fn validator() Validation(t) {
            return .{};
        }
    };
}

pub fn schema(t: type) type {
    return struct {
        pub fn validator() Validation(t) {
            return .{};
        }
        pub fn infer() type {
            return _infer(t);
        }
    };
}

test String {
    { //check defaults
        const name_field = String(.{});
        try std.testing.expect(name_field.min == null);
        try std.testing.expect(name_field.max == null);
        try std.testing.expect(name_field.tag == .string);
        try std.testing.expect(name_field.default == null);
        try std.testing.expect(name_field.field_type == []const u8);
    }

    { //with settings
        const name_field = String(.{
            .min = 1,
            .max = 25,
            .min_err_msg = "min custom error msg",
            .max_err_msg = "max custom error msg",
            .default = "asgard",
        });
        try std.testing.expect(name_field.min.? == 1);
        try std.testing.expect(name_field.max.? == 25);
        try std.testing.expect(name_field.tag == .string);
        try std.testing.expect(name_field.field_type == ?[]const u8);
        try std.testing.expectEqualStrings(name_field.default.?, "asgard");
        try std.testing.expectEqualStrings(name_field.min_err_msg.?, "min custom error msg");
        try std.testing.expectEqualStrings(name_field.max_err_msg.?, "max custom error msg");
    }

    { // in struct with default value
        const sample_schema = schema(struct {
            name: String(.{
                .min = 1,
                .max = 25,
                .default = "asgard",
            }),
        });
        const instance: sample_schema.infer() = .{};
        try std.testing.expect(@FieldType(sample_schema.infer(), "name") == ?[]const u8);
        try std.testing.expectEqualStrings(instance.name.?, "asgard");
    }

    { // in struct with optional type
        const sample_schema = schema(struct {
            name: String(.{ .optional = true }),
        });
        const instance: sample_schema.infer() = .{};
        try std.testing.expect(@FieldType(sample_schema.infer(), "name") == ?[]const u8);
        try std.testing.expect(instance.name == null);
    }

    { // in struct with defined value
        const sample_schema = schema(struct {
            name: String(.{ .default = "asgard" }),
        });
        const instance: sample_schema.infer() = .{ .name = "no-change" };
        try std.testing.expect(@FieldType(sample_schema.infer(), "name") == ?[]const u8);
        try std.testing.expectEqualStrings(instance.name.?, "no-change");
    }
    { // validation
        const sample_schema = schema(struct {
            username: String(.{
                .min = 5,
                .max = 25,
                .min_err_msg = "custom min error message",
            }),
        });
        const instance: sample_schema.infer() = .{
            .username = "tes1",
        };
        var it_errors = false;
        var validator = sample_schema.validator();
        _ = validator.validate(instance, null) catch {
            try std.testing.expect(validator.field_error != null);
            const field_error = validator.field_error.?;
            try std.testing.expectEqualStrings(field_error.name, "username");
            try std.testing.expectEqualStrings(field_error.message, "custom min error message");
            it_errors = true;
        };
        try std.testing.expect(it_errors);
    }
    { // validation max
        const sample_schema = schema(struct {
            username: String(.{
                .min = 1,
                .max = 5,
                .max_err_msg = "custom max error message",
            }),
        });
        const instance: sample_schema.infer() = .{
            .username = "123456",
        };
        var it_errors = false;
        var validator = sample_schema.validator();
        _ = validator.validate(instance, null) catch {
            try std.testing.expect(validator.field_error != null);
            const field_error = validator.field_error.?;
            try std.testing.expectEqualStrings(field_error.name, "username");
            try std.testing.expectEqualStrings(field_error.message, "custom max error message");
            it_errors = true;
        };
        try std.testing.expect(it_errors);
    }
}

test Array {
    { //default
        const car_brands = Array(String(.{}), .{});
        try std.testing.expect(car_brands.tag == .array);
        try std.testing.expect(car_brands.min == null);
        try std.testing.expect(car_brands.max == null);
        try std.testing.expect(car_brands.default == null);
        try std.testing.expect(car_brands.field_type == []const []const u8);
    }

    { //with settings
        const car_brands = Array(String(.{}), .{
            .min = 1,
            .max = 25,
            .min_err_msg = "min custom error msg",
            .max_err_msg = "max custom error msg",
            .default = &.{"bmw"},
            .optional = true,
        });
        try std.testing.expect(car_brands.min.? == 1);
        try std.testing.expect(car_brands.max.? == 25);
        try std.testing.expectEqual(car_brands.tag, .array);
        try std.testing.expectEqual(car_brands.field_type, ?[]const []const u8);
        try std.testing.expectEqualSlices([]const u8, car_brands.default.?, &.{"bmw"});
        try std.testing.expectEqualStrings(car_brands.min_err_msg.?, "min custom error msg");
        try std.testing.expectEqualStrings(car_brands.max_err_msg.?, "max custom error msg");
    }
    { // min validation
        const sample_schema = schema(struct {
            car_brands: Array(
                String(.{}),
                .{
                    .min = 1,
                    .min_err_msg = "custom min err msg",
                },
            ),
        });
        const instance: sample_schema.infer() = .{
            .car_brands = &.{},
        };
        var it_errors = false;
        var validator = sample_schema.validator();
        _ = validator.validate(instance, null) catch {
            try std.testing.expect(validator.field_error != null);
            const field_error = validator.field_error.?;
            try std.testing.expectEqual("car_brands", field_error.name);
            try std.testing.expectEqual("custom min err msg", field_error.message);
            it_errors = true;
        };
        try std.testing.expect(it_errors);
    }
    { // max validation
        const sample_schema = schema(struct {
            car_brands: Array(
                String(.{}),
                .{
                    .max = 2,
                    .max_err_msg = "custom max err msg",
                },
            ),
        });
        const instance: sample_schema.infer() = .{
            .car_brands = &.{ "1", "2", "3" },
        };
        var it_errors = false;
        var validator = sample_schema.validator();
        _ = validator.validate(instance, null) catch {
            try std.testing.expect(validator.field_error != null);
            try std.testing.expectEqual("car_brands", validator.field_error.?.name);
            try std.testing.expectEqual("custom max err msg", validator.field_error.?.message);
            it_errors = true;
        };
        try std.testing.expect(it_errors);
    }
    { // child min validation
        const sample_err_msg = "car brand item";
        const sample_schema = schema(struct {
            car_brands: Array(
                String(.{ .min = 2, .min_err_msg = sample_err_msg }),
                .{},
            ),
        });
        const instance: sample_schema.infer() = .{
            .car_brands = &.{ "1", "2", "3" },
        };
        var validator = sample_schema.validator();
        _ = validator.validate(instance, null) catch {
            try std.testing.expectEqualStrings(sample_err_msg, validator.field_error.?.message);
        };
    }
}

test Object {
    const OrderItem = schema(struct {
        merchant_id: String(.{}),
        items: Array(Object(
            struct {
                variant_id: String(.{}),
                quantity: Numeric(u64, .{ .min = 1 }),
            },
            .{ .default = null },
        ), .{
            .min = 1,
        }),
    });

    var validator = OrderItem.validator();
    const instance: OrderItem.infer() = .{
        .merchant_id = "69",
        .items = &.{.{ .variant_id = "adsf", .quantity = 0 }},
    };

    const validated = validator.validate(instance, null) catch {
        try std.testing.expectEqualStrings("Falls below the minimum of 1", validator.field_error.?.message);
        try std.testing.expectEqualStrings("quantity", validator.field_error.?.name);
        return;
    };
    std.log.info("{}", .{validated});
}

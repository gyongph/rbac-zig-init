const std = @import("std");
const rand = std.crypto.random;
const fmt = std.fmt;
const testing = std.testing;

pub fn random(T: type, min: T, max: T) T {
    return rand.intRangeAtMost(T, min, max);
}

pub fn toStringAlloc(allocator: std.mem.Allocator, number: usize, comptime _fmt: []const u8) ![]u8 {
    return fmt.allocPrint(allocator, _fmt, .{number});
}

pub fn toString(comptime num: anytype, comptime _fmt: []const u8) *const [fmt.count(_fmt, .{num}):0]u8 {
    return fmt.comptimePrint(_fmt, .{num});
}

pub fn isNumericType(T: type) bool {
    const info = @typeInfo(T);
    switch (info) {
        .optional => |opt| return isNumericType(opt.child),
        .pointer => |ptr| {
            if (ptr.size == .One) return isNumericType(ptr.child);
            return false;
        },
        .comptime_float, .comptime_int, .float, .int => return true,
        else => return false,
    }
}

pub fn isNumeric(val: anytype) bool {
    const T = @TypeOf(val);
    return isNumericType(T);
}

test isNumeric {
    const string = "";
    const no_val = null;
    const b = true;
    const int: u1 = 1;
    const float: f16 = 1;
    const s_int: i16 = -1;
    const comp_int = 1;
    const comp_s_int = -1;
    const comp_float = 0.5;
    try testing.expect(isNumeric(string) == false);
    try testing.expect(isNumeric(no_val) == false);
    try testing.expect(isNumeric(b) == false);
    try testing.expect(isNumeric(int));
    try testing.expect(isNumeric(float));
    try testing.expect(isNumeric(s_int));
    try testing.expect(isNumeric(comp_int));
    try testing.expect(isNumeric(comp_s_int));
    try testing.expect(isNumeric(comp_float));

    const o_string: ?@TypeOf(string) = "";
    const o_int: ?@TypeOf(int) = 1;
    const o_float: ?@TypeOf(float) = 1;
    const o_s_int: ?@TypeOf(s_int) = -1;
    const o_bool: ?@TypeOf(b) = false;
    const o_comp_int: ?@TypeOf(comp_int) = 1;
    const o_comp_s_int: ?@TypeOf(comp_s_int) = -1;
    const o_comp_float: ?@TypeOf(comp_float) = 0.5;
    try testing.expect(isNumeric(o_string) == false);
    try testing.expect(isNumeric(o_bool) == false);
    try testing.expect(isNumeric(o_int));
    try testing.expect(isNumeric(o_float));
    try testing.expect(isNumeric(o_s_int));
    try testing.expect(isNumeric(o_comp_int));
    try testing.expect(isNumeric(o_comp_s_int));
    try testing.expect(isNumeric(o_comp_float));

    const p_string = &string;
    const p_no_val = &no_val;
    const p_int = &int;
    const p_float = &float;
    const p_s_int = &s_int;
    const p_bool = &b;
    const p_comp_int = &comp_int;
    const p_comp_s_int = &comp_s_int;
    const p_comp_float = &comp_float;
    try testing.expect(isNumeric(p_string) == false);
    try testing.expect(isNumeric(p_bool) == false);
    try testing.expect(isNumeric(p_no_val) == false);
    try testing.expect(isNumeric(p_int));
    try testing.expect(isNumeric(p_float));
    try testing.expect(isNumeric(p_s_int));
    try testing.expect(isNumeric(p_comp_int));
    try testing.expect(isNumeric(p_comp_s_int));
    try testing.expect(isNumeric(p_comp_float));

    const p_o_string = &o_string;
    const p_o_int = &o_int;
    const p_o_float = &o_float;
    const p_o_s_int = &o_s_int;
    const p_o_bool = &o_bool;
    const p_o_comp_int = &o_comp_int;
    const p_o_comp_s_int = &o_comp_s_int;
    const p_o_comp_float = &o_comp_float;
    try testing.expect(isNumeric(p_o_string) == false);
    try testing.expect(isNumeric(p_o_bool) == false);
    try testing.expect(isNumeric(p_o_int));
    try testing.expect(isNumeric(p_o_float));
    try testing.expect(isNumeric(p_o_s_int));
    try testing.expect(isNumeric(p_o_comp_int));
    try testing.expect(isNumeric(p_o_comp_s_int));
    try testing.expect(isNumeric(p_o_comp_float));
}

pub fn lowest(t: type, items: []const t) t {
    if (items.len < 2) @compileError("Minimum length is two");
    switch (@typeInfo(t)) {
        .int, .float, .comptime_int, .comptime_float => {
            var _lowest: t = items[0];
            for (items[1..]) |item| {
                if (_lowest > item) _lowest = item;
            }
            return _lowest;
        },
        else => @compileError("Not a number"),
    }
}

pub fn highest(t: type, items: []const t) t {
    if (items.len < 2) @compileError("Minimum length is two");
    switch (@typeInfo(t)) {
        .int, .float, .comptime_int, .comptime_float => {
            var _lowest: t = items[0];
            for (items[1..]) |item| {
                if (_lowest < item) _lowest = item;
            }
            return _lowest;
        },
        else => @compileError("Not a number"),
    }
}

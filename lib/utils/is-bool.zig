const std = @import("std");
const testing = std.testing;
pub fn isBoolType(T: type) bool {
    const info = @typeInfo(T);
    switch (info) {
        .optional => |opt| return isBoolType(opt.child),
        .pointer => |ptr| {
            if (ptr.size == .One) return isBoolType(ptr.child);
            return false;
        },
        .bool => return true,
        else => return false,
    }
}

pub fn isBool(val: anytype) bool {
    const T = @TypeOf(val);
    return isBoolType(T);
}

test isBoolType {
    const string = "";
    const no_val = null;
    const int: u1 = 1;
    const float: f16 = 1;
    const s_int: i16 = -1;
    const b = true;
    try testing.expect(isBool(string) == false);
    try testing.expect(isBool(no_val) == false);
    try testing.expect(isBool(int) == false);
    try testing.expect(isBool(float) == false);
    try testing.expect(isBool(s_int) == false);
    try testing.expect(isBool(b));

    const o_string: ?@TypeOf(string) = "";
    const o_int: ?@TypeOf(int) = 1;
    const o_float: ?@TypeOf(float) = 1;
    const o_s_int: ?@TypeOf(s_int) = -1;
    const o_bool: ?@TypeOf(b) = false;
    try testing.expect(isBool(o_string) == false);
    try testing.expect(isBool(o_int) == false);
    try testing.expect(isBool(o_float) == false);
    try testing.expect(isBool(o_s_int) == false);
    try testing.expect(isBool(o_bool));

    const p_string = &string;
    const p_no_val = &no_val;
    const p_int = &int;
    const p_float = &float;
    const p_s_int = &s_int;
    const p_bool = &b;
    try testing.expect(isBool(p_string) == false);
    try testing.expect(isBool(p_no_val) == false);
    try testing.expect(isBool(p_int) == false);
    try testing.expect(isBool(p_float) == false);
    try testing.expect(isBool(p_s_int) == false);
    try testing.expect(isBool(p_bool));

    const p_o_string = &o_string;
    const p_o_int = &o_int;
    const p_o_float = &o_float;
    const p_o_s_int = &o_s_int;
    const p_o_bool = &o_bool;
    try testing.expect(isBool(p_o_string) == false);
    try testing.expect(isBool(p_o_int) == false);
    try testing.expect(isBool(p_o_float) == false);
    try testing.expect(isBool(p_o_s_int) == false);
    try testing.expect(isBool(p_o_bool));
}

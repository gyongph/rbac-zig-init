const std = @import("std");
const testing = std.testing;

fn getEnumBitPos(T: anytype, S: type) S {
    return std.math.pow(S, 2, @intFromEnum(T));
}

fn _Set(comptime T: type, S: type) type {
    return struct {
        const Self = @This();
        code: S = 0,
        pub fn init(comptime sets: []const T) Self {
            var code: S = 0;
            for (sets) |item| {
                const enum_bit_pos = getEnumBitPos(item, S);
                code |= enum_bit_pos;
            }
            return Self{ .code = code };
        }
        pub fn has(self: Self, t: T) bool {
            const enum_bit_pos = getEnumBitPos(t, S);
            return self.code & enum_bit_pos > 0;
        }
        pub fn remove(self: *Self, t: T) void {
            const enum_bit_pos = getEnumBitPos(t, S);
            self.code &= ~enum_bit_pos;
        }
        pub fn add(self: *Self, t: T) void {
            const enum_bit_pos = getEnumBitPos(t, S);
            self.code |= enum_bit_pos;
        }
    };
}

/// **T** is a an enum type.
///
/// Ex.
/// ```
/// EnumPlus( enum{ Guest, Owner } )
/// ```
pub fn EnumPlus(comptime T: type) type {
    const t_info = @typeInfo(T);
    if (t_info != .@"enum") @compileError("T must be an enum type");
    if (t_info.@"enum".fields.len == 0) @compileError("The provided enum has zero member!");
    if (t_info.@"enum".fields.len > 128) @compileError("The provided enum has a length more than 128! The length of enum cannot be mapped via the maximum size for unsigned integer which is 128.");
    const S: type = GetUnsignedIntegerSize(t_info.@"enum".fields.len);
    return struct {
        const Self = @This();
        pub const Set = _Set(T, S);
        pub const member: type = T;
        pub const size = S;
        pub fn select(comptime e: T) S {
            return getEnumBitPos(e, S);
        }
        pub fn selectMany(comptime e: []const T) S {
            var code: S = 0;
            for (e) |item| {
                const enum_bit_pos = getEnumBitPos(item, S);
                code |= enum_bit_pos;
            }
            return code;
        }
        pub fn createGroup(comptime sets: []const T) Set {
            return Set.init(sets);
        }
        /// **from**: unnsigned integer
        ///
        /// **has**: enum literal
        ///
        /// Ex.
        /// ```
        /// const code = EnumPlusInstance.select( .Sample );
        /// EnumPlusInstance.verify(code, .Sample)
        /// ```
        pub fn verify(from: S, has: T) bool {
            return from & getEnumBitPos(has, S) > 0;
        }
    };
}

test "ENUM PLUS" {
    const ROLE = enum { Admin, Guest, Customer };
    const AppRole = EnumPlus(ROLE);
    var LowLevelRole = AppRole.createGroup(&.{ .Customer, .Guest });

    try testing.expect(@TypeOf(LowLevelRole.code) == u3);
    try testing.expect(ROLE.Admin == AppRole.member.Admin);
    try testing.expect(LowLevelRole.has(.Admin) == false);

    LowLevelRole.remove(.Customer);
    try testing.expect(LowLevelRole.has(.Customer) == false);

    LowLevelRole.add(.Customer);
    try testing.expect(LowLevelRole.has(.Customer) == true);

    const admin_code = AppRole.select(.Admin);
    try testing.expect(AppRole.verify(admin_code, .Admin));
    try testing.expect(AppRole.verify(admin_code, .Customer) == false);
    const set_code = AppRole.selectMany(&.{ .Admin, .Customer });
    try testing.expect(AppRole.verify(set_code, .Admin));
    try testing.expect(AppRole.verify(set_code, .Customer));
    try testing.expect(AppRole.verify(set_code, .Guest) == false);
}

fn GetUnsignedIntegerSize(comptime size: u8) type {
    return comptime switch (size) {
        1 => u1,
        2 => u2,
        3 => u3,
        4 => u4,
        5 => u5,
        6 => u6,
        7 => u7,
        8 => u8,
        9 => u9,
        10 => u10,
        11 => u11,
        12 => u12,
        13 => u13,
        14 => u14,
        15 => u15,
        16 => u16,
        17 => u17,
        18 => u18,
        19 => u19,
        20 => u20,
        21 => u21,
        22 => u22,
        23 => u23,
        24 => u24,
        25 => u25,
        26 => u26,
        27 => u27,
        28 => u28,
        29 => u29,
        30 => u30,
        31 => u31,
        32 => u32,
        33 => u33,
        34 => u34,
        35 => u35,
        36 => u36,
        37 => u37,
        38 => u38,
        39 => u39,
        40 => u40,
        41 => u41,
        42 => u42,
        43 => u43,
        44 => u44,
        45 => u45,
        46 => u46,
        47 => u47,
        48 => u48,
        49 => u49,
        50 => u50,
        51 => u51,
        52 => u52,
        53 => u53,
        54 => u54,
        55 => u55,
        56 => u56,
        57 => u57,
        58 => u58,
        59 => u59,
        60 => u60,
        61 => u61,
        62 => u62,
        63 => u63,
        64 => u64,
        65 => u65,
        66 => u66,
        67 => u67,
        68 => u68,
        69 => u69,
        70 => u70,
        71 => u71,
        72 => u72,
        73 => u73,
        74 => u74,
        75 => u75,
        76 => u76,
        77 => u77,
        78 => u78,
        79 => u79,
        80 => u80,
        81 => u81,
        82 => u82,
        83 => u83,
        84 => u84,
        85 => u85,
        86 => u86,
        87 => u87,
        88 => u88,
        89 => u89,
        90 => u90,
        91 => u91,
        92 => u92,
        93 => u93,
        94 => u94,
        95 => u95,
        96 => u96,
        97 => u97,
        98 => u98,
        99 => u99,
        100 => u100,
        101 => u101,
        102 => u102,
        103 => u103,
        104 => u104,
        105 => u105,
        106 => u106,
        107 => u107,
        108 => u108,
        109 => u109,
        110 => u110,
        111 => u111,
        112 => u112,
        113 => u113,
        114 => u114,
        115 => u115,
        116 => u116,
        117 => u117,
        118 => u118,
        119 => u119,
        120 => u120,
        121 => u121,
        122 => u122,
        123 => u123,
        124 => u124,
        125 => u125,
        126 => u126,
        127 => u127,
        else => u128,
    };
}

test "GetUnsignedInteger" {
    const numToString = std.fmt.allocPrint;
    inline for (1..128) |i| {
        const value: u8 = @intCast(i);
        const ui_type = GetUnsignedIntegerSize(value);

        const stringified_num = try numToString(testing.allocator, "{d}", .{value});
        defer testing.allocator.free(stringified_num);

        const type_name_should_be = try std.mem.concat(testing.allocator, u8, &.{ "u", stringified_num });
        defer testing.allocator.free(type_name_should_be);

        try testing.expectEqualStrings(type_name_should_be, @typeName(ui_type));
    }
}

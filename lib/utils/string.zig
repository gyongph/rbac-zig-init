const std = @import("std");
const testing = std.testing;
const rand = std.crypto.random;

const seed = "124657890ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
pub fn random(comptime len: usize) [len]u8 {
    std.debug.assert(len > 0);
    var buff: [len]u8 = undefined;
    var counter = len;
    var shuffled: [seed.len]u8 = undefined;
    @memcpy(&shuffled, seed);
    rand.shuffle(u8, &shuffled);
    while (counter > 0) : (counter -= 1) {
        const random_index = rand.intRangeAtMost(u6, 0, seed.len - 1);
        buff[counter - 1] = shuffled[random_index];
    }
    return buff[0..len].*;
}

test "random" {
    const random_sample = random(25);
    try testing.expect(random_sample.len == 25);
    try testing.expect(@TypeOf(random_sample) == [25]u8);
    const invalid_char_pos = std.mem.indexOfNonePos(u8, &random_sample, 0, seed); // checks if found unknown character
    try testing.expect(invalid_char_pos == null);
}

pub fn allocRandom(allocator: std.mem.Allocator, len: usize) ![]u8 {
    std.debug.assert(len > 0);
    var buff = try allocator.alloc(u8, len);
    var counter = len;
    var shuffled: [seed.len]u8 = undefined;
    @memcpy(&shuffled, seed);
    rand.shuffle(u8, &shuffled);

    while (counter > 0) : (counter -= 1) {
        const random_index = rand.intRangeAtMost(u6, 0, seed.len - 1);
        buff[counter - 1] = shuffled[random_index];
    }
    return buff;
}

test "allocRandom" {
    const random_sample = try allocRandom(testing.allocator, 25);
    defer testing.allocator.free(random_sample);
    try testing.expect(random_sample.len == 25);
    try testing.expectEqual(@TypeOf(random_sample), []u8);
    const invalid_char_pos = std.mem.indexOfNonePos(u8, random_sample, 0, seed); // checks if found unknown character
    try testing.expect(invalid_char_pos == null);
}

pub fn parseInt(comptime T: type, buf: []const u8, base: u8) !T {
    return try std.fmt.parseInt(T, buf, base);
}

pub fn isStringType(T: anytype) bool {
    const info = @typeInfo(T);
    switch (info) {
        .optional => |opt| return isStringType(opt.child),
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) return true;
            return false;
        },
        else => return false,
    }
}

pub fn isString(val: anytype) bool {
    const T = @TypeOf(val);
    return isStringType(T);
}

pub const Printer = struct {
    alloc: std.mem.Allocator,
    pub fn print(self: @This(), comptime str: []const u8, args: anytype) anyerror![]const u8 {
        return try std.fmt.allocPrint(self.alloc, str, args);
    }
};

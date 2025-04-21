const std = @import("std");

fn isCharValid(char: u8) bool {
    switch (char) {
        'a'...'z' => return true,
        'A'...'Z' => return true,
        '0'...'9' => return true,
        '-', '.', '_', '~' => return true,
        else => return false,
    }
    return false;
}

pub fn encode(alloc: std.mem.Allocator, s: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    defer result.deinit();
    try std.Uri.Component.percentEncode(result.writer(), s, isCharValid);
    return result.toOwnedSlice();
}

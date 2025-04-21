const std = @import("std");
const Self = @This();
timestamp: u64,
sec: u6,
min: u6,
hr: u5,
day: u9,
mon: u4,
yr: u16,

pub fn init(ms: u64) Self {
    const total_sec = @divTrunc(ms, std.time.ms_per_s);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = total_sec };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1;
    const hr = day_seconds.getHoursIntoDay();
    const min = day_seconds.getMinutesIntoHour();
    const sec = day_seconds.getSecondsIntoMinute();

    return Self{
        .timestamp = ms,
        .sec = sec,
        .min = min,
        .hr = hr,
        .day = day,
        .mon = month,
        .yr = year,
    };
}

pub fn now() Self {
    const current = std.time.milliTimestamp();
    if (current < 0) @panic("Days since epoch Jan 1, 1970 is only supported");
    return Self.init(@intCast(current));
}

pub fn format(
    self: Self,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = options;
    var y: usize = 0;
    var M: usize = 0;
    var d: usize = 0;
    var H: usize = 0;
    var m: usize = 0;
    var s: usize = 0;
    for (fmt, 0..) |char, i| {
        var is_time_code: bool = true;
        const next: ?u8 = if (i == fmt.len - 1) null else fmt[i + 1];
        switch (char) {
            'y' => y = y + 1,
            'M' => M = M + 1,
            'd' => d = d + 1,
            'H' => H = H + 1,
            'm' => m = m + 1,
            's' => s = s + 1,
            else => {
                is_time_code = false;
                try writer.print("{s}", .{[1]u8{char}});
            },
        }
        const end = i == fmt.len - 1;
        if (!end and (next != null and next.? == char)) {
            continue;
        } else {
            switch (y) {
                4 => {
                    _ = try writer.print("{d:0>4}", .{self.yr});
                    y = 0;
                    continue;
                },
                2 => {
                    _ = try writer.print("{}", .{self.yr % 100});
                    y = 0;
                    continue;
                },
                else => {},
            }

            if (M == 2) {
                M = 0;
                _ = try writer.print("{d:0>2}", .{self.mon});
                continue;
            }
            if (d == 2) {
                d = 0;
                _ = try writer.print("{d:0>2}", .{self.day});
                continue;
            }
            if (H == 2) {
                H = 0;
                _ = try writer.print("{d:0>2}", .{self.hr});
                continue;
            }

            if (m == 2) {
                m = 0;
                _ = try writer.print("{d:0>2}", .{self.min});
                continue;
            }
            if (s == 2) {
                s = 0;
                _ = try writer.print("{d:0>2}", .{self.sec});
                continue;
            }
            if (next == null and is_time_code) {
                std.log.warn("Date format is not corret", .{});
                return error.malformed_date_format;
            }
        }
    }
}

test format {
    const allocator = std.testing.allocator;
    const date = init(0);
    const output = try std.fmt.allocPrint(allocator, "{yyyyMMddTHHmmssZ}", .{date});
    defer allocator.free(output);
    try std.testing.expectEqualStrings("19700101T000000Z", output);
}

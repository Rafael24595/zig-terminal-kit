const std = @import("std");

const testing = std.testing;

/// Describes a time unit and its duration in milliseconds.
pub const TimeUnit = struct {
    label: []const u8,
    time: i64,
};

/// Predefined time units with fixed durations in milliseconds.
pub const Millisecond: TimeUnit = .{ .label = "ms", .time = 1 };
/// Uses a fixed 1000-millisecond second rather than a calendar-based second.
pub const Second: TimeUnit = .{ .label = "s", .time = 1000 };
/// Uses a fixed 60-second minute rather than a calendar-based minute.
pub const Minute: TimeUnit = .{ .label = "m", .time = Second.time * 60 };
/// Uses a fixed 60-minute hour rather than a calendar-based hour.
pub const Hour: TimeUnit = .{ .label = "h", .time = Minute.time * 60 };
/// Uses a fixed 24-hour day rather than a calendar-based day.
pub const Day: TimeUnit = .{ .label = "d", .time = Hour.time * 24 };
/// Uses a fixed 365-day year rather than a calendar-based year.
pub const Year: TimeUnit = .{ .label = "y", .time = Day.time * 365 };

/// Units are processed from largest to smallest to build a compact duration.
const TimeUnits: [6]TimeUnit = .{ Year, Day, Hour, Minute, Second, Millisecond };

/// Converts a duration in milliseconds into a compact string.
///
/// The optional limit is exclusive: formatting stops when the specified unit
/// is reached, so that unit and all smaller units are omitted.
///
/// Examples:
///   1500 ms -> "1s500ms"
///   3726000 ms with Second as the limit -> "1h2m"
///
/// The caller owns the returned slice and must free it with the same allocator.
/// This implementation is intended for non-negative durations.
pub fn milliseconds_to_time(alloc: std.mem.Allocator, ms: i64, limit: ?TimeUnit) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(alloc, 0);
    defer buffer.deinit(alloc);

    var fix_ms = ms;
    for (TimeUnits) |unit| {
        if (limit != null and std.mem.eql(u8, unit.label, limit.?.label)) {
            break;
        }

        const amount = @divFloor(fix_ms, unit.time);
        if (amount > 0 or buffer.capacity > 0 or std.mem.eql(u8, unit.label, "ms")) {
            const uAmount: usize = @intCast(amount);

            const time = if (std.mem.eql(u8, unit.label, "ms"))
                try std.fmt.allocPrint(alloc, "{d:0<3}{s}", .{ uAmount, unit.label })
            else
                try std.fmt.allocPrint(alloc, "{d:0<1}{s}", .{ uAmount, unit.label });

            defer alloc.free(time);

            try buffer.appendSlice(alloc, time);
        }

        fix_ms = @mod(fix_ms, unit.time);
    }

    return try std.fmt.allocPrint(alloc, "{s}", .{buffer.items});
}

test "millisecondsToTime - only milliseconds" {
    const alloc = testing.allocator;

    const result = try milliseconds_to_time(alloc, 5, null);
    defer alloc.free(result);

    try testing.expectEqualStrings("500ms", result);
}

test "millisecondsToTime - seconds and milliseconds" {
    const alloc = testing.allocator;

    const result = try milliseconds_to_time(alloc, 1500, null);
    defer alloc.free(result);

    try testing.expectEqualStrings("1s500ms", result);
}

test "millisecondsToTime - minutes and milliseconds" {
    const alloc = testing.allocator;

    const result = try milliseconds_to_time(alloc, 61_250, null);
    defer alloc.free(result);

    try testing.expectEqualStrings("1m1s250ms", result);
}

test "millisecondsToTime - hours minutes seconds" {
    const alloc = testing.allocator;

    const result = try milliseconds_to_time(alloc, 3_726_000, null);
    defer alloc.free(result);

    try testing.expectEqualStrings("1h2m6s000ms", result);
}

test "millisecondsToTime - seconds limit" {
    const alloc = testing.allocator;

    const result = try milliseconds_to_time(alloc, 3_726_000, Second);
    defer alloc.free(result);

    try testing.expectEqualStrings("1h2m", result);
}

test "millisecondsToTime - days and years" {
    const alloc = testing.allocator;

    const one_year_ms = Year.time;
    const result = try milliseconds_to_time(alloc, one_year_ms, null);
    defer alloc.free(result);

    try testing.expectEqualStrings("1y0d0h0m0s000ms", result);
}

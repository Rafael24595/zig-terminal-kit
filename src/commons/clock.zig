const std = @import("std");

/// Provides an injectable source of timestamps in milliseconds.
pub const Clock = struct {
    /// Optional state passed to the timestamp provider.
    context: ?*anyopaque = null,
    /// Returns the current timestamp in milliseconds.
    now_fn: *const fn (?*anyopaque) i64,

    /// Returns the current timestamp using this clock's provider.
    pub fn now(self: Clock) i64 {
        return self.now_fn(self.context);
    }
};

/// Clock backed by the system wall-clock time.
pub const system_clock = Clock{
    .now_fn = system_now,
};

fn system_now(_: ?*anyopaque) i64 {
    return std.time.milliTimestamp();
}

/// Provides monotonic timestamps based on a persistent timer.
pub const MonotonicClock = struct {
    timer: std.time.Timer,

    pub fn init() !@This() {
        return .{
            .timer = try std.time.Timer.start(),
        };
    }

    fn now(context: ?*anyopaque) i64 {
        const ptr = context orelse unreachable;
        const self: *@This() = @ptrCast(@alignCast(ptr));

        return @intCast(self.timer.read() / std.time.ns_per_ms);
    }

    pub fn clock(self: *@This()) Clock {
        return .{
            .context = self,
            .now_fn = now,
        };
    }
};

test "MonotonicClock returns non-decreasing timestamps" {
    var monotonic = try MonotonicClock.init();
    const clock = monotonic.clock();

    const first = clock.now();
    const second = clock.now();

    try std.testing.expect(second >= first);
}

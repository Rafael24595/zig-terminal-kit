const std = @import("std");

const clock = @import("./clock.zig");

/// Tracks rendered frames and periodically calculates their rate over time.
pub const Counter = struct {
    clock: clock.Clock,
    /// Timestamp of the last rate update, in milliseconds since the Unix epoch.
    last_time: i64,
    /// Most recently calculated frames per second.
    last_stable: u16,
    /// Number of frames counted since the last rate update.
    frames: u64,

    /// Initializes the counter with no recorded frames or calculated rate.
    pub fn init() @This() {
        //TODO: Use monotonic clock as default?
        const clk = clock.system_clock;

        return .{
            .clock = clk,
            .last_time = 0,
            .last_stable = 0,
            .frames = 0,
        };
    }

    /// Records a newly rendered frame.
    pub fn frame_increment(self: *@This()) void {
        self.frames +|= 1;
    }

    /// Returns the latest frame-rate estimate, recalculating it when the
    /// specified interval has elapsed.
    ///
    /// `interval` is expressed in milliseconds. The first call initializes
    /// the timestamp and returns the existing estimate without recalculating.
    /// If the interval has not elapsed, the previous estimate is returned.
    /// The calculated rate is capped at the maximum value of `u16`.
    pub fn get_frame_rate(self: *@This(), interval: i64) u16 {
        const current_time = self.clock.now();

        if (self.last_time == 0) {
            self.last_time = current_time;
            return self.last_stable;
        }

        const elapsed = current_time - self.last_time;
        if (elapsed < interval) {
            return self.last_stable;
        }

        if (elapsed > 0) {
            const fps = (self.frames * 1000) / @as(u64, @intCast(elapsed));
            self.last_stable = @intCast(@min(fps, std.math.maxInt(u16)));
        }

        self.last_time = current_time;
        self.frames = 0;

        return self.last_stable;
    }
};

const MockClock = struct {
    time: i64,

    fn now(context: ?*anyopaque) i64 {
        const ptr = context orelse unreachable;
        const self: *@This() = @ptrCast(@alignCast(ptr));
        return self.time;
    }
};

test "frame_per returns the last stable value on first call" {
    var counter = Counter.init();

    counter.last_time = 0;
    counter.last_stable = 12;
    counter.frames = 5;

    const fps = counter.get_frame_rate(std.time.ms_per_s);

    try std.testing.expectEqual(12, fps);
    try std.testing.expect(counter.last_time > 0);
}

test "frame_increment increments the frame counter" {
    var counter = Counter.init();
    counter.frames = 0;

    counter.frame_increment();

    try std.testing.expectEqual(1, counter.frames);
}

test "frame_increment saturates at the maximum frame count" {
    const maxU64 = std.math.maxInt(u64);

    var counter = Counter.init();
    counter.frames = maxU64;

    counter.frame_increment();

    try std.testing.expectEqual(maxU64, counter.frames);
}

test "frame_per returns the last stable value on its first call" {
    var counter = Counter.init();

    counter.last_time = 0;
    counter.last_stable = 30;
    counter.frames = 10;

    const fps = counter.get_frame_rate(std.time.ms_per_s);

    try std.testing.expectEqual(30, fps);
    try std.testing.expect(counter.last_time > 0);
    try std.testing.expectEqual(10, counter.frames);
}

test "frame_per retains the stable value before the interval elapses" {
    var counter = Counter.init();

    counter.last_time = std.time.milliTimestamp();
    counter.last_stable = 30;
    counter.frames = 10;

    const fps = counter.get_frame_rate(std.time.ms_per_s);

    try std.testing.expectEqual(30, fps);
    try std.testing.expectEqual(10, counter.frames);
}

test "frame_per recalculates the frame rate after the interval elapses" {
    var counter = Counter.init();

    var mock = MockClock{
        .time = 2000,
    };

    counter.clock = .{
        .context = &mock,
        .now_fn = MockClock.now,
    };

    counter.last_time = 1_000;
    counter.frames = 30;

    const fps = counter.get_frame_rate(std.time.ms_per_s);
    try std.testing.expectEqual(30, fps);

    mock.time = 1_500;
    counter.last_time = 1_000;
    counter.frames = 30;

    const fpms = counter.get_frame_rate(500);
    try std.testing.expectEqual(60, fpms);
}

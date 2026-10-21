const std = @import("std");

const math = std.math;

const testing = std.testing;

const default_max_speed = 3000;

/// Stores shared runtime state for a terminal application.
///
/// Provides coordination for frame timing, pause handling, exit and reload
/// requests, and thread notifications.
///
/// Notifications are coalesced: multiple pending notifications may be
/// represented by a single wake-up.
pub const RuntimeState = struct {
    /// Protects the condition variable and notification state.
    mutex: std.Thread.Mutex = .{},

    max_speed: u64 = default_max_speed,

    /// Timestamp, in milliseconds, at which the runtime effectively started.
    start_timestamp: std.atomic.Value(i64) = .init(0),
    /// Timestamp, in milliseconds, at which the current pause began.
    pause_timestamp: std.atomic.Value(i64) = .init(0),

    /// Target frame interval, in milliseconds.
    speed_ms: std.atomic.Value(u64) = .init(0),

    /// Indicates whether the runtime is currently paused.
    pause: std.atomic.Value(bool) = .init(false),
    /// Indicates that the runtime has been requested to exit
    exit: std.atomic.Value(bool) = .init(false),
    /// Indicates that a reload has been requested.
    reload: std.atomic.Value(bool) = .init(false),

    /// Wakes a thread waiting for a runtime notification.
    cond: std.Thread.Condition = .{},

    /// Indicates whether a notification is waiting to be consumed.
    ///
    /// Access must be synchronized using `mutex`.
    notification_pending: bool = false,

    pub fn init(max_speed: u64) @This() {
        return .{
            .max_speed = max_speed,
        };
    }

    /// Updates the target frame interval and notifies waiting threads.
    ///
    /// `speed` is expressed in milliseconds.
    pub fn set_speed(self: *@This(), speed: u64) void {
        self.speed_ms.store(speed, .release);
        self.notify();
    }

    /// Modifies the target frame interval by the specified amount and notifies waiting threads.
    ///
    /// `mod` is expressed in milliseconds. The resulting speed is clamped to the range [0, max_speed].
    pub fn mod_speed(self: *@This(), mod: i64) void {
        const speed = self.speed_ms.load(.acquire);

        const next: u64 = if (mod >= 0) blk: {
            const delta: u64 = @intCast(mod);
            break :blk speed +| delta;
        } else blk: {
            const delta: u64 = @intCast(-@as(i128, mod));
            break :blk speed -| delta;
        };

        self.speed_ms.store(
            @min(next, self.max_speed),
            .release,
        );

        self.notify();
    }

    /// Requests that the runtime terminate and notifies waiting threads.
    pub fn request_exit(self: *@This()) void {
        self.exit.store(true, .release);
        self.notify();
    }

    /// Requests a reload and notifies waiting threads.
    pub fn request_reload(self: *@This()) void {
        self.reload.store(true, .release);
        self.notify();
    }

    /// Consumes a pending reload request.
    ///
    /// Returns `true` if a request was pending and has been cleared;
    /// otherwise, returns `false`.
    pub fn consume_reload(self: *@This()) bool {
        return self.reload.swap(false, .acq_rel);
    }

    /// Toggles the runtime between paused and running states.
    ///
    /// When pausing, records the pause timestamp.
    /// When resuming, adjusts the start timestamp to exclude the paused
    /// duration.
    pub fn toggle_pause(self: *@This()) void {
        const now = std.time.milliTimestamp();

        const was_paused = self.pause.swap(
            !self.pause.load(.acquire),
            .acq_rel,
        );

        if (!was_paused) {
            self.pause_timestamp.store(now, .release);
            self.notify();
            return;
        }

        const pause_timestamp = self.pause_timestamp.load(.acquire);
        const start_timestamp = self.start_timestamp.load(.acquire);
        const diff = now - pause_timestamp;

        self.start_timestamp.store(start_timestamp + diff, .release);

        self.notify();
    }

    /// Waits for a notification or until the specified timeout expires.
    ///
    /// `timeout_ns` is expressed in nanoseconds.
    ///
    /// Returns when a notification is consumed or the timeout expires.
    /// Propagates errors other than timeout errors.
    pub fn wait_for_frame(self: *@This(), timeout_ns: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.notification_pending) {
            self.notification_pending = false;
            return;
        }

        self.cond.timedWait(&self.mutex, timeout_ns) catch |err| switch (err) {
            error.Timeout => {},
            else => return err,
        };

        self.notification_pending = false;
    }

    fn notify(self: *@This()) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.notification_pending = true;
        self.cond.signal();
    }
};

/// Handles an interrupt signal by requesting the runtime to exit.
pub fn on_interrupt(context: *anyopaque) void {
    const state: *RuntimeState = @ptrCast(@alignCast(context));
    state.request_exit();
}

/// Returns `true` if the runtime has been requested to exit.
pub inline fn should_exit(state: *const RuntimeState) bool {
    return state.exit.load(.acquire);
}

/// Returns `true` if the runtime has been requested to reload.
pub inline fn should_reload(state: *const RuntimeState) bool {
    return state.reload.load(.acquire);
}

test "initial state has no pending requests" {
    var state = RuntimeState{};

    try testing.expect(!state.pause.load(.monotonic));
    try testing.expect(!state.exit.load(.monotonic));
    try testing.expect(!state.reload.load(.monotonic));

    try testing.expectEqual(0, state.speed_ms.load(.monotonic));
}

test "set_speed updates the frame interval" {
    var state = RuntimeState{};

    state.set_speed(100);

    try testing.expectEqual(
        @as(u64, 100),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed increases the frame interval" {
    var state = RuntimeState{};

    state.mod_speed(100);

    try testing.expectEqual(
        @as(u64, 100),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed decreases the frame interval" {
    var state = RuntimeState{};

    state.set_speed(100);
    state.mod_speed(-30);

    try testing.expectEqual(
        @as(u64, 70),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed clamps the frame interval to zero" {
    var state = RuntimeState{};

    state.set_speed(10);
    state.mod_speed(-20);

    try testing.expectEqual(
        @as(u64, 0),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed clamps the frame interval to max_speed" {
    var state = RuntimeState{};

    state.set_speed(state.max_speed - 10);
    state.mod_speed(20);

    try testing.expectEqual(
        state.max_speed,
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed handles zero adjustment" {
    var state = RuntimeState{};

    state.set_speed(100);
    state.mod_speed(0);

    try testing.expectEqual(
        @as(u64, 100),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed handles minimum adjustment" {
    var state = RuntimeState{};

    state.set_speed(100);
    state.mod_speed(std.math.minInt(i64));

    try testing.expectEqual(
        @as(u64, 0),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed handles maximum adjustment" {
    var state = RuntimeState{};

    state.mod_speed(std.math.maxInt(i64));

    try testing.expectEqual(
        state.max_speed,
        state.speed_ms.load(.monotonic),
    );
}

test "request_exit sets the exit flag" {
    var state = RuntimeState{};

    state.request_exit();

    try testing.expect(state.exit.load(.monotonic));
}

test "reload request is consumed exactly once" {
    var state = RuntimeState{};

    state.request_reload();

    try testing.expect(state.consume_reload());
    try testing.expect(!state.consume_reload());
}

test "pending notification is consumed without waiting" {
    var state = RuntimeState{};

    state.set_speed(50);

    try state.wait_for_frame(std.time.ns_per_s);

    state.mutex.lock();
    const pending = state.notification_pending;
    state.mutex.unlock();

    try testing.expect(!pending);
}

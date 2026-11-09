const std = @import("std");

const math = std.math;

const testing = std.testing;

const Clock = @import("../commons/clock.zig").Clock;

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

    /// Provides timestamps for frame timing and pause handling.
    clock: Clock,

    /// The maximum allowed frame interval, in milliseconds.
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

    /// Indicates whether debug mode is enabled.
    debug: std.atomic.Value(bool) = .init(false),
    /// Indicates whether the runtime controls are visible.
    controls: std.atomic.Value(bool) = .init(false),
    /// Indicates the current help cursor position.
    help_cursor: std.atomic.Value(usize) = .init(0),

    /// Wakes a thread waiting for a runtime notification.
    cond: std.Thread.Condition = .{},

    /// Indicates whether a notification is waiting to be consumed.
    ///
    /// Access must be synchronized using `mutex`.
    notification_pending: bool = false,

    /// Initializes a new `RuntimeState` instance with the specified parameters.
    ///
    /// `start_ms` is the initial start timestamp, in milliseconds.
    /// `speed_ms` is the initial target frame interval, in milliseconds.
    /// `debug` indicates whether debug mode is initially enabled.
    /// `controls` indicates whether the runtime controls are initially visible.
    pub fn init(
        clock: Clock,
        start_ms: i64,
        speed_ms: u64,
        debug: bool,
        controls: bool,
    ) @This() {
        return .{
            .clock = clock,
            .start_timestamp = .init(start_ms),
            .speed_ms = .init(speed_ms),
            .debug = .init(debug),
            .controls = .init(controls),
        };
    }

    /// Returns the current runtime timestamp, in milliseconds.
    pub fn get_start_timestamp(self: @This()) i64 {
        return self.start_timestamp.load(.acquire);
    }

    /// Sets the start timestamp, in milliseconds.
    pub fn set_start_timestamp(self: *@This(), timestamp: i64) void {
        self.start_timestamp.store(timestamp, .release);
    }

    /// Resets the start timestamp to the current time, in milliseconds.
    pub fn reset_start_timestamp(self: *@This()) void {
        self.start_timestamp.store(self.clock.now(), .release);
    }

    /// Returns the current pause timestamp, in milliseconds.
    pub fn get_pause_timestamp(self: @This()) i64 {
        return self.pause_timestamp.load(.acquire);
    }

    /// Returns the current runtime duration, in milliseconds.
    pub fn get_runtime(self: @This()) i64 {
        const end_ms = if (self.is_paused())
            self.get_pause_timestamp()
        else
            self.clock.now();

        return end_ms - self.get_start_timestamp();
    }

    /// Returns the current target frame interval, in milliseconds.
    pub fn get_speed(self: @This()) u64 {
        return self.speed_ms.load(.acquire);
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

    /// Returns `true` if the runtime is currently paused.
    pub fn is_paused(self: @This()) bool {
        return self.pause.load(.acquire);
    }

    /// Toggles the runtime between paused and running states.
    ///
    /// When pausing, records the pause timestamp.
    /// When resuming, adjusts the start timestamp to exclude the paused
    /// duration.
    pub fn toggle_pause(self: *@This()) void {
        const now = self.clock.now();

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

    /// Returns `true` if debug mode is currently enabled.
    pub fn show_debug(self: @This()) bool {
        return self.debug.load(.acquire);
    }

    /// Toggles the debug mode state.
    pub fn toggle_debug(self: *@This()) void {
        self.debug.store(
            !self.debug.load(.acquire),
            .release,
        );
    }

    /// Returns the current help cursor position.
    pub fn get_help_cursor(self: @This()) usize {
        return self.help_cursor.load(.acquire);
    }

    /// Increments the help cursor position by one.
    pub fn inc_help_cursor(self: *@This()) void {
        self.help_cursor.store(self.get_help_cursor() +| 1, .release);
    }

    /// Decrements the help cursor position by one, ensuring it does not go below zero.
    pub fn dec_help_cursor(self: *@This()) void {
        self.help_cursor.store(self.get_help_cursor() -| 1, .release);
    }

    /// Sets the help cursor position to the specified page index.
    pub fn set_help_cursor(self: *@This(), page: usize) void {
        self.help_cursor.store(page, .release);
    }

    /// Returns `true` if the runtime controls are currently visible.
    pub fn show_controls(self: @This()) bool {
        return self.controls.load(.acquire);
    }

    /// Toggles the runtime controls visibility state.
    pub fn toggle_controls(self: *@This()) void {
        self.controls.store(
            !self.controls.load(.acquire),
            .release,
        );
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

const MockClock = struct {
    timestamp: i64,

    fn now(context: ?*anyopaque) i64 {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        return self.timestamp;
    }

    fn clock(self: *@This()) Clock {
        return .{
            .context = self,
            .now_fn = now,
        };
    }
};

test "initial state has no pending requests" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    try testing.expect(!state.pause.load(.monotonic));
    try testing.expect(!state.exit.load(.monotonic));
    try testing.expect(!state.reload.load(.monotonic));

    try testing.expectEqual(0, state.speed_ms.load(.monotonic));
}

test "set_speed updates the frame interval" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(100);

    try testing.expectEqual(
        @as(u64, 100),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed increases the frame interval" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.mod_speed(100);

    try testing.expectEqual(
        @as(u64, 100),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed decreases the frame interval" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(100);
    state.mod_speed(-30);

    try testing.expectEqual(
        @as(u64, 70),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed clamps the frame interval to zero" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(10);
    state.mod_speed(-20);

    try testing.expectEqual(
        @as(u64, 0),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed clamps the frame interval to max_speed" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(state.max_speed - 10);
    state.mod_speed(20);

    try testing.expectEqual(
        state.max_speed,
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed handles zero adjustment" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(100);
    state.mod_speed(0);

    try testing.expectEqual(
        @as(u64, 100),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed handles minimum adjustment" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(100);
    state.mod_speed(std.math.minInt(i64));

    try testing.expectEqual(
        @as(u64, 0),
        state.speed_ms.load(.monotonic),
    );
}

test "mod_speed handles maximum adjustment" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.mod_speed(std.math.maxInt(i64));

    try testing.expectEqual(
        state.max_speed,
        state.speed_ms.load(.monotonic),
    );
}

test "request_exit sets the exit flag" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.request_exit();

    try testing.expect(state.exit.load(.monotonic));
}

test "reload request is consumed exactly once" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.request_reload();

    try testing.expect(state.consume_reload());
    try testing.expect(!state.consume_reload());
}

test "pending notification is consumed without waiting" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    state.set_speed(50);

    try state.wait_for_frame(std.time.ns_per_s);

    state.mutex.lock();
    const pending = state.notification_pending;
    state.mutex.unlock();

    try testing.expect(!pending);
}

test "toggle_debug switches debug mode state" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    try testing.expect(!state.debug.load(.monotonic));

    state.toggle_debug();
    try testing.expect(state.debug.load(.monotonic));

    state.toggle_debug();
    try testing.expect(!state.debug.load(.monotonic));
}

test "toggle_controls switches controls visibility state" {
    var fake_clock = MockClock{
        .timestamp = 0,
    };

    var state = RuntimeState{
        .clock = fake_clock.clock(),
    };

    try testing.expect(!state.controls.load(.monotonic));

    state.toggle_controls();
    try testing.expect(state.controls.load(.monotonic));

    state.toggle_controls();
    try testing.expect(!state.controls.load(.monotonic));
}

test "reset_start_timestamp updates the start timestamp" {
    var fake_clock = MockClock{
        .timestamp = 500,
    };

    var state = RuntimeState.init(
        fake_clock.clock(),
        100,
        0,
        false,
        false,
    );

    state.reset_start_timestamp();

    try testing.expectEqual(
        @as(i64, 500),
        state.get_start_timestamp(),
    );
}

test "reset_start_timestamp replaces a previous timestamp" {
    var fake_clock = MockClock{
        .timestamp = 1000,
    };

    var state = RuntimeState.init(
        fake_clock.clock(),
        250,
        0,
        false,
        false,
    );

    fake_clock.timestamp = 2000;

    state.reset_start_timestamp();

    try testing.expectEqual(
        @as(i64, 2000),
        state.get_start_timestamp(),
    );
}

test "reset_start_timestamp can be called multiple times" {
    var fake_clock = MockClock{
        .timestamp = 100,
    };

    var state = RuntimeState.init(
        fake_clock.clock(),
        0,
        0,
        false,
        false,
    );

    state.reset_start_timestamp();

    try testing.expectEqual(
        @as(i64, 100),
        state.get_start_timestamp(),
    );

    fake_clock.timestamp = 300;

    state.reset_start_timestamp();

    try testing.expectEqual(
        @as(i64, 300),
        state.get_start_timestamp(),
    );
}

const std = @import("std");

pub const RuntimeState = struct {
    mutex: std.Thread.Mutex = .{},

    start_timestamp: std.atomic.Value(i64) = .init(0),
    pause_timestamp: std.atomic.Value(i64) = .init(0),

    speed_ms: std.atomic.Value(u64) = .init(0),

    pause: std.atomic.Value(bool) = .init(false),
    exit: std.atomic.Value(bool) = .init(false),
    reload: std.atomic.Value(bool) = .init(false),

    cond: std.Thread.Condition = .{},
    notification_pending: bool = false,

    pub fn setSpeed(self: *@This(), speed: u64) void {
        self.speed_ms.store(speed, .release);
        self.notify();
    }

    pub fn requestExit(self: *@This()) void {
        self.exit.store(true, .release);
        self.notify();
    }

    pub fn requestReload(self: *@This()) void {
        self.reload.store(true, .release);
        self.notify();
    }

    pub fn consumeReload(self: *@This()) bool {
        return self.reload.swap(false, .acq_rel);
    }

    pub fn togglePause(self: *@This()) void {
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

    pub fn waitForFrame(self: *@This(), timeout_ns: u64) !void {
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

test "initial state has no pending requests" {
    var state = RuntimeState{};

    try testing.expect(!state.pause.load(.monotonic));
    try testing.expect(!state.exit.load(.monotonic));
    try testing.expect(!state.reload.load(.monotonic));

    try testing.expectEqual(@as(u64, 0), state.speed_ms.load(.monotonic));
}

test "set_speed updates the frame interval" {
    var state = RuntimeState{};

    state.set_speed(100);

    try testing.expectEqual(
        @as(u64, 100),
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

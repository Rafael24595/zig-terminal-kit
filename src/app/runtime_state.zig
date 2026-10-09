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

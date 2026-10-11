const std = @import("std");
const builtin = @import("builtin");

const windows = std.os.windows;

/// A callback invoked when a supported interrupt signal is received.
/// The callback runs on the signal receiver thread, not inside the OS signal handler.
pub const Callback = *const fn (*anyopaque) void;

/// Errors that can occur while installing or uninstalling signal handling.
pub const InstallError = error{
    /// The signal handler is already installed.
    AlreadyInstalled,
    /// The signal handler is not installed.
    InstallationInProgress,
    /// The signal handler is being uninstalled.
    UninstallationInProgress,
    /// Failed to create a pipe for signal communication.
    FailedToCreatePipe,
    /// Failed to set the console control handler.
    FailedToSetCtrlHandler,
    /// Failed to create an event for signal communication.
    FailedToCreateEvent,
};

const InstallState = enum {
    uninstalled,
    installing,
    installed,
    uninstalling,
};

const PosixResources = struct {
    read_fd: std.posix.fd_t,
    write_fd: std.posix.fd_t,
    previous_action: std.posix.Sigaction,
};

var state_mutex: std.Thread.Mutex = .{};
var state: InstallState = .uninstalled;

var callback: ?Callback = null;
var context: ?*anyopaque = null;

var receiver_thread: ?std.Thread = null;

var stop_requested: std.atomic.Value(bool) = .init(false);
var signal_pending: std.atomic.Value(bool) = .init(false);

var posix_resources: ?PosixResources = null;
var signal_write_fd: std.posix.fd_t = -1;

var windows_event: ?windows.HANDLE = null;

extern "kernel32" fn SetEvent(hEvent: windows.HANDLE) callconv(.winapi) windows.BOOL;

/// Installs interrupt handling and starts the receiver thread.
///
/// The context pointer is passed to the callback without modification.
/// The caller must keep the context alive until uninstall has completed.
///
/// Returns AlreadyInstalled if signal handling is already installed.
/// Returns an error if another installation or uninstallation is in progress.
///
/// The callback must not call uninstall from the receiver thread, because
/// uninstallation waits for that thread to terminate.
pub fn install(ctx: *anyopaque, cb: Callback) !void {
    state_mutex.lock();

    switch (state) {
        .uninstalled => {
            state = .installing;
        },
        .installing => {
            state_mutex.unlock();
            return InstallError.InstallationInProgress;
        },
        .installed => {
            state_mutex.unlock();
            return InstallError.AlreadyInstalled;
        },
        .uninstalling => {
            state_mutex.unlock();
            return InstallError.UninstallationInProgress;
        },
    }

    callback = cb;
    context = ctx;

    stop_requested.store(false, .release);
    signal_pending.store(false, .release);

    state_mutex.unlock();

    install_platform() catch |err| {
        state_mutex.lock();
        callback = null;
        context = null;
        state = .uninstalled;
        state_mutex.unlock();

        return err;
    };

    state_mutex.lock();
    state = .installed;
    state_mutex.unlock();
}

/// Stops signal handling, waits for the receiver thread to terminate,
/// and releases the resources owned by the active installation.
///
/// Does nothing if signal handling is not installed.
/// Returns an error if installation or uninstallation is already in progress.
///
/// The caller must not invoke this function from the receiver callback.
pub fn uninstall() !void {
    state_mutex.lock();

    switch (state) {
        .uninstalled => {
            state_mutex.unlock();
            return;
        },
        .installing => {
            state_mutex.unlock();
            return InstallError.InstallationInProgress;
        },
        .installed => state = .uninstalling,
        .uninstalling => {
            state_mutex.unlock();
            return InstallError.UninstallationInProgress;
        },
    }

    state_mutex.unlock();

    uninstall_platform();

    state_mutex.lock();

    callback = null;
    context = null;
    state = .uninstalled;

    state_mutex.unlock();
}

fn install_platform() !void {
    if (builtin.os.tag == .windows) {
        return try install_windows();
    }
    try install_posix();
}

fn uninstall_platform() void {
    if (builtin.os.tag == .windows) {
        return uninstall_windows();
    }
    uninstall_posix();
}

fn install_windows() !void {
    const event = try get_windows_event();

    stop_requested.store(false, .release);
    signal_pending.store(false, .release);

    const thread = try std.Thread.spawn(
        .{},
        windows_receiver,
        .{event},
    );

    errdefer {
        stop_requested.store(true, .release);
        _ = SetEvent(event);
        thread.join();
    }

    const result = windows.kernel32.SetConsoleCtrlHandler(
        win_ctrl_handler,
        1,
    );

    if (result == 0) {
        return InstallError.FailedToSetCtrlHandler;
    }

    receiver_thread = thread;
}

fn get_windows_event() !windows.HANDLE {
    if (windows_event) |event| {
        return event;
    }

    const event = windows.kernel32.CreateEventExW(
        null,
        null,
        0,
        windows.SYNCHRONIZE | windows.EVENT_MODIFY_STATE,
    ) orelse return InstallError.FailedToCreateEvent;

    windows_event = event;
    return event;
}

fn windows_receiver(event: windows.HANDLE) void {
    while (true) {
        const result = windows.kernel32.WaitForSingleObject(
            event,
            windows.INFINITE,
        );

        if (result != windows.WAIT_OBJECT_0) {
            return;
        }

        if (stop_requested.load(.acquire)) {
            return;
        }

        if (signal_pending.swap(false, .acq_rel)) {
            dispatch_callback();
        }
    }
}

fn uninstall_windows() void {
    const event = windows_event orelse return;

    _ = windows.kernel32.SetConsoleCtrlHandler(
        win_ctrl_handler,
        0,
    );

    stop_requested.store(true, .release);

    _ = SetEvent(event);

    if (receiver_thread) |thread| {
        thread.join();
        receiver_thread = null;
    }
}

fn win_ctrl_handler(ctrl_type: windows.DWORD) callconv(.winapi) windows.BOOL {
    if (ctrl_type != 0 and ctrl_type != 1) {
        return 0;
    }

    const event = windows_event orelse return 0;

    signal_pending.store(true, .release);
    _ = SetEvent(event);

    return 1;
}

fn install_posix() !void {
    var fds: [2]std.posix.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) {
        return InstallError.FailedToCreatePipe;
    }

    signal_write_fd = fds[1];

    errdefer {
        _ = std.c.close(fds[0]);
        _ = std.c.close(fds[1]);
        signal_write_fd = -1;
    }

    const action = std.posix.Sigaction{
        .handler = .{ .handler = unix_sigint_handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    var previous_action: std.posix.Sigaction = undefined;

    std.posix.sigaction(
        std.posix.SIG.INT,
        &action,
        &previous_action,
    );

    errdefer {
        std.posix.sigaction(
            std.posix.SIG.INT,
            &previous_action,
            null,
        );
    }

    posix_resources = .{
        .read_fd = fds[0],
        .write_fd = fds[1],
        .previous_action = previous_action,
    };

    receiver_thread = try std.Thread.spawn(
        .{},
        posix_receiver,
        .{fds[0]},
    );
}

fn posix_receiver(fd: std.posix.fd_t) void {
    var byte: u8 = undefined;

    while (true) {
        const count = std.c.read(fd, @ptrCast(&byte), 1);

        if (count == 1) {
            if (byte == 0) {
                return;
            }

            dispatch_callback();
            continue;
        }

        if (count == 0) {
            return;
        }

        if (std.posix.errno(-1) == .INTR) {
            continue;
        }

        return;
    }
}

fn uninstall_posix() void {
    const resources = posix_resources orelse return;

    std.posix.sigaction(
        std.posix.SIG.INT,
        &resources.previous_action,
        null,
    );

    const stop_byte: u8 = 0;
    _ = std.c.write(
        resources.write_fd,
        @ptrCast(&stop_byte),
        1,
    );

    if (receiver_thread) |thread| {
        thread.join();
        receiver_thread = null;
    }

    _ = std.c.close(resources.read_fd);
    _ = std.c.close(resources.write_fd);

    signal_write_fd = -1;
    posix_resources = null;
}

fn unix_sigint_handler(sig_num: i32) callconv(.c) void {
    _ = sig_num;

    const byte: u8 = 1;
    if (signal_write_fd >= 0) {
        _ = std.c.write(signal_write_fd, @ptrCast(&byte), 1);
    }
}

fn dispatch_callback() void {
    const cb = callback orelse return;
    const ctx = context orelse return;
    cb(ctx);
}

fn testCallback(ctx: *anyopaque) void {
    const calls_ptr: *usize = @ptrCast(@alignCast(ctx));
    calls_ptr.* = calls_ptr.* + 1;
}

test "signals can be installed and uninstalled repeatedly" {
    var calls: usize = 0;

    try install(&calls, testCallback);
    defer uninstall() catch {};

    try std.testing.expectError(
        InstallError.AlreadyInstalled,
        install(&calls, testCallback),
    );

    try uninstall();

    try install(&calls, testCallback);
    try uninstall();
}

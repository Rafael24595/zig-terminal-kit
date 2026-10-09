const std = @import("std");
const builtin = @import("builtin");

pub const Callback = *const fn (*anyopaque) void;

var callback: Callback = undefined;
var context: *anyopaque = undefined;

var signal_write_fd: std.posix.fd_t = -1;

pub fn install(ctx: *anyopaque, cb: Callback) !void {
    context = ctx;
    callback = cb;

    if (builtin.os.tag == .windows) {
        const result = std.os.windows.kernel32.SetConsoleCtrlHandler(
            winCtrlHandler,
            1,
        );

        if (result == 0) {
            return error.FailedToSetCtrlHandler;
        }
        
        return;
    }

    var fds: [2]std.posix.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) {
        return error.FailedToCreatePipe;
    }

    signal_write_fd = fds[1];

    errdefer {
        _ = std.c.close(fds[0]);
        _ = std.c.close(fds[1]);
        signal_write_fd = -1;
    }

    var thread = try std.Thread.spawn(
        .{},
        receiveSignal,
        .{fds[0]},
    );

    thread.detach();

    const action = std.posix.Sigaction{
        .handler = .{ .handler = unixSigintHandler },
        .mask = undefined,
        .flags = 0,
    };

    _ = std.posix.sigaction(std.posix.SIG.INT, &action, null);
}

fn winCtrlHandler(ctrl_type: std.os.windows.DWORD) callconv(.c) std.os.windows.BOOL {
    _ = ctrl_type;
    callback(context);
    return 1;
}

fn unixSigintHandler(sig_num: i32) callconv(.c) void {
    _ = sig_num;

    const byte: u8 = 1;
    _ = std.c.write(signal_write_fd, @ptrCast(&byte), 1);
}

fn receiveSignal(fd: std.posix.fd_t) void {
    var byte: u8 = undefined;

    while (true) {
        const count = std.c.read(fd, @ptrCast(&byte), 1);

        if (count > 0) {
            callback(context);
            return;
        }

        if (count == 0) return;
    }
}

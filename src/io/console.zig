const std = @import("std");
const builtin = @import("builtin");

const win = std.os.windows;
const k32 = win.kernel32;

pub const HIDE_CURSOR = "\x1b[?25l";
pub const SHOW_CURSOR = "\x1b[?25h";

pub const CLEAN_CONSOLE = "\x1B[2J";
pub const CLEAN_HISTORY = "\x1B[3J";
pub const RESET_CURSOR = "\x1b[H";

pub const CLEAN_ALL = CLEAN_CONSOLE ++ CLEAN_HISTORY ++ RESET_CURSOR;

pub const CTRL_C: u8 = 3;

pub const SPACE: u8 = 0x20;
pub const BACKSPACE: u8 = 0x08;
pub const DEL: u8 = 0x7F;

const ENABLE_PROCESSED_INPUT: win.DWORD = 0x0001;
const ENABLE_LINE_INPUT: win.DWORD = 0x0002;
const ENABLE_ECHO_INPUT: win.DWORD = 0x0004;

const ENABLE_VIRTUAL_TERMINAL_PROCESSING: win.DWORD = 0x0004;

var original_termios: ?std.posix.termios = null;
var original_mode: win.DWORD = 0;

pub const WinSize = struct {
    cols: usize,
    rows: usize,
};

pub fn enable_raw_mode() !void {
    if (builtin.os.tag == .windows) {
        return try enable_raw_mode_windows();
    }

    try enable_raw_mode_posix();
}

pub fn disable_raw_mode() void {
    if (builtin.os.tag == .windows) {
        return disable_raw_mode_windows();
    }

    disable_raw_mode_posix();
}

fn enable_raw_mode_posix() !void {
    const fd: std.posix.fd_t = std.posix.STDIN_FILENO;

    var tio = try std.posix.tcgetattr(fd);
    original_termios = tio;

    tio.lflag.ICANON = false;
    tio.lflag.ECHO = false;

    tio.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    tio.cc[@intFromEnum(std.posix.V.TIME)] = 1;

    try std.posix.tcsetattr(fd, .FLUSH, tio);
}

fn disable_raw_mode_posix() void {
    if (original_termios) |tio| {
        _ = std.posix.tcsetattr(
            std.posix.STDIN_FILENO,
            .FLUSH,
            tio,
        ) catch {};
    }
}

fn enable_raw_mode_windows() !void {
    const handle = k32.GetStdHandle(
        win.STD_INPUT_HANDLE,
    ) orelse return error.NoStdInput;

    var original: win.DWORD = undefined;
    if (k32.GetConsoleMode(handle, &original) == 0) {
        return error.ConsoleMode;
    }

    var mode = original;

    mode &= ~ENABLE_LINE_INPUT;
    mode &= ~ENABLE_ECHO_INPUT;
    mode &= ~ENABLE_PROCESSED_INPUT;

    if (k32.SetConsoleMode(handle, mode) == 0) {
        return error.ConsoleMode;
    }

    original_mode = original;
    windows_raw_mode_enabled = true;
}

fn disable_raw_mode_windows() void {
    if (!windows_raw_mode_enabled) {
        return;
    }

    const handle = k32.GetStdHandle(
        win.STD_INPUT_HANDLE,
    ) orelse return;

    if (k32.SetConsoleMode(handle, original_mode) != 0) {
        windows_raw_mode_enabled = false;
    }
}

pub fn enable_ansi() !void {
    if (builtin.os.tag != .windows) {
        return;
    }

    const handle = k32.GetStdHandle(
        win.STD_OUTPUT_HANDLE,
    ) orelse return error.NoStdout;

    var mode: win.DWORD = undefined;
    if (k32.GetConsoleMode(handle, &mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    const new_mode = mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (new_mode == mode) {
        return;
    }

    if (k32.SetConsoleMode(handle, new_mode) == 0) {
        return error.SetConsoleModeFailed;
    }
}

pub fn enable_utf8() !void {
    if (builtin.os.tag != .windows) {
        return;
    }

    if (k32.SetConsoleOutputCP(65001) == 0) {
        return error.SetConsoleOutputCPFailed;
    }
}

pub fn winsize() !WinSize {
    if (comptime builtin.os.tag == .windows) {
        return windows_winsize();
    }

    if (comptime builtin.os.tag == .linux) {
        return linux_winsize();
    }

    return error.InvalidConsoleSize;
}

fn linux_winsize() !WinSize {
    var ws: std.posix.winsize = undefined;

    const err = std.os.linux.ioctl(
        std.posix.STDOUT_FILENO,
        std.os.linux.T.IOCGWINSZ,
        @intFromPtr(&ws),
    );

    if (err < 0) {
        return error.IoctlFailed;
    }

    const cols: usize = @intCast(ws.col);
    const rows: usize = @intCast(ws.row);

    if (rows == 0 or cols == 0) {
        return error.InvalidConsoleSize;
    }

    return WinSize{
        .cols = cols,
        .rows = rows,
    };
}

fn windows_winsize() !WinSize {
    var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

    const hConsole = k32.GetStdHandle(
        win.STD_OUTPUT_HANDLE,
    ) orelse return error.NoStdout;

    const ok = k32.GetConsoleScreenBufferInfo(hConsole, &info);
    if (ok == 0) {
        return error.WinAPI;
    }

    const rows: i32 =
        @as(i32, info.srWindow.Bottom) -
        @as(i32, info.srWindow.Top) + 1;

    const cols: i32 =
        @as(i32, info.srWindow.Right) -
        @as(i32, info.srWindow.Left) + 1;

    if (rows <= 0 or cols <= 0) {
        return error.InvalidConsoleSize;
    }

    return .{
        .cols = @intCast(cols),
        .rows = @intCast(rows),
    };
}

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

var original_termios: ?std.posix.termios = null;
var original_mode: win.DWORD = 0;

pub const WinSize = struct {
    cols: usize,
    rows: usize,
};

pub fn enableRawMode() !void {
    if (builtin.os.tag == .windows) {
        return try enableRawModeWindows();
    }

    try enableRawModePosix();
}

pub fn disableRawMode() void {
    if (builtin.os.tag == .windows) {
        return disableRawModeWindows();
    }

    disableRawModePosix();
}

fn enableRawModePosix() !void {
    const fd: std.posix.fd_t = std.posix.STDIN_FILENO;

    var tio = try std.posix.tcgetattr(fd);
    original_termios = tio;

    tio.lflag.ICANON = false;
    tio.lflag.ECHO = false;

    tio.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    tio.cc[@intFromEnum(std.posix.V.TIME)] = 1;

    try std.posix.tcsetattr(fd, .FLUSH, tio);
}

fn disableRawModePosix() void {
    if (original_termios) |tio| {
        _ = std.posix.tcsetattr(
            std.posix.STDIN_FILENO,
            .FLUSH,
            tio,
        ) catch {};
    }
}

fn enableRawModeWindows() !void {
    const h = k32.GetStdHandle(win.STD_INPUT_HANDLE);

    if (k32.GetConsoleMode(h.?, &original_mode) == 0) {
        return error.ConsoleMode;
    }

    var mode = original_mode;

    mode &= ~ENABLE_LINE_INPUT;
    mode &= ~ENABLE_ECHO_INPUT;
    mode &= ~ENABLE_PROCESSED_INPUT;

    if (k32.SetConsoleMode(h.?, mode) == 0) {
        return error.ConsoleMode;
    }
}

fn disableRawModeWindows() void {
    const h = k32.GetStdHandle(win.STD_INPUT_HANDLE);
    _ = k32.SetConsoleMode(h.?, original_mode);
}

pub fn enableANSI() !void {
    if (builtin.os.tag == .windows) {
        const oHandle = k32.GetStdHandle(win.STD_OUTPUT_HANDLE);
        if (oHandle == null) {
            return;
        }

        const handle = oHandle.?;
        var mode: u32 = 0;
        if (k32.GetConsoleMode(handle, &mode) == 0) {
            return;
        }

        _ = k32.SetConsoleMode(handle, mode | 0x0004);
    }
}

pub fn enableUTF8() !void {
    if (builtin.os.tag == .windows) {
        _ = k32.SetConsoleOutputCP(65001);
    }
}

pub fn winSize() !WinSize {
    return switch (builtin.os.tag) {
        .linux => linuxWinSize(),
        .windows => windowsWinSize(),
        else => WinSize{ .cols = 0, .rows = 0 },
    };
}

pub fn linuxWinSize() !WinSize {
    var ws: std.posix.winsize = undefined;

    const err = std.os.linux.ioctl(
        std.posix.STDOUT_FILENO,
        std.os.linux.T.IOCGWINSZ,
        @intFromPtr(&ws),
    );

    if (err == -1) {
        return error.IoctlFailed;
    }

    const cols: usize = @intCast(ws.col);
    const rows: usize = @intCast(ws.row);

    return WinSize{ .cols = cols, .rows = rows };
}

pub fn windowsWinSize() !WinSize {
    var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

    const hConsole = k32.GetStdHandle(win.STD_OUTPUT_HANDLE) orelse return error.NoStdout;

    const ok = k32.GetConsoleScreenBufferInfo(hConsole, &info);
    if (ok == 0) return error.WinAPI;

    const rows: usize = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
    const cols: usize = @intCast(info.srWindow.Right - info.srWindow.Left + 1);

    return WinSize{ .cols = cols, .rows = rows };
}

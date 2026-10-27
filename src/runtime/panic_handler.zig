const std = @import("std");

/// Returns a custom panic handler type that executes the given recovery
/// function before standard panic handling.
///
/// Example:
/// ```zig
/// pub const panic = PanicHandler(cleanup).panic;
///
/// fn cleanup() void {
///     console.disable_mouse();
///     console.disable_ansi_input();
///     console.disable_raw_mode();
///
///     const stdout = std.fs.File.stdout();
///     stdout.writeAll(
///         console.SHOW_CURSOR ++
///             console.CLEAN_ALL ++
///             console.RESET_CURSOR,
///     ) catch {};
/// }
pub fn PanicHandler(comptime recovery: fn () void) type {
    return struct {
        pub const panic = std.debug.FullPanic(handlePanic);

        fn handlePanic(
            msg: []const u8,
            first_trace_addr: ?usize,
        ) noreturn {
            recovery();
            std.debug.defaultPanic(msg, first_trace_addr);
        }
    };
}

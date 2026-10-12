const std = @import("std");

/// Provides formatted output to a file using an arena for temporary strings.
///
/// The arena must remain valid for the lifetime of the Printer and any
/// formatted strings that have not yet been discarded by reset().
pub const Printer = struct {
    /// Arena used to allocate formatted strings.
    arena: *std.heap.ArenaAllocator,
    /// Destination file for printed output.
    out: std.fs.File,

    /// Writes a byte slice to the output file.
    ///
    /// Returns an error if the write operation fails.
    pub fn print(self: *@This(), bytes: []const u8) !void {
        try self.out.writeAll(bytes);
    }

    /// Formats a message and writes it to the output file.
    ///
    /// The formatted string is allocated in the arena and remains valid
    /// until the arena is reset or deinitialized.
    pub fn printf(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        const msg = try self.format(fmt, args);
        try self.print(msg);
    }

    /// Writes a byte slice to the output file, ignoring any write errors.
    ///
    /// Use this method only when output failure can safely be ignored.
    pub fn prints(self: *@This(), bytes: []const u8) void {
        self.out.writeAll(bytes) catch {};
    }

    /// Formats a string and allocates the result in the arena.
    ///
    /// The caller does not need to free the returned slice individually.
    /// Its memory is reclaimed when reset() is called or the arena is
    /// deinitialized.
    pub fn format(self: *@This(), comptime fmt: []const u8, args: anytype) ![]u8 {
        return try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
    }

    /// Releases the arena's current allocations while keeping the arena
    /// available for subsequent formatting operations.
    ///
    /// Any previously returned formatted strings become invalid after reset.
    pub fn reset(self: *@This()) void {
        _ = self.arena.reset(.free_all);
    }
};

test "format returns a formatted string" {
    var arena = std.heap.ArenaAllocator.init(
        std.testing.allocator,
    );

    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format("Hello, {s}!", .{"world"});
    try std.testing.expectEqualStrings("Hello, world!", result);
}

test "format supports multiple argument types" {
    var arena = std.heap.ArenaAllocator.init(
        std.testing.allocator,
    );

    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format(
        "{s} {d} {s}",
        .{ "Count:", 42, "items" },
    );

    try std.testing.expectEqualStrings("Count: 42 items", result);
}

test "reset allows subsequent formatting" {
    var arena = std.heap.ArenaAllocator.init(
        std.testing.allocator,
    );

    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const first = try printer.format("First: {d}", .{1});
    try std.testing.expectEqualStrings("First: 1", first);

    printer.reset();

    const second = try printer.format("Second: {d}", .{2});
    try std.testing.expectEqualStrings("Second: 2", second);
}

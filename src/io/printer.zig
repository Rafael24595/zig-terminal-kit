const std = @import("std");

pub const Printer = struct {
    arena: *std.heap.ArenaAllocator,
    out: std.fs.File,

    pub fn print(self: *@This(), bytes: []const u8) !void {
        try self.out.writeAll(bytes);
    }

    pub fn printf(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        const msg = try self.format(fmt, args);
        try self.print(msg);
    }

    pub fn prints(self: *@This(), bytes: []const u8) void {
        self.out.writeAll(bytes) catch {};
    }

    pub fn format(self: *@This(), comptime fmt: []const u8, args: anytype) ![]u8 {
        return try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
    }

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

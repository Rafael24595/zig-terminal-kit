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

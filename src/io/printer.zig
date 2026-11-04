const std = @import("std");

/// Represents a text string that has been formatted with a maximum width and cursor position.
pub const LimitedText = struct {
    /// The formatted text string, which may be truncated with '~' characters to indicate omitted content.
    text: []const u8,
    /// The maximum cursor position that can be used to scroll through the text.
    max_cursor: usize,
};

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
    pub fn printf(
        self: *@This(),
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
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
    pub fn format(
        self: *@This(),
        comptime fmt: []const u8,
        args: anytype,
    ) ![]u8 {
        return try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
    }

    /// Formats a string with a maximum width and returns a LimitedText struct.
    ///
    /// The LimitedText struct contains the formatted text and the maximum cursor position.
    /// The formatted text is allocated in the arena and remains valid until the arena is reset or deinitialized.
    pub fn format_limited(
        self: *@This(),
        cursor: usize,
        width: usize,
        comptime fmt: []const u8,
        args: anytype,
    ) !LimitedText {
        if (width == 0) {
            return .{
                .text = "",
                .max_cursor = 0,
            };
        }

        const source = try self.format(fmt, args);

        const source_len = source.len;
        if (source_len <= width) {
            return .{
                .text = source,
                .max_cursor = 0,
            };
        }

        var capacity = width;

        var left: usize = 0;
        if (cursor > 0) {
            left = 1;
            capacity -= left;
        }

        const max_start = source_len - capacity;
        const offset = @min(cursor, max_start);
        const remaining = source_len - offset;

        var right: usize = 0;
        if (remaining > capacity) {
            right = 1;
            capacity -= right;
        }

        const content = @min(remaining, capacity);

        return self.build_limited_text(
            width,
            source,
            offset,
            left,
            right,
            content,
        );
    }

    inline fn build_limited_text(
        self: *@This(),
        width: usize,
        source: []u8,
        offset: usize,
        left: usize,
        right: usize,
        content: usize,
    ) !LimitedText {
        const result_len = left + content + right;
        const text = try self.arena.allocator().alloc(u8, result_len);

        var index: usize = 0;

        if (left > 0) {
            text[index] = '~';
            index += 1;
        }

        @memcpy(
            text[index..][0..content],
            source[offset..][0..content],
        );

        if (right > 0) {
            index += content;
            text[index] = '~';
        }

        var max_cursor: usize = 0;
        if (source.len > width and width > 1) {
            max_cursor = source.len - (width - 1);
        }

        return .{
            .text = text,
            .max_cursor = max_cursor,
        };
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

test "format_limited: text fits without truncation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        0,
        10,
        "{s}",
        .{"hello"},
    );

    try std.testing.expectEqualStrings("hello", result.text);
    try std.testing.expectEqual(0, result.max_cursor);
}

test "format_limited: starts at beginning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        0,
        5,
        "{s}",
        .{"abcdefghij"},
    );

    try std.testing.expectEqualStrings("abcd~", result.text);
    try std.testing.expectEqual(6, result.max_cursor);
}

test "format_limited: scrolls from beginning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        2,
        5,
        "{s}",
        .{"abcdefghij"},
    );

    try std.testing.expectEqualStrings("~cde~", result.text);
    try std.testing.expectEqual(6, result.max_cursor);
}

test "format_limited: reaches end" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        100,
        5,
        "{s}",
        .{"abcdefghij"},
    );

    try std.testing.expectEqualStrings("~ghij", result.text);
    try std.testing.expectEqual(6, result.max_cursor);
}

test "format_limited: clamps cursor to maximum offset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        100,
        8,
        "{s}",
        .{"abcdefghijklmnopqrstuvwxyz"},
    );

    try std.testing.expectEqualStrings("~tuvwxyz", result.text);
    try std.testing.expectEqual(19, result.max_cursor);
}

test "format_limited: cursor advances independently for different lengths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const short = try printer.format_limited(
        34,
        85,
        "{s}",
        .{"short text"},
    );

    const long = try printer.format_limited(
        34,
        85,
        "Scroll left: [,] | " ++
            "Scroll right: [.] | " ++
            "Pause: [p, space] | " ++
            "Inc sleep: [+] | " ++
            "Dec sleep: [-] | " ++
            "Drain: [d] | " ++
            "Orientation: [o] | " ++
            "Flux: [f] | " ++
            "Show debug: [/] | " ++
            "Show controls: [*] | " ++
            "Exit: [q, ctrl+c]",
        .{},
    );

    try std.testing.expectEqual(0, short.max_cursor);
    try std.testing.expectEqual(109, long.max_cursor);

    try std.testing.expect(long.text.len <= 85);
}

test "format_limited: zero width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        0,
        0,
        "{s}",
        .{"hello"},
    );

    try std.testing.expectEqualStrings("", result.text);
    try std.testing.expectEqual(0, result.max_cursor);
}

test "format_limited: width one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        0,
        1,
        "{s}",
        .{"abc"},
    );

    try std.testing.expect(result.text.len <= 1);
}

test "format_limited: empty text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        0,
        5,
        "{s}",
        .{""},
    );

    try std.testing.expectEqualStrings("", result.text);
    try std.testing.expectEqual(0, result.max_cursor);
}

test "format_limited: exact width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = undefined,
    };

    const result = try printer.format_limited(
        0,
        5,
        "{s}",
        .{"abcde"},
    );

    try std.testing.expectEqualStrings("abcde", result.text);
    try std.testing.expectEqual(0, result.max_cursor);
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

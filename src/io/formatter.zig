const std = @import("std");

const testing = std.testing;

const Printer = @import("../io/printer.zig").Printer;

const color = @import("../style/color.zig");

/// Represents a value that can be converted to a formatted string.
pub const TypeFormatter = union(enum) {
    none,
    str: []const u8,
    bool: bool,
    int: i64,
    float: f64,

    pub fn format(self: TypeFormatter, printer: *Printer) ![]u8 {
        return switch (self) {
            .none => "",
            .str => |s| printer.format("{s}", .{s}),
            .bool => |b| printer.format("{s}", .{if (b) "true" else "false"}),
            .int => |i| printer.format("{d}", .{i}),
            .float => |f| printer.format("{d:.2}", .{f}),
        };
    }
};

/// Represents a matrix formatter that can be used to colorize output.
pub const FormatterMatrixUnion = union(enum) {
    /// Selects the ANSI 256 color formatter.
    ansi: FormatterMatrix(
        "\x1b[38;5;{d}m{s}",
        "\x1b[0m",
        format_ansi,
    ),

    /// Selects the RGB color formatter.
    rgb: FormatterMatrix(
        "\x1b[38;2;{d};{d};{d}m{s}",
        "\x1b[0m",
        format_rgb,
    ),

    /// Selects the unformatted formatter (no color).
    unfo: FormatterMatrix(
        "",
        "\x1b[0m",
        unformatted,
    ),

    /// Returns the combined prefix and suffix byte length.
    pub fn fmt_bytes(self: @This()) usize {
        return switch (self) {
            .ansi => |f| f.fmt_bytes(),
            .rgb => |f| f.fmt_bytes(),
            .unfo => |f| f.fmt_bytes(),
        };
    }

    /// Returns the format string used for the color prefix.
    pub fn prefix(self: @This()) []const u8 {
        return switch (self) {
            .ansi => |f| f.prefix(),
            .rgb => |f| f.prefix(),
            .unfo => |f| f.prefix(),
        };
    }

    /// Returns the format string used to reset the color.
    pub fn sufix(self: @This()) []const u8 {
        return switch (self) {
            .ansi => |f| f.sufix(),
            .rgb => |f| f.sufix(),
            .unfo => |f| f.sufix(),
        };
    }

    /// Formats the color prefix into the provided buffer.
    pub fn format_prefix(
        self: @This(),
        buf: []u8,
        r: u8,
        g: u8,
        b: u8,
    ) []const u8 {
        return switch (self) {
            .ansi => |f| f.format_prefix(buf, r, g, b),
            .rgb => |f| f.format_prefix(buf, r, g, b),
            .unfo => |f| f.format_prefix(buf, r, g, b),
        };
    }
};

/// Represents a cell formatter that can be used to colorize individual characters.
pub const FormatterCellUnion = union(enum) {
    /// Selects the ANSI 256 color formatter.
    ansi: FormatterCell(
        "\x1b[38;5;{d}m{s}",
        format_ansi,
    ),

    /// Selects the RGB color formatter.
    rgb: FormatterCell(
        "\x1b[38;2;{d};{d};{d}m{s}",
        format_rgb,
    ),

    /// Selects the unformatted formatter (no color).
    unfo: FormatterCell(
        "{s}",
        unformatted,
    ),

    /// Returns the byte length of the cell format string.
    pub fn fmt_bytes(self: @This()) usize {
        return switch (self) {
            .ansi => |f| f.fmt_bytes(),
            .rgb => |f| f.fmt_bytes(),
            .unfo => |f| f.fmt_bytes(),
        };
    }

    /// Formats a cell using the selected color format.
    pub fn format(
        self: @This(),
        buf: []u8,
        r: u8,
        g: u8,
        b: u8,
        c: []const u8,
    ) ![]const u8 {
        return switch (self) {
            .ansi => |f| f.format(buf, r, g, b, c),
            .rgb => |f| f.format(buf, r, g, b, c),
            .unfo => |f| f.format(buf, r, g, b, c),
        };
    }
};

fn FormatterMatrix(
    comptime prefix_fmt: []const u8,
    comptime sufix_fmt: []const u8,
    comptime adapter: fn (
        buffer: []u8,
        comptime fmt: []const u8,
        r: u8,
        g: u8,
        b: u8,
        c: []const u8,
    ) []const u8,
) type {
    return struct {
        pub fn fmt_bytes(_: @This()) usize {
            return prefix_fmt.len + sufix_fmt.len;
        }

        pub fn prefix(_: @This()) []const u8 {
            return prefix_fmt;
        }

        pub fn sufix(_: @This()) []const u8 {
            return sufix_fmt;
        }

        pub fn format_prefix(
            _: @This(),
            buf: []u8,
            r: u8,
            g: u8,
            b: u8,
        ) []const u8 {
            return adapter(buf, prefix_fmt, r, g, b, "");
        }
    };
}

fn FormatterCell(
    comptime char_fmt: []const u8,
    comptime adapter: fn (
        buffer: []u8,
        comptime fmt: []const u8,
        r: u8,
        g: u8,
        b: u8,
        c: []const u8,
    ) []const u8,
) type {
    return struct {
        pub fn fmt_bytes(_: @This()) usize {
            return char_fmt.len;
        }

        pub fn format(
            _: @This(),
            buf: []u8,
            r: u8,
            g: u8,
            b: u8,
            c: []const u8,
        ) []const u8 {
            return adapter(buf, char_fmt, r, g, b, c);
        }
    };
}

fn unformatted(
    _: []u8,
    comptime _: []const u8,
    _: u8,
    _: u8,
    _: u8,
    c: []const u8,
) []const u8 {
    return c;
}

fn format_ansi(
    buffer: []u8,
    comptime fmt: []const u8,
    r: u8,
    g: u8,
    b: u8,
    c: []const u8,
) []const u8 {
    const a = color.rgb_to_ansi256(r, g, b);
    return std.fmt.bufPrint(
        buffer,
        fmt,
        .{ a, c },
    ) catch unreachable;
}

fn format_rgb(
    buffer: []u8,
    comptime fmt: []const u8,
    r: u8,
    g: u8,
    b: u8,
    c: []const u8,
) []const u8 {
    return std.fmt.bufPrint(
        buffer,
        fmt,
        .{ r, g, b, c },
    ) catch unreachable;
}

test "TypeFormatter - none" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var fmt = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    defer fmt.reset();

    const tf = TypeFormatter{ .none = {} };
    const result = try tf.format(&fmt);

    try testing.expectEqualStrings("", result);
}

test "TypeFormatter - string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var fmt = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    defer fmt.reset();

    const tf = TypeFormatter{ .str = "hola" };
    const result = try tf.format(&fmt);

    try testing.expectEqualStrings("hola", result);
}

test "TypeFormatter - bool true" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var fmt = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    defer fmt.reset();

    const tf = TypeFormatter{ .bool = true };
    const result = try tf.format(&fmt);

    try testing.expectEqualStrings("true", result);
}

test "TypeFormatter - bool false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var fmt = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    defer fmt.reset();

    const tf = TypeFormatter{ .bool = false };
    const result = try tf.format(&fmt);

    try testing.expectEqualStrings("false", result);
}

test "TypeFormatter - int" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var fmt = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    defer fmt.reset();

    const tf = TypeFormatter{ .int = 42 };
    const result = try tf.format(&fmt);

    try testing.expectEqualStrings("42", result);
}

test "TypeFormatter - float" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var fmt = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    defer fmt.reset();

    const tf = TypeFormatter{ .float = 3.14159 };
    const result = try tf.format(&fmt);

    try testing.expectEqualStrings("3.14", result);
}

test "cell formatter formats RGB colors" {
    const formatter: FormatterCellUnion = .{ .rgb = .{} };
    var buffer: [64]u8 = undefined;

    const result = try formatter.format(
        &buffer,
        255,
        0,
        0,
        "X",
    );

    try std.testing.expectEqualStrings("\x1b[38;2;255;0;0mX", result);
}

test "cell formatter returns unformatted characters" {
    const formatter: FormatterCellUnion = .{ .unfo = .{} };
    var buffer: [64]u8 = undefined;

    const result = try formatter.format(
        &buffer,
        255,
        0,
        0,
        "X",
    );

    try std.testing.expectEqualStrings("X", result);
}

test "cell formatter formats ANSI colors" {
    const formatter: FormatterCellUnion = .{ .ansi = .{} };
    var buffer: [64]u8 = undefined;

    const result = try formatter.format(
        &buffer,
        255,
        0,
        0,
        "X",
    );

    try std.testing.expectEqualStrings("\x1b[38;5;196mX", result);
}

test "matrix formatter formats RGB prefix" {
    const formatter: FormatterMatrixUnion = .{ .rgb = .{} };
    var buffer: [64]u8 = undefined;

    const result = formatter.format_prefix(
        &buffer,
        255,
        0,
        0,
    );

    try std.testing.expectEqualStrings("\x1b[38;2;255;0;0m", result);
}

test "matrix formatter returns an empty prefix when unformatted" {
    const formatter: FormatterMatrixUnion = .{ .unfo = .{} };
    var buffer: [64]u8 = undefined;

    const result = formatter.format_prefix(
        &buffer,
        255,
        0,
        0,
    );

    try std.testing.expectEqualStrings("", result);
}

test "matrix formatter exposes prefix and suffix lengths" {
    const formatter: FormatterMatrixUnion = .{ .rgb = .{} };

    try std.testing.expectEqualStrings(
        "\x1b[38;2;{d};{d};{d}m{s}",
        formatter.prefix(),
    );
    try std.testing.expectEqualStrings("\x1b[0m", formatter.sufix());
    try std.testing.expectEqual(
        formatter.prefix().len + formatter.sufix().len,
        formatter.fmt_bytes(),
    );
}

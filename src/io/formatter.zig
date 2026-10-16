const std = @import("std");

const testing = std.testing;

const Printer = @import("../io/printer.zig").Printer;

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

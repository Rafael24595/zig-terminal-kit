const std = @import("std");

const Printer = @import("../io/printer.zig").Printer;
const TypeFormatter = @import("../commons/utils.zig").TypeFormatter;

const ParseError = error{
    InvalidValue,
    InvalidBounds,
    MissingArgument,
};

/// Describes a command-line flag and its help-text metadata.
pub const Flag = struct {
    /// Short form of the flag, such as "-v".
    flag_short: []const u8,
    /// Optional long form of the flag, such as "--verbose".
    flag_long: ?[]const u8 = null,
    /// Optional type label displayed in the help text.
    type: ?[]const u8 = null,
    /// Main description displayed next to the flag.
    desc: []const u8,
    /// Internal or canonical name used in messages and parsing.
    name: []const u8,
    /// Optional additional description displayed on a separate line.
    aux_desc: ?[]const u8 = null,
};

/// Formats a flag as a help-text row.
///
/// Optional fields are rendered as empty strings when absent.
/// A default value is appended unless it is `.none`.
/// An auxiliary description, when present, is displayed on a new line.
///
/// The returned slice is managed by the supplied Printer.
pub fn format_flag(
    printer: *Printer,
    flag: Flag,
    default: TypeFormatter,
) ![]u8 {
    const flag_short = flag.flag_short;
    const flag_desc = flag.desc;

    var flag_long: []const u8 = "";
    if (flag.flag_long != null) {
        flag_long = flag.flag_long.?;
    }

    var flag_type: []const u8 = "";
    if (flag.type != null) {
        flag_type = flag.type.?;
    }

    var data = try printer.format(
        "  {s:<3} {s:<12}  {s:<8}  {s}",
        .{ flag_short, flag_long, flag_type, flag_desc },
    );

    if (default != .none) {
        const d = try default.format(printer);
        data = try printer.format("{s} (default: {s})", .{ data, d });
    }

    if (flag.aux_desc != null) {
        data = try printer.format("{s}\n{s:<32}{s}", .{ data, "", flag.aux_desc.? });
    }

    return try printer.format("{s} \n", .{data});
}

/// Parses the argument following a flag as a floating-point value.
///
/// If min or max is provided, the parsed value is clamped to those bounds.
/// Missing or invalid values are reported and terminate the process with
/// exit code 1.
///
/// The caller must ensure that T is a supported floating-point type.
pub fn parse_float(
    comptime T: type,
    printer: *Printer,
    args: [][:0]u8,
    i: usize,
    flag: Flag,
    min: ?T,
    max: ?T,
) !T {
    if (i + 1 >= args.len) {
        try printer.printf("Missing argument for {s} ({s})\n", .{ flag.flag_short, flag.name });
        std.process.exit(1);
    }

    const value = args[i + 1];

    return parse_float_value(T, value, min, max) catch |err| {
        switch (err) {
            ParseError.InvalidValue => try printer.printf(
                "Invalid {s} value: {s}\n",
                .{ flag.name, value },
            ),
            ParseError.InvalidBounds => try printer.printf(
                "Invalid bounds for {s}\n",
                .{flag.name},
            ),
            ParseError.MissingArgument => unreachable,
        }

        std.process.exit(1);
    };
}

fn parse_float_value(
    comptime T: type,
    value: []const u8,
    min: ?T,
    max: ?T,
) ParseError!T {
    if (min != null and max != null and min.? > max.?) {
        return ParseError.InvalidBounds;
    }

    var result = std.fmt.parseFloat(T, value) catch {
        return ParseError.InvalidValue;
    };

    if (min) |lower| {
        result = @max(result, lower);
    }

    if (max) |upper| {
        result = @min(result, upper);
    }

    return result;
}

/// Parses the argument following a flag as a base-10 integer.
///
/// If min or max is provided, the parsed value is clamped to those bounds.
/// Missing or invalid values are reported and terminate the process with
/// exit code 1.
///
/// The caller must ensure that T is a supported integer type.
pub fn parse_int(
    comptime T: type,
    printer: *Printer,
    args: [][:0]u8,
    i: usize,
    flag: Flag,
    min: ?T,
    max: ?T,
) !T {
    if (i + 1 >= args.len) {
        try printer.printf("Missing argument for {s} ({s})\n", .{ flag.flag_short, flag.name });
        std.process.exit(1);
    }

    const value = args[i + 1];

    return parse_int_value(T, value, min, max) catch |err| {
        switch (err) {
            ParseError.InvalidValue => try printer.printf(
                "Invalid {s} value: {s}\n",
                .{ flag.name, value },
            ),
            ParseError.InvalidBounds => try printer.printf(
                "Invalid bounds for {s}\n",
                .{flag.name},
            ),
            ParseError.MissingArgument => unreachable,
        }

        std.process.exit(1);
    };
}

fn parse_int_value(
    comptime T: type,
    value: []const u8,
    min: ?T,
    max: ?T,
) ParseError!T {
    if (min != null and max != null and min.? > max.?) {
        return ParseError.InvalidBounds;
    }

    var result = std.fmt.parseInt(T, value, 10) catch {
        return ParseError.InvalidValue;
    };

    if (min) |lower| {
        result = @max(result, lower);
    }

    if (max) |upper| {
        result = @min(result, upper);
    }

    return result;
}

/// Parses the argument following a flag as an enum field name.
///
/// Passing "help" prints the available enum options using the flag name
/// as the heading, then exits successfully.
/// Invalid values print an error and the available options before exiting
/// with exit code 1.
pub fn parse_enum(
    comptime T: type,
    printer: *Printer,
    args: [][:0]u8,
    i: usize,
    flag: Flag,
) !T {
    if (i + 1 >= args.len) {
        try printer.printf("Missing argument for {s} ({s})\n", .{ flag.flag_short, flag.name });
        std.process.exit(1);
    }

    const value = args[i + 1];

    if (std.mem.eql(u8, value, "help")) {
        try print_enum_options_with_title(T, flag.name, printer);
        std.process.exit(0);
    }

    return parse_enum_value(T, value) catch {
        try printer.printf("Invalid {s}: {s}\n", .{ flag.name, value });
        try print_enum_options(T, printer);
        std.process.exit(1);
    };
}

fn parse_enum_value(comptime T: type, value: []const u8) error{InvalidValue}!T {
    return std.meta.stringToEnum(T, value) orelse ParseError.InvalidValue;
}

fn print_enum_options(comptime T: type, printer: *Printer) !void {
    try print_enum_options_with_title(T, "Available", printer);
}

fn print_enum_options_with_title(comptime T: type, title: []const u8, printer: *Printer) !void {
    const info = @typeInfo(T);
    try printer.printf("{s} options:\n", .{title});
    inline for (info.@"enum".fields) |field| {
        try printer.printf(" - {s}\n", .{field.name});
    }
}

const TestMode = enum {
    fast,
    safe,
    debug,
};

test "parse_int_value parses decimal integers" {
    try std.testing.expectEqual(
        42,
        try parse_int_value(i32, "42", null, null),
    );

    try std.testing.expectEqual(
        -12,
        try parse_int_value(i32, "-12", null, null),
    );
}

test "parse_int_value clamps values to bounds" {
    try std.testing.expectEqual(
        10,
        try parse_int_value(i32, "5", 10, 100),
    );

    try std.testing.expectEqual(
        100,
        try parse_int_value(i32, "150", 10, 100),
    );
}

test "parse_int_value rejects invalid input" {
    try std.testing.expectError(
        ParseError.InvalidValue,
        parse_int_value(i32, "abc", null, null),
    );

    try std.testing.expectError(
        ParseError.InvalidValue,
        parse_int_value(i32, "12.5", null, null),
    );
}

test "parse_int_value rejects inverted bounds" {
    try std.testing.expectError(
        ParseError.InvalidBounds,
        parse_int_value(i32, "42", 100, 10),
    );
}

test "parse_float_value parses decimal values" {
    const result = try parse_float_value(f64, "3.25", null, null);
    try std.testing.expectApproxEqAbs(3.25, result, 0.000001);
}

test "parse_float_value clamps values to bounds" {
    const lower_result = try parse_float_value(f64, "2.5", 5.0, 10.0);
    try std.testing.expectEqual(5.0, lower_result);

    const upper_result = try parse_float_value(f64, "12.5", 5.0, 10.0);
    try std.testing.expectEqual(10.0, upper_result);
}

test "parse_float_value rejects invalid input" {
    try std.testing.expectError(
        ParseError.InvalidValue,
        parse_float_value(f64, "not-a-number", null, null),
    );
}

test "parse_float_value rejects inverted bounds" {
    try std.testing.expectError(
        ParseError.InvalidBounds,
        parse_float_value(f64, "42.0", 100.0, 10.0),
    );
}

test "parse_enum_value accepts valid field names" {
    try std.testing.expectEqual(
        TestMode.fast,
        try parse_enum_value(TestMode, "fast"),
    );

    try std.testing.expectEqual(
        TestMode.safe,
        try parse_enum_value(TestMode, "safe"),
    );
}

test "parse_enum_value rejects unknown field names" {
    try std.testing.expectError(
        ParseError.InvalidValue,
        parse_enum_value(TestMode, "unknown"),
    );

    try std.testing.expectError(
        ParseError.InvalidValue,
        parse_enum_value(TestMode, "FAST"),
    );
}

test "format_flag includes short flag and description" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    const flag = Flag{
        .flag_short = "-v",
        .desc = "Enable verbose output",
        .name = "verbose",
    };

    const result = try format_flag(
        &printer,
        flag,
        .{ .none = {} },
    );

    try std.testing.expect(std.mem.indexOf(u8, result, "-v") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, result, "Enable verbose output") != null,
    );
    try std.testing.expect(std.mem.indexOf(u8, result, "default:") == null);
}

test "format_flag includes optional fields and default value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var printer = Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    const flag = Flag{
        .flag_short = "-n",
        .flag_long = "--number",
        .type = "INT",
        .desc = "Number of items",
        .name = "number",
        .aux_desc = "Must be between 1 and 10",
    };

    const result = try format_flag(
        &printer,
        flag,
        .{ .int = 5 },
    );

    try std.testing.expect(std.mem.indexOf(u8, result, "--number") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "INT") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "default: 5") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, result, "Must be between 1 and 10") != null,
    );
}

const std = @import("std");

const Printer = @import("../io/printer.zig").Printer;
const TypeFormatter = @import("../commons/utils.zig").TypeFormatter;

pub const Flag = struct {
    flag_short: []const u8,
    flag_long: ?[]const u8 = null,
    type: ?[]const u8 = null,
    desc: []const u8,
    name: []const u8,
    aux_desc: ?[]const u8 = null,
};

pub fn format_flag(printer: *Printer, flag: Flag, default: TypeFormatter) ![]u8 {
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

    var data = try printer.format("  {s:<3} {s:<12}  {s:<8}  {s}", .{ flag_short, flag_long, flag_type, flag_desc });

    if (default != .none) {
        const d = try default.format(printer);
        data = try printer.format("{s} (default: {s})", .{ data, d });
    }

    if (flag.aux_desc != null) {
        data = try printer.format("{s}\n{s:<32}{s}", .{ data, "", flag.aux_desc.? });
    }

    return try printer.format("{s} \n", .{data});
}

pub fn parse_float(comptime T: type, printer: *Printer, args: [][:0]u8, i: usize, flag: Flag, min: ?T, max: ?T) !T {
    if (i + 1 >= args.len) {
        try printer.printf("Missing argument for {s} ({s})\n", .{ flag.flag_short, flag.name });
        std.process.exit(1);
    }

    const value = args[i + 1];
    var result = std.fmt.parseFloat(T, value) catch {
        try printer.printf("Invalid {s} value: {s}\n", .{ flag.name, value });
        std.process.exit(1);
    };

    if (min != null) {
        result = @max(result, min.?);
    }

    if (max != null) {
        result = @min(result, max.?);
    }

    return result;
}

pub fn parse_int(comptime T: type, printer: *Printer, args: [][:0]u8, i: usize, flag: Flag, min: ?T, max: ?T) !T {
    if (i + 1 >= args.len) {
        try printer.printf("Missing argument for {s} ({s})\n", .{ flag.flag_short, flag.name });
        std.process.exit(1);
    }

    const value = args[i + 1];
    var result = std.fmt.parseInt(T, value, 10) catch {
        try printer.printf("Invalid {s} value: {s}\n", .{ flag.name, value });
        std.process.exit(1);
    };

    if (min != null) {
        result = @max(result, min.?);
    }

    if (max != null) {
        result = @min(result, max.?);
    }

    return result;
}

pub fn parse_enum(comptime T: type, printer: *Printer, args: [][:0]u8, i: usize, flag: Flag) !T {
    if (i + 1 >= args.len) {
        try printer.printf("Missing argument for {s} ({s})\n", .{ flag.flag_short, flag.name });
        std.process.exit(1);
    }

    const value = args[i + 1];
    if (std.mem.eql(u8, value, "help")) {
        try print_enum_options_with_title(T, flag.name, printer);
        std.process.exit(0);
    }

    return std.meta.stringToEnum(T, value) orelse {
        try printer.printf("Invalid {s}: {s}\n", .{ flag.name, value });
        try print_enum_options(T, printer);
        std.process.exit(1);
    };
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

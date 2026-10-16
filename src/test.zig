const std = @import("std");

test {
    std.testing.refAllDeclsRecursive(@import("app/runtime_state.zig"));
    std.testing.refAllDeclsRecursive(@import("app/signals.zig"));

    std.testing.refAllDeclsRecursive(@import("commons/allocator.zig"));
    std.testing.refAllDeclsRecursive(@import("commons/clock.zig"));
    std.testing.refAllDeclsRecursive(@import("commons/frame.zig"));
    std.testing.refAllDeclsRecursive(@import("commons/mini_lcg.zig"));
    std.testing.refAllDeclsRecursive(@import("commons/time.zig"));

    std.testing.refAllDeclsRecursive(@import("configuration/configuration.zig"));

    std.testing.refAllDeclsRecursive(@import("io/console.zig"));
    std.testing.refAllDeclsRecursive(@import("io/formatter.zig"));
    std.testing.refAllDeclsRecursive(@import("io/printer.zig"));
}

test {
    _ = @import("app/runtime_state.zig");
    _ = @import("app/signals.zig");

    _ = @import("commons/allocator.zig");
    _ = @import("commons/clock.zig");
    _ = @import("commons/frame.zig");
    _ = @import("commons/mini_lcg.zig");
    _ = @import("commons/time.zig");

    _ = @import("configuration/configuration.zig");

    _ = @import("io/console.zig");
    _ = @import("io/formatter.zig");
    _ = @import("io/printer.zig");
}

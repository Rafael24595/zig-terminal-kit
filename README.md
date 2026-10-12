# zig-terminal-kit

A lightweight utility library for terminal applications written in **Zig 0.15.1**.

`zig-terminal-kit` provides reusable utilities for terminal control, argument parsing, memory allocation tracking, value formatting, time conversion, and deterministic pseudo-random number generation.

## Features

- **Console utilities:** ANSI escape sequences, terminal input modes, UTF-8 output support on Windows, and terminal size detection.
- **Printing and formatting:** Write text to files and format strings using an arena allocator.
- **Configuration:** Flag definitions and argument parsing helpers for numeric and enum values.
- **Memory tracking:** An allocator wrapper that tracks requested allocation sizes.
- **General utilities:** Millisecond-to-time conversion and formatting of common value types.
- **Pseudo-random numbers:** A lightweight, deterministic linear congruential generator (LCG).

## Requirements

- Zig **0.15.1**.
- Some POSIX functionality uses the C interface and may require linking libc in the consuming executable.
- Terminal size detection is currently implemented for Windows and Linux.

## Installation

Add the dependency to your project's `build.zig.zon`. Replace the placeholder URL and hash with those for the version you want to use.

```zig
.dependencies = .{
    .terminal_kit = .{
        .url = "REPOSITORY_OR_PACKAGE_URL",
        .hash = "PACKAGE_HASH",
    },
},
```

In `build.zig`, import the dependency module:

```zig
const terminal_kit_dep = b.dependency("terminal_kit", .{});

exe.root_module.addImport(
    "terminal_kit",
    terminal_kit_dep.module("zig_terminal_kit"),
);
```

Then import the library in your Zig source files:

```zig
const terminal_kit = @import("terminal_kit");
```

If you use POSIX functions that require libc, enable libc linking for the consuming module when necessary for your target.

## Public modules

The root module exposes the following modules:

| Module | Description |
|---|---|
| `runtime_state` | Application runtime state utilities. |
| `signals` | Signal-related utilities and pipe-based communication. |
| `allocator` | Allocation tracking utilities. |
| `mini_lcg` | Deterministic pseudo-random number generator. |
| `utils` | Time conversion and value formatting. |
| `configuration` | Command-line flags and argument parsing. |
| `console` | Terminal control and dimension detection. |
| `printer` | Text output and formatting. |

Refer to the source code for the exact public API and function signatures.

## Usage

### Printing and formatting

`Printer` writes to a `std.fs.File` and formats strings using an `ArenaAllocator`.

```zig
const std = @import("std");
const terminal_kit = @import("terminal_kit");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var printer = terminal_kit.printer.Printer{
        .arena = &arena,
        .out = std.fs.File.stdout(),
    };

    try printer.printf("Hello, {s}!\n", .{"world"});

    const message = try printer.format("Value: {d}", .{42});
    try printer.print(message);

    // Release temporary allocations when they are no longer needed.
    printer.reset();
}
```

**Memory lifetime:** Strings returned by `format()` are allocated in the printer's arena. Calling `reset()` invalidates previously formatted strings, so do not use them afterward.

`print()` and `printf()` propagate write errors. `prints()` intentionally ignores them.

### Converting milliseconds to a duration

```zig
const std = @import("std");
const terminal_kit = @import("terminal_kit");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const duration = try terminal_kit.utils.millisecondsToTime(
        arena.allocator(),
        3_726_000,
        null,
    );

    // Example output: 1h2m6s000ms
    std.debug.print("{s}\n", .{duration});
}
```

The conversion uses fixed time units: a 365-day year, a 24-hour day, and their corresponding smaller units.

The optional `limit` parameter stops the breakdown before the specified unit, making the limit exclusive.

### Formatting values

`TypeFormatter` represents `none`, strings, booleans, integers, and floating-point values.

```zig
const terminal_kit = @import("terminal_kit");

// Assumes `printer` has already been initialized.
const value = terminal_kit.utils.TypeFormatter{
    .float = 3.14159,
};

const formatted = try value.format(&printer);
// formatted contains "3.14"
```

Floating-point values are formatted to two decimal places.

### Generating deterministic pseudo-random numbers

```zig
const terminal_kit = @import("terminal_kit");

var rng = terminal_kit.mini_lcg.MiniLCG.init(1234);
const value = rng.rand_in_range(0, 10);
```

The range is inclusive. Using the same seed produces the same sequence, making the generator useful for reproducible results.

**This generator is not cryptographically secure.** Its modulo-based range mapping can also introduce distribution bias.

### Querying terminal dimensions

```zig
const terminal_kit = @import("terminal_kit");

const size = try terminal_kit.console.winsize();

// size.cols: visible columns
// size.rows: visible rows
```

Terminal size detection is implemented for Windows and Linux. Unsupported platforms return an error.

### Console control

The `console` module provides ANSI constants such as:

- `HIDE_CURSOR` and `SHOW_CURSOR`
- `CLEAN_CONSOLE` and `CLEAN_HISTORY`
- `RESET_CURSOR` and `CLEAN_ALL`
- Control character constants such as `CTRL_C`, `SPACE`, `BACKSPACE`, and `DEL`

It also provides functions to enable raw-style input, restore the previous input settings, enable ANSI output processing on Windows, and enable UTF-8 console output on Windows.

When enabling raw mode, call `disable_raw_mode()` before exiting to attempt to restore the previous terminal settings.

Console state is stored in module-level variables. These operations are not designed for concurrent calls without external synchronization.

## Memory tracking

The `allocator` module provides an allocator wrapper that tracks the number of bytes requested through allocations made using the wrapper.

Keep the following considerations in mind:

- The counter tracks requested allocation sizes, not the underlying allocator's internal overhead.
- The tracer must remain at a stable memory address and stay alive while its allocator is in use.
- The underlying allocator must also remain valid.
- The counter is not thread-safe without external synchronization.

## Build and test

Run the test suite on the host system:

```sh
zig build test
```

The `test-compile` step must be defined in `build.zig` as a dependency on the test compilation artifact, without running it. Cross-compilation verifies that the tests compile for the target; it does not replace running them on that platform.

## Portability and limitations

- Console functions may require a real terminal and can fail when standard input or output is redirected.
- Terminal size detection is not available on every platform.
- Raw input mode modifies terminal settings and should be restored before the application exits.
- `MiniLCG` is intended for reproducible, non-cryptographic use.
- `Printer` and `TypeFormatter` may return strings backed by arena allocations. Manage the arena's lifetime accordingly.
- Allocation tracking does not account for internal allocator overhead.

## License

See the repository license for details.

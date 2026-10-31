# zig-terminal-kit

A lightweight utility library for terminal applications written in **Zig 0.15.1**.

`zig-terminal-kit` provides reusable utilities for terminal control, argument parsing, memory allocation tracking, value formatting, time conversion, and deterministic pseudo-random number generation.

## Features

- **Console utilities:** ANSI escape sequences, terminal input modes, UTF-8 output support on Windows, terminal size detection, ANSI virtual-terminal input support on Windows and mouse reporting
- **Printing and formatting:** Write text to files and format strings using an arena allocator.
- **Configuration:** Flag definitions and argument parsing helpers for numeric and enum values.
- **Memory tracking:** An allocator wrapper that tracks requested allocation sizes.
- **General utilities:** Millisecond-to-time conversion and formatting of common value types.
- **Pseudo-random numbers:** A lightweight, deterministic SplitMix64 pseudo-random number generator.
- **Color formatting:** Reusable formatters for ANSI 256-color, RGB, and unformatted terminal output, supporting both matrix-level color prefixes and individual cell formatting.
- **Console control**: Terminal control utilities, including ANSI virtual-terminal input support on Windows and mouse reporting.
- **Input event parsing**: Incremental parsing of SGR mouse sequences into structured mouse events.
- **Panic handling**: Custom panic handlers with a recovery callback to restore terminal state before standard panic handling.

## Requirements

- Zig **0.15.1**.
- Some POSIX functionality uses the C interface and may require linking libc in the consuming executable.
- Terminal size detection is currently implemented for Windows and Linux.

## Installation

### Add the dependency

Choose the version you want to install and replace `0.4.0` in the URL below with the desired release version.

Run the following command from your project directory:

```bash
zig fetch --save=terminal_kit https://github.com/Rafael24595/zig-terminal-kit/releases/download/0.4.0/zig_terminal_kit-0.4.0.tar.gz
```

This downloads the selected release and adds the dependency, including its content hash, to your `build.zig.zon`.


### Import the module

In your `build.zig`, add the dependency module to your executable:

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

You can now access the library's public modules through `terminal_kit`.

**Note:** If you use POSIX functionality that requires libc, enable libc linking for the consuming module when necessary for your target platform.


## Public modules

The root module exposes the following modules:

| Module | Description |
|---|---|
| `runtime_state` | Application runtime state utilities. |
| `signals` | Signal-related utilities and pipe-based communication. |
| `allocator` | Allocation tracking utilities. |
| `clock` | System and monotonic clocks for measuring timestamps and elapsed time. |
| `frame` | Frame counting and periodic frame-rate calculation (FPS). |
| `mini_lcg` | Deprecated: use `splitmix64` instead. |
| `splitmix64` | Deterministic SplitMix64 pseudo-random number generator. |
| `time` | Time conversion utilities. |
| `configuration` | Command-line flags and argument parsing. |
| `console` | Terminal control, dimension detection, ANSI input configuration on Windows, mouse reporting, and terminal dimensions. |
| `event` | Incremental parsing of SGR mouse sequences and structured mouse event types. |
| `formatter` | Value formatting utilities and reusable ANSI/RGB color formatters for matrices and individual cells. |
| `printer` | Text output and formatting. |
| `panic_handler` | Creates custom panic handlers with a recovery callback. |
| `color` | Named colors and their 8-bit RGB representations. |

Refer to the source code for the exact public API and function signatures.

## Deprecated modules

The `mini_lcg` module is deprecated and will be removed in a future release.

Use `splitmix64` instead. It provides the `SplitMix64` generator with the same general-purpose functionality:

- Inclusive integer range generation.
- Floating-point generation in the range `[0.0, 1.0)`.
- In-place Fisher–Yates shuffling.

The new implementation uses a different algorithm, so generated sequences are not compatible with those produced by `MiniLCG`, even when using the same seed.

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

### Parsing command-line arguments

The `configuration` module provides `InitResult(T)` and `from_args()` to share command-line argument handling across applications while keeping each application's configuration parsing separate.

Define an `init` function that parses the arguments and returns an `InitResult(Configuration)`. The result can represent a successfully parsed configuration, an informational request such as `--help` or `--version`, or an error message.

```zig
const std = @import("std");
const terminal_kit = @import("terminal_kit");

const kit_conf = terminal_kit.configuration;
const Printer = terminal_kit.printer.Printer;

const Configuration = struct {
    debug: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        printer: *Printer,
        args: [][:0]u8,
    ) !kit_conf.InitResult(Configuration) {
        _ = allocator;

        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--debug")) {
                return .{ .run = .{ .debug = true } };
            }

            return .{
                .err = try printer.format("Unknown argument: {s}\n", .{arg}),
            };
        }

        return .{ .run = .{} };
    }
};

pub fn main() !void {
    // Assumes allocator and printer have been initialized.
    const config = try kit_conf.from_args(
        Configuration,
        allocator,
        &printer,
        Configuration.init,
    );

    // Continue using config.
    _ = config;
}
```

`from_args()` allocates the process arguments, invokes the supplied initialization function, and returns the configuration when parsing succeeds. For `.inf`, it exits with status code `0`; for `.err`, it prints the message and exits with status code `1`.

Error messages returned in `.err` must remain valid until they are printed. When using `Printer.format()`, the message is backed by the printer's arena and becomes invalid after `printer.reset()`.

Errors propagated by the initialization function are returned to the caller rather than converted into process exit codes.

### Converting milliseconds to a duration

```zig
const std = @import("std");
const terminal_kit = @import("terminal_kit");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const duration = try terminal_kit.time.milliseconds_to_time(
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

### Working with clocks

The `clock` module provides a common interface for retrieving timestamps in milliseconds through two clock implementations:

- `system_clock` returns Unix timestamps using the system wall clock.
- `MonotonicClock` returns elapsed time since its timer was started, making it suitable for measuring durations and frame intervals.

**System clock**

```zig
const terminal_kit = @import("terminal_kit");

const timestamp_ms = terminal_kit.clock.system_clock.now();
```

**Monotonic clock**

```zig
const terminal_kit = @import("terminal_kit");

var monotonic = try terminal_kit.clock.MonotonicClock.init();
const clock = monotonic.clock();

const timestamp_ms = clock.now();
```

Both implementations return timestamps in milliseconds, but their reference points differ. System-clock timestamps represent Unix time and can change when the system clock is adjusted. Monotonic timestamps are relative to the timer's start and are intended for measuring elapsed time.

Keep the `MonotonicClock` instance alive and at a stable memory address while using a `Clock` obtained from `clock()`, because the returned interface stores a pointer to that instance.

### Measuring frame rate

The `Counter` type tracks rendered frames and periodically calculates the frame rate in frames per second (FPS).

```zig
const terminal_kit = @import("terminal_kit");

var counter = terminal_kit.frame.Counter.init();

// Call once for each rendered frame.
counter.frame_increment();

// Retrieve the latest frame-rate estimate.
const fps = counter.get_frame_rate(1000);
```

The `interval` argument specifies the minimum elapsed time, in milliseconds, before the frame rate is recalculated. The returned value is always expressed in frames per second, regardless of the interval.

The first call initializes the timestamp and returns the existing estimate without recalculating it. Until the interval elapses, subsequent calls return the most recently calculated value.

The counter uses the system clock by default and supports injecting a different `Clock` implementation when needed.


### Formatting values

`TypeFormatter` represents `none`, strings, booleans, integers, and floating-point values.

```zig
const terminal_kit = @import("terminal_kit");

// Assumes `printer` has already been initialized.
const value = terminal_kit.formatter.TypeFormatter{
    .float = 3.14159,
};

const formatted = try value.format(&printer);
// formatted contains "3.14"
```

Floating-point values are formatted to two decimal places.

### Formatting terminal colors

The `formatter` module provides `FormatterMatrixUnion` and `FormatterCellUnion` to support terminal color formatting at different levels.

- `FormatterMatrixUnion` handles formatting applied to the matrix as a whole, including the color prefix and reset suffix.
- `FormatterCellUnion` handles formatting applied to individual cells.

Depending on the implementation, matrix-level formatting may be unnecessary even when individual cells require colors. For example, the following configuration leaves the matrix unformatted while allowing each cell to use ANSI 256-color or RGB formatting.

```zig
const kit_formatter = @import("terminal_kit").formatter;

pub const FormatterCode = enum {
    ansi,
    rgb,
};

pub fn matrix_union_of(_: FormatterCode) kit_formatter.FormatterMatrixUnion {
    return .{ .unfo = .{} };
}

pub fn cell_union_of(f: FormatterCode) kit_formatter.FormatterCellUnion {
    return switch (f) {
        .ansi => .{ .ansi = .{} },
        .rgb => .{ .rgb = .{} },
    };
}
```

Both formatter types expose `fmt_bytes()` to report the byte length associated with their formatting strings. `FormatterMatrixUnion` also provides `prefix()`, `sufix()`, and `format_prefix()`, while `FormatterCellUnion` provides `format()`.

The `.unfo` variant leaves text unformatted. The `.ansi` and `.rgb` variants apply their respective terminal color escape sequences.

### Working with colors

The `style.colors` module provides a set of named colors and their RGB representations.

```zig
const terminal_kit = @import("terminal_kit");

const rgb = terminal_kit.style.colors.rgb_of(.coral);

// rgb[0]: red component
// rgb[1]: green component
// rgb[2]: blue component
```

Each RGB component is an 8-bit unsigned integer in the range `0`–`255`. The module includes standard named colors as well as neon variants.

The module provides color data only; converting RGB values into terminal escape sequences is handled separately.

### Generating deterministic pseudo-random numbers

The `splitmix64` module provides the `SplitMix64` pseudo-random number generator.

```zig
const terminal_kit = @import("terminal_kit");

var rng = terminal_kit.splitmix64.SplitMix64.init(1234);

// Generate an integer in the inclusive range [0, 10].
const value = rng.rand_in_range(0, 10);

// Generate an f32 in the range [0.0, 1.0).
const fraction = rng.float();

// Shuffle a slice in place.
var values = [_]u8{ 1, 2, 3, 4, 5 };
rng.shuffle(u8, &values);
```

The generator is deterministic: using the same seed and making the same sequence of calls produces the same results.

`rand_in_range()` returns an integer within the inclusive range `[min, max]`. `float()` returns an `f32` in the range `[0.0, 1.0)`. `shuffle()` rearranges the elements of a slice in place using the Fisher–Yates algorithm.

The generator uses SplitMix64, a non-cryptographic pseudo-random number generation algorithm. Its output is suitable for general-purpose randomized behavior, but it must not be used for security-sensitive applications.

The modulo-based range mapping in `rand_in_range()` can introduce a small distribution bias, which may also affect the distribution of shuffled permutations.

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

It also provides functions to enable raw-style input, restore the previous input settings, enable ANSI output processing on Windows, enable ANSI virtual-terminal input on Windows, and enable UTF-8 console output on Windows.

Mouse reporting can be enabled and disabled using `enable_mouse()` and `disable_mouse()`. These functions configure the terminal to report mouse events using escape sequences, including SGR mouse sequences. They do not parse incoming input; use the `event` module to process these sequences.

For example:

```zig
const kit = @import("zig-terminal-kit");
const console = kit.console;

try console.enable_ansi_input();
try console.enable_mouse();

// Read and process terminal input here.

console.disable_mouse();
console.disable_ansi_input();
```

`enable_ansi_input()` enables ANSI virtual-terminal input on Windows and does nothing on other platforms. It may return an error if the standard input handle cannot be accessed or configured. Mouse reporting depends on the capabilities of the terminal emulator.

When enabling raw mode, call `disable_raw_mode()` before exiting to attempt to restore the previous terminal settings. Similarly, pair `enable_ansi_input()` and `enable_mouse()` with their corresponding disable functions during normal shutdown.

Console state is stored in module-level variables. These operations are not designed for concurrent calls without external synchronization.

### Parsing mouse events

The `event` module provides an incremental parser for SGR mouse escape sequences. It processes incoming input one byte at a time and reports whether the input was ignored, belongs to an incomplete sequence, is invalid, or completed a mouse event.

```zig
const kit = @import("zig-terminal-kit");

var parser = kit.event.MouseParser{};

fn processInputByte(byte: u8) void {
    switch (parser.feed(byte)) {
        .ignored => {},
        .pending, .invalid => {},
        .event => |event| {
            if (event.pressed and event.button == 0) {
                // Handle a left mouse button press.
                handleLeftClick(event.row, event.col);
            }
        },
    }
}
```

`MouseEvent` exposes the button code, terminal column, terminal row, and whether the button was pressed or released. Both `col` and `row` use **1-based terminal coordinates**.

Keep the same `MouseParser` instance while processing a stream of input bytes so that incomplete sequences can be accumulated across successive reads.

The parser recognizes SGR mouse sequences; it is not a general-purpose keyboard or terminal escape-sequence parser. Applications that also process keyboard input should account for how other escape sequences and invalid input are handled.

The parser uses a fixed-size buffer to accumulate incoming sequences.

### Handling panics

The `panic_handler` module lets you create a custom panic handler that runs a recovery function before delegating to Zig's default panic handler. This is useful for restoring terminal settings, such as raw mode, mouse input, and cursor visibility, when a panic occurs.

```zig
const std = @import("std");
const kit = @import("zig-terminal-kit");

const console = kit.console;
const PanicHandler = kit.panic_handler.PanicHandler;

pub const panic = PanicHandler(cleanupTerminal).panic;

fn cleanupTerminal() void {
    console.disable_mouse();
    console.disable_ansi_input();
    console.disable_raw_mode();

    const stdout = std.fs.File.stdout();
    stdout.writeAll(
        console.SHOW_CURSOR ++
            console.CLEAN_ALL ++
            console.RESET_CURSOR,
    ) catch {};
}
```

The recovery function must be declared at compile time as a function with the signature `fn () void`. It is executed before the default panic handler, which retains responsibility for reporting the panic and terminating the program.

Keep recovery code minimal and safe to run even if initialization is incomplete. Unlike normal control flow, panic handling should not rely on `defer` statements to restore resources.

### Parsing mouse events

The `event` module provides an incremental parser for SGR mouse escape sequences. It processes incoming input one byte at a time and reports whether the input was ignored, is part of an incomplete sequence, is invalid, or completed a mouse event.

```zig
const kit = @import("zig-terminal-kit");

var parser = kit.event.MouseParser{};

fn processInputByte(byte: u8) void {
    switch (parser.feed(byte)) {
        .ignored => {},
        .pending, .invalid => {},
        .event => |event| {
            if (event.pressed and event.button == 0) {
                // Handle a left mouse button press.
                handleLeftClick(event.row, event.col);
            }
        },
    }
}
```

`MouseEvent` exposes the button code, terminal column, terminal row, and whether the button was pressed or released. Both `col` and `row` use **1-based terminal coordinates**.

`MouseParser` is incremental, so keep the same parser instance while processing a stream of input bytes. The parser recognizes SGR mouse sequences; it is not a general-purpose keyboard or terminal escape-sequence parser. Configure mouse reporting in the terminal before expecting mouse events.

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
- `SplitMix64` is intended for reproducible, non-cryptographic pseudo-random number generation.
- `Printer` and `TypeFormatter` may return strings backed by arena allocations. Manage the arena's lifetime accordingly.
- Allocation tracking does not account for internal allocator overhead.

## License

See the repository license for details.

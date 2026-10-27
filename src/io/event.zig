const std = @import("std");

const MOUSE_BUFFER_CAPACITY = 32;

const ESC: u8 = 0x1b;
const SGR_MOUSE_PREFIX = "\x1b[<";

const SGR_MOUSE_PRESS: u8 = 'M';
const SGR_MOUSE_RELEASE: u8 = 'm';

const CSI_PARAMETER_MIN: u8 = 0x30;
const CSI_PARAMETER_MAX: u8 = 0x3f;
const CSI_FINAL_MIN: u8 = 0x40;
const CSI_FINAL_MAX: u8 = 0x7e;

/// Represents the parsing outcome of a single incoming byte stream element.
pub const FeedResult = union(enum) {
    /// The byte was ignored because it was not part of a mouse event sequence.
    ignored,
    /// The byte was accepted and the parser is waiting for more bytes to complete the sequence.
    pending,
    /// The byte was accepted but the sequence is invalid or malformed.
    invalid,
    /// The byte was accepted and a complete mouse event has been parsed.
    event: MouseEvent,
};

/// Represents an parsed SGR mouse interaction event.
pub const MouseEvent = struct {
    /// The button code associated with the mouse event.
    button: u16,
    /// The column position of the mouse event (1-based).
    col: u32,
    /// The row position of the mouse event (1-based).
    row: u32,
    /// Indicates whether the mouse button was pressed (true) or released (false).
    pressed: bool,
};

/// Parser for SGR mouse escape sequences.
pub const MouseParser = struct {
    /// Buffer to accumulate incoming bytes for parsing.
    buf: [MOUSE_BUFFER_CAPACITY]u8 = undefined,
    /// Current length of the accumulated byte sequence.
    len: usize = 0,

    /// Feeds a single byte into the parser and returns the resulting state.
    pub fn feed(self: *@This(), byte: u8) FeedResult {
        if (self.len == 0) {
            if (byte != ESC) {
                return .ignored;
            }

            self.start(byte);
            return .pending;
        }

        if (self.len == self.buf.len) {
            self.reset();
            return .invalid;
        }

        self.push(byte);

        const prefix_len = @min(self.len, SGR_MOUSE_PREFIX.len);

        const buf_prefix = self.buf[0..prefix_len];
        const prefix = SGR_MOUSE_PREFIX[0..prefix_len];

        if (!std.mem.eql(u8, buf_prefix, prefix)) {
            if (byte >= CSI_FINAL_MIN and byte <= CSI_FINAL_MAX) {
                self.reset();
            }
            return .invalid;
        }

        if (self.len < SGR_MOUSE_PREFIX.len) {
            return .pending;
        }

        if (byte == SGR_MOUSE_PRESS or byte == SGR_MOUSE_RELEASE) {
            const sequence = self.buf[0..self.len];
            const event = parse_mouse_event(sequence);

            self.reset();

            if (event) |mouse_event| {
                return .{ .event = mouse_event };
            }

            return .invalid;
        }

        if (byte < CSI_PARAMETER_MIN or byte > CSI_PARAMETER_MAX) {
            self.reset();
            return .invalid;
        }

        return .pending;
    }

    inline fn start(self: *@This(), byte: u8) void {
        self.buf[0] = byte;
        self.len = 1;
    }

    inline fn push(self: *@This(), byte: u8) void {
        self.buf[self.len] = byte;
        self.len += 1;
    }

    inline fn reset(self: *@This()) void {
        self.len = 0;
    }
};

fn parse_mouse_event(seq: []const u8) ?MouseEvent {
    if (!std.mem.startsWith(u8, seq, SGR_MOUSE_PREFIX)) {
        return null;
    }

    if (seq.len <= SGR_MOUSE_PREFIX.len) {
        return null;
    }

    const terminator = seq[seq.len - 1];

    const is_press = terminator == SGR_MOUSE_PRESS;
    const is_release = terminator == SGR_MOUSE_RELEASE;

    if (!is_press and !is_release) {
        return null;
    }

    var fields = std.mem.splitScalar(
        u8,
        seq[SGR_MOUSE_PREFIX.len .. seq.len - 1],
        ';',
    );

    const button = std.fmt.parseInt(u16, fields.next() orelse return null, 10) catch return null;

    const col = std.fmt.parseInt(
        u32,
        fields.next() orelse return null,
        10,
    ) catch return null;

    const row = std.fmt.parseInt(
        u32,
        fields.next() orelse return null,
        10,
    ) catch return null;

    if (fields.next() != null or col == 0 or row == 0) {
        return null;
    }

    return .{
        .button = button,
        .col = col,
        .row = row,
        .pressed = is_press,
    };
}

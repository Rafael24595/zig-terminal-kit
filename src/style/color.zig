/// Supported named colors and their RGB representations.
pub const Color = enum {
    white,
    black,
    red,
    green,
    blue,
    yellow,
    cyan,
    magenta,
    orange,
    purple,
    gray,
    pink,
    brown,
    aqua,
    navy,
    teal,
    lavender,
    lime,
    coral,
    gold,
    neon_pink,
    neon_green,
    neon_blue,
    neon_yellow,
    neon_orange,
    neon_purple,
    neon_cyan,
    neon_red,
};

const ColorMap = [_][3]u8{
    .{ 255, 255, 255 }, // white
    .{ 0, 0, 0 }, // black
    .{ 255, 0, 0 }, // red
    .{ 0, 255, 0 }, // green
    .{ 0, 0, 255 }, // blue
    .{ 255, 255, 0 }, // yellow
    .{ 0, 255, 255 }, // cyan
    .{ 255, 0, 255 }, // magenta
    .{ 255, 128, 0 }, // orange
    .{ 128, 0, 128 }, // purple
    .{ 128, 128, 128 }, // gray
    .{ 255, 192, 203 }, // pink
    .{ 165, 42, 42 }, // brown
    .{ 127, 255, 212 }, // aqua
    .{ 0, 0, 128 }, // navy
    .{ 0, 128, 128 }, // teal
    .{ 230, 230, 250 }, // lavender
    .{ 0, 255, 0 }, // lime
    .{ 255, 127, 80 }, // coral
    .{ 255, 215, 0 }, // gold
    .{ 255, 0, 144 }, // neon_pink
    .{ 57, 255, 20 }, // neon_green
    .{ 0, 191, 255 }, // neon_blue
    .{ 207, 255, 4 }, // neon_yellow
    .{ 255, 95, 31 }, // neon_orange
    .{ 191, 0, 255 }, // neon_purple
    .{ 0, 255, 255 }, // neon_cyan
    .{ 255, 16, 83 }, // neon_red
};

/// Returns the 8-bit RGB components associated with a named color.
pub fn rgb_of(c: Color) [3]u8 {
    return ColorMap[@intFromEnum(c)];
}

/// Supported named colors and their RGB representations.
pub const Color = enum {
    white,
    black,
    red,
    green,
    green_dark,
    green_medium,
    green_bright,
    green_olive,
    green_moss,
    blue,
    yellow,
    cyan,
    magenta,
    orange,
    purple,
    deep_purple,
    hot_purple,
    gray,
    gray_dark,
    gray_light,
    pink,
    brown,
    aqua,
    navy,
    teal,
    lavender,
    pale_lavender,
    violet,
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
    .{ 0, 128, 0 }, // green_dark
    .{ 0, 200, 0 }, // green_medium
    .{ 128, 255, 128 }, // green_bright
    .{ 85, 107, 47 }, // green_olive
    .{ 120, 160, 60 }, // green_moss
    .{ 0, 0, 255 }, // blue
    .{ 255, 255, 0 }, // yellow
    .{ 0, 255, 255 }, // cyan
    .{ 255, 0, 255 }, // magenta
    .{ 255, 128, 0 }, // orange
    .{ 128, 0, 128 }, // purple
    .{ 48, 0, 72 }, // deep_purple
    .{ 255, 0, 255 }, // hot_purple
    .{ 128, 128, 128 }, // gray
    .{ 64, 64, 64 }, // gray_dark
    .{ 192, 192, 192 }, // gray_light
    .{ 255, 192, 203 }, // pink
    .{ 165, 42, 42 }, // brown
    .{ 127, 255, 212 }, // aqua
    .{ 0, 0, 128 }, // navy
    .{ 0, 128, 128 }, // teal
    .{ 230, 230, 250 }, // lavender
    .{ 245, 240, 255 }, // pale_lavender
    .{ 138, 43, 226 }, // Violet
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

const std = @import("std");

/// Maximum value of `usize` for the current architecture.
const MAX_USIZE = std.math.maxInt(usize);

/// Multiplier used by the linear congruential generator.
const LCG_MULTIPLIER: u64 = 1_664_525;

/// Increment used by the linear congruential generator.
const LCG_INCREMENT: u64 = 1_013_904_223;

/// Number of random bits used to generate an f32 fraction.
const FLOAT_RANDOM_BITS = 24;

/// Number of bits to shift the random value to extract the fraction.
const FLOAT_RANDOM_SHIFT = 64 - FLOAT_RANDOM_BITS;

/// Number of distinct fractions representable by those bits (2^24).
const FLOAT_RANDOM_RANGE: f32 = @floatFromInt(
    @as(u32, 1) << FLOAT_RANDOM_BITS,
);

/// Deprecated: use `SplitMix64` instead.
/// This type will be removed in a future version.
///
/// A small, deterministic pseudo-random number generator based on a
/// Linear Congruential Generator (LCG).
///
/// This generator is intended for simple non-cryptographic use cases.
/// It is not suitable for security-sensitive applications.
pub const MiniLCG = struct {
    /// Internal generator state. The default seed is 1.
    seed: u64 = 1,

    /// Initializes the generator with the given seed.
    ///
    /// Identical seeds produce identical sequences of values.
    pub fn init(seed: u64) @This() {
        return MiniLCG{ .seed = seed };
    }

    fn next(self: *@This()) u64 {
        const mul = @mulWithOverflow(self.seed, LCG_MULTIPLIER);
        const add = @addWithOverflow(mul[0], LCG_INCREMENT);
        self.seed = add[0];
        return self.seed;
    }

    /// Returns a pseudo-random integer in the inclusive range [min, max].
    ///
    /// If min exceeds max, the bounds are swapped when runtime safety
    /// assertions are disabled. With runtime safety enabled, the assertion
    /// detects the invalid argument order.
    ///
    /// The generated value is reduced using modulo, which can introduce
    /// a small distribution bias for some ranges.
    pub fn rand_in_range(self: *@This(), min: usize, max: usize) usize {
        if (comptime std.debug.runtime_safety) {
            std.debug.assert(min <= max);
        }

        const rnd: usize = @truncate(self.next());

        const lower: usize = @min(min, max);
        const upper: usize = @max(min, max);

        if (lower == 0 and upper == MAX_USIZE) {
            return rnd;
        }

        const range = upper - lower + 1;
        const value = rnd % range;

        return @intCast(lower + value);
    }

    /// Returns a pseudo-random `f32` in the range [0.0, 1.0).
    ///
    /// Uses the upper 24 bits of the generator output to produce
    /// 2^24 possible values, spaced 2^-24 apart.
    /// The result is deterministic and not cryptographically secure.
    pub fn float(self: *@This()) f32 {
        const rnd_bits = self.next() >> FLOAT_RANDOM_SHIFT;
        const rnd_value: f32 = @floatFromInt(rnd_bits);
        return rnd_value / FLOAT_RANDOM_RANGE;
    }

    /// Shuffles the elements of the provided array in place using
    /// the Fisher-Yates algorithm.
    ///
    /// The result is deterministic for a given initial generator state.
    /// The distribution of permutations depends on the quality of the
    /// generator and its bounded integer mapping.
    pub fn shuffle(self: *MiniLCG, comptime T: type, data: []T) void {
        if (data.len < 2) {
            return;
        }

        var i: usize = data.len - 1;
        while (i > 0) : (i -= 1) {
            const j = self.rand_in_range(0, i);

            const a = &data[i];
            const b = &data[j];

            const tmp = a.*;
            a.* = b.*;
            b.* = tmp;
        }
    }
};

test "random number in range with specific seed" {
    var lcg = MiniLCG.init(1234);

    var num = lcg.rand_in_range(0, 10);
    try std.testing.expectEqual(1, num);

    num = lcg.rand_in_range(0, 10);
    try std.testing.expectEqual(7, num);

    num = lcg.rand_in_range(0, 10);
    try std.testing.expectEqual(3, num);
}

test "full usize range does not overflow" {
    var rng = MiniLCG.init(1234);

    const value = rng.rand_in_range(0, MAX_USIZE);

    try std.testing.expect(value <= MAX_USIZE);
}

test "supports ranges larger than u8" {
    var rng = MiniLCG.init(1234);
    const min: usize = 1_000;
    const max: usize = 100_000;

    for (0..100) |_| {
        const value = rng.rand_in_range(min, max);
        try std.testing.expect(value >= min and value <= max);
    }
}

test "lcg determinism" {
    var a = MiniLCG.init(42);
    var b = MiniLCG.init(42);

    for (0..10) |_| {
        const ra = a.rand_in_range(0, 100);
        const rb = b.rand_in_range(0, 100);
        try std.testing.expectEqual(ra, rb);
    }
}

test "different seeds produce different sequences" {
    var a = MiniLCG.init(1);
    var b = MiniLCG.init(2);

    for (0..10) |_| {
        const ra = a.rand_in_range(0, 255);
        const rb = b.rand_in_range(0, 255);
        try std.testing.expect(ra != rb);
    }
}

test "respects range boundaries" {
    var lcg = MiniLCG.init(9876);

    for (0..1000) |_| {
        const v = lcg.rand_in_range(5, 15);
        try std.testing.expect(v >= 5 and v <= 15);
    }
}

test "single value range returns same result" {
    var lcg = MiniLCG.init(123);
    for (0..10) |_| {
        try std.testing.expectEqual(7, lcg.rand_in_range(7, 7));
    }
}

test "handles seed overflow" {
    var lcg = MiniLCG.init(std.math.maxInt(u64));
    const v = lcg.rand_in_range(0, 255);
    try std.testing.expect(v <= 255);
}

test "float returns values in the expected range" {
    var rng = MiniLCG.init(1234);

    for (0..1000) |_| {
        const value = rng.float();

        try std.testing.expect(value >= 0.0);
        try std.testing.expect(value < 1.0);
    }
}

test "float is deterministic for identical seeds" {
    var a = MiniLCG.init(42);
    var b = MiniLCG.init(42);

    for (0..100) |_| {
        try std.testing.expectEqual(a.float(), b.float());
    }
}

test "shuffle preserves all elements" {
    var rng = MiniLCG.init(1234);
    const original = [_]u8{ 1, 2, 3, 4, 5 };
    var values = original;

    rng.shuffle(u8, &values);

    var sorted = values;
    std.mem.sort(u8, &sorted, {}, std.sort.asc(u8));

    try std.testing.expectEqualSlices(u8, &original, &sorted);
}

test "shuffle is deterministic for identical seeds" {
    var a = MiniLCG.init(42);
    var b = MiniLCG.init(42);

    var values_a = [_]u8{ 1, 2, 3, 4, 5, 6 };
    var values_b = values_a;

    a.shuffle(u8, &values_a);
    b.shuffle(u8, &values_b);

    try std.testing.expectEqualSlices(u8, &values_a, &values_b);
}

test "shuffle handles empty and single-element slices" {
    var rng = MiniLCG.init(42);

    var empty: [0]u8 = .{};
    var single = [_]u8{7};

    rng.shuffle(u8, &empty);
    rng.shuffle(u8, &single);

    try std.testing.expectEqual(@as(u8, 7), single[0]);
}

const std = @import("std");

/// Maximum value of `usize` for the current architecture.
const MAX_USIZE = std.math.maxInt(usize);

/// Increment value used in the SplitMix64 algorithm.
const SPLITMIX64_INCREMENT: u64 = 0x9E3779B97F4A7C15;
/// First multiplier used in the SplitMix64 mixing function.
const SPLITMIX64_MIX_MULTIPLIER_1: u64 = 0xBF58476D1CE4E5B9;
/// Second multiplier used in the SplitMix64 mixing function.
const SPLITMIX64_MIX_MULTIPLIER_2: u64 = 0x94D049BB133111EB;

/// Number of bits to shift during the first mixing operation.
const SPLITMIX64_SHIFT_1: u6 = 30;
/// Number of bits to shift during the second mixing operation.
const SPLITMIX64_SHIFT_2: u6 = 27;
/// Number of bits to shift during the final mixing operation.
const SPLITMIX64_SHIFT_3: u6 = 31;

/// Number of random bits used to generate an f32 value.
const FLOAT_RANDOM_BITS = 24;

/// Number of bits to shift the random value to extract the fraction.
const FLOAT_RANDOM_SHIFT = 64 - FLOAT_RANDOM_BITS;

/// Number of distinct fractions representable by those bits (2^24).
const FLOAT_RANDOM_RANGE: f32 = @floatFromInt(
    @as(u32, 1) << FLOAT_RANDOM_BITS,
);

/// A small, deterministic pseudo-random number generator based on
/// the SplitMix64 algorithm.
///
/// This generator is intended for simple non-cryptographic use cases.
/// It is not suitable for security-sensitive applications.
pub const SplitMix64 = struct {
    /// Internal generator state. The default seed is 1.
    seed: u64 = 1,

    /// Initializes the generator with the given seed.
    ///
    /// Identical seeds produce identical sequences of values.
    pub fn init(seed: u64) @This() {
        return .{ .seed = seed };
    }

    fn next(self: *@This()) u64 {
        self.seed +%= SPLITMIX64_INCREMENT;

        var z = self.seed;

        z = (z ^ (z >> SPLITMIX64_SHIFT_1)) *% SPLITMIX64_MIX_MULTIPLIER_1;
        z = (z ^ (z >> SPLITMIX64_SHIFT_2)) *% SPLITMIX64_MIX_MULTIPLIER_2;

        return z ^ (z >> SPLITMIX64_SHIFT_3);
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
    pub fn shuffle(self: *@This(), comptime T: type, data: []T) void {
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
    var rng = SplitMix64.init(1234);

    var num = rng.rand_in_range(0, 10);
    try std.testing.expectEqual(0, num);

    num = rng.rand_in_range(0, 10);
    try std.testing.expectEqual(3, num);

    num = rng.rand_in_range(0, 10);
    try std.testing.expectEqual(7, num);
}

test "handles ranges near usize maximum" {
    var rng = SplitMix64.init(1234);

    const max = MAX_USIZE;
    const min = max - 10;

    for (0..100) |_| {
        const value = rng.rand_in_range(min, max);
        try std.testing.expect(value >= min and value <= max);
    }
}

test "supports ranges larger than u8" {
    var rng = SplitMix64.init(1234);
    const min: usize = 1_000;
    const max: usize = 100_000;

    for (0..100) |_| {
        const value = rng.rand_in_range(min, max);
        try std.testing.expect(value >= min and value <= max);
    }
}

test "rng determinism" {
    var a = SplitMix64.init(42);
    var b = SplitMix64.init(42);

    for (0..10) |_| {
        const ra = a.rand_in_range(0, 100);
        const rb = b.rand_in_range(0, 100);
        try std.testing.expectEqual(ra, rb);
    }
}

test "different seeds produce different sequences" {
    var a = SplitMix64.init(1);
    var b = SplitMix64.init(2);

    for (0..10) |_| {
        try std.testing.expect(a.next() != b.next());
    }
}

test "respects range boundaries" {
    var rng = SplitMix64.init(9876);

    for (0..1000) |_| {
        const v = rng.rand_in_range(5, 15);
        try std.testing.expect(v >= 5 and v <= 15);
    }
}

test "single value range returns same result" {
    var rng = SplitMix64.init(123);
    for (0..10) |_| {
        try std.testing.expectEqual(7, rng.rand_in_range(7, 7));
    }
}

test "handles seed overflow" {
    var rng = SplitMix64.init(std.math.maxInt(u64));
    const v = rng.rand_in_range(0, 255);
    try std.testing.expect(v <= 255);
}

test "float returns values in the expected range" {
    var rng = SplitMix64.init(1234);

    for (0..1000) |_| {
        const value = rng.float();

        try std.testing.expect(value >= 0.0);
        try std.testing.expect(value < 1.0);
    }
}

test "float is deterministic for identical seeds" {
    var a = SplitMix64.init(42);
    var b = SplitMix64.init(42);

    for (0..100) |_| {
        try std.testing.expectEqual(a.float(), b.float());
    }
}

test "shuffle preserves all elements" {
    var rng = SplitMix64.init(1234);
    const original = [_]u8{ 1, 2, 3, 4, 5 };
    var values = original;

    rng.shuffle(u8, &values);

    var sorted = values;
    std.mem.sort(u8, &sorted, {}, std.sort.asc(u8));

    try std.testing.expectEqualSlices(u8, &original, &sorted);
}

test "shuffle is deterministic for identical seeds" {
    var a = SplitMix64.init(42);
    var b = SplitMix64.init(42);

    var values_a = [_]u8{ 1, 2, 3, 4, 5, 6 };
    var values_b = values_a;

    a.shuffle(u8, &values_a);
    b.shuffle(u8, &values_b);

    try std.testing.expectEqualSlices(u8, &values_a, &values_b);
}

test "shuffle handles empty and single-element slices" {
    var rng = SplitMix64.init(42);

    var empty: [0]u8 = .{};
    var single = [_]u8{7};

    rng.shuffle(u8, &empty);
    rng.shuffle(u8, &single);

    try std.testing.expectEqual(7, single[0]);
}

test "produces expected SplitMix64 output" {
    var rng = SplitMix64.init(0);
    try std.testing.expectEqual(0xE220A8397B1DCDAF, rng.next());
}

test "generates varied values in range 0 to 31" {
    var rng = SplitMix64.init(1234);

    var values = [_]bool{false} ** 32;

    for (0..1000) |_| {
        const value = rng.rand_in_range(0, 31);
        values[value] = true;
    }

    for (values) |generated| {
        try std.testing.expect(generated);
    }
}

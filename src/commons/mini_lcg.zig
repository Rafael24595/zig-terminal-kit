const std = @import("std");

pub const MiniLCG = struct {
    seed: u64 = 1,

    pub fn init(seed: u64) @This() {
        return MiniLCG{ .seed = seed };
    }

    fn next(self: *@This()) u64 {
        const mul = @mulWithOverflow(self.seed, 1664525);
        const add = @addWithOverflow(mul[0], 1013904223);
        self.seed = add[0];
        return self.seed;
    }

    pub fn randInRange(self: *@This(), min: u8, max: u8) u8 {
        var rnd: u64 = self.next();

        rnd = ((rnd >> 16) ^ (rnd >> 8)) & 0xFFFF;

        const min64: u64 = @intCast(min);
        const max64: u64 = @intCast(max);

        const range: u64 = max64 - min64 + 1;
        const value: u64 = rnd % range;

        return @intCast(min64 + value);
    }
};

test "random number in range with specific seed" {
    var lcg = MiniLCG.init(1234);

    var num = lcg.randInRange(0, 10);
    try std.testing.expectEqual(1, num);

    num = lcg.randInRange(0, 10);
    try std.testing.expectEqual(6, num);

    num = lcg.randInRange(0, 10);
    try std.testing.expectEqual(9, num);
}

test "lcg determinism" {
    var a = MiniLCG.init(42);
    var b = MiniLCG.init(42);

    for (0..10) |_| {
        const ra = a.randInRange(0, 100);
        const rb = b.randInRange(0, 100);
        try std.testing.expectEqual(ra, rb);
    }
}

test "different seeds produce different sequences" {
    var a = MiniLCG.init(1);
    var b = MiniLCG.init(2);

    for (0..10) |_| {
        const ra = a.randInRange(0, 255);
        const rb = b.randInRange(0, 255);
        try std.testing.expect(ra != rb);
    }
}

test "respects range boundaries" {
    var lcg = MiniLCG.init(9876);

    for (0..1000) |_| {
        const v = lcg.randInRange(5, 15);
        try std.testing.expect(v >= 5 and v <= 15);
    }
}

test "single value range returns same result" {
    var lcg = MiniLCG.init(123);
    for (0..10) |_| {
        try std.testing.expectEqual(7, lcg.randInRange(7, 7));
    }
}

test "handles seed overflow" {
    var lcg = MiniLCG.init(std.math.maxInt(u64));
    const v = lcg.randInRange(0, 255);
    try std.testing.expect(v <= 255);
}

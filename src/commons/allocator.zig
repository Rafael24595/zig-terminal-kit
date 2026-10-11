const std = @import("std");

/// Wraps an allocator and tracks the number of bytes currently allocated
/// through this tracer.
///
/// The tracer must remain at a stable address and stay alive for as long as
/// its allocator interface is being used.
pub const AllocatorTracer = struct {
    base: std.mem.Allocator,
    bytes_in_use: usize,

    /// Initializes the tracer without allocating any memory.
    pub fn init(base: std.mem.Allocator) @This() {
        return AllocatorTracer{
            .base = base,
            .bytes_in_use = 0,
        };
    }

    /// Returns an allocator interface that forwards operations to this tracer.
    ///
    /// The returned allocator stores a pointer to this instance, so the tracer
    /// must not be moved or destroyed while the allocator is in use.
    pub fn allocator(self: *AllocatorTracer) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &std.mem.Allocator.VTable{
                .alloc = alloc_wrapper,
                .resize = resize_wrapper,
                .remap = remap_wrapper,
                .free = free_wrapper,
            },
        };
    }

    /// Allocates memory using the underlying allocator and records its size
    /// when the allocation succeeds.
    pub fn alloc(
        self: *AllocatorTracer,
        len: usize,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const result = self.base.rawAlloc(len, alignment, ret_addr);
        if (result != null) {
            self.bytes_in_use += len;
        }
        return result;
    }

    /// Attempts to resize an allocation in place.
    ///
    /// Updates the tracked byte count only when the underlying allocator
    /// reports success.
    pub fn resize(
        self: *AllocatorTracer,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const old_len = memory.len;

        const result = self.base.rawResize(
            memory,
            alignment,
            new_len,
            ret_addr,
        );

        if (result) {
            self.update_bytes(old_len, new_len);
        }

        return result;
    }

    /// Attempts to resize an allocation, potentially moving it.
    ///
    /// Updates the tracked byte count only when the underlying allocator
    /// returns a valid pointer.
    pub fn remap(
        self: *AllocatorTracer,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const old_len = memory.len;

        const result = self.base.rawRemap(
            memory,
            alignment,
            new_len,
            ret_addr,
        );

        if (result != null) {
            self.update_bytes(old_len, new_len);
        }

        return result;
    }

    /// Releases an allocation and subtracts its size from the tracked total.
    pub fn free(
        self: *AllocatorTracer,
        memory: []u8,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        self.bytes_in_use -= memory.len;
        self.base.rawFree(memory, alignment, ret_addr);
    }

    /// Returns the number of bytes currently tracked as allocated.
    pub fn bytes(self: *const AllocatorTracer) usize {
        return self.bytes_in_use;
    }

    fn update_bytes(self: *AllocatorTracer, old_len: usize, new_len: usize) void {
        if (new_len >= old_len) {
            self.bytes_in_use += new_len - old_len;
            return;
        }

        const decrease = old_len - new_len;
        if (comptime std.debug.runtime_safety) {
            std.debug.assert(self.bytes_in_use >= decrease);
        }

        self.bytes_in_use -= decrease;
    }
};

fn alloc_wrapper(
    self: *anyopaque,
    len: usize,
    alignment: std.mem.Alignment,
    ret_addr: usize,
) ?[*]u8 {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    return ca.alloc(len, alignment, ret_addr);
}

fn resize_wrapper(
    self: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) bool {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    return ca.resize(memory, alignment, new_len, ret_addr);
}

fn remap_wrapper(
    self: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    return ca.remap(memory, alignment, new_len, ret_addr);
}

fn free_wrapper(
    self: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    ret_addr: usize,
) void {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    ca.free(memory, alignment, ret_addr);
}

test "allocator tracer starts with zero bytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracer = AllocatorTracer.init(gpa.allocator());

    try std.testing.expectEqual(0, tracer.bytes());
}

test "allocator tracer tracks allocation and free" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracer = AllocatorTracer.init(gpa.allocator());
    const alloc = tracer.allocator();

    const memory = try alloc.alloc(u8, 32);
    try std.testing.expectEqual(32, tracer.bytes());

    alloc.free(memory);
    try std.testing.expectEqual(0, tracer.bytes());
}

test "allocator tracer tracks resize when supported" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracer = AllocatorTracer.init(gpa.allocator());
    const alloc = tracer.allocator();

    const memory = try alloc.alloc(u8, 10);
    defer alloc.free(memory);

    if (alloc.resize(memory, 8)) {
        try std.testing.expectEqual(8, tracer.bytes());
    } else {
        try std.testing.expectEqual(10, tracer.bytes());
    }
}

test "allocator tracer tracks ArrayList allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracer = AllocatorTracer.init(gpa.allocator());
    const alloc = tracer.allocator();

    {
        var list = try std.ArrayList(u8).initCapacity(alloc, 2);
        defer list.deinit(alloc);

        const bytes_after_init = tracer.bytes();
        try std.testing.expect(bytes_after_init >= 2);

        try list.append(alloc, 'a');
        try list.append(alloc, 'b');

        try std.testing.expectEqual(bytes_after_init, tracer.bytes());
    }

    try std.testing.expectEqual(0, tracer.bytes());
}

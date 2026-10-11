const std = @import("std");

pub const AllocatorTracer = struct {
    base: std.mem.Allocator,
    bytes_in_use: usize,

    pub fn init(base: std.mem.Allocator) @This() {
        return AllocatorTracer{
            .base = base,
            .bytes_in_use = 0,
        };
    }

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

    pub fn alloc(self: *AllocatorTracer, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const result = self.base.rawAlloc(len, alignment, ret_addr);
        if (result != null) {
            self.bytes_in_use += len;
        }
        return result;
    }

    pub fn resize(self: *AllocatorTracer, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
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

    pub fn remap(self: *AllocatorTracer, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
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

    pub fn free(self: *AllocatorTracer, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        self.bytes_in_use -= memory.len;
        self.base.rawFree(memory, alignment, ret_addr);
    }

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

fn alloc_wrapper(self: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    return ca.alloc(len, alignment, ret_addr);
}

fn resize_wrapper(self: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    return ca.resize(memory, alignment, new_len, ret_addr);
}

fn remap_wrapper(self: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    return ca.remap(memory, alignment, new_len, ret_addr);
}

fn free_wrapper(self: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const ca: *AllocatorTracer = @ptrCast(@alignCast(self));
    ca.free(memory, alignment, ret_addr);
}

test "initialize the allocator with zero bytes with init method" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var base = gpa.allocator();

    var tracer = AllocatorTracer.init(&base);
    try std.testing.expectEqual(0, tracer.bytes());
}

test "increment the bytes in use with alloc method" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var base = gpa.allocator();

    var tracer = AllocatorTracer.init(&base);
    var alloc = tracer.allocator();

    const ptr = try alloc.alloc(u8, 16);
    defer alloc.free(ptr);

    try std.testing.expectEqual(16, tracer.bytes());
}

test "decrement the bytes in use with free method" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var base = gpa.allocator();

    var tracer = AllocatorTracer.init(&base);
    var alloc = tracer.allocator();

    const ptr = try alloc.alloc(u8, 32);
    alloc.free(ptr);
    try std.testing.expectEqual(0, tracer.bytes());
}

test "resize the bytes in use with resize method" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var base = gpa.allocator();

    var tracer = AllocatorTracer.init(&base);
    var alloc = tracer.allocator();

    const buf = try alloc.alloc(u8, 10);
    try std.testing.expect(tracer.bytes() == 10);

    if (alloc.resize(buf, 20)) {
        try std.testing.expectEqual(20, tracer.bytes());
    } else {
        try std.testing.expectEqual(10, tracer.bytes());
    }

    alloc.free(buf);
    try std.testing.expectEqual(0, tracer.bytes());
}

test "integration with ArrayList" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var base = gpa.allocator();

    var tracer = AllocatorTracer.init(&base);
    const alloc = tracer.allocator();

    var list = try std.ArrayList(u8).initCapacity(alloc, 2);
    defer list.deinit(alloc);

    try list.append(alloc, 'a');
    try list.append(alloc, 'b');

    try std.testing.expectEqual(2, tracer.bytes());
}

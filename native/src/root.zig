const std = @import("std");
const types = @import("types.zig");
const vm = @import("vm.zig");
const compiler = @import("compiler.zig");

pub const Value = types.Value;
pub const O5Result = types.O5Result;
pub const Prog = vm.Prog;

const max_slots: usize = 1024;

const SpinLock = struct {
    flag: std.atomic.Value(u8) = .{ .raw = 0 },

    pub fn lock(s: *SpinLock) void {
        while (s.flag.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(s: *SpinLock) void {
        s.flag.store(0, .release);
    }
};

var prog_lock: SpinLock = .{};
var prog_slots: [max_slots]?*Prog = std.mem.zeroes([max_slots]?*Prog);
var prog_free: [max_slots]u16 = undefined;
var prog_free_count: usize = 0;

fn progAlloc(prog: *Prog) ?u16 {
    prog_lock.lock();
    defer prog_lock.unlock();

    var idx: ?u16 = null;
    if (prog_free_count > 0) {
        prog_free_count -= 1;
        idx = prog_free[prog_free_count];
    } else {
        var k: usize = 0;
        while (k < max_slots) : (k += 1) {
            if (prog_slots[k] == null) {
                idx = @intCast(k);
                break;
            }
        }
    }

    if (idx) |v| {
        prog_slots[v] = prog;
        return v;
    }
    return null;
}

fn progGet(h: i64) ?*Prog {
    if (h <= 0 or h > max_slots) return null;
    prog_lock.lock();
    defer prog_lock.unlock();
    return prog_slots[@intCast(h - 1)];
}

export fn o5s_compile(src: [*]const u8, len: usize) i64 {
    const allocator = std.heap.c_allocator;
    const prog = compiler.compileSource(src[0..len], allocator) catch return 0;
    const slot = progAlloc(prog) orelse {
        prog.deinit();
        return 0;
    };
    return @as(i64, slot) + 1;
}

export fn o5s_free(h: i64) void {
    if (h <= 0 or h > max_slots) return;
    prog_lock.lock();
    defer prog_lock.unlock();
    const idx: usize = @intCast(h - 1);
    if (prog_slots[idx]) |prog| {
        prog.deinit();
        prog_slots[idx] = null;
        if (prog_free_count < max_slots) {
            prog_free[prog_free_count] = @intCast(idx);
            prog_free_count += 1;
        }
    }
}

export fn o5s_run(
    h: i64,
    host_vars: ?[*]const f64,
    host_count: usize,
    out_res: *O5Result,
) i32 {
    const prog = progGet(h) orelse return -1;
    const vars_slice = if (host_vars) |ptr| ptr[0..host_count] else &[_]f64{};

    const val = vm.run(prog, 0, vars_slice) catch |err| {
        return switch (err) {
            error.StackOverflow => -2,
            error.StackUnderflow => -3,
            error.StepLimitExceeded => -4,
            error.OutOfBounds => -6,
            error.StringTooLong => -7,
            error.InputEmpty => -8,
            error.AssertionFailed => -9,
            else => -5,
        };
    };

    out_res.* = .{
        .num = val.num,
        .str_ptr = val.str_ptr,
        .str_len = val.str_len,
        .val_type = @intFromEnum(val.val_type),
    };
    return 0;
}

export fn o5s_run_tag(
    h: i64,
    tag_idx: usize,
    host_vars: ?[*]const f64,
    host_count: usize,
    out_res: *O5Result,
) i32 {
    const prog = progGet(h) orelse return -1;
    if (tag_idx >= prog.tags.len) return -2;

    const entry_ip = prog.tags[tag_idx].entry_ip;
    const vars_slice = if (host_vars) |ptr| ptr[0..host_count] else &[_]f64{};

    const val = vm.run(prog, entry_ip, vars_slice) catch |err| {
        return switch (err) {
            error.StackOverflow => -3,
            error.StackUnderflow => -4,
            error.StepLimitExceeded => -5,
            error.InputEmpty => -8,
            error.AssertionFailed => -9,
            else => -6,
        };
    };

    out_res.* = .{
        .num = val.num,
        .str_ptr = val.str_ptr,
        .str_len = val.str_len,
        .val_type = @intFromEnum(val.val_type),
    };
    return 0;
}

export fn o5s_tag_count(h: i64) usize {
    const prog = progGet(h) orelse return 0;
    return prog.tags.len;
}

export fn o5s_tag_name(h: i64, tag_idx: usize, out_buf: [*]u8, max_buf: usize) usize {
    const prog = progGet(h) orelse return 0;
    if (tag_idx >= prog.tags.len) return 0;
    const name = prog.tags[tag_idx].name;
    const len = @min(name.len, max_buf);
    @memcpy(out_buf[0..len], name[0..len]);
    return len;
}

export fn o5s_tag_find(h: i64, name_ptr: [*]const u8, name_len: usize) i32 {
    const prog = progGet(h) orelse return -1;
    const target = name_ptr[0..name_len];
    for (prog.tags, 0..) |t, i| {
        if (std.mem.eql(u8, t.name, target)) {
            return @intCast(i);
        }
    }
    return -1;
}

export fn o5s_host_tag_count(h: i64) usize {
    const prog = progGet(h) orelse return 0;
    return prog.host_tags.len;
}

export fn o5s_host_tag_name(h: i64, host_idx: usize, out_buf: [*]u8, max_buf: usize) usize {
    const prog = progGet(h) orelse return 0;
    if (host_idx >= prog.host_tags.len) return 0;
    const name = prog.host_tags[host_idx];
    const len = @min(name.len, max_buf);
    @memcpy(out_buf[0..len], name[0..len]);
    return len;
}

export fn o5s_reset_state(h: i64) void {
    const prog = progGet(h) orelse return;
    prog.resetState();
}

/// Drain the Dbg.out buffer: copy up to max_buf bytes out and clear it.
/// Returns bytes copied.
export fn o5s_dbg_take(out_buf: [*]u8, max_buf: usize) usize {
    return vm.dbgTake(out_buf[0..max_buf]);
}

/// Feed the Dbg.in slot (truncated to 256B). Returns bytes stored.
export fn o5s_dbg_feed(in_ptr: [*]const u8, in_len: usize) usize {
    return vm.dbgFeed(in_ptr[0..in_len]);
}

/// Seed the Rng state (0 selects the default seed).
export fn o5s_rng_seed(seed: u64) void {
    vm.rngSeed(seed);
}

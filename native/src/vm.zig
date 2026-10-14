const std = @import("std");
const math = std.math;
const types = @import("types.zig");

pub const Value = types.Value;
pub const ValueType = types.ValueType;
pub const Op = types.Op;
pub const OpCode = types.OpCode;
pub const Builtin = types.Builtin;
pub const TagDef = types.TagDef;
pub const FuncDef = types.FuncDef;
pub const O5Result = types.O5Result;

pub const max_stack: usize = 256;
pub const max_locals: usize = 512;
pub const max_calls: usize = 64;
pub const max_steps: usize = 1_000_000;

threadlocal var thread_scratch: [65536]u8 = undefined;

pub const EvalError = error{
    StackOverflow,
    StackUnderflow,
    CallStackOverflow,
    CallStackUnderflow,
    StepLimitExceeded,
    InvalidOpcode,
    OutOfMemory,
    OutOfBounds,
    StringTooLong,
    InvalidType,
    InputEmpty,
    AssertionFailed,
};

pub const Prog = struct {
    ops: []Op,
    string_pool: []u8,
    host_tags: [][]const u8,
    tags: []TagDef,
    funcs: []FuncDef,
    state_slots: []Value,
    state_inits: []Value,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Prog) void {
        self.allocator.free(self.ops);
        self.allocator.free(self.string_pool);
        for (self.host_tags) |tag_name| {
            self.allocator.free(tag_name);
        }
        self.allocator.free(self.host_tags);
        for (self.tags) |tag_def| {
            self.allocator.free(tag_def.name);
        }
        self.allocator.free(self.tags);
        for (self.funcs) |func_def| {
            self.allocator.free(func_def.name);
        }
        self.allocator.free(self.funcs);
        self.allocator.free(self.state_slots);
        self.allocator.free(self.state_inits);
        self.allocator.destroy(self);
    }

    pub fn resetState(self: *Prog) void {
        @memcpy(self.state_slots, self.state_inits);
    }

    pub fn getString(self: *const Prog, packed_arg: i64) []const u8 {
        const offset: usize = @intCast(@as(u32, @truncate(@as(u64, @bitCast(packed_arg)))));
        const len: usize = @intCast(@as(u32, @truncate(@as(u64, @bitCast(packed_arg)) >> 32)));
        if (offset + len <= self.string_pool.len) {
            return self.string_pool[offset .. offset + len];
        }
        return "";
    }
};

fn appendString(scratch: []u8, pos: *usize, text: []const u8) !void {
    if (pos.* + text.len > scratch.len) return EvalError.OutOfMemory;
    @memcpy(scratch[pos.* .. pos.* + text.len], text);
    pos.* += text.len;
}

fn appendNumber(scratch: []u8, pos: *usize, num: f64) !void {
    if (math.isNan(num)) {
        try appendString(scratch, pos, "NaN");
        return;
    }
    if (math.isPositiveInf(num)) {
        try appendString(scratch, pos, "Infinity");
        return;
    }
    if (math.isNegativeInf(num)) {
        try appendString(scratch, pos, "-Infinity");
        return;
    }

    if (num == @trunc(num) and @abs(num) < 9007199254740992.0) {
        const int_val: i64 = @intFromFloat(num);
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{int_val}) catch return EvalError.OutOfMemory;
        try appendString(scratch, pos, s);
    } else {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{num}) catch return EvalError.OutOfMemory;
        try appendString(scratch, pos, s);
    }
}

extern fn o5s_vm_exec_x86_64(
    prog: *Prog,
    entry_ip: usize,
    host_vars: ?[*]const f64,
    host_count: usize,
    out_res: *O5Result,
) callconv(.{ .x86_64_sysv = .{} }) i32;

threadlocal var asm_scratch_pos: usize = 0;

// ---- std.dbg / std.fmt / std.rng: fixed-size, stack-friendly state ----
// No heap, no allocator. All buffers are statically bounded:
// - dbg_out: single 256B append buffer drained by the host.
// - dbg_in: single 256B slot fed by the host (consumed on read).
// - rng: one u64 of xorshift64* state.
threadlocal var dbg_out_buf: [types.max_str_len]u8 = undefined;
threadlocal var dbg_out_len: usize = 0;
threadlocal var dbg_in_buf: [types.max_str_len]u8 = undefined;
threadlocal var dbg_in_len: usize = 0;
threadlocal var rng_state: u64 = 0x9E3779B97F4A7C15;

const rng_default_seed: u64 = 0x9E3779B97F4A7C15;

pub fn rngSeed(s: u64) void {
    rng_state = if (s == 0) rng_default_seed else s;
}

fn rngNextU64() u64 {
    var x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return x *% 0x2545F4914F6CDD1D;
}

fn rngUnit() f64 {
    return @as(f64, @floatFromInt(rngNextU64() >> 11)) * (1.0 / 9007199254740992.0);
}

fn appendValueDbg(v: Value) EvalError!void {
    if (v.val_type == .str) {
        appendString(&dbg_out_buf, &dbg_out_len, v.toSlice()) catch return EvalError.StringTooLong;
    } else {
        appendNumber(&dbg_out_buf, &dbg_out_len, v.num) catch return EvalError.StringTooLong;
    }
}

/// Dbg.out(v): append value + '\n' to the fixed out-buffer. Traps on overflow.
pub fn dbgOut(v: Value) EvalError!void {
    try appendValueDbg(v);
    if (dbg_out_len >= dbg_out_buf.len) return EvalError.StringTooLong;
    dbg_out_buf[dbg_out_len] = '\n';
    dbg_out_len += 1;
}

/// Dbg.in(): consume the fed input slot. Traps InputEmpty when nothing was fed.
pub fn dbgInTake() EvalError!Value {
    if (dbg_in_len == 0) return EvalError.InputEmpty;
    const v = Value.fromStr(dbg_in_buf[0..dbg_in_len]);
    dbg_in_len = 0;
    return v;
}

/// Host drain: copy out-buffer out and clear it. Returns bytes copied.
pub fn dbgTake(out: []u8) usize {
    const n = @min(dbg_out_len, out.len);
    @memcpy(out[0..n], dbg_out_buf[0..n]);
    dbg_out_len = 0;
    return n;
}

/// Host feed: fill the input slot (truncated to 256B). Returns bytes stored.
pub fn dbgFeed(data: []const u8) usize {
    const n = @min(data.len, dbg_in_buf.len);
    @memcpy(dbg_in_buf[0..n], data[0..n]);
    dbg_in_len = n;
    return n;
}

pub fn dbgOutLen() usize {
    return dbg_out_len;
}

/// Bitwise-op coercion mirroring x86 cvttsd2si saturation
/// (NaN / out-of-range -> INT64_MIN). Fractionals truncate.
fn f64ToI64Sat(v: f64) i64 {
    if (math.isNan(v) or v >= 9223372036854775808.0 or v <= -9223372036854775808.0) {
        return std.math.minInt(i64);
    }
    return @intFromFloat(v);
}

/// Str.len: byte length. Non-str is InvalidType (strict: no silent 0.0).
fn strLen(v: Value) EvalError!f64 {
    if (v.val_type != .str) return EvalError.InvalidType;
    return @floatFromInt(v.str_len);
}

/// Str.sub(s, a, b): zero-copy byte slice [a, b). Out-of-range traps OutOfBounds.
fn strSub(s: Value, a: f64, b: f64) EvalError!Value {
    if (s.val_type != .str) return EvalError.InvalidType;
    const len: f64 = @floatFromInt(s.str_len);
    if (math.isNan(a) or math.isNan(b)) return EvalError.OutOfBounds;
    if (a != @trunc(a) or b != @trunc(b)) return EvalError.OutOfBounds;
    if (a < 0 or b < 0 or a > b or b > len) return EvalError.OutOfBounds;
    const ai: usize = @intFromFloat(a);
    const bi: usize = @intFromFloat(b);
    return Value.fromStr(s.toSlice()[ai..bi]);
}

/// Str.find(s, sub): byte index or -1. Empty needle matches at 0.
fn strFind(s: Value, sub: Value) EvalError!f64 {
    if (s.val_type != .str or sub.val_type != .str) return EvalError.InvalidType;
    const hay = s.toSlice();
    const ndl = sub.toSlice();
    if (ndl.len == 0) return 0.0;
    if (ndl.len > hay.len) return -1.0;
    var i: usize = 0;
    while (i + ndl.len <= hay.len) : (i += 1) {
        if (std.mem.eql(u8, hay[i .. i + ndl.len], ndl)) return @floatFromInt(i);
    }
    return -1.0;
}

/// Str.num(s): parse decimal, invalid -> NaN (never traps).
fn strNum(v: Value) EvalError!f64 {
    if (v.val_type != .str) return EvalError.InvalidType;
    return std.fmt.parseFloat(f64, v.toSlice()) catch std.math.nan(f64);
}

/// Hsh.fnv(s): FNV-1a 32-bit over bytes, exact in f64.
fn hshFnv(v: Value) EvalError!f64 {
    if (v.val_type != .str) return EvalError.InvalidType;
    var h: u32 = 2166136261;
    for (v.toSlice()) |byte| {
        h ^= byte;
        h *%= 16777619;
    }
    return @floatFromInt(h);
}

fn nosHash(ix: i32, iy: i32) u32 {
    var h: u64 = @as(u64, @bitCast(@as(i64, ix))) *% 0x9E3779B97F4A7C15 +% @as(u64, @bitCast(@as(i64, iy)));
    h ^= h >> 30;
    h *%= 0xBF58476D1CE4E5B9;
    h ^= h >> 27;
    h *%= 0x94D049BB133111EB;
    h ^= h >> 31;
    return @truncate(h);
}

fn nosLattice(ix: i32, iy: i32) f64 {
    return @as(f64, @floatFromInt(nosHash(ix, iy))) / 4294967296.0 * 2.0 - 1.0;
}

fn nosFade(f: f64) f64 {
    return f * f * (3.0 - 2.0 * f);
}

/// Deterministic value noise in [-1, 1]. Coordinates wrap mod 1024
/// (keeps int casts UB-free for arbitrary finite inputs).
fn nosPer(x: f64) f64 {
    if (!std.math.isFinite(x)) return 0.0 * x;
    const fl = @floor(x);
    const fx = @mod(fl, 1024.0);
    const ix: i32 = @intFromFloat(@floor(fx));
    const f = x - fl;
    const t = nosFade(f);
    return nosLattice(ix, 0) * (1.0 - t) + nosLattice(ix + 1, 0) * t;
}

fn nosPer2(x: f64, y: f64) f64 {
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return std.math.nan(f64);
    const xfl = @floor(x);
    const yfl = @floor(y);
    const fx = @mod(xfl, 1024.0);
    const fy = @mod(yfl, 1024.0);
    const ix: i32 = @intFromFloat(@floor(fx));
    const iy: i32 = @intFromFloat(@floor(fy));
    const u = nosFade(x - xfl);
    const v = nosFade(y - yfl);
    const a = nosLattice(ix, iy) * (1.0 - u) + nosLattice(ix + 1, iy) * u;
    const b = nosLattice(ix, iy + 1) * (1.0 - u) + nosLattice(ix + 1, iy + 1) * u;
    return a * (1.0 - v) + b * v;
}

/// Dbg.asr failure note (best effort single line, then trap regardless).
fn asrNote(msg: ?Value) void {
    appendString(&dbg_out_buf, &dbg_out_len, "assert failed") catch {};
    if (msg) |m| {
        if (m.val_type == .str and m.str_len > 0) {
            appendString(&dbg_out_buf, &dbg_out_len, ": ") catch {};
            appendString(&dbg_out_buf, &dbg_out_len, m.toSlice()) catch {};
        }
    }
    if (dbg_out_len < dbg_out_buf.len) {
        dbg_out_buf[dbg_out_len] = '\n';
        dbg_out_len += 1;
    }
}

/// Mini printf into a fixed buffer: `{}` = next arg, `{d}` = truncated int,
/// `{{` / `}}` = literal braces. Unknown `{...}` is copied literally,
/// missing args render as "". Traps StringTooLong on overflow.
pub fn fmtInto(out: []u8, fmt: []const u8, args: []const Value) EvalError!usize {
    var pos: usize = 0;
    var ai: usize = 0;
    var i: usize = 0;
    while (i < fmt.len) {
        const c = fmt[i];
        if (c == '{') {
            if (i + 1 < fmt.len and fmt[i + 1] == '{') {
                if (pos >= out.len) return EvalError.StringTooLong;
                out[pos] = '{';
                pos += 1;
                i += 2;
                continue;
            }
            var j = i + 1;
            while (j < fmt.len and fmt[j] != '}') : (j += 1) {}
            if (j >= fmt.len) {
                // Unterminated '{': literal.
                if (pos >= out.len) return EvalError.StringTooLong;
                out[pos] = '{';
                pos += 1;
                i += 1;
                continue;
            }
            const spec = fmt[i + 1 .. j];
            if (spec.len == 0 or std.mem.eql(u8, spec, "d")) {
                if (ai < args.len) {
                    const arg = args[ai];
                    if (arg.val_type == .str) {
                        if (spec.len == 0) {
                            appendString(out, &pos, arg.toSlice()) catch return EvalError.StringTooLong;
                        }
                        // `{d}` on str renders as "".
                    } else {
                        const n = if (spec.len == 0) arg.num else @trunc(arg.num);
                        appendNumber(out, &pos, n) catch return EvalError.StringTooLong;
                    }
                }
                // Missing args render as "".
                ai += 1;
            } else {
                // Unknown spec: copy literally including braces.
                if (pos + spec.len + 2 > out.len) return EvalError.StringTooLong;
                out[pos] = '{';
                @memcpy(out[pos + 1 .. pos + 1 + spec.len], spec);
                out[pos + 1 + spec.len] = '}';
                pos += spec.len + 2;
            }
            i = j + 1;
        } else if (c == '}' and i + 1 < fmt.len and fmt[i + 1] == '}') {
            if (pos >= out.len) return EvalError.StringTooLong;
            out[pos] = '}';
            pos += 1;
            i += 2;
        } else {
            if (pos >= out.len) return EvalError.StringTooLong;
            out[pos] = c;
            pos += 1;
            i += 1;
        }
    }
    return pos;
}

export fn o5s_asm_str_add(l: *Value, r: *Value) callconv(.{ .x86_64_sysv = .{} }) void {
    const scratch = &thread_scratch;
    if (asm_scratch_pos + 1024 > scratch.len) {
        asm_scratch_pos = 0;
    }
    const start_pos = asm_scratch_pos;
    if (l.val_type == .str) {
        appendString(scratch, &asm_scratch_pos, l.toSlice()) catch return;
    } else {
        appendNumber(scratch, &asm_scratch_pos, l.num) catch return;
    }
    if (r.val_type == .str) {
        appendString(scratch, &asm_scratch_pos, r.toSlice()) catch return;
    } else {
        appendNumber(scratch, &asm_scratch_pos, r.num) catch return;
    }
    const len = asm_scratch_pos - start_pos;
    if (len <= types.max_str_len) {
        l.* = Value.fromStr(scratch[start_pos .. start_pos + len]);
    }
}

export fn o5s_asm_str_eq(l: *Value, r: *Value) callconv(.{ .x86_64_sysv = .{} }) u32 {
    if (l.val_type == .str and r.val_type == .str) {
        return if (std.mem.eql(u8, l.toSlice(), r.toSlice())) 1 else 0;
    }
    return 0;
}

export fn o5s_asm_str_copy(v: *Value) callconv(.{ .x86_64_sysv = .{} }) void {
    if (v.val_type != .str or v.str_ptr == null or v.str_len == 0) return;
    const scratch = &thread_scratch;
    if (asm_scratch_pos + v.str_len > scratch.len) {
        asm_scratch_pos = 0;
    }
    const start_pos = asm_scratch_pos;
    @memcpy(scratch[start_pos .. start_pos + v.str_len], v.toSlice());
    asm_scratch_pos += v.str_len;
    v.* = Value.fromStr(scratch[start_pos .. start_pos + v.str_len]);
}

/// Shared Fmt.f implementation: args[0] is the format string.
/// Result borrows the thread scratch ring (same lifetime rules as `+`).
fn builtinFmt(args: []const Value) EvalError!Value {
    const scratch = &thread_scratch;
    if (asm_scratch_pos + types.max_str_len > scratch.len) {
        asm_scratch_pos = 0;
    }
    const start_pos = asm_scratch_pos;
    const out = scratch[start_pos .. start_pos + types.max_str_len];
    var num_buf: [64]u8 = undefined;
    const fmt_slice: []const u8 = if (args[0].val_type == .str)
        args[0].toSlice()
    else blk: {
        var pos: usize = 0;
        appendNumber(&num_buf, &pos, args[0].num) catch return EvalError.StringTooLong;
        break :blk num_buf[0..pos];
    };
    const len = try fmtInto(out, fmt_slice, args[1..]);
    asm_scratch_pos += types.max_str_len;
    return Value.fromStr(scratch[start_pos .. start_pos + len]);
}

/// Result protocol for o5s_asm_builtin_call: err == 0 on success with a
/// SIGNED stack delta (positive pushes, e.g. +24 for arity-0 producers);
/// err < 0 carries the negated VM error code (-7 StringTooLong, -8 InputEmpty).
pub const AsmBuiltinRes = extern struct {
    delta: i64,
    err: i64,
};

export fn o5s_asm_builtin_call(packed_arg: i64, stack_top: [*]Value) callconv(.{ .x86_64_sysv = .{} }) AsmBuiltinRes {
    const ok = struct {
        fn r(delta: i64) AsmBuiltinRes {
            return .{ .delta = delta, .err = 0 };
        }
    }.r;
    const fail = struct {
        fn e(code: i64) AsmBuiltinRes {
            return .{ .delta = 0, .err = code };
        }
    }.e;
    const builtin_id: Builtin = @enumFromInt(@as(u8, @truncate(@as(u64, @bitCast(packed_arg)))));
    const arity: u8 = @truncate(@as(u64, @bitCast(packed_arg)) >> 8);
    // fmt is variadic (format string + up to 7 args): dispatch before arity.
    if (builtin_id == .fmt) {
        const n: usize = @max(arity, 1);
        const args = (stack_top - n)[0..n];
        const res = builtinFmt(args) catch return fail(-7);
        (stack_top - n)[0] = res;
        return ok(-@as(i64, @intCast((n - 1) * 24)));
    }
    // Dbg.asr(cond[, msg]): trap AssertionFailed (-9) with a buffer note.
    if (builtin_id == .dbg_asr) {
        if (arity < 1 or arity > 2) return fail(-5);
        const cond = (stack_top - arity)[0];
        if (!cond.isTruthy()) {
            const msg: ?Value = if (arity == 2) (stack_top - 1)[0] else null;
            asrNote(msg);
            return fail(-9);
        }
        (stack_top - arity)[0] = Value.fromNum(0.0);
        const n: usize = arity;
        return ok(-@as(i64, @intCast((n - 1) * 24)));
    }
    if (arity == 0) {
        switch (builtin_id) {
            .dbg_in => {
                stack_top[0] = dbgInTake() catch return fail(-8);
                return ok(24);
            },
            .rng_next => {
                stack_top[0] = Value.fromNum(rngUnit());
                return ok(24);
            },
            else => {
                stack_top[0] = Value.fromNum(0.0);
                return ok(24);
            },
        }
    }
    if (arity == 1) {
        const ptr = stack_top - 1;
        const arg0 = ptr[0].num;
        switch (builtin_id) {
            .dbg_out => {
                dbgOut(ptr[0]) catch return fail(-7);
                ptr[0] = Value.fromNum(0.0);
                return ok(0);
            },
            .rng_seed => {
                rngSeed(@as(u64, @bitCast(arg0)));
                ptr[0] = Value.fromNum(0.0);
                return ok(0);
            },
            .str_len => {
                ptr[0] = Value.fromNum(strLen(ptr[0]) catch return fail(-5));
                return ok(0);
            },
            .str_num => {
                ptr[0] = Value.fromNum(strNum(ptr[0]) catch return fail(-5));
                return ok(0);
            },
            .hsh_fnv => {
                ptr[0] = Value.fromNum(hshFnv(ptr[0]) catch return fail(-5));
                return ok(0);
            },
            .nos_per => {
                ptr[0] = Value.fromNum(nosPer(arg0));
                return ok(0);
            },
            else => {
                const res = switch (builtin_id) {
                    .sin => @sin(arg0),
                    .cos => @cos(arg0),
                    .tan => @tan(arg0),
                    .asin => math.asin(arg0),
                    .acos => math.acos(arg0),
                    .atan => math.atan(arg0),
                    .sqrt => @sqrt(arg0),
                    .abs => @abs(arg0),
                    .floor => @floor(arg0),
                    .ceil => @ceil(arg0),
                    .round => @round(arg0),
                    .log => @log(arg0),
                    .exp => @exp(arg0),
                    else => arg0,
                };
                ptr[0] = Value.fromNum(res);
                return ok(0);
            },
        }
    } else if (arity == 2) {
        const ptr1 = stack_top - 1;
        const ptr0 = stack_top - 2;
        const arg1 = ptr1[0].num;
        const arg0 = ptr0[0].num;
        if (builtin_id == .str_find) {
            ptr0[0] = Value.fromNum(strFind(ptr0[0], ptr1[0]) catch return fail(-5));
            return ok(-24);
        }
        if (builtin_id == .nos_per2) {
            ptr0[0] = Value.fromNum(nosPer2(arg0, arg1));
            return ok(-24);
        }
        const res = switch (builtin_id) {
            .atan2 => math.atan2(arg0, arg1),
            .min => @min(arg0, arg1),
            .max => @max(arg0, arg1),
            .pow => math.pow(f64, arg0, arg1),
            .rng_range => arg0 + (arg1 - arg0) * rngUnit(),
            else => 0.0,
        };
        ptr0[0] = Value.fromNum(res);
        return ok(-24);
    } else if (arity == 3) {
        const ptr2 = stack_top - 1;
        const ptr1 = stack_top - 2;
        const ptr0 = stack_top - 3;
        const arg2 = ptr2[0].num;
        const arg1 = ptr1[0].num;
        const arg0 = ptr0[0].num;
        if (builtin_id == .str_sub) {
            ptr0[0] = strSub(ptr0[0], arg1, arg2) catch |err| return fail(switch (err) {
                error.OutOfBounds => -6,
                else => -5,
            });
            return ok(-48);
        }
        const res = switch (builtin_id) {
            .clamp => math.clamp(arg0, arg1, arg2),
            .lerp => math.lerp(arg0, arg1, arg2),
            else => 0.0,
        };
        ptr0[0] = Value.fromNum(res);
        return ok(-48);
    }
    return ok(0);
}

pub fn run(
    prog: *Prog,
    entry_ip: usize,
    host_vars: []const f64,
) EvalError!Value {
    if (@import("builtin").cpu.arch == .x86_64 and @import("builtin").os.tag == .linux) {
        var res: O5Result = .{};
        const vars_ptr = if (host_vars.len > 0) host_vars.ptr else null;
        const ret_code = o5s_vm_exec_x86_64(prog, entry_ip, vars_ptr, host_vars.len, &res);
        if (ret_code == 0) {
            return Value{
                .num = res.num,
                .str_ptr = res.str_ptr,
                .str_len = res.str_len,
                .val_type = @enumFromInt(res.val_type),
            };
        } else if (ret_code == -6) {
            return EvalError.OutOfBounds;
        } else if (ret_code == -2) {
            return EvalError.StackOverflow;
        } else if (ret_code == -3) {
            return EvalError.StackUnderflow;
        } else if (ret_code == -4) {
            return EvalError.StepLimitExceeded;
        } else if (ret_code == -7) {
            return EvalError.StringTooLong;
        } else if (ret_code == -8) {
            return EvalError.InputEmpty;
        } else if (ret_code == -9) {
            return EvalError.AssertionFailed;
        }
        // Never fall through: re-executing in the interpreter would
        // double all side effects (dbg buffer, rng state, sta slots).
        return EvalError.InvalidOpcode;
    }

    const scratch = &thread_scratch;
    var scratch_pos: usize = 0;

    var stack: [max_stack]Value = undefined;
    var sp: usize = 0;

    var locals: [max_locals]Value = std.mem.zeroes([max_locals]Value);
    const CallFrame = struct {
        ret_ip: usize,
        prev_fp: usize,
    };
    var call_stack: [max_calls]CallFrame = undefined;
    var csp: usize = 0;
    var fp: usize = 0;

    var ip: usize = entry_ip;
    const ops = prog.ops;
    const ops_len = ops.len;
    var steps: usize = 0;

    while (ip < ops_len) {
        steps += 1;
        if (steps > max_steps) return EvalError.StepLimitExceeded;

        const op = ops[ip];
        ip += 1;

        switch (op.code) {
            .nop => {},

            .push_num => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                stack[sp] = Value.fromNum(@bitCast(op.arg));
                sp += 1;
            },

            .push_0 => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                stack[sp] = Value.fromNum(0.0);
                sp += 1;
            },

            .push_1 => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                stack[sp] = Value.fromNum(1.0);
                sp += 1;
            },

            .push_str => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                const s = prog.getString(op.arg);
                stack[sp] = Value.fromStr(s);
                sp += 1;
            },

            .pop => {
                if (sp > 0) sp -= 1;
            },

            .dup => {
                if (sp < 1) return EvalError.StackUnderflow;
                if (sp >= max_stack) return EvalError.StackOverflow;
                stack[sp] = stack[sp - 1];
                sp += 1;
            },

            .load_local => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                const slot: usize = fp + @as(usize, @intCast(op.arg));
                stack[sp] = if (slot < max_locals) locals[slot] else Value.fromNum(0.0);
                sp += 1;
            },

            .store_local => {
                if (sp < 1) return EvalError.StackUnderflow;
                sp -= 1;
                const slot: usize = fp + @as(usize, @intCast(op.arg));
                if (slot < max_locals) {
                    locals[slot] = stack[sp];
                }
            },

            .load_state => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                const slot: usize = @intCast(op.arg);
                stack[sp] = if (slot < prog.state_slots.len) prog.state_slots[slot] else Value.fromNum(0.0);
                sp += 1;
            },

            .store_state => {
                if (sp < 1) return EvalError.StackUnderflow;
                sp -= 1;
                const slot: usize = @intCast(op.arg);
                if (slot < prog.state_slots.len) {
                    prog.state_slots[slot] = stack[sp];
                }
            },

            .load_host => {
                if (sp >= max_stack) return EvalError.StackOverflow;
                const idx: usize = @intCast(op.arg);
                const val = if (idx < host_vars.len) host_vars[idx] else 0.0;
                stack[sp] = Value.fromNum(val);
                sp += 1;
            },

            .check_bounds => {
                if (sp < 1) return EvalError.StackUnderflow;
                const top = stack[sp - 1];
                if (top.val_type != .num) return EvalError.InvalidType;
                const bound: f64 = @floatFromInt(op.arg);
                // NOTE: NaN comparisons are all false, so check explicitly:
                // without this, @intFromFloat(NaN) below is UB in release.
                if (math.isNan(top.num) or top.num < 0.0 or top.num >= bound) {
                    return EvalError.OutOfBounds;
                }
                const idx_int: i64 = @intFromFloat(top.num);
                if (@as(f64, @floatFromInt(idx_int)) != top.num) {
                    return EvalError.OutOfBounds;
                }
            },

            .load_local_elem => {
                if (sp < 1) return EvalError.StackUnderflow;
                const idx_val = stack[sp - 1];
                sp -= 1;
                if (idx_val.val_type != .num) return EvalError.InvalidType;
                const idx_int: i64 = @intFromFloat(idx_val.num);
                const slot_i64 = @as(i64, @intCast(fp)) + op.arg + idx_int;
                if (slot_i64 < 0 or slot_i64 >= max_locals) return EvalError.OutOfBounds;
                const slot: usize = @intCast(slot_i64);
                stack[sp] = locals[slot];
                sp += 1;
            },

            .store_local_elem => {
                if (sp < 2) return EvalError.StackUnderflow;
                const val = stack[sp - 1];
                const idx_val = stack[sp - 2];
                sp -= 2;
                if (idx_val.val_type != .num) return EvalError.InvalidType;
                const idx_int: i64 = @intFromFloat(idx_val.num);
                const slot_i64 = @as(i64, @intCast(fp)) + op.arg + idx_int;
                if (slot_i64 < 0 or slot_i64 >= max_locals) return EvalError.OutOfBounds;
                const slot: usize = @intCast(slot_i64);
                locals[slot] = val;
            },

            .load_state_elem => {
                if (sp < 1) return EvalError.StackUnderflow;
                const idx_val = stack[sp - 1];
                sp -= 1;
                if (idx_val.val_type != .num) return EvalError.InvalidType;
                const idx: usize = @intFromFloat(idx_val.num);
                const base: usize = @intCast(op.arg);
                const slot = base + idx;
                if (slot >= prog.state_slots.len) return EvalError.OutOfBounds;
                stack[sp] = prog.state_slots[slot];
                sp += 1;
            },

            .store_state_elem => {
                if (sp < 2) return EvalError.StackUnderflow;
                const val = stack[sp - 1];
                const idx_val = stack[sp - 2];
                sp -= 2;
                if (idx_val.val_type != .num) return EvalError.InvalidType;
                const idx: usize = @intFromFloat(idx_val.num);
                const base: usize = @intCast(op.arg);
                const slot = base + idx;
                if (slot >= prog.state_slots.len) return EvalError.OutOfBounds;
                prog.state_slots[slot] = val;
            },

            .add => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;

                if (l.val_type == .str or r.val_type == .str) {
                    const start_pos = scratch_pos;
                    if (l.val_type == .str) {
                        try appendString(scratch, &scratch_pos, l.toSlice());
                    } else {
                        try appendNumber(scratch, &scratch_pos, l.num);
                    }

                    if (r.val_type == .str) {
                        try appendString(scratch, &scratch_pos, r.toSlice());
                    } else {
                        try appendNumber(scratch, &scratch_pos, r.num);
                    }

                    const len = scratch_pos - start_pos;
                    if (len > types.max_str_len) return EvalError.StringTooLong;
                    stack[sp - 1] = Value.fromStr(scratch[start_pos .. start_pos + len]);
                } else {
                    stack[sp - 1] = Value.fromNum(l.num + r.num);
                }
            },

            .sub => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(l.num - r.num);
            },

            .mul => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(l.num * r.num);
            },

            .div => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(l.num / r.num);
            },

            .mod => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                if (r.num == 0.0) {
                    stack[sp - 1] = Value.fromNum(math.nan(f64));
                } else {
                    stack[sp - 1] = Value.fromNum(@rem(l.num, r.num));
                }
            },

            .neg => {
                if (sp < 1) return EvalError.StackUnderflow;
                const top = stack[sp - 1];
                stack[sp - 1] = Value.fromNum(-top.num);
            },

            .bit_and => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = f64ToI64Sat(l.num);
                const b: i64 = f64ToI64Sat(r.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a & b));
            },

            .bit_or => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = f64ToI64Sat(l.num);
                const b: i64 = f64ToI64Sat(r.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a | b));
            },

            .bit_xor => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = f64ToI64Sat(l.num);
                const b: i64 = f64ToI64Sat(r.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a ^ b));
            },

            .bit_not => {
                if (sp < 1) return EvalError.StackUnderflow;
                const top = stack[sp - 1];
                const a: i64 = f64ToI64Sat(top.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(~a));
            },

            .shl => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = f64ToI64Sat(l.num);
                const shift: u6 = @truncate(@as(u64, @bitCast(f64ToI64Sat(r.num))) & 63);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a << shift));
            },

            .shr => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = f64ToI64Sat(l.num);
                const shift: u6 = @truncate(@as(u64, @bitCast(f64ToI64Sat(r.num))) & 63);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a >> shift));
            },

            .eq => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                var res = false;
                if (l.val_type == .str and r.val_type == .str) {
                    res = std.mem.eql(u8, l.toSlice(), r.toSlice());
                } else if (l.val_type == .num and r.val_type == .num) {
                    res = l.num == r.num;
                }
                stack[sp - 1] = Value.fromNum(if (res) 1.0 else 0.0);
            },

            .ne => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                var res = false;
                if (l.val_type == .str and r.val_type == .str) {
                    res = !std.mem.eql(u8, l.toSlice(), r.toSlice());
                } else if (l.val_type == .num and r.val_type == .num) {
                    res = l.num != r.num;
                } else {
                    res = true;
                }
                stack[sp - 1] = Value.fromNum(if (res) 1.0 else 0.0);
            },

            .lt => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(if (l.num < r.num) 1.0 else 0.0);
            },

            .le => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(if (l.num <= r.num) 1.0 else 0.0);
            },

            .gt => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(if (l.num > r.num) 1.0 else 0.0);
            },

            .ge => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                stack[sp - 1] = Value.fromNum(if (l.num >= r.num) 1.0 else 0.0);
            },

            .lnot => {
                if (sp < 1) return EvalError.StackUnderflow;
                const top = stack[sp - 1];
                stack[sp - 1] = Value.fromNum(if (!top.isTruthy()) 1.0 else 0.0);
            },

            .jmp => {
                ip = @intCast(op.arg);
            },

            .jmp_if_zero => {
                if (sp < 1) return EvalError.StackUnderflow;
                sp -= 1;
                if (!stack[sp].isTruthy()) {
                    ip = @intCast(op.arg);
                }
            },

            .jmp_if_nonzero => {
                if (sp < 1) return EvalError.StackUnderflow;
                sp -= 1;
                if (stack[sp].isTruthy()) {
                    ip = @intCast(op.arg);
                }
            },

            .call_builtin => {
                const builtin_id: Builtin = @enumFromInt(@as(u8, @truncate(@as(u64, @bitCast(op.arg)))));
                const arity: u8 = @truncate(@as(u64, @bitCast(op.arg)) >> 8);
                if (sp < arity) return EvalError.StackUnderflow;

                // fmt is variadic (format string + up to 7 args): dispatch before arity.
                if (builtin_id == .fmt) {
                    const n: usize = @max(arity, 1);
                    const res = try builtinFmt(stack[sp - n .. sp]);
                    sp -= n - 1;
                    stack[sp - 1] = res;
                } else if (builtin_id == .dbg_asr) {
                    if (arity < 1 or arity > 2) return EvalError.StackUnderflow;
                    const cond = stack[sp - arity];
                    if (!cond.isTruthy()) {
                        const msg: ?Value = if (arity == 2) stack[sp - 1] else null;
                        asrNote(msg);
                        return EvalError.AssertionFailed;
                    }
                    sp -= arity - 1;
                    stack[sp - 1] = Value.fromNum(0.0);
                } else if (arity == 0) {
                    if (sp >= max_stack) return EvalError.StackOverflow;
                    switch (builtin_id) {
                        .dbg_in => stack[sp] = try dbgInTake(),
                        .rng_next => stack[sp] = Value.fromNum(rngUnit()),
                        else => stack[sp] = Value.fromNum(0.0),
                    }
                    sp += 1;
                } else if (arity == 1) {
                    switch (builtin_id) {
                        .dbg_out => {
                            try dbgOut(stack[sp - 1]);
                            stack[sp - 1] = Value.fromNum(0.0);
                        },
                        .rng_seed => {
                            rngSeed(@as(u64, @bitCast(stack[sp - 1].num)));
                            stack[sp - 1] = Value.fromNum(0.0);
                        },
                        .str_len => stack[sp - 1] = Value.fromNum(try strLen(stack[sp - 1])),
                        .str_num => stack[sp - 1] = Value.fromNum(try strNum(stack[sp - 1])),
                        .hsh_fnv => stack[sp - 1] = Value.fromNum(try hshFnv(stack[sp - 1])),
                        .nos_per => stack[sp - 1] = Value.fromNum(nosPer(stack[sp - 1].num)),
                        else => {
                            const arg0 = stack[sp - 1].num;
                            const res = switch (builtin_id) {
                                .sin => @sin(arg0),
                                .cos => @cos(arg0),
                                .tan => @tan(arg0),
                                .asin => math.asin(arg0),
                                .acos => math.acos(arg0),
                                .atan => math.atan(arg0),
                                .sqrt => @sqrt(arg0),
                                .abs => @abs(arg0),
                                .floor => @floor(arg0),
                                .ceil => @ceil(arg0),
                                .round => @round(arg0),
                                .log => @log(arg0),
                                .exp => @exp(arg0),
                                else => arg0,
                            };
                            stack[sp - 1] = Value.fromNum(res);
                        },
                    }
                } else if (arity == 2) {
                    const arg1 = stack[sp - 1].num;
                    const arg0 = stack[sp - 2].num;
                    sp -= 1;
                    const res = switch (builtin_id) {
                        .atan2 => math.atan2(arg0, arg1),
                        .min => @min(arg0, arg1),
                        .max => @max(arg0, arg1),
                        .pow => math.pow(f64, arg0, arg1),
                        .rng_range => arg0 + (arg1 - arg0) * rngUnit(),
                        else => 0.0,
                    };
                    if (builtin_id == .str_find) {
                        stack[sp - 1] = Value.fromNum(try strFind(stack[sp - 1], stack[sp]));
                    } else if (builtin_id == .nos_per2) {
                        stack[sp - 1] = Value.fromNum(nosPer2(arg0, arg1));
                    } else {
                        stack[sp - 1] = Value.fromNum(res);
                    }
                } else if (arity == 3) {
                    const arg2 = stack[sp - 1].num;
                    const arg1 = stack[sp - 2].num;
                    const arg0 = stack[sp - 3].num;
                    sp -= 2;
                    const res = switch (builtin_id) {
                        .clamp => math.clamp(arg0, arg1, arg2),
                        .lerp => math.lerp(arg0, arg1, arg2),
                        else => 0.0,
                    };
                    if (builtin_id == .str_sub) {
                        // stack[sp-1] is now the first arg (s); arg1/arg2 were nums.
                        stack[sp - 1] = try strSub(stack[sp - 1], arg1, arg2);
                    } else {
                        stack[sp - 1] = Value.fromNum(res);
                    }
                }
            },

            .call => {
                if (csp >= max_calls) return EvalError.CallStackOverflow;
                const target_ip: usize = @intCast(@as(u32, @truncate(@as(u64, @bitCast(op.arg)))));
                const frame_shift: usize = @intCast(@as(u32, @truncate(@as(u64, @bitCast(op.arg)) >> 32)) / 24);
                if (fp + frame_shift >= max_locals) return EvalError.StackOverflow;
                call_stack[csp] = .{ .ret_ip = ip, .prev_fp = fp };
                csp += 1;
                fp += frame_shift;
                ip = target_ip;
            },

            .ret => {
                if (csp > 0) {
                    csp -= 1;
                    ip = call_stack[csp].ret_ip;
                    fp = call_stack[csp].prev_fp;
                } else {
                    break;
                }
            },

            .loop_step => {
                const packed_u: u64 = @bitCast(op.arg);
                const vslot: usize = @intCast(@as(u16, @truncate(packed_u)));
                const limit_slot: usize = @intCast(@as(u16, @truncate(packed_u >> 16)));
                const target_ip: usize = @intCast(@as(u32, @truncate(packed_u >> 32)));

                const new_val = locals[fp + vslot].num + 1.0;
                locals[fp + vslot].num = new_val;
                if (new_val < locals[fp + limit_slot].num) {
                    ip = target_ip;
                }
            },

            .add_local => {
                const packed_u: u64 = @bitCast(op.arg);
                const dest_slot: usize = @intCast(@as(u16, @truncate(packed_u)));
                const src_slot: usize = @intCast(@as(u16, @truncate(packed_u >> 16)));
                locals[fp + dest_slot].num += locals[fp + src_slot].num;
            },
            .inc_local => {
                const dest_slot: usize = @intCast(op.arg);
                locals[fp + dest_slot].num += 1.0;
            },
            .dec_local => {
                const dest_slot: usize = @intCast(op.arg);
                locals[fp + dest_slot].num -= 1.0;
            },

            .table_jmp => {
                if (sp < 1) return EvalError.StackUnderflow;
                const val_v = stack[sp - 1];
                sp -= 1;
                if (val_v.val_type != .num) return EvalError.InvalidType;
                const min_val: i32 = @bitCast(@as(u32, @truncate(@as(u64, @bitCast(op.arg)))));
                const count: u32 = @truncate(@as(u64, @bitCast(op.arg)) >> 32);
                const val_f = val_v.num;
                // Mirror the asm path (cvttsd2si saturates to INT64_MIN):
                // non-representable values fall through to the default arm.
                const val_i: i64 = if (math.isNan(val_f) or val_f >= 9223372036854775808.0 or val_f <= -9223372036854775808.0)
                    std.math.minInt(i64)
                else
                    @intFromFloat(val_f);
                if (val_f == @as(f64, @floatFromInt(val_i)) and val_i >= min_val and val_i < @as(i64, min_val) + @as(i64, count)) {
                    const idx: usize = @intCast(val_i - min_val);
                    ip = @intCast(ops[ip + 1 + idx].arg);
                    continue;
                } else {
                    ip = @intCast(ops[ip + 1 + count].arg);
                    continue;
                }
            },

            .halt => {
                break;
            },
        }
    }

    if (sp > 0) {
        return stack[sp - 1];
    }
    return Value.fromNum(0.0);
}

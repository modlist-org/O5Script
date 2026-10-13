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

export fn o5s_asm_builtin_call(packed_arg: i64, stack_top: [*]Value) callconv(.{ .x86_64_sysv = .{} }) usize {
    const builtin_id: Builtin = @enumFromInt(@as(u8, @truncate(@as(u64, @bitCast(packed_arg)))));
    const arity: u8 = @truncate(@as(u64, @bitCast(packed_arg)) >> 8);
    if (arity == 1) {
        const ptr = stack_top - 1;
        const arg0 = ptr[0].num;
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
        return 0;
    } else if (arity == 2) {
        const ptr1 = stack_top - 1;
        const ptr0 = stack_top - 2;
        const arg1 = ptr1[0].num;
        const arg0 = ptr0[0].num;
        const res = switch (builtin_id) {
            .atan2 => math.atan2(arg0, arg1),
            .min => @min(arg0, arg1),
            .max => @max(arg0, arg1),
            .pow => math.pow(f64, arg0, arg1),
            else => 0.0,
        };
        ptr0[0] = Value.fromNum(res);
        return 24;
    } else if (arity == 3) {
        const ptr2 = stack_top - 1;
        const ptr1 = stack_top - 2;
        const ptr0 = stack_top - 3;
        const arg2 = ptr2[0].num;
        const arg1 = ptr1[0].num;
        const arg0 = ptr0[0].num;
        const res = switch (builtin_id) {
            .clamp => math.clamp(arg0, arg1, arg2),
            .lerp => math.lerp(arg0, arg1, arg2),
            else => 0.0,
        };
        ptr0[0] = Value.fromNum(res);
        return 48;
    }
    return 0;
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
        }
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
                if (top.num < 0.0 or top.num >= bound) {
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
                const idx: usize = @intFromFloat(idx_val.num);
                const base: usize = fp + @as(usize, @intCast(op.arg));
                const slot = base + idx;
                if (slot >= max_locals) return EvalError.OutOfBounds;
                stack[sp] = locals[slot];
                sp += 1;
            },

            .store_local_elem => {
                if (sp < 2) return EvalError.StackUnderflow;
                const val = stack[sp - 1];
                const idx_val = stack[sp - 2];
                sp -= 2;
                if (idx_val.val_type != .num) return EvalError.InvalidType;
                const idx: usize = @intFromFloat(idx_val.num);
                const base: usize = fp + @as(usize, @intCast(op.arg));
                const slot = base + idx;
                if (slot >= max_locals) return EvalError.OutOfBounds;
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
                const a: i64 = @intFromFloat(l.num);
                const b: i64 = @intFromFloat(r.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a & b));
            },

            .bit_or => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = @intFromFloat(l.num);
                const b: i64 = @intFromFloat(r.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a | b));
            },

            .bit_xor => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = @intFromFloat(l.num);
                const b: i64 = @intFromFloat(r.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a ^ b));
            },

            .bit_not => {
                if (sp < 1) return EvalError.StackUnderflow;
                const top = stack[sp - 1];
                const a: i64 = @intFromFloat(top.num);
                stack[sp - 1] = Value.fromNum(@floatFromInt(~a));
            },

            .shl => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = @intFromFloat(l.num);
                const shift: u6 = @truncate(@as(u64, @bitCast(@as(i64, @intFromFloat(r.num)))) & 63);
                stack[sp - 1] = Value.fromNum(@floatFromInt(a << shift));
            },

            .shr => {
                if (sp < 2) return EvalError.StackUnderflow;
                const r = stack[sp - 1];
                const l = stack[sp - 2];
                sp -= 1;
                const a: i64 = @intFromFloat(l.num);
                const shift: u6 = @truncate(@as(u64, @bitCast(@as(i64, @intFromFloat(r.num)))) & 63);
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

                if (arity == 1) {
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
                } else if (arity == 2) {
                    const arg1 = stack[sp - 1].num;
                    const arg0 = stack[sp - 2].num;
                    sp -= 1;
                    const res = switch (builtin_id) {
                        .atan2 => math.atan2(arg0, arg1),
                        .min => @min(arg0, arg1),
                        .max => @max(arg0, arg1),
                        .pow => math.pow(f64, arg0, arg1),
                        else => 0.0,
                    };
                    stack[sp - 1] = Value.fromNum(res);
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
                    stack[sp - 1] = Value.fromNum(res);
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

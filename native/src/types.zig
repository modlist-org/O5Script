const std = @import("std");

pub const ValueType = enum(u8) {
    num = 0,
    str = 1,
};

pub const Value = extern struct {
    num: f64 = 0.0,
    str_ptr: ?[*]const u8 = null,
    str_len: u32 = 0,
    val_type: ValueType = .num,
    _pad: [3]u8 = [_]u8{ 0, 0, 0 },

    pub fn fromNum(n: f64) Value {
        return .{
            .num = n,
            .str_ptr = null,
            .str_len = 0,
            .val_type = .num,
        };
    }

    pub fn fromStr(s: []const u8) Value {
        return .{
            .num = 0.0,
            .str_ptr = s.ptr,
            .str_len = @intCast(s.len),
            .val_type = .str,
        };
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self.val_type) {
            .num => self.num != 0.0 and !std.math.isNan(self.num),
            .str => self.str_len > 0,
        };
    }

    pub fn toSlice(self: Value) []const u8 {
        if (self.val_type == .str and self.str_ptr != null and self.str_len > 0) {
            return self.str_ptr.?[0..self.str_len];
        }
        return "";
    }
};

pub const O5Result = extern struct {
    num: f64 = 0.0,
    str_ptr: ?[*]const u8 = null,
    str_len: u32 = 0,
    val_type: u8 = 0,
    _pad: [3]u8 = [_]u8{ 0, 0, 0 },
};

pub const OpCode = enum(u8) {
    nop = 0,
    push_num,
    push_0,
    push_1,
    push_str,
    pop,
    dup,

    load_local,
    store_local,
    load_state,
    store_state,
    load_host,

    add,
    sub,
    mul,
    div,
    mod,
    neg,

    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    shl,
    shr,

    eq,
    ne,
    lt,
    le,
    gt,
    ge,

    lnot,

    jmp,
    jmp_if_zero,
    jmp_if_nonzero,

    call_builtin,
    call,
    ret,
    halt,
};

pub const Op = extern struct {
    code: OpCode,
    _pad: [7]u8 = [_]u8{ 0, 0, 0, 0, 0, 0, 0 },
    arg: i64 = 0,
};

pub const Builtin = enum(u8) {
    sin = 0,
    cos = 1,
    tan = 2,
    asin = 3,
    acos = 4,
    atan = 5,
    atan2 = 6,
    sqrt = 7,
    abs = 8,
    floor = 9,
    ceil = 10,
    round = 11,
    min = 12,
    max = 13,
    clamp = 14,
    lerp = 15,
    pow = 16,
    log = 17,
    exp = 18,
};

pub const TagDef = struct {
    name: []const u8,
    entry_ip: usize,
};

pub const FuncDef = struct {
    name: []const u8,
    entry_ip: usize,
    param_count: usize,
};

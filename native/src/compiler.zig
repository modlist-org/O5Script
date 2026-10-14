const std = @import("std");
const types = @import("types.zig");
const vm = @import("vm.zig");

pub const Op = types.Op;
pub const OpCode = types.OpCode;
pub const Builtin = types.Builtin;
pub const Value = types.Value;
pub const TagDef = types.TagDef;
pub const FuncDef = types.FuncDef;
pub const Prog = vm.Prog;

const max_ops = 8192;
const max_locals = 128;
const max_tags = 64;
const max_funcs = 64;
const max_host_tags = 128;
const max_loops = 16;
const max_breaks = 16;

pub const DataType = enum {
    unknown,
    num,
    str,
};

pub const CompileError = error{
    OutOfOps,
    OutOfMemory,
    StringPoolOverflow,
    StringLiteralTooLong,
    TooManyHostTags,
    TooManyLocals,
    TooManyStates,
    SyntaxError,
    IndexOutOfBounds,
    ExpectedArrayDimension,
    ExpectedClosingBracket,
    TooManyDimensions,
    DimensionMismatch,
    ArraySizeMismatch,
    TooManyFuncs,
    TooManyCalls,
    UndefinedFunction,
    MissingReturn,
    ExpectedFunctionBody,
    ArgumentCountMismatch,

    // Static compile-time safety checks
    UndefinedVariable,
    CannotAssignToConstant,
    BreakOutsideLoop,
    ContinueOutsideLoop,
    TypeMismatch,
    UnknownType,
    InvalidJumpTarget,
    StackUnderflow,
    StackOverflow,
    StackMismatch,
    LifetimeError,
    DuplicateVariable,
};

pub const TokenType = enum {
    eof,
    number,
    string,
    ident,
    host_tag,
    kw_let,
    kw_sta,
    kw_con,
    kw_if,
    kw_lf,
    kw_el,
    kw_lop,
    kw_out,
    kw_skp,
    kw_fun,
    kw_ret,
    kw_tag,
    kw_tru,
    kw_fls,
    kw_stu,
    kw_jmp,
    kw_go,
    label,

    plus,
    minus,
    star,
    slash,
    percent,

    amp,
    pipe,
    caret,
    tilde,
    less_less,
    greater_greater,

    and_and,
    or_or,
    bang,

    equal,
    plus_equal,
    minus_equal,
    star_equal,
    slash_equal,

    equal_equal,
    bang_equal,
    less,
    less_equal,
    greater,
    greater_equal,

    question,
    colon,
    arrow,
    at,
    dot,
    dot_dot,
    dot_dot_equal,

    l_paren,
    r_paren,
    l_brace,
    r_brace,
    l_bracket,
    r_bracket,
    comma,
    semicolon,
};

pub const Token = struct {
    tag: TokenType,
    text: []const u8,
    num_val: f64 = 0.0,
};

pub const Lexer = struct {
    src: []const u8,
    pos: usize = 0,

    pub fn init(src: []const u8) Lexer {
        return .{ .src = src, .pos = 0 };
    }

    fn peekChar(self: *Lexer) ?u8 {
        if (self.pos >= self.src.len) return null;
        return self.src[self.pos];
    }

    fn nextChar(self: *Lexer) ?u8 {
        if (self.pos >= self.src.len) return null;
        const c = self.src[self.pos];
        self.pos += 1;
        return c;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.pos += 1;
                continue;
            }
            if (c == '/' and self.pos + 1 < self.src.len) {
                const next = self.src[self.pos + 1];
                if (next == '/') {
                    self.pos += 2;
                    while (self.pos < self.src.len and self.src[self.pos] != '\n') {
                        self.pos += 1;
                    }
                    continue;
                } else if (next == '*') {
                    self.pos += 2;
                    while (self.pos + 1 < self.src.len) {
                        if (self.src[self.pos] == '*' and self.src[self.pos + 1] == '/') {
                            self.pos += 2;
                            break;
                        }
                        self.pos += 1;
                    }
                    continue;
                }
            }
            break;
        }
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.src.len) {
            return .{ .tag = .eof, .text = "" };
        }

        const start = self.pos;
        const c = self.nextChar().?;

        if (c == '#') {
            while (self.peekChar()) |ch| {
                if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                    _ = self.nextChar();
                } else break;
            }
            return .{ .tag = .host_tag, .text = self.src[start + 1 .. self.pos] };
        }

        if (c == '$') {
            while (self.peekChar()) |ch| {
                if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                    _ = self.nextChar();
                } else break;
            }
            return .{ .tag = .label, .text = self.src[start + 1 .. self.pos] };
        }

        if (std.ascii.isDigit(c) or (c == '.' and self.peekChar() != null and std.ascii.isDigit(self.peekChar().?))) {
            var has_dot = (c == '.');
            while (self.peekChar()) |ch| {
                if (ch == '.' and !has_dot) {
                    if (self.pos + 1 < self.src.len and self.src[self.pos + 1] == '.') {
                        break;
                    }
                    has_dot = true;
                    _ = self.nextChar();
                } else if (std.ascii.isDigit(ch)) {
                    _ = self.nextChar();
                } else break;
            }
            const num_str = self.src[start..self.pos];
            const val = std.fmt.parseFloat(f64, num_str) catch 0.0;
            return .{ .tag = .number, .text = num_str, .num_val = val };
        }

        if (std.ascii.isAlphabetic(c) or c == '_') {
            while (self.peekChar()) |ch| {
                if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                    _ = self.nextChar();
                } else break;
            }
            const ident = self.src[start..self.pos];
            const kw = if (std.mem.eql(u8, ident, "let")) TokenType.kw_let
                else if (std.mem.eql(u8, ident, "sta")) TokenType.kw_sta
                else if (std.mem.eql(u8, ident, "con")) TokenType.kw_con
                else if (std.mem.eql(u8, ident, "if")) TokenType.kw_if
                else if (std.mem.eql(u8, ident, "lf")) TokenType.kw_lf
                else if (std.mem.eql(u8, ident, "el")) TokenType.kw_el
                else if (std.mem.eql(u8, ident, "lop")) TokenType.kw_lop
                else if (std.mem.eql(u8, ident, "out")) TokenType.kw_out
                else if (std.mem.eql(u8, ident, "skp")) TokenType.kw_skp
                else if (std.mem.eql(u8, ident, "fun")) TokenType.kw_fun
                else if (std.mem.eql(u8, ident, "ret")) TokenType.kw_ret
                else if (std.mem.eql(u8, ident, "tag")) TokenType.kw_tag
                else if (std.mem.eql(u8, ident, "tru")) TokenType.kw_tru
                else if (std.mem.eql(u8, ident, "fls")) TokenType.kw_fls
                else if (std.mem.eql(u8, ident, "stu")) TokenType.kw_stu
                else if (std.mem.eql(u8, ident, "jmp")) TokenType.kw_jmp
                else if (std.mem.eql(u8, ident, "go")) TokenType.kw_go
                else TokenType.ident;
            return .{ .tag = kw, .text = ident };
        }

        if (c == '"') {
            while (self.peekChar()) |ch| {
                if (ch == '"') {
                    _ = self.nextChar();
                    break;
                }
                if (ch == '\\' and self.pos + 1 < self.src.len) {
                    _ = self.nextChar();
                }
                _ = self.nextChar();
            }
            return .{ .tag = .string, .text = self.src[start..self.pos] };
        }

        switch (c) {
            '+' => {
                if (self.matchChar('=')) return .{ .tag = .plus_equal, .text = "+=" };
                return .{ .tag = .plus, .text = "+" };
            },
            '-' => {
                if (self.matchChar('=')) return .{ .tag = .minus_equal, .text = "-=" };
                return .{ .tag = .minus, .text = "-" };
            },
            '*' => {
                if (self.matchChar('=')) return .{ .tag = .star_equal, .text = "*=" };
                return .{ .tag = .star, .text = "*" };
            },
            '/' => {
                if (self.matchChar('=')) return .{ .tag = .slash_equal, .text = "/=" };
                return .{ .tag = .slash, .text = "/" };
            },
            '%' => return .{ .tag = .percent, .text = "%" },
            '&' => {
                if (self.matchChar('&')) return .{ .tag = .and_and, .text = "&&" };
                return .{ .tag = .amp, .text = "&" };
            },
            '|' => {
                if (self.matchChar('|')) return .{ .tag = .or_or, .text = "||" };
                return .{ .tag = .pipe, .text = "|" };
            },
            '^' => return .{ .tag = .caret, .text = "^" },
            '~' => return .{ .tag = .tilde, .text = "~" },
            '!' => {
                if (self.matchChar('=')) return .{ .tag = .bang_equal, .text = "!=" };
                return .{ .tag = .bang, .text = "!" };
            },
            '=' => {
                if (self.matchChar('=')) return .{ .tag = .equal_equal, .text = "==" };
                if (self.matchChar('>')) return .{ .tag = .arrow, .text = "=>" };
                return .{ .tag = .equal, .text = "=" };
            },
            '<' => {
                if (self.matchChar('<')) return .{ .tag = .less_less, .text = "<<" };
                if (self.matchChar('=')) return .{ .tag = .less_equal, .text = "<=" };
                return .{ .tag = .less, .text = "<" };
            },
            '>' => {
                if (self.matchChar('>')) return .{ .tag = .greater_greater, .text = ">>" };
                if (self.matchChar('=')) return .{ .tag = .greater_equal, .text = ">=" };
                return .{ .tag = .greater, .text = ">" };
            },
            '.' => {
                if (self.matchChar('.')) {
                    if (self.matchChar('=')) return .{ .tag = .dot_dot_equal, .text = "..=" };
                    return .{ .tag = .dot_dot, .text = ".." };
                }
                return .{ .tag = .dot, .text = "." };
            },
            '@' => return .{ .tag = .at, .text = "@" },
            '?' => return .{ .tag = .question, .text = "?" },
            ':' => return .{ .tag = .colon, .text = ":" },
            '(' => return .{ .tag = .l_paren, .text = "(" },
            ')' => return .{ .tag = .r_paren, .text = ")" },
            '{' => return .{ .tag = .l_brace, .text = "{" },
            '}' => return .{ .tag = .r_brace, .text = "}" },
            '[' => return .{ .tag = .l_bracket, .text = "[" },
            ']' => return .{ .tag = .r_bracket, .text = "]" },
            ',' => return .{ .tag = .comma, .text = "," },
            ';' => return .{ .tag = .semicolon, .text = ";" },
            else => return .{ .tag = .eof, .text = "" },
        }
    }

    fn matchChar(self: *Lexer, expected: u8) bool {
        if (self.pos < self.src.len and self.src[self.pos] == expected) {
            self.pos += 1;
            return true;
        }
        return false;
    }
};

const LoopContext = struct {
    continue_ip: usize = 0,
    breaks: [max_breaks]usize = undefined,
    break_count: usize = 0,
    continues: [max_breaks]usize = undefined,
    continue_count: usize = 0,
};


pub const Compiler = struct {
    lexer: Lexer,
    cur: Token,
    peek: Token,

    ops: [max_ops]Op = undefined,
    op_count: usize = 0,

    string_bytes: [65536]u8 = undefined,
    string_len: usize = 0,

    locals: [max_locals][]const u8 = undefined,
    local_types: [max_locals]DataType = @splat(.unknown),
    local_consts: [max_locals]bool = @splat(false),
    local_count: usize = 0,

    states: [max_locals][]const u8 = undefined,
    state_types: [max_locals]DataType = @splat(.unknown),
    state_funcs: [max_locals]?[]const u8 = @splat(null),
    state_inits: [max_locals]Value = undefined,
    state_count: usize = 0,

    host_tags: [max_host_tags][]const u8 = undefined,
    host_tag_count: usize = 0,

    tags: [max_tags]TagDef = undefined,
    tag_count: usize = 0,

    funcs: [max_funcs]FuncDef = undefined,
    func_ret_types: [max_funcs]DataType = @splat(.unknown),
    func_ret_structs: [max_funcs]?[]const u8 = @splat(null),
    func_param_annots: [max_funcs][8]?TypeAnnotation = @splat(@splat(null)),
    func_count: usize = 0,

    modules: [16]ModuleBinding = undefined,
    module_count: usize = 0,

    loops: [max_loops]LoopContext = undefined,
    loop_depth: usize = 0,
    labels: [64]Label = undefined,
    label_count: usize = 0,
    label_fixups: [64]LabelFixup = undefined,
    label_fixup_count: usize = 0,
    jmp_contexts: [8]JmpContext = undefined,
    jmp_depth: usize = 0,
    scope_depth: usize = 0,
    local_scope_depth: [max_locals]usize = @splat(0),
    arrays: [64]ArrayVar = undefined,
    array_count: usize = 0,
    struct_defs: [16]StructDef = undefined,
    struct_def_count: usize = 0,
    struct_vars: [32]StructVar = undefined,
    struct_var_count: usize = 0,
    method_name_buf: [2048]u8 = undefined,
    method_name_len: usize = 0,

    call_fixups: [64]CallFixup = undefined,
    call_fixup_count: usize = 0,
    current_func_had_ret: bool = false,
    current_func_ret_type: DataType = .unknown,
    current_func_ret_is_slf: bool = false,
    current_func_ret_struct: ?[]const u8 = null,
    current_func_slf_slot: usize = 0,
    current_func_name: ?[]const u8 = null,
    last_expr_type: DataType = .unknown,
    last_stmt_had_value: bool = false,
    copy_depth: usize = 0,
    expr_depth: usize = 0,
    last_chain_recv: ?SlfRecv = null,

    allocator: std.mem.Allocator,

    pub const Label = struct {
        name: []const u8,
        ip: usize,
    };

    pub const LabelFixup = struct {
        name: []const u8,
        op_idx: usize,
    };

    pub const JmpContext = struct {
        breaks: [64]usize = undefined,
        break_count: usize = 0,
    };

    pub const CallFixup = struct {
        op_idx: usize,
        func_name: []const u8,
        frame_offset: usize,
        arg_count: usize,
    };

    pub const ArrayInfo = struct {
        dims: [4]u32 = [_]u32{ 0, 0, 0, 0 },
        dim_count: u8 = 0,
        total_elements: u32 = 0,
        elem_type: DataType = .unknown,
        is_state: bool = false,
        base_slot: usize = 0,

        pub fn stride(self: ArrayInfo, dim_idx: usize) u32 {
            var s: u32 = 1;
            var i = self.dim_count;
            while (i > dim_idx + 1) {
                i -= 1;
                s *= self.dims[i];
            }
            return s;
        }
    };

    pub const StructField = struct {
        name: []const u8,
        offset: usize,
        data_type: DataType,
        struct_name: ?[]const u8 = null,
        slot_count: usize = 1,
    };

    pub const StructDef = struct {
        name: []const u8,
        fields: [16]StructField = undefined,
        field_count: usize = 0,
        total_slots: usize = 0,
        methods: [16]StructMethod = undefined,
        method_count: usize = 0,

        pub const StructMethod = struct {
            name: []const u8,
            func_name: []const u8,
            uses_slf: bool,
        };

        pub fn addField(self: *StructDef, name: []const u8, dt: DataType, child_struct: ?[]const u8, slot_cnt: usize) CompileError!void {
            if (self.field_count >= 16) return error.TooManyLocals;
            const off = self.total_slots;
            self.fields[self.field_count] = .{
                .name = name,
                .offset = off,
                .data_type = dt,
                .struct_name = child_struct,
                .slot_count = slot_cnt,
            };
            self.field_count += 1;
            self.total_slots += slot_cnt;
        }

        pub fn addMethod(self: *StructDef, name: []const u8, func_name: []const u8, uses_slf: bool) CompileError!void {
            if (self.method_count >= 16) return error.TooManyFuncs;
            self.methods[self.method_count] = .{
                .name = name,
                .func_name = func_name,
                .uses_slf = uses_slf,
            };
            self.method_count += 1;
        }

        pub fn findField(self: StructDef, name: []const u8) ?StructField {
            for (self.fields[0..self.field_count]) |f| {
                if (std.mem.eql(u8, f.name, name)) return f;
            }
            return null;
        }

        pub fn findMethod(self: StructDef, name: []const u8) ?StructMethod {
            for (self.methods[0..self.method_count]) |m| {
                if (std.mem.eql(u8, m.name, name)) return m;
            }
            return null;
        }
    };

    pub const StructVar = struct {
        name: []const u8,
        struct_name: []const u8,
        base_slot: usize,
        owned_base_slot: ?usize = null,
        is_state: bool = false,
        scope_depth: usize = 0,
        is_reference: bool = false,
        is_const: bool = false,
        is_param_ref: bool = false,
    };

    // Receiver descriptor for `: slf` method chaining (`p.a().b()`).
    // `slf` always aliases the original receiver object, so a chained link
    // re-emits the receiver push from this static description instead of
    // reusing the runtime value on the stack.
    pub const SlfRecv = struct {
        struct_name: []const u8,
        svar_base: usize,
        total_off: usize,
        is_param_ref: bool,
        is_state: bool,
        eff_base: usize = 0,
        eff_valid: bool = false,
        link_off: usize = 0,
    };

    pub const TypeAnnotation = struct {
        data_type: DataType = .unknown,
        array: ?ArrayInfo = null,
        struct_name: ?[]const u8 = null,
        is_copy: bool = false,
        is_const: bool = false,
    };

    pub const ArrayVar = struct {
        name: []const u8,
        info: ArrayInfo,
    };

    pub const ModuleKind = enum {
        std,
        math,
        dbg,
        fmt,
        rng,
        str,
        hsh,
        nos,
    };

    pub const ModuleBinding = struct {
        name: []const u8,
        kind: ModuleKind,
    };

    pub fn init(src: []const u8, allocator: std.mem.Allocator) Compiler {
        var c = Compiler{
            .lexer = Lexer.init(src),
            .cur = undefined,
            .peek = undefined,
            .allocator = allocator,
            .module_count = 0,
            .array_count = 0,
            .struct_def_count = 0,
            .struct_var_count = 0,
            .local_count = 0,
            .state_count = 0,
            .host_tag_count = 0,
            .tag_count = 0,
            .func_count = 0,
            .loop_depth = 0,
            .label_count = 0,
            .label_fixup_count = 0,
            .jmp_depth = 0,
            .scope_depth = 0,
            .call_fixup_count = 0,
            .current_func_had_ret = false,
            .current_func_ret_type = .unknown,
            .current_func_ret_is_slf = false,
            .current_func_ret_struct = null,
            .current_func_slf_slot = 0,
            .last_expr_type = .unknown,
            .last_stmt_had_value = false,
            .copy_depth = 0,
            .expr_depth = 0,
            .last_chain_recv = null,
        };
        c.cur = c.lexer.nextToken();
        c.peek = c.lexer.nextToken();
        return c;
    }

    fn advance(self: *Compiler) void {
        self.cur = self.peek;
        self.peek = self.lexer.nextToken();
    }

    fn match(self: *Compiler, tag: TokenType) bool {
        if (self.cur.tag == tag) {
            self.advance();
            return true;
        }
        return false;
    }

    fn emit(self: *Compiler, code: OpCode, arg: i64) CompileError!usize {
        if (self.op_count >= max_ops) return error.OutOfOps;
        const idx = self.op_count;
        self.ops[idx] = .{ .code = code, .arg = arg };
        self.op_count += 1;
        return idx;
    }

    fn patchJump(self: *Compiler, jump_idx: usize, target_ip: usize) void {
        self.ops[jump_idx].arg = @intCast(target_ip);
    }

    fn addString(self: *Compiler, text: []const u8) CompileError!i64 {
        if (text.len > types.max_str_len) return error.StringLiteralTooLong;
        const offset = self.string_len;
        const len = text.len;
        if (offset + len > self.string_bytes.len) return error.StringPoolOverflow;
        @memcpy(self.string_bytes[offset .. offset + len], text);
        self.string_len += len;
        const packed_val: u64 = @as(u64, @intCast(offset)) | (@as(u64, @intCast(len)) << 32);
        return @bitCast(packed_val);
    }

    fn addStringUnescaped(self: *Compiler, text: []const u8) CompileError!i64 {
        const offset = self.string_len;
        var write_pos = offset;
        var i: usize = 0;
        while (i < text.len) {
            if (write_pos - offset >= types.max_str_len) return error.StringLiteralTooLong;
            if (write_pos >= self.string_bytes.len) return error.StringPoolOverflow;
            if (text[i] == '{' and i + 1 < text.len and text[i + 1] == '{') {
                self.string_bytes[write_pos] = '{';
                write_pos += 1;
                i += 2;
            } else if (text[i] == '}' and i + 1 < text.len and text[i + 1] == '}') {
                self.string_bytes[write_pos] = '}';
                write_pos += 1;
                i += 2;
            } else if (text[i] == '\\' and i + 1 < text.len) {
                const esc = text[i + 1];
                const ch: u8 = switch (esc) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '"' => '"',
                    else => esc,
                };
                self.string_bytes[write_pos] = ch;
                write_pos += 1;
                i += 2;
            } else {
                self.string_bytes[write_pos] = text[i];
                write_pos += 1;
                i += 1;
            }
        }
        const len = write_pos - offset;
        self.string_len = write_pos;
        const packed_val: u64 = @as(u64, @intCast(offset)) | (@as(u64, @intCast(len)) << 32);
        return @bitCast(packed_val);
    }

    fn getOrAddHostTag(self: *Compiler, name: []const u8) CompileError!usize {
        for (self.host_tags[0..self.host_tag_count], 0..) |tag_name, i| {
            if (std.mem.eql(u8, tag_name, name)) return i;
        }
        if (self.host_tag_count >= max_host_tags) return error.TooManyHostTags;
        const idx = self.host_tag_count;
        self.host_tags[idx] = name;
        self.host_tag_count += 1;
        return idx;
    }

    fn findLocal(self: *Compiler, name: []const u8) ?usize {
        var i = self.local_count;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals[i], name)) return i;
        }
        return null;
    }

    fn addLocal(self: *Compiler, name: []const u8) CompileError!usize {
        if (self.local_count >= max_locals) return error.TooManyLocals;
        const idx = self.local_count;
        self.locals[idx] = name;
        self.local_types[idx] = .unknown;
        self.local_consts[idx] = false;
        self.local_scope_depth[idx] = self.scope_depth;
        self.local_count += 1;
        return idx;
    }

    fn findState(self: *Compiler, name: []const u8) ?usize {
        var i = self.state_count;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.states[i], name)) {
                if (self.current_func_name) |cfn| {
                    if (self.state_funcs[i]) |sfn| {
                        if (std.mem.eql(u8, sfn, cfn)) return i;
                    }
                } else {
                    if (self.state_funcs[i] == null) return i;
                }
            }
        }
        if (self.current_func_name != null) {
            var j = self.state_count;
            while (j > 0) {
                j -= 1;
                if (std.mem.eql(u8, self.states[j], name) and self.state_funcs[j] == null) {
                    return j;
                }
            }
        }
        return null;
    }

    fn addState(self: *Compiler, name: []const u8) CompileError!usize {
        if (self.state_count >= max_locals) return error.TooManyStates;
        const idx = self.state_count;
        self.states[idx] = name;
        self.state_types[idx] = .unknown;
        self.state_funcs[idx] = self.current_func_name;
        self.state_inits[idx] = Value.fromNum(0.0);
        self.state_count += 1;
        return idx;
    }

    fn findArray(self: *Compiler, name: []const u8) ?ArrayInfo {
        var i = self.array_count;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.arrays[i].name, name)) {
                return self.arrays[i].info;
            }
        }
        return null;
    }

    fn addArray(self: *Compiler, name: []const u8, info: ArrayInfo) CompileError!void {
        if (self.array_count >= 64) return error.TooManyLocals;
        self.arrays[self.array_count] = .{ .name = name, .info = info };
        self.array_count += 1;
    }

    fn findStructDef(self: *Compiler, name: []const u8) ?StructDef {
        for (self.struct_defs[0..self.struct_def_count]) |d| {
            if (std.mem.eql(u8, d.name, name)) return d;
        }
        return null;
    }

    fn findStructDefPtr(self: *Compiler, name: []const u8) ?*StructDef {
        for (self.struct_defs[0..self.struct_def_count]) |*d| {
            if (std.mem.eql(u8, d.name, name)) return d;
        }
        return null;
    }

    fn addStructDef(self: *Compiler, def: StructDef) CompileError!void {
        if (self.struct_def_count >= 16) return error.TooManyLocals;
        self.struct_defs[self.struct_def_count] = def;
        self.struct_def_count += 1;
    }

    fn findStructVar(self: *Compiler, name: []const u8) ?StructVar {
        var i = self.struct_var_count;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.struct_vars[i].name, name)) return self.struct_vars[i];
        }
        return null;
    }

    fn findStructVarPtr(self: *Compiler, name: []const u8) ?*StructVar {
        var i = self.struct_var_count;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.struct_vars[i].name, name)) return &self.struct_vars[i];
        }
        return null;
    }

    fn addStructVar(self: *Compiler, name: []const u8, struct_name: []const u8, base_slot: usize, is_state: bool, is_ref: bool) CompileError!void {
        if (self.struct_var_count >= 32) return error.TooManyLocals;
        self.struct_vars[self.struct_var_count] = .{
            .name = name,
            .struct_name = struct_name,
            .base_slot = base_slot,
            .owned_base_slot = if (is_ref) null else base_slot,
            .is_state = is_state,
            .scope_depth = self.scope_depth,
            .is_reference = is_ref,
            .is_const = false,
            .is_param_ref = false,
        };
        self.struct_var_count += 1;
    }

    fn findFunc(self: *Compiler, name: []const u8) ?usize {
        for (self.funcs[0..self.func_count], 0..) |f, i| {
            if (std.mem.eql(u8, f.name, name)) return i;
        }
        return null;
    }

    fn registerFunc(self: *Compiler, name: []const u8, entry_ip: usize, param_count: usize) CompileError!usize {
        if (self.func_count >= max_funcs) return error.TooManyFuncs;
        const idx = self.func_count;
        self.funcs[idx] = .{
            .name = name,
            .entry_ip = entry_ip,
            .param_count = param_count,
        };
        self.func_ret_types[idx] = self.current_func_ret_type;
        self.func_ret_structs[idx] = self.current_func_ret_struct;
        self.func_count += 1;

        for (self.call_fixups[0..self.call_fixup_count]) |*cf| {
            if (std.mem.eql(u8, cf.func_name, name)) {
                if (cf.arg_count != param_count) return error.ArgumentCountMismatch;
                const packed_arg: i64 = @bitCast((@as(u64, @intCast(cf.frame_offset * 24)) << 32) | @as(u64, @intCast(entry_ip)));
                self.ops[cf.op_idx].arg = packed_arg;
                cf.func_name = "";
            }
        }
        return idx;
    }

    fn emitCall(self: *Compiler, name: []const u8, arg_count: usize) CompileError!void {
        const frame_offset = self.local_count;
        if (self.findFunc(name)) |fidx| {
            const func = self.funcs[fidx];
            if (func.param_count != arg_count) return error.ArgumentCountMismatch;
            const packed_arg: i64 = @bitCast((@as(u64, @intCast(frame_offset * 24)) << 32) | @as(u64, @intCast(func.entry_ip)));
            _ = try self.emit(.call, packed_arg);
            self.last_expr_type = self.func_ret_types[fidx];
        } else {
            if (self.call_fixup_count >= 64) return error.TooManyCalls;
            const op_idx = try self.emit(.call, 0);
            self.call_fixups[self.call_fixup_count] = .{
                .op_idx = op_idx,
                .func_name = name,
                .frame_offset = frame_offset,
                .arg_count = arg_count,
            };
            self.call_fixup_count += 1;
            self.last_expr_type = .unknown;
        }
    }

    fn methodReturnsSlf(self: *Compiler, m: StructDef.StructMethod, sname: []const u8) bool {
        if (self.findFunc(m.func_name)) |fi| {
            if (self.func_ret_structs[fi]) |rs| return std.mem.eql(u8, rs, sname);
        }
        return false;
    }

    // Re-emit the receiver (slf) argument push for a chained `: slf` call.
    // Same codegen as the initial method-call receiver push; `slf` always
    // aliases the original receiver object, so the static description stays valid.
    fn emitRecvPush(self: *Compiler, recv: *SlfRecv) CompileError!void {
        if (recv.is_param_ref) {
            _ = try self.emit(.load_local, @intCast(recv.svar_base));
            const adj: f64 = @floatFromInt(@as(i64, @intCast(recv.total_off)) - @as(i64, @intCast(self.local_count)));
            if (adj != 0.0) {
                _ = try self.emit(.push_num, @bitCast(adj));
                _ = try self.emit(.add, 0);
            }
            recv.eff_valid = false;
        } else {
            var base_slot = recv.svar_base + recv.total_off;
            if (recv.is_state) {
                const sdef = self.findStructDef(recv.struct_name) orelse return error.UnknownType;
                const tmp_base = self.local_count;
                for (0..sdef.total_slots) |si| {
                    _ = try self.addLocal("");
                    _ = try self.emit(.load_state, @intCast(base_slot + si));
                    _ = try self.emit(.store_local, @intCast(tmp_base + si));
                }
                base_slot = tmp_base;
            }
            recv.eff_base = base_slot;
            recv.eff_valid = true;
            recv.link_off = recv.total_off;
            const rel_off: f64 = @floatFromInt(@as(i64, @intCast(base_slot)) - @as(i64, @intCast(self.local_count)));
            _ = try self.emit(.push_num, @bitCast(rel_off));
        }
    }

    // Single-slot field load for a chain ending on a field (`p.a().x`).
    // Mirrors the plain field-load codegen in parsePrimary.
    fn emitRecvField(self: *Compiler, recv: *SlfRecv) CompileError!void {
        if (recv.is_param_ref) {
            _ = try self.emit(.load_local, @intCast(recv.svar_base));
            _ = try self.emit(.load_local_elem, @intCast(recv.total_off));
        } else if (recv.is_state and !recv.eff_valid) {
            _ = try self.emit(.load_state, @intCast(recv.svar_base + recv.total_off));
        } else if (recv.eff_valid) {
            _ = try self.emit(.load_local, @intCast(recv.eff_base + recv.total_off - recv.link_off));
        } else {
            _ = try self.emit(.load_local, @intCast(recv.svar_base + recv.total_off));
        }
    }

    // Parse chained links after an `: slf` method call (`p.a().b()`, `p.a().x`).
    // Called with cur positioned right after the initial call's `)`, with the
    // returned offset on the stack top. Each link pops the previous offset and
    // re-emits the receiver push (`slf` always aliases the original object),
    // keeping the operand stack balanced.
    fn maybeParseSlfChain(self: *Compiler, recv: SlfRecv, m: StructDef.StructMethod) CompileError!void {
        if (self.cur.tag != .dot) return;
        if (!self.methodReturnsSlf(m, recv.struct_name)) return;
        var r = recv;
        var cur_s = recv.struct_name;
        var pending_field = false;
        var pending_dt: DataType = .unknown;
        var slf_on_stack = true;
        while (self.cur.tag == .dot) {
            self.advance();
            if (self.cur.tag != .ident) return error.SyntaxError;
            const fname = self.cur.text;
            self.advance();
            const sdef = self.findStructDef(cur_s) orelse return error.SyntaxError;
            if (sdef.findMethod(fname)) |m2| {
                if (self.cur.tag != .l_paren) return error.SyntaxError;
                pending_field = false;
                if (slf_on_stack) {
                    _ = try self.emit(.pop, 0);
                    slf_on_stack = false;
                }
                var call_arg_count: usize = 0;
                if (m2.uses_slf) {
                    try self.emitRecvPush(&r);
                    call_arg_count += 1;
                }
                _ = self.match(.l_paren);
                while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                    try self.parseExpression();
                    call_arg_count += 1;
                    if (!self.match(.comma)) break;
                }
                if (!self.match(.r_paren)) return error.SyntaxError;
                try self.emitCall(m2.func_name, call_arg_count);
                if (!m2.uses_slf or !self.methodReturnsSlf(m2, cur_s)) {
                    if (self.expr_depth == 1) self.last_chain_recv = null;
                    return;
                }
                slf_on_stack = true;
            } else if (sdef.findField(fname)) |f| {
                r.total_off += f.offset;
                pending_field = true;
                pending_dt = f.data_type;
                if (f.struct_name) |child| {
                    cur_s = child;
                    r.struct_name = child;
                } else {
                    if (self.cur.tag == .dot) return error.SyntaxError;
                    break;
                }
            } else {
                return error.UndefinedVariable;
            }
        }
        if (pending_field) {
            if (slf_on_stack) _ = try self.emit(.pop, 0);
            try self.emitRecvField(&r);
            self.last_expr_type = pending_dt;
        }
        if (self.expr_depth == 1) self.last_chain_recv = r;
    }

    // Read-only validation that cur starts a pure `: slf` call chain covering
    // the whole RHS (`p.a().b()` followed by `;`/`}`/eof). Used by `let` to
    // decide alias-vs-value *before* parsing. Never emits. Mirrors
    // maybeParseSlfChain; anything rejected here falls back to the normal
    // value path (existing errors preserved).
    fn scanSlfChain(self: *Compiler) bool {
        if (self.cur.tag != .ident) return false;
        const svar = self.findStructVar(self.cur.text) orelse return false;
        if (self.peek.tag != .dot) return false;
        var lx = self.lexer;
        var c = self.cur;
        var p = self.peek;
        var cur_s: []const u8 = svar.struct_name;
        var last_link_call = false;
        while (p.tag == .dot) {
            c = p;
            p = lx.nextToken(); // c == dot
            c = p;
            p = lx.nextToken(); // c == ident?
            if (c.tag != .ident) return false;
            const fname = c.text;
            const sdef = self.findStructDef(cur_s) orelse return false;
            if (p.tag == .l_paren) {
                const m = sdef.findMethod(fname) orelse return false;
                if (!m.uses_slf) return false;
                if (!self.methodReturnsSlf(m, cur_s)) return false;
                c = p;
                p = lx.nextToken(); // c == '('
                var depth: usize = 1;
                while (depth > 0) {
                    c = p;
                    p = lx.nextToken();
                    if (c.tag == .eof) return false;
                    if (c.tag == .l_paren or c.tag == .l_brace or c.tag == .l_bracket) {
                        depth += 1;
                    } else if (c.tag == .r_paren or c.tag == .r_brace or c.tag == .r_bracket) {
                        depth -= 1;
                    }
                }
                // c == matching r_paren
                last_link_call = true;
            } else {
                const f = sdef.findField(fname) orelse return false;
                if (f.struct_name) |child| {
                    cur_s = child;
                } else {
                    return false; // scalar field ending -> value path
                }
                last_link_call = false;
            }
        }
        if (!last_link_call) return false;
        return p.tag == .semicolon or p.tag == .r_brace or p.tag == .eof;
    }

    // Bind `name` as a reference alias to a `: slf` chain result.
    // `slf` always aliases the receiver object, so this is equivalent to
    // aliasing the (possibly nested) receiver itself. Stack top (the
    // returned offset) must already be popped by the caller.
    fn aliasChainResult(self: *Compiler, name: []const u8, rcv: SlfRecv) CompileError!void {
        if (rcv.is_param_ref and rcv.total_off != 0) {
            // Materialize the effective base into a temp: nested refs under a
            // param receiver have no static slot to alias.
            const tmp = try self.addLocal("");
            _ = try self.emit(.load_local, @intCast(rcv.svar_base));
            const off: f64 = @floatFromInt(@as(i64, @intCast(rcv.total_off)));
            _ = try self.emit(.push_num, @bitCast(off));
            _ = try self.emit(.add, 0);
            _ = try self.emit(.store_local, @intCast(tmp));
            try self.addStructVar(name, rcv.struct_name, tmp, false, true);
            self.struct_vars[self.struct_var_count - 1].is_param_ref = true;
        } else if (rcv.is_param_ref) {
            try self.addStructVar(name, rcv.struct_name, rcv.svar_base, false, true);
            self.struct_vars[self.struct_var_count - 1].is_param_ref = true;
        } else if (rcv.is_state) {
            if (!rcv.eff_valid) return error.SyntaxError;
            try self.addStructVar(name, rcv.struct_name, rcv.eff_base, false, false);
        } else {
            try self.addStructVar(name, rcv.struct_name, rcv.svar_base + rcv.total_off, false, true);
        }
    }

    fn findModule(self: *Compiler, name: []const u8) ?ModuleKind {
        for (self.modules[0..self.module_count]) |m| {
            if (std.mem.eql(u8, m.name, name)) return m.kind;
        }
        return null;
    }

    fn addModule(self: *Compiler, name: []const u8, kind: ModuleKind) void {
        if (self.module_count < 16) {
            self.modules[self.module_count] = .{ .name = name, .kind = kind };
            self.module_count += 1;
        }
    }

    fn findBuiltin(name: []const u8) ?struct { id: Builtin, arity: u8 } {
        if (std.mem.eql(u8, name, "sin")) return .{ .id = .sin, .arity = 1 };
        if (std.mem.eql(u8, name, "cos")) return .{ .id = .cos, .arity = 1 };
        if (std.mem.eql(u8, name, "tan")) return .{ .id = .tan, .arity = 1 };
        if (std.mem.eql(u8, name, "asin")) return .{ .id = .asin, .arity = 1 };
        if (std.mem.eql(u8, name, "acos")) return .{ .id = .acos, .arity = 1 };
        if (std.mem.eql(u8, name, "atan")) return .{ .id = .atan, .arity = 1 };
        if (std.mem.eql(u8, name, "atan2")) return .{ .id = .atan2, .arity = 2 };
        if (std.mem.eql(u8, name, "sqrt")) return .{ .id = .sqrt, .arity = 1 };
        if (std.mem.eql(u8, name, "abs")) return .{ .id = .abs, .arity = 1 };
        if (std.mem.eql(u8, name, "floor")) return .{ .id = .floor, .arity = 1 };
        if (std.mem.eql(u8, name, "ceil")) return .{ .id = .ceil, .arity = 1 };
        if (std.mem.eql(u8, name, "round")) return .{ .id = .round, .arity = 1 };
        if (std.mem.eql(u8, name, "min")) return .{ .id = .min, .arity = 2 };
        if (std.mem.eql(u8, name, "max")) return .{ .id = .max, .arity = 2 };
        if (std.mem.eql(u8, name, "clamp")) return .{ .id = .clamp, .arity = 3 };
        if (std.mem.eql(u8, name, "lerp")) return .{ .id = .lerp, .arity = 3 };
        if (std.mem.eql(u8, name, "pow")) return .{ .id = .pow, .arity = 2 };
        if (std.mem.eql(u8, name, "log")) return .{ .id = .log, .arity = 1 };
        if (std.mem.eql(u8, name, "exp")) return .{ .id = .exp, .arity = 1 };
        return null;
    }

    fn verifyBytecode(self: *Compiler) CompileError!void {
        for (self.ops[0..self.op_count], 0..) |op, ip| {
            switch (op.code) {
                .jmp, .jmp_if_zero, .jmp_if_nonzero => {
                    if (op.arg < 0 or op.arg >= self.op_count) {
                        return error.InvalidJumpTarget;
                    }
                },
                .table_jmp => {
                    const count: usize = @truncate(@as(u64, @bitCast(op.arg)) >> 32);
                    for (0..count + 1) |ti| {
                        if (ip + 1 + ti >= self.op_count) return error.InvalidJumpTarget;
                        const target_op = self.ops[ip + 1 + ti];
                        if (target_op.arg < 0 or target_op.arg >= self.op_count) {
                            return error.InvalidJumpTarget;
                        }
                    }
                },
                .loop_step => {
                    const target_ip: u32 = @truncate(@as(u64, @bitCast(op.arg)) >> 32);
                    if (target_ip >= self.op_count) {
                        return error.InvalidJumpTarget;
                    }
                },
                .call => {
                    const target_ip: u32 = @truncate(@as(u64, @bitCast(op.arg)));
                    if (target_ip >= self.op_count) {
                        return error.InvalidJumpTarget;
                    }
                },
                else => {},
            }
        }

        var stack_depths: [max_ops]i16 = @splat(-1);
        var worklist: [max_ops]usize = undefined;
        var head: usize = 0;
        var tail: usize = 0;

        if (self.op_count > 0) {
            stack_depths[0] = 0;
            worklist[tail] = 0;
            tail += 1;
        }

        for (self.funcs[0..self.func_count]) |f| {
            if (f.entry_ip < self.op_count) {
                const p_depth: i16 = @intCast(f.param_count);
                if (stack_depths[f.entry_ip] == -1) {
                    stack_depths[f.entry_ip] = p_depth;
                    worklist[tail] = f.entry_ip;
                    tail += 1;
                }
            }
        }

        for (self.tags[0..self.tag_count]) |t| {
            if (t.entry_ip < self.op_count) {
                if (stack_depths[t.entry_ip] == -1) {
                    stack_depths[t.entry_ip] = 0;
                    worklist[tail] = t.entry_ip;
                    tail += 1;
                }
            }
        }

        while (head < tail) {
            const ip = worklist[head];
            head += 1;
            const current_depth = stack_depths[ip];
            const op = self.ops[ip];

            var delta: i32 = 0;
            switch (op.code) {
                .nop => delta = 0,
                .push_num, .push_0, .push_1, .push_str => delta = 1,
                .load_local, .load_state, .load_host => delta = 1,
                .pop, .store_local, .store_state => delta = -1,
                .dup => delta = 1,
                .check_bounds => delta = 0,
                .load_local_elem, .load_state_elem => delta = 0,
                .store_local_elem, .store_state_elem => delta = -2,
                .add, .sub, .mul, .div, .mod => delta = -1,
                .bit_and, .bit_or, .bit_xor, .shl, .shr => delta = -1,
                .eq, .ne, .lt, .le, .gt, .ge => delta = -1,
                .neg, .lnot, .bit_not => delta = 0,
                .jmp => delta = 0,
                .jmp_if_zero, .jmp_if_nonzero => delta = -1,
                .call_builtin => {
                    const arity: i32 = @intCast((op.arg >> 8) & 0xff);
                    delta = 1 - arity;
                },
                .call => {
                    var p_count: i32 = 0;
                    const call_entry = @as(u32, @truncate(@as(u64, @bitCast(op.arg))));
                    for (self.funcs[0..self.func_count]) |f| {
                        if (f.entry_ip == call_entry) {
                            p_count = @intCast(f.param_count);
                            break;
                        }
                    }
                    delta = 1 - p_count;
                },
                .ret => delta = -1,
                .halt => delta = 0,
                .loop_step, .add_local, .inc_local, .dec_local => delta = 0,
                .table_jmp => delta = -1,
            }

            const next_depth = current_depth + delta;
            if (next_depth < 0) return error.StackUnderflow;
            if (next_depth > 512) return error.StackOverflow;

            if (op.code == .ret or op.code == .halt) {
                continue;
            }

            if (op.code == .table_jmp) {
                const count: usize = @truncate(@as(u64, @bitCast(op.arg)) >> 32);
                for (0..count + 1) |ti| {
                    const target_op = self.ops[ip + 1 + ti];
                    const target: usize = @intCast(target_op.arg);
                    if (stack_depths[target] == -1) {
                        stack_depths[target] = @intCast(next_depth);
                        worklist[tail] = target;
                        tail += 1;
                    } else if (stack_depths[target] != next_depth) {
                        return error.StackMismatch;
                    }
                }
                continue;
            }

            if (op.code == .jmp) {
                const target: usize = @intCast(op.arg);
                if (stack_depths[target] == -1) {
                    stack_depths[target] = @intCast(next_depth);
                    worklist[tail] = target;
                    tail += 1;
                } else if (stack_depths[target] != next_depth) {
                    return error.StackMismatch;
                }
                continue;
            }

            if (op.code == .jmp_if_zero or op.code == .jmp_if_nonzero) {
                const target: usize = @intCast(op.arg);
                if (stack_depths[target] == -1) {
                    stack_depths[target] = @intCast(next_depth);
                    worklist[tail] = target;
                    tail += 1;
                } else if (stack_depths[target] != next_depth) {
                    return error.StackMismatch;
                }
            } else if (op.code == .loop_step) {
                const target: usize = @truncate(@as(u64, @bitCast(op.arg)) >> 32);
                if (stack_depths[target] == -1) {
                    stack_depths[target] = @intCast(next_depth);
                    worklist[tail] = target;
                    tail += 1;
                } else if (stack_depths[target] != next_depth) {
                    return error.StackMismatch;
                }
            }

            if (ip + 1 < self.op_count) {
                const next_ip = ip + 1;
                if (stack_depths[next_ip] == -1) {
                    stack_depths[next_ip] = @intCast(next_depth);
                    worklist[tail] = next_ip;
                    tail += 1;
                } else if (stack_depths[next_ip] != next_depth) {
                    return error.StackMismatch;
                }
            }
        }
    }

    pub fn compile(self: *Compiler) CompileError!*Prog {
        while (self.cur.tag != .eof) {
            try self.parseStatement();
        }
        _ = try self.emit(.halt, 0);

        for (self.call_fixups[0..self.call_fixup_count]) |cf| {
            if (cf.func_name.len > 0) {
                return error.UndefinedFunction;
            }
        }

        for (self.label_fixups[0..self.label_fixup_count]) |lf| {
            if (lf.name.len > 0) {
                return error.UndefinedVariable;
            }
        }

        try self.verifyBytecode();

        const prog = self.allocator.create(Prog) catch return error.OutOfMemory;
        errdefer self.allocator.destroy(prog);

        const ops_slice = self.allocator.dupe(Op, self.ops[0..self.op_count]) catch return error.OutOfMemory;
        errdefer self.allocator.free(ops_slice);

        const str_slice = self.allocator.dupe(u8, self.string_bytes[0..self.string_len]) catch return error.OutOfMemory;
        errdefer self.allocator.free(str_slice);

        var host_slice = self.allocator.alloc([]const u8, self.host_tag_count) catch return error.OutOfMemory;
        errdefer self.allocator.free(host_slice);
        for (self.host_tags[0..self.host_tag_count], 0..) |t, i| {
            host_slice[i] = self.allocator.dupe(u8, t) catch return error.OutOfMemory;
        }

        var tag_slice = self.allocator.alloc(TagDef, self.tag_count) catch return error.OutOfMemory;
        errdefer self.allocator.free(tag_slice);
        for (self.tags[0..self.tag_count], 0..) |t, i| {
            tag_slice[i] = .{
                .name = self.allocator.dupe(u8, t.name) catch return error.OutOfMemory,
                .entry_ip = t.entry_ip,
            };
        }

        var func_slice = self.allocator.alloc(FuncDef, self.func_count) catch return error.OutOfMemory;
        errdefer self.allocator.free(func_slice);
        for (self.funcs[0..self.func_count], 0..) |f, i| {
            func_slice[i] = .{
                .name = self.allocator.dupe(u8, f.name) catch return error.OutOfMemory,
                .entry_ip = f.entry_ip,
                .param_count = f.param_count,
            };
        }

        const state_slice = self.allocator.dupe(Value, self.state_inits[0..self.state_count]) catch return error.OutOfMemory;
        errdefer self.allocator.free(state_slice);
        const state_inits_slice = self.allocator.dupe(Value, self.state_inits[0..self.state_count]) catch return error.OutOfMemory;

        prog.* = .{
            .ops = ops_slice,
            .string_pool = str_slice,
            .host_tags = host_slice,
            .tags = tag_slice,
            .funcs = func_slice,
            .state_slots = state_slice,
            .state_inits = state_inits_slice,
            .allocator = self.allocator,
        };
        return prog;
    }

    fn parseTypeAnnotation(self: *Compiler) CompileError!?TypeAnnotation {
        if (!self.match(.colon)) return null;
        var is_copy = false;
        if (self.match(.pipe)) {
            is_copy = true;
        }
        var info = ArrayInfo{};
        var has_array = false;
        while (self.match(.l_bracket)) {
            has_array = true;
            if (self.cur.tag != .number) return error.ExpectedArrayDimension;
            if (std.math.isNan(self.cur.num_val) or self.cur.num_val < 0 or self.cur.num_val >= 4294967296.0) {
                return error.DimensionMismatch;
            }
            const dim: u32 = @intFromFloat(self.cur.num_val);
            self.advance();
            if (!self.match(.r_bracket)) return error.ExpectedClosingBracket;
            if (info.dim_count >= 4) return error.TooManyDimensions;
            info.dims[info.dim_count] = dim;
            info.dim_count += 1;
        }
        var dt: DataType = .unknown;
        var sname_annot: ?[]const u8 = null;
        if (self.cur.tag == .ident) {
            const tname = self.cur.text;
            self.advance();
            if (std.mem.eql(u8, tname, "num")) {
                dt = .num;
            } else if (std.mem.eql(u8, tname, "str")) {
                dt = .str;
            } else if (self.findStructDef(tname) != null) {
                sname_annot = tname;
            } else if (std.mem.eql(u8, tname, "slf")) {
                // `slf` return type: resolved to the receiver struct in
                // parseFuncInternal; rejected everywhere else (UnknownType).
                sname_annot = "slf";
            } else {
                return error.UnknownType;
            }
        } else if (has_array) {
            return error.SyntaxError;
        }
        if (is_copy) {
            if (!self.match(.pipe)) return error.SyntaxError;
        }
        if (has_array) {
            if (sname_annot != null) return error.UnknownType;
            var total: u32 = 1;
            for (info.dims[0..info.dim_count]) |d| {
                total *= d;
            }
            info.total_elements = total;
            info.elem_type = dt;
            return TypeAnnotation{ .data_type = dt, .array = info, .struct_name = null, .is_copy = is_copy };
        }
        return TypeAnnotation{ .data_type = dt, .array = null, .struct_name = sname_annot, .is_copy = is_copy };
    }

    fn skipTypeAnnotation(self: *Compiler) CompileError!void {
        _ = try self.parseTypeAnnotation();
    }

    fn isTypedArrayHeader(self: *Compiler) bool {
        if (self.cur.tag != .l_bracket) return false;
        const saved_pos = self.lexer.pos;
        const saved_cur = self.cur;
        const saved_peek = self.peek;

        var matched = false;
        if (self.cur.tag == .l_bracket and self.peek.tag == .number) {
            self.advance();
            self.advance();
            if (self.cur.tag == .r_bracket) {
                self.advance();
                while (self.cur.tag == .l_bracket and self.peek.tag == .number) {
                    self.advance();
                    self.advance();
                    if (self.cur.tag == .r_bracket) {
                        self.advance();
                    } else break;
                }
                if (self.cur.tag == .ident and self.peek.tag == .l_brace) {
                    matched = true;
                }
            }
        }

        self.lexer.pos = saved_pos;
        self.cur = saved_cur;
        self.peek = saved_peek;
        return matched;
    }

    fn parseArrayLiteral(self: *Compiler, info: *ArrayInfo) CompileError!void {
        const is_typed = self.isTypedArrayHeader();
        if (is_typed) {
            var dim_idx: usize = 0;
            while (self.match(.l_bracket)) {
                if (self.cur.tag != .number) return error.ExpectedArrayDimension;
                if (std.math.isNan(self.cur.num_val) or self.cur.num_val < 0 or self.cur.num_val >= 4294967296.0) {
                    return error.DimensionMismatch;
                }
                const d: u32 = @intFromFloat(self.cur.num_val);
                self.advance();
                if (!self.match(.r_bracket)) return error.ExpectedClosingBracket;
                if (dim_idx >= 4) return error.TooManyDimensions;
                info.dims[dim_idx] = d;
                dim_idx += 1;
            }
            info.dim_count = @intCast(dim_idx);
            if (self.cur.tag == .ident) {
                const elem_tname = self.cur.text;
                self.advance();
                if (std.mem.eql(u8, elem_tname, "num")) {
                    info.elem_type = .num;
                } else if (std.mem.eql(u8, elem_tname, "str")) {
                    info.elem_type = .str;
                } else {
                    return error.UnknownType;
                }
            }

            var total: u32 = 1;
            for (info.dims[0..info.dim_count]) |d| {
                total *= d;
            }
            info.total_elements = total;

            var flat_idx: usize = 0;
            try self.parseArrayElements(info, 0, &flat_idx, true);
        } else {
            var flat_idx: usize = 0;
            try self.parseArrayElements(info, 0, &flat_idx, false);
            if (info.dim_count == 0) info.dim_count = 1;
            info.total_elements = @intCast(flat_idx);
        }
    }

    fn parseArrayElements(
        self: *Compiler,
        info: *ArrayInfo,
        current_dim: usize,
        flat_idx: *usize,
        is_typed: bool,
    ) CompileError!void {
        const opening: TokenType = if (is_typed and current_dim == 0) .l_brace else .l_bracket;
        const closing: TokenType = if (is_typed and current_dim == 0) .r_brace else .r_bracket;

        if (!self.match(opening)) return error.SyntaxError;

        var count: u32 = 0;
        while (self.cur.tag != closing and self.cur.tag != .eof) {
            if (self.cur.tag == .l_bracket and (info.dim_count == 0 or current_dim + 1 < info.dim_count)) {
                if (info.dim_count == 0) info.dim_count = @intCast(current_dim + 2);
                try self.parseArrayElements(info, current_dim + 1, flat_idx, false);
            } else {
                try self.parseExpression();
                if (info.elem_type != .unknown and self.last_expr_type != .unknown and info.elem_type != self.last_expr_type) {
                    return error.TypeMismatch;
                }
                const slot = if (info.is_state) try self.addState("") else try self.addLocal("");
                _ = try self.emit(if (info.is_state) .store_state else .store_local, @intCast(slot));
                flat_idx.* += 1;
            }
            count += 1;
            if (!self.match(.comma)) break;
        }

        if (!self.match(closing)) return error.ExpectedClosingBracket;

        if (info.dims[current_dim] == 0) {
            info.dims[current_dim] = count;
        } else if (info.dims[current_dim] != count) {
            return error.ArraySizeMismatch;
        }
    }

    fn emitArrayIndexing(self: *Compiler, arr: ArrayInfo) CompileError!void {
        var dim_idx: usize = 0;
        while (self.match(.l_bracket)) {
            if (dim_idx >= arr.dim_count) return error.TooManyDimensions;
            const bound = arr.dims[dim_idx];

            if (self.cur.tag == .number and self.peek.tag == .r_bracket) {
                const idx_num = self.cur.num_val;
                if (idx_num < 0 or idx_num >= @as(f64, @floatFromInt(bound))) {
                    return error.IndexOutOfBounds;
                }
            }

            try self.parseExpression();
            _ = try self.emit(.check_bounds, @intCast(bound));
            if (!self.match(.r_bracket)) return error.ExpectedClosingBracket;

            if (dim_idx == 0 and arr.dim_count > 1) {
                const stride = arr.stride(dim_idx);
                _ = try self.emit(.push_num, @bitCast(@as(f64, @floatFromInt(stride))));
                _ = try self.emit(.mul, 0);
            } else if (dim_idx > 0) {
                _ = try self.emit(.add, 0);
            }
            dim_idx += 1;
            if (self.cur.tag != .l_bracket) break;
        }

        if (arr.is_state) {
            _ = try self.emit(.load_state_elem, @intCast(arr.base_slot));
        } else {
            _ = try self.emit(.load_local_elem, @intCast(arr.base_slot));
        }
    }

    fn parseStructDef(self: *Compiler) CompileError!void {
        _ = self.match(.kw_stu);
        if (self.cur.tag != .ident) return error.SyntaxError;
        const sname = self.cur.text;
        self.advance();
        if (!self.match(.l_brace)) return error.SyntaxError;

        const def = StructDef{ .name = sname };
        try self.addStructDef(def);
        const def_idx = self.struct_def_count - 1;

        while (self.cur.tag != .r_brace and self.cur.tag != .eof) {
            if (self.match(.kw_fun)) {
                if (self.cur.tag != .ident) return error.SyntaxError;
                const mname = self.cur.text;
                self.advance();
                try self.parseFuncInternal(sname, mname);
                _ = self.match(.comma);
                _ = self.match(.semicolon);
            } else if (self.cur.tag == .ident and self.peek.tag == .l_paren) {
                const mname = self.cur.text;
                self.advance();
                try self.parseFuncInternal(sname, mname);
                _ = self.match(.comma);
                _ = self.match(.semicolon);
            } else if (self.cur.tag == .ident and self.peek.tag == .colon) {
                const fname = self.cur.text;
                self.advance();
                self.advance();
                if (self.cur.tag != .ident) return error.SyntaxError;
                const tname = self.cur.text;
                self.advance();
                if (std.mem.eql(u8, tname, "num")) {
                    try self.struct_defs[def_idx].addField(fname, .num, null, 1);
                } else if (std.mem.eql(u8, tname, "str")) {
                    try self.struct_defs[def_idx].addField(fname, .str, null, 1);
                } else if (self.findStructDef(tname)) |child_sdef| {
                    try self.struct_defs[def_idx].addField(fname, .unknown, tname, child_sdef.total_slots);
                } else {
                    return error.UnknownType;
                }
                _ = self.match(.comma);
                _ = self.match(.semicolon);
            } else {
                return error.SyntaxError;
            }
        }
        if (!self.match(.r_brace)) return error.SyntaxError;
        _ = self.match(.semicolon);
    }

    fn parseStructInit(self: *Compiler, sdef: StructDef, base_slot: usize, is_state: bool, is_decl: bool) CompileError!void {
        if (self.cur.tag == .ident and std.mem.eql(u8, self.cur.text, sdef.name)) {
            self.advance();
        }

        if (self.cur.tag == .ident and self.peek.tag != .l_brace) {
            const src_name = self.cur.text;
            if (self.findStructVar(src_name)) |src| {
                if (!std.mem.eql(u8, src.struct_name, sdef.name)) return error.TypeMismatch;
                self.advance();
                for (0..sdef.total_slots) |fi| {
                    const src_slot = src.base_slot + fi;
                    const dst_slot = base_slot + fi;
                    if (src.is_state) {
                        _ = try self.emit(.load_state, @intCast(src_slot));
                    } else {
                        _ = try self.emit(.load_local, @intCast(src_slot));
                    }
                    if (is_state) {
                        _ = try self.emit(.store_state, @intCast(dst_slot));
                    } else {
                        _ = try self.emit(.store_local, @intCast(dst_slot));
                    }
                }
                return;
            }
        }

        if (self.match(.l_brace)) {
            var initialized: [64]bool = @splat(false);
            var idx: usize = 0;
            while (self.cur.tag != .r_brace and self.cur.tag != .eof) {
                if (self.cur.tag == .ident and self.peek.tag == .colon) {
                    const fname = self.cur.text;
                    self.advance();
                    self.advance();
                    const field = sdef.findField(fname) orelse return error.SyntaxError;
                    if (field.struct_name) |child_sname| {
                        const child_def = self.findStructDef(child_sname) orelse return error.SyntaxError;
                        try self.parseStructInit(child_def, base_slot + field.offset, is_state, is_decl);
                        for (0..field.slot_count) |k| initialized[field.offset + k] = true;
                    } else {
                        const slot = base_slot + field.offset;
                        if (is_decl and is_state) {
                            var val: f64 = 0.0;
                            if (self.cur.tag == .number) {
                                val = self.cur.num_val;
                                self.advance();
                            } else if (self.match(.minus) and self.cur.tag == .number) {
                                val = -self.cur.num_val;
                                self.advance();
                            } else {
                                return error.SyntaxError;
                            }
                            self.state_inits[slot] = Value.fromNum(val);
                            initialized[field.offset] = true;
                        } else {
                            try self.parseExpression();
                            if (field.data_type != .unknown and self.last_expr_type != .unknown and field.data_type != self.last_expr_type) {
                                return error.TypeMismatch;
                            }
                            if (is_state) {
                                _ = try self.emit(.store_state, @intCast(slot));
                            } else {
                                _ = try self.emit(.store_local, @intCast(slot));
                            }
                            initialized[field.offset] = true;
                        }
                    }
                } else {
                    if (idx >= sdef.field_count) return error.SyntaxError;
                    const field = sdef.fields[idx];
                    if (field.struct_name) |child_sname| {
                        const child_def = self.findStructDef(child_sname) orelse return error.SyntaxError;
                        try self.parseStructInit(child_def, base_slot + field.offset, is_state, is_decl);
                        for (0..field.slot_count) |k| initialized[field.offset + k] = true;
                        idx += 1;
                    } else {
                        const slot = base_slot + field.offset;
                        if (is_decl and is_state) {
                            var val: f64 = 0.0;
                            if (self.cur.tag == .number) {
                                val = self.cur.num_val;
                                self.advance();
                            } else if (self.match(.minus) and self.cur.tag == .number) {
                                val = -self.cur.num_val;
                                self.advance();
                            } else {
                                return error.SyntaxError;
                            }
                            self.state_inits[slot] = Value.fromNum(val);
                            initialized[field.offset] = true;
                            idx += 1;
                        } else {
                            try self.parseExpression();
                            if (field.data_type != .unknown and self.last_expr_type != .unknown and field.data_type != self.last_expr_type) {
                                return error.TypeMismatch;
                            }
                            if (is_state) {
                                _ = try self.emit(.store_state, @intCast(slot));
                            } else {
                                _ = try self.emit(.store_local, @intCast(slot));
                            }
                            initialized[field.offset] = true;
                            idx += 1;
                        }
                    }
                }
                _ = self.match(.comma);
            }
            if (!self.match(.r_brace)) return error.SyntaxError;

            if (!is_decl or !is_state) {
                for (0..sdef.total_slots) |fi| {
                    if (!initialized[fi]) {
                        const slot = base_slot + fi;
                        _ = try self.emit(.push_0, 0);
                        if (is_state) {
                            _ = try self.emit(.store_state, @intCast(slot));
                        } else {
                            _ = try self.emit(.store_local, @intCast(slot));
                        }
                    }
                }
            }
            return;
        }

        if (self.match(.l_bracket)) {
            for (0..sdef.field_count) |fi| {
                if (self.cur.tag == .r_bracket or self.cur.tag == .eof) {
                    if (!is_decl or !is_state) {
                        const slot = base_slot + fi;
                        _ = try self.emit(.push_0, 0);
                        if (is_state) {
                            _ = try self.emit(.store_state, @intCast(slot));
                        } else {
                            _ = try self.emit(.store_local, @intCast(slot));
                        }
                    }
                } else {
                    const field = sdef.fields[fi];
                    const slot = base_slot + field.offset;
                    if (is_decl and is_state) {
                        var val: f64 = 0.0;
                        if (self.cur.tag == .number) {
                            val = self.cur.num_val;
                            self.advance();
                        } else if (self.match(.minus) and self.cur.tag == .number) {
                            val = -self.cur.num_val;
                            self.advance();
                        } else {
                            return error.SyntaxError;
                        }
                        self.state_inits[slot] = Value.fromNum(val);
                        _ = self.match(.comma);
                    } else {
                        try self.parseExpression();
                        if (field.data_type != .unknown and self.last_expr_type != .unknown and field.data_type != self.last_expr_type) {
                            return error.TypeMismatch;
                        }
                        if (is_state) {
                            _ = try self.emit(.store_state, @intCast(slot));
                        } else {
                            _ = try self.emit(.store_local, @intCast(slot));
                        }
                        _ = self.match(.comma);
                    }
                }
            }
            if (!self.match(.r_bracket)) return error.SyntaxError;
            return;
        }

        return error.SyntaxError;
    }

    fn isCaseLabel(self: *Compiler) bool {
        if (self.cur.tag == .ident and std.mem.eql(u8, self.cur.text, "_") and (self.peek.tag == .colon or self.peek.tag == .arrow)) return true;
        if (self.cur.tag == .string and (self.peek.tag == .colon or self.peek.tag == .arrow or self.peek.tag == .pipe)) return true;
        if (self.cur.tag == .number and (self.peek.tag == .colon or self.peek.tag == .arrow or self.peek.tag == .pipe or self.peek.tag == .dot_dot or self.peek.tag == .dot_dot_equal)) return true;
        if (self.cur.tag == .minus and self.peek.tag == .number) return true;
        return false;
    }

    fn parseJmp(self: *Compiler, is_expr: bool) CompileError!bool {
        try self.parseExpression();
        const target_slot = try self.addLocal("");
        _ = try self.emit(.store_local, @intCast(target_slot));

        if (self.jmp_depth >= 8) return error.TooManyLocals;
        self.jmp_contexts[self.jmp_depth] = .{};
        self.jmp_depth += 1;

        const jmp_to_dispatch = try self.emit(.jmp, 0);
        if (!self.match(.l_brace)) return error.SyntaxError;

        const PatKind = enum { num, range, str, default };
        const PatItem = struct {
            kind: PatKind,
            num_val: f64 = 0.0,
            range_max: f64 = 0.0,
            is_inclusive: bool = false,
            str_val: []const u8 = "",
        };
        const JmpArm = struct {
            items: [8]PatItem = undefined,
            item_count: usize = 0,
            is_default: bool = false,
            entry_ip: usize = 0,
            exit_jmp: ?usize = null,
            is_arrow: bool = true,
        };
        var arms: [64]JmpArm = undefined;
        var arm_count: usize = 0;
        var default_arm_idx: ?usize = null;
        var had_non_arrow = false;

        while (self.cur.tag != .r_brace and self.cur.tag != .eof) {
            if (arm_count >= 64) return error.TooManyLocals;
            var arm = JmpArm{};

            if (self.cur.tag == .ident and std.mem.eql(u8, self.cur.text, "_")) {
                self.advance();
                arm.is_default = true;
            } else {
                while (true) {
                    var item = PatItem{ .kind = .num };
                    if (self.cur.tag == .number or (self.cur.tag == .minus and self.peek.tag == .number)) {
                        var n: f64 = 0.0;
                        if (self.match(.minus)) {
                            n = -self.cur.num_val;
                            self.advance();
                        } else {
                            n = self.cur.num_val;
                            self.advance();
                        }
                        var is_range = false;
                        var is_inclusive = false;
                        if (self.match(.dot_dot_equal)) {
                            is_range = true;
                            is_inclusive = true;
                        } else if (self.match(.dot_dot)) {
                            is_range = true;
                            is_inclusive = false;
                        }
                        if (is_range) {
                            var n2: f64 = 0.0;
                            if (self.match(.minus)) {
                                if (self.cur.tag != .number) return error.SyntaxError;
                                n2 = -self.cur.num_val;
                                self.advance();
                            } else if (self.cur.tag == .number) {
                                n2 = self.cur.num_val;
                                self.advance();
                            } else return error.SyntaxError;
                            item = .{ .kind = .range, .num_val = n, .range_max = n2, .is_inclusive = is_inclusive };
                        } else {
                            item = .{ .kind = .num, .num_val = n };
                        }
                    } else if (self.cur.tag == .string) {
                        const raw = self.cur.text;
                        const s = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') raw[1 .. raw.len - 1] else raw;
                        self.advance();
                        item = .{ .kind = .str, .str_val = s };
                    } else return error.SyntaxError;

                    if (arm.item_count >= 8) return error.TooManyLocals;
                    arm.items[arm.item_count] = item;
                    arm.item_count += 1;

                    if (self.match(.pipe)) {
                        continue;
                    }
                    break;
                }
            }

            if (self.match(.arrow)) {
                arm.is_arrow = true;
                arm.entry_ip = self.op_count;

                if (self.cur.tag == .l_brace) {
                    if (is_expr) {
                        const had_val = try self.parseBlock();
                        if (!had_val) _ = try self.emit(.push_0, 0);
                    } else {
                        const had_val = try self.parseBlock();
                        if (had_val) _ = try self.emit(.pop, 0);
                    }
                    _ = self.match(.comma);
                } else {
                    try self.parseExpression();
                    if (!is_expr) {
                        _ = try self.emit(.pop, 0);
                    }
                    _ = self.match(.comma);
                    _ = self.match(.semicolon);
                }
                arm.exit_jmp = try self.emit(.jmp, 0);
            } else if (self.match(.colon)) {
                arm.is_arrow = false;
                had_non_arrow = true;
                arm.entry_ip = self.op_count;

                if (self.isCaseLabel()) {
                    // Fallthrough to next label
                } else if (self.cur.tag == .l_brace) {
                    _ = self.match(.l_brace);
                    while (self.cur.tag != .r_brace and self.cur.tag != .eof) {
                        try self.parseStatement();
                    }
                    _ = self.match(.r_brace);
                } else {
                    while (!self.isCaseLabel() and self.cur.tag != .r_brace and self.cur.tag != .eof) {
                        try self.parseStatement();
                    }
                }
            } else {
                return error.SyntaxError;
            }

            if (arm.is_default) {
                default_arm_idx = arm_count;
            }
            arms[arm_count] = arm;
            arm_count += 1;
        }

        if (!self.match(.r_brace)) return error.SyntaxError;

        const fallthrough_jmp = if (had_non_arrow) try self.emit(.jmp, 0) else null;
        const dispatch_ip = self.op_count;
        self.patchJump(jmp_to_dispatch, dispatch_ip);

        // Check if Jump Table optimization is possible:
        var can_table = (arm_count >= 2 and !had_non_arrow);
        var min_val: f64 = std.math.inf(f64);
        var max_val: f64 = -std.math.inf(f64);
        for (arms[0..arm_count]) |a| {
            if (a.is_default) continue;
            for (a.items[0..a.item_count]) |it| {
                if (it.kind != .num) { can_table = false; break; }
                if (it.num_val != @floor(it.num_val)) { can_table = false; break; }
                if (it.num_val < min_val) min_val = it.num_val;
                if (it.num_val > max_val) max_val = it.num_val;
            }
            if (!can_table) break;
        }
        if (can_table and (max_val - min_val >= 64 or min_val < -128)) {
            can_table = false;
        }
        // intFromFloat below traps on out-of-range: keep the table in i32.
        if (can_table and (min_val < -2147483648.0 or max_val > 2147483647.0)) {
            can_table = false;
        }

        const default_entry = if (default_arm_idx) |dai| arms[dai].entry_ip else null;

        if (can_table) {
            const min_i: i32 = @intFromFloat(min_val);
            const count: u32 = @as(u32, @intFromFloat(max_val - min_val)) + 1;
            const packed_arg: i64 = @bitCast(@as(u64, @as(u32, @bitCast(min_i))) | (@as(u64, count) << 32));

            _ = try self.emit(.load_local, @intCast(target_slot));
            _ = try self.emit(.table_jmp, packed_arg);

            var entry_jumps: [64]usize = undefined;
            for (0..count) |ci| {
                const cur_val = min_val + @as(f64, @floatFromInt(ci));
                var target_ip: ?usize = null;
                for (arms[0..arm_count]) |a| {
                    if (a.is_default) continue;
                    for (a.items[0..a.item_count]) |it| {
                        if (it.kind == .num and it.num_val == cur_val) {
                            target_ip = a.entry_ip;
                            break;
                        }
                    }
                    if (target_ip != null) break;
                }
                const j = try self.emit(.jmp, 0);
                entry_jumps[ci] = j;
                if (target_ip) |tip| {
                    self.patchJump(j, tip);
                }
            }
            const def_jmp = try self.emit(.jmp, 0);
            var unhandled_expr_push: ?usize = null;
            if (default_entry == null and is_expr) {
                unhandled_expr_push = try self.emit(.push_0, 0);
            }
            const fallback_ip = if (default_entry) |de| de else (if (unhandled_expr_push) |uep| uep else self.op_count);
            self.patchJump(def_jmp, fallback_ip);
            for (0..count) |ci| {
                if (self.ops[entry_jumps[ci]].arg == 0) {
                    self.patchJump(entry_jumps[ci], fallback_ip);
                }
            }
        } else {
            for (arms[0..arm_count]) |a| {
                if (a.is_default) continue;
                for (a.items[0..a.item_count]) |it| {
                    _ = try self.emit(.load_local, @intCast(target_slot));
                    switch (it.kind) {
                        .num => {
                            if (it.num_val == 0.0) {
                                _ = try self.emit(.push_0, 0);
                            } else if (it.num_val == 1.0) {
                                _ = try self.emit(.push_1, 0);
                            } else {
                                _ = try self.emit(.push_num, @bitCast(it.num_val));
                            }
                            _ = try self.emit(.eq, 0);
                            _ = try self.emit(.jmp_if_nonzero, @intCast(a.entry_ip));
                        },
                        .str => {
                            const str_arg = try self.addString(it.str_val);
                            _ = try self.emit(.push_str, str_arg);
                            _ = try self.emit(.eq, 0);
                            _ = try self.emit(.jmp_if_nonzero, @intCast(a.entry_ip));
                        },
                        .range => {
                            _ = try self.emit(.push_num, @bitCast(it.num_val));
                            _ = try self.emit(.ge, 0);
                            const skip_range = try self.emit(.jmp_if_zero, 0);
                            _ = try self.emit(.load_local, @intCast(target_slot));
                            _ = try self.emit(.push_num, @bitCast(it.range_max));
                            if (it.is_inclusive) {
                                _ = try self.emit(.le, 0);
                            } else {
                                _ = try self.emit(.lt, 0);
                            }
                            _ = try self.emit(.jmp_if_nonzero, @intCast(a.entry_ip));
                            self.patchJump(skip_range, self.op_count);
                        },
                        .default => {},
                    }
                }
            }

            if (default_entry) |de| {
                _ = try self.emit(.jmp, @intCast(de));
            } else if (is_expr) {
                _ = try self.emit(.push_0, 0);
            }
        }

        const end_ip = self.op_count;
        if (fallthrough_jmp) |fj| {
            self.patchJump(fj, end_ip);
        }

        for (arms[0..arm_count]) |a| {
            if (a.exit_jmp) |ej| {
                self.patchJump(ej, end_ip);
            }
        }

        const jctx = self.jmp_contexts[self.jmp_depth - 1];
        for (jctx.breaks[0..jctx.break_count]) |b_ip| {
            self.patchJump(b_ip, end_ip);
        }
        self.jmp_depth -= 1;
        self.local_count = target_slot;

        if (is_expr) {
            self.last_stmt_had_value = true;
        }
        return is_expr;
    }

    fn formatMethodName(self: *Compiler, rs: []const u8, mname: []const u8) CompileError![]const u8 {
        const needed = rs.len + 1 + mname.len;
        if (self.method_name_len + needed > self.method_name_buf.len) return error.TooManyFuncs;
        const start = self.method_name_len;
        @memcpy(self.method_name_buf[self.method_name_len .. self.method_name_len + rs.len], rs);
        self.method_name_len += rs.len;
        self.method_name_buf[self.method_name_len] = '.';
        self.method_name_len += 1;
        @memcpy(self.method_name_buf[self.method_name_len .. self.method_name_len + mname.len], mname);
        self.method_name_len += mname.len;
        return self.method_name_buf[start..self.method_name_len];
    }

    fn parseFuncInternal(self: *Compiler, receiver_struct: ?[]const u8, method_name: []const u8) CompileError!void {
        _ = self.match(.l_paren);

        const full_name = if (receiver_struct) |rs|
            try self.formatMethodName(rs, method_name)
        else
            method_name;

        const saved_func_name = self.current_func_name;
        self.current_func_name = full_name;

        var uses_slf = false;
        var ret_is_slf = false;
        {
            // Lookahead for `: slf` return type: params are parsed before the
            // return annotation, but slf injection must be decided first.
            var lx = self.lexer;
            var c = self.cur;
            var p = self.peek;
            var depth: usize = 1; // already consumed '('
            while (depth > 0) {
                if (c.tag == .eof) break;
                if (c.tag == .l_paren) depth += 1 else if (c.tag == .r_paren) depth -= 1;
                c = p;
                p = lx.nextToken();
            }
            if (depth == 0 and c.tag == .colon and p.tag == .ident and std.mem.eql(u8, p.text, "slf")) {
                ret_is_slf = true;
            }
        }
        if (ret_is_slf and receiver_struct != null) uses_slf = true;
        if (receiver_struct != null) {
            var scan_lexer = self.lexer;
            var brace_depth: usize = 0;
            var in_body = false;
            while (true) {
                const tok = scan_lexer.nextToken();
                if (tok.tag == .eof) break;
                if (tok.tag == .l_brace) {
                    brace_depth += 1;
                    in_body = true;
                } else if (tok.tag == .r_brace) {
                    if (brace_depth > 0) brace_depth -= 1;
                    if (brace_depth == 0 and in_body) break;
                } else if (tok.tag == .ident and std.mem.eql(u8, tok.text, "slf")) {
                    uses_slf = true;
                    break;
                }
            }
        }

        var param_count: usize = 0;
        var param_names: [8][]const u8 = undefined;
        var param_types: [8]DataType = @splat(.unknown);
        var param_consts: [8]bool = @splat(false);
        var param_annots: [8]?TypeAnnotation = @splat(null);

        if (uses_slf) {
            param_names[0] = "slf";
            param_types[0] = .unknown;
            param_consts[0] = false;
            param_annots[0] = TypeAnnotation{
                .data_type = .unknown,
                .struct_name = receiver_struct.?,
                .is_copy = false,
                .is_const = false,
            };
            param_count = 1;
        }

        while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
            var is_con = false;
            if (self.match(.kw_con)) {
                is_con = true;
            }
            if (param_count >= 8) return error.TooManyLocals;
            param_consts[param_count] = is_con;
            param_names[param_count] = self.cur.text;
            self.advance();
            const p_annot = try self.parseTypeAnnotation();
            param_annots[param_count] = p_annot;
            param_types[param_count] = if (p_annot) |a| a.data_type else .unknown;
            param_count += 1;
            if (!self.match(.comma)) break;
        }
        _ = self.match(.r_paren);
        const ret_annot = try self.parseTypeAnnotation();
        var ret_struct: ?[]const u8 = null;
        if (ret_annot) |a| {
            if (a.struct_name) |sn| {
                if (std.mem.eql(u8, sn, "slf")) {
                    if (receiver_struct == null) return error.UnknownType;
                    ret_is_slf = true;
                    ret_struct = receiver_struct.?;
                } else {
                    ret_struct = sn;
                }
            }
        }
        const saved_func_ret_type = self.current_func_ret_type;
        self.current_func_ret_type = if (ret_annot) |a| a.data_type else .unknown;
        const saved_func_ret_is_slf = self.current_func_ret_is_slf;
        self.current_func_ret_is_slf = ret_is_slf;
        const saved_func_ret_struct = self.current_func_ret_struct;
        self.current_func_ret_struct = ret_struct;

        const skip_jmp = try self.emit(.jmp, 0);
        const entry_ip = self.op_count;
        const fidx = try self.registerFunc(full_name, entry_ip, param_count);
        self.func_param_annots[fidx] = param_annots;

        if (receiver_struct) |rs| {
            if (self.findStructDefPtr(rs)) |sdef_ptr| {
                try sdef_ptr.addMethod(method_name, full_name, uses_slf);
            }
        }

        const saved_locals = self.locals;
        const saved_local_types = self.local_types;
        const saved_local_consts = self.local_consts;
        const saved_local_count = self.local_count;
        self.local_count = 0;
        const saved_arrays = self.array_count;
        const saved_struct_vars = self.struct_var_count;
        const saved_labels = self.label_count;
        const saved_label_fixups = self.label_fixup_count;

        var p = param_count;
        while (p > 0) {
            p -= 1;
            const pname = param_names[p];
            const is_con = param_consts[p];
            const annot = param_annots[p];
            if (annot != null and annot.?.struct_name != null) {
                const sname = annot.?.struct_name.?;
                const sdef = self.findStructDef(sname) orelse return error.UnknownType;
                if (annot.?.is_copy) {
                    const ref_slot = try self.addLocal("");
                    _ = try self.emit(.store_local, @intCast(ref_slot));
                    const base_slot = self.local_count;
                    for (0..sdef.total_slots) |_| {
                        _ = try self.addLocal("");
                    }
                    try self.addStructVar(pname, sname, base_slot, false, false);
                    if (self.struct_var_count > 0) {
                        self.struct_vars[self.struct_var_count - 1].is_const = is_con;
                    }
                    for (0..sdef.total_slots) |fi| {
                        _ = try self.emit(.load_local, @intCast(ref_slot));
                        _ = try self.emit(.load_local_elem, @intCast(fi));
                        _ = try self.emit(.store_local, @intCast(base_slot + fi));
                    }
                } else {
                    const slot = try self.addLocal(pname);
                    self.local_consts[slot] = is_con;
                    _ = try self.emit(.store_local, @intCast(slot));
                    try self.addStructVar(pname, sname, slot, false, true);
                    if (self.struct_var_count > 0) {
                        self.struct_vars[self.struct_var_count - 1].is_const = is_con;
                        self.struct_vars[self.struct_var_count - 1].is_param_ref = true;
                    }
                }
            } else {
                const slot = try self.addLocal(pname);
                self.local_types[slot] = param_types[p];
                self.local_consts[slot] = is_con;
                _ = try self.emit(.store_local, @intCast(slot));
            }
        }

        // slf is always stored last, so its slot is local_count - 1.
        const saved_func_slf_slot = self.current_func_slf_slot;
        self.current_func_slf_slot = if (uses_slf) self.local_count - 1 else 0;

        if (self.match(.arrow)) {
            try self.parseExpression();
            if (self.current_func_ret_type != .unknown and self.last_expr_type != .unknown and self.current_func_ret_type != self.last_expr_type) {
                return error.TypeMismatch;
            }
            _ = try self.emit(.ret, 0);
        } else if (self.cur.tag == .l_brace) {
            self.current_func_had_ret = false;
            _ = try self.parseBlock();
            if (!self.current_func_had_ret) {
                if (self.current_func_ret_is_slf) {
                    _ = try self.emit(.load_local, @intCast(self.current_func_slf_slot));
                    _ = try self.emit(.ret, 0);
                } else if (receiver_struct != null) {
                    _ = try self.emit(.push_0, 0);
                    _ = try self.emit(.ret, 0);
                } else {
                    return error.MissingReturn;
                }
            } else {
                _ = try self.emit(.ret, 0);
            }
        } else {
            return error.ExpectedFunctionBody;
        }

        self.current_func_name = saved_func_name;
        self.current_func_ret_type = saved_func_ret_type;
        self.current_func_ret_is_slf = saved_func_ret_is_slf;
        self.current_func_ret_struct = saved_func_ret_struct;
        self.current_func_slf_slot = saved_func_slf_slot;
        self.array_count = saved_arrays;
        self.struct_var_count = saved_struct_vars;
        self.locals = saved_locals;
        self.local_types = saved_local_types;
        self.local_consts = saved_local_consts;
        self.local_count = saved_local_count;
        for (self.label_fixups[saved_label_fixups..self.label_fixup_count]) |lf| {
            if (lf.name.len > 0) return error.UndefinedVariable;
        }
        self.label_count = saved_labels;
        self.label_fixup_count = saved_label_fixups;
        self.patchJump(skip_jmp, self.op_count);
        _ = self.match(.semicolon);
    }

    fn parseStatement(self: *Compiler) CompileError!void {
        self.last_stmt_had_value = false;
        self.last_chain_recv = null;
        if (self.match(.kw_jmp)) {
            _ = try self.parseJmp(false);
            return;
        }

        if (self.match(.kw_go)) {
            if (self.cur.tag != .label) return error.SyntaxError;
            const target = self.cur.text;
            self.advance();
            _ = self.match(.semicolon);

            var found_ip: ?usize = null;
            for (self.labels[0..self.label_count]) |l| {
                if (std.mem.eql(u8, l.name, target)) {
                    found_ip = l.ip;
                    break;
                }
            }
            if (found_ip) |fip| {
                _ = try self.emit(.jmp, @intCast(fip));
            } else {
                if (self.label_fixup_count >= 64) return error.TooManyLocals;
                const op_idx = try self.emit(.jmp, 0);
                self.label_fixups[self.label_fixup_count] = .{ .name = target, .op_idx = op_idx };
                self.label_fixup_count += 1;
            }
            return;
        }

        if (self.cur.tag == .label) {
            const name = self.cur.text;
            self.advance();
            _ = self.match(.colon);
            _ = self.match(.semicolon);

            for (self.labels[0..self.label_count]) |l| {
                if (std.mem.eql(u8, l.name, name)) return error.DuplicateVariable;
            }
            if (self.label_count >= 64) return error.TooManyLocals;
            const label_ip = self.op_count;
            self.labels[self.label_count] = .{ .name = name, .ip = label_ip };
            self.label_count += 1;

            for (self.label_fixups[0..self.label_fixup_count]) |*lf| {
                if (std.mem.eql(u8, lf.name, name)) {
                    self.patchJump(lf.op_idx, label_ip);
                    lf.name = "";
                }
            }
            return;
        }

        if (self.match(.kw_stu)) {
            try self.parseStructDef();
            return;
        }

        if (self.match(.kw_let)) {
            const name = self.cur.text;
            self.advance();
            const annot = try self.parseTypeAnnotation();
            if (annot) |a| {
                if (a.struct_name) |sn| {
                    // `: slf` is only valid as a method return type.
                    if (std.mem.eql(u8, sn, "slf")) return error.UnknownType;
                }
            }
            if (annot) |a| {
                if (a.struct_name) |sname| {
                    const sdef = self.findStructDef(sname) orelse return error.UnknownType;
                    if (self.match(.equal)) {
                        if (self.match(.pipe)) {
                            if (self.cur.tag != .ident) return error.SyntaxError;
                            const src_name = self.cur.text;
                            const src = self.findStructVar(src_name) orelse return error.UndefinedVariable;
                            if (!std.mem.eql(u8, src.struct_name, sname)) return error.TypeMismatch;
                            self.advance();
                            if (!self.match(.pipe)) return error.SyntaxError;
                            _ = self.match(.semicolon);
                            const base_slot = self.local_count;
                            for (0..sdef.total_slots) |fi| {
                                const s = try self.addLocal("");
                                self.local_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                            }
                            try self.addStructVar(name, sname, base_slot, false, false);
                            for (0..sdef.total_slots) |fi| {
                                if (src.is_state) {
                                    _ = try self.emit(.load_state, @intCast(src.base_slot + fi));
                                } else {
                                    _ = try self.emit(.load_local, @intCast(src.base_slot + fi));
                                }
                                _ = try self.emit(.store_local, @intCast(base_slot + fi));
                            }
                            return;
                        } else if (self.cur.tag == .ident and self.findStructVar(self.cur.text) != null and self.peek.tag != .dot and self.peek.tag != .l_brace) {
                            const src_name = self.cur.text;
                            const src = self.findStructVar(src_name).?;
                            if (!std.mem.eql(u8, src.struct_name, sname)) return error.TypeMismatch;
                            self.advance();
                            _ = self.match(.semicolon);
                            try self.addStructVar(name, sname, src.base_slot, src.is_state, true);
                            return;
                        } else if (self.cur.tag == .ident and self.findStructVar(self.cur.text) != null and self.peek.tag == .dot and self.scanSlfChain()) {
                            // `let q: S = p.a().b();` — q aliases the receiver.
                            try self.parseExpression();
                            const rcv = self.last_chain_recv orelse return error.SyntaxError;
                            if (!std.mem.eql(u8, rcv.struct_name, sname)) return error.TypeMismatch;
                            _ = try self.emit(.pop, 0);
                            try self.aliasChainResult(name, rcv);
                            _ = self.match(.semicolon);
                            return;
                        }
                        const base_slot = self.local_count;
                        for (0..sdef.total_slots) |fi| {
                            const s = try self.addLocal("");
                            self.local_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                        }
                        try self.addStructVar(name, sname, base_slot, false, false);
                        try self.parseStructInit(sdef, base_slot, false, true);
                    } else {
                        const base_slot = self.local_count;
                        for (0..sdef.total_slots) |fi| {
                            const s = try self.addLocal("");
                            self.local_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                        }
                        try self.addStructVar(name, sname, base_slot, false, false);
                        for (0..sdef.total_slots) |fi| {
                            const slot = base_slot + fi;
                            _ = try self.emit(.push_0, 0);
                            _ = try self.emit(.store_local, @intCast(slot));
                        }
                    }
                    _ = self.match(.semicolon);
                    return;
                }
            }
            if (self.match(.equal)) {
                if (self.match(.pipe)) {
                    if (self.cur.tag == .ident and self.findStructVar(self.cur.text) != null) {
                        const src_name = self.cur.text;
                        const src = self.findStructVar(src_name).?;
                        const sdef = self.findStructDef(src.struct_name).?;
                        self.advance();
                        if (!self.match(.pipe)) return error.SyntaxError;
                        _ = self.match(.semicolon);
                        const base_slot = self.local_count;
                        for (0..sdef.total_slots) |fi| {
                            const s = try self.addLocal("");
                            self.local_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                        }
                        try self.addStructVar(name, src.struct_name, base_slot, false, false);
                        for (0..sdef.total_slots) |fi| {
                            if (src.is_state) {
                                _ = try self.emit(.load_state, @intCast(src.base_slot + fi));
                            } else {
                                _ = try self.emit(.load_local, @intCast(src.base_slot + fi));
                            }
                            _ = try self.emit(.store_local, @intCast(base_slot + fi));
                        }
                        return;
                    }
                    try self.parseExpression();
                    if (!self.match(.pipe)) return error.SyntaxError;
                    const slot = try self.addLocal(name);
                    self.local_types[slot] = self.last_expr_type;
                    _ = try self.emit(.store_local, @intCast(slot));
                    _ = self.match(.semicolon);
                    return;
                }
                if (self.cur.tag == .ident and self.findStructVar(self.cur.text) != null and self.peek.tag != .dot and self.peek.tag != .l_brace) {
                    const src_name = self.cur.text;
                    const src = self.findStructVar(src_name).?;
                    self.advance();
                    _ = self.match(.semicolon);
                    try self.addStructVar(name, src.struct_name, src.base_slot, src.is_state, true);
                    return;
                }
                if (self.cur.tag == .ident and self.findStructVar(self.cur.text) != null and self.peek.tag == .dot and self.scanSlfChain()) {
                    // `let q = p.a().b();` — q aliases the receiver.
                    try self.parseExpression();
                    const rcv = self.last_chain_recv orelse return error.SyntaxError;
                    _ = try self.emit(.pop, 0);
                    try self.aliasChainResult(name, rcv);
                    _ = self.match(.semicolon);
                    return;
                }
                if (self.cur.tag == .ident and self.findStructDef(self.cur.text) != null and self.peek.tag == .l_brace) {
                    const sname = self.cur.text;
                    const sdef = self.findStructDef(sname).?;
                    const base_slot = self.local_count;
                    for (0..sdef.total_slots) |fi| {
                        const s = try self.addLocal("");
                        self.local_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                    }
                    try self.addStructVar(name, sname, base_slot, false, false);
                    try self.parseStructInit(sdef, base_slot, false, true);
                    _ = self.match(.semicolon);
                    return;
                }
                if (self.cur.tag == .l_bracket) {
                    var arr_info = if (annot) |a| (a.array orelse ArrayInfo{}) else ArrayInfo{};
                    if (annot) |a| arr_info.elem_type = a.data_type;
                    arr_info.base_slot = self.local_count;
                    arr_info.is_state = false;
                    try self.parseArrayLiteral(&arr_info);
                    try self.addArray(name, arr_info);
                    _ = self.match(.semicolon);
                    return;
                }
                try self.parseExpression();
                if (annot) |a| {
                    if (a.data_type != .unknown and self.last_expr_type != .unknown and a.data_type != self.last_expr_type) {
                        return error.TypeMismatch;
                    }
                }
            } else {
                if (annot) |t_annot| {
                    if (t_annot.array) |t_arr| {
                        var arr_info = t_arr;
                        arr_info.base_slot = self.local_count;
                        arr_info.is_state = false;
                        for (0..arr_info.total_elements) |_| {
                            const s = try self.addLocal("");
                            _ = try self.emit(.push_0, 0);
                            _ = try self.emit(.store_local, @intCast(s));
                        }
                        try self.addArray(name, arr_info);
                        _ = self.match(.semicolon);
                        return;
                    }
                }
                _ = try self.emit(.push_0, 0);
            }
            const slot = try self.addLocal(name);
            self.local_types[slot] = if (annot) |a| (if (a.data_type != .unknown) a.data_type else self.last_expr_type) else self.last_expr_type;
            _ = try self.emit(.store_local, @intCast(slot));
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_sta)) {
            const name = self.cur.text;
            self.advance();
            const annot = try self.parseTypeAnnotation();
            if (annot) |a| {
                if (a.struct_name) |sn| {
                    if (std.mem.eql(u8, sn, "slf")) return error.UnknownType;
                }
            }
            if (annot) |a| {
                if (a.struct_name) |sname| {
                    const sdef = self.findStructDef(sname) orelse return error.UnknownType;
                    const base_slot = self.state_count;
                    for (0..sdef.total_slots) |fi| {
                        const s = try self.addState("");
                        self.state_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                    }
                    try self.addStructVar(name, sname, base_slot, true, false);

                    if (self.match(.equal)) {
                        try self.parseStructInit(sdef, base_slot, true, true);
                    }
                    _ = self.match(.semicolon);
                    return;
                }
            }
            if (self.match(.equal)) {
                if (self.cur.tag == .ident and self.findStructDef(self.cur.text) != null and self.peek.tag == .l_brace) {
                    const sname = self.cur.text;
                    const sdef = self.findStructDef(sname).?;
                    const base_slot = self.state_count;
                    for (0..sdef.total_slots) |fi| {
                        const s = try self.addState("");
                        self.state_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                    }
                    try self.addStructVar(name, sname, base_slot, true, false);
                    try self.parseStructInit(sdef, base_slot, true, true);
                    _ = self.match(.semicolon);
                    return;
                }
                if (self.cur.tag == .l_bracket) {
                    var arr_info = if (annot) |a| (a.array orelse ArrayInfo{}) else ArrayInfo{};
                    if (annot) |a| arr_info.elem_type = a.data_type;
                    arr_info.base_slot = self.state_count;
                    arr_info.is_state = true;
                    try self.parseArrayLiteral(&arr_info);
                    try self.addArray(name, arr_info);
                    _ = self.match(.semicolon);
                    return;
                }
                if (self.cur.tag == .number) {
                    if (annot) |a| {
                        if (a.data_type == .str) return error.TypeMismatch;
                    }
                    const init_val = self.cur.num_val;
                    self.advance();
                    const slot = try self.addState(name);
                    self.state_types[slot] = .num;
                    self.state_inits[slot] = Value.fromNum(init_val);
                    _ = self.match(.semicolon);
                    return;
                } else if (self.match(.minus) and self.cur.tag == .number) {
                    if (annot) |a| {
                        if (a.data_type == .str) return error.TypeMismatch;
                    }
                    const init_val = -self.cur.num_val;
                    self.advance();
                    const slot = try self.addState(name);
                    self.state_types[slot] = .num;
                    self.state_inits[slot] = Value.fromNum(init_val);
                    _ = self.match(.semicolon);
                    return;
                } else {
                    try self.parseExpression();
                    if (annot) |a| {
                        if (a.data_type != .unknown and self.last_expr_type != .unknown and a.data_type != self.last_expr_type) {
                            return error.TypeMismatch;
                        }
                    }
                }
            }
            const slot = try self.addState(name);
            self.state_types[slot] = if (annot) |a| (if (a.data_type != .unknown) a.data_type else self.last_expr_type) else self.last_expr_type;
            self.state_inits[slot] = Value.fromNum(0.0);
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_con)) {
            const name = self.cur.text;
            self.advance();
            const annot = try self.parseTypeAnnotation();
            if (annot) |a| {
                if (a.struct_name) |sn| {
                    if (std.mem.eql(u8, sn, "slf")) return error.UnknownType;
                }
            }
            _ = self.match(.equal);

            if (self.match(.at)) {
                _ = self.match(.l_paren);
                if (self.cur.tag == .string) {
                    const raw = self.cur.text;
                    const path = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
                        raw[1 .. raw.len - 1]
                    else
                        raw;
                    self.advance();
                    _ = self.match(.r_paren);
                    _ = self.match(.semicolon);

                    if (std.ascii.eqlIgnoreCase(path, "std")) {
                        self.addModule(name, .std);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.math")) {
                        self.addModule(name, .math);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.dbg")) {
                        self.addModule(name, .dbg);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.fmt")) {
                        self.addModule(name, .fmt);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.rng")) {
                        self.addModule(name, .rng);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.str")) {
                        self.addModule(name, .str);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.hsh")) {
                        self.addModule(name, .hsh);
                        return;
                    } else if (std.ascii.eqlIgnoreCase(path, "std.nos")) {
                        self.addModule(name, .nos);
                        return;
                    }
                    return;
                }
            }

            if (self.cur.tag == .ident) {
                const target_id = self.cur.text;
                if (self.findModule(target_id)) |mod| {
                    if (mod == .std and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "math")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .math);
                            return;
                        }
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "dbg")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .dbg);
                            return;
                        }
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "fmt")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .fmt);
                            return;
                        }
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "rng")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .rng);
                            return;
                        }
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "str")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .str);
                            return;
                        }
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "hsh")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .hsh);
                            return;
                        }
                        if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "nos")) {
                            self.advance();
                            _ = self.match(.semicolon);
                            self.addModule(name, .nos);
                            return;
                        }
                    }
                }
            }

            try self.parseExpression();
            if (annot) |a| {
                if (a.data_type != .unknown and self.last_expr_type != .unknown and a.data_type != self.last_expr_type) {
                    return error.TypeMismatch;
                }
            }
            const slot = try self.addLocal(name);
            self.local_types[slot] = if (annot) |a| (if (a.data_type != .unknown) a.data_type else self.last_expr_type) else self.last_expr_type;
            self.local_consts[slot] = true;
            _ = try self.emit(.store_local, @intCast(slot));
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_if)) {
            try self.parseIfStatement();
            return;
        }

        if (self.match(.kw_lop)) {
            try self.parseLoop();
            return;
        }

        if (self.match(.kw_out)) {
            if (self.jmp_depth > 0 and self.loop_depth == 0) {
                const jmp_idx = try self.emit(.jmp, 0);
                var jctx = &self.jmp_contexts[self.jmp_depth - 1];
                if (jctx.break_count < 64) {
                    jctx.breaks[jctx.break_count] = jmp_idx;
                    jctx.break_count += 1;
                }
                _ = self.match(.semicolon);
                return;
            }
            if (self.loop_depth == 0) return error.BreakOutsideLoop;
            const jmp_idx = try self.emit(.jmp, 0);
            var loop = &self.loops[self.loop_depth - 1];
            if (loop.break_count < max_breaks) {
                loop.breaks[loop.break_count] = jmp_idx;
                loop.break_count += 1;
            }
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_skp)) {
            if (self.jmp_depth > 0) {
                const jmp_idx = try self.emit(.jmp, 0);
                var jctx = &self.jmp_contexts[self.jmp_depth - 1];
                if (jctx.break_count < 64) {
                    jctx.breaks[jctx.break_count] = jmp_idx;
                    jctx.break_count += 1;
                }
                _ = self.match(.semicolon);
                return;
            }
            if (self.loop_depth == 0) return error.ContinueOutsideLoop;
            const jmp_idx = try self.emit(.jmp, 0);
            var loop = &self.loops[self.loop_depth - 1];
            if (loop.continue_count < max_breaks) {
                loop.continues[loop.continue_count] = jmp_idx;
                loop.continue_count += 1;
            }
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_ret)) {
            self.current_func_had_ret = true;
            if (self.cur.tag != .semicolon and self.cur.tag != .r_brace and self.cur.tag != .eof) {
                try self.parseExpression();
                if (self.current_func_ret_type != .unknown and self.last_expr_type != .unknown and self.current_func_ret_type != self.last_expr_type) {
                    return error.TypeMismatch;
                }
            } else {
                if (self.current_func_ret_is_slf) {
                    // Bare `ret;` inside an `: slf` method returns the receiver.
                    _ = try self.emit(.load_local, @intCast(self.current_func_slf_slot));
                } else {
                    if (self.current_func_ret_type != .unknown and self.current_func_ret_type != .num) {
                        return error.TypeMismatch;
                    }
                    _ = try self.emit(.push_0, 0);
                }
            }
            _ = try self.emit(.ret, 0);
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_tag)) {
            const name = self.cur.text;
            self.advance();
            _ = self.match(.arrow);

            const skip_jmp = try self.emit(.jmp, 0);
            const entry_ip = self.op_count;
            if (self.tag_count < max_tags) {
                self.tags[self.tag_count] = .{ .name = name, .entry_ip = entry_ip };
                self.tag_count += 1;
            }

            if (self.cur.tag == .l_brace) {
                const saved_locals = self.local_count;
                _ = try self.parseBlock();
                self.local_count = saved_locals;
                _ = try self.emit(.halt, 0);
            } else if (self.cur.tag == .ident and self.peek.tag != .l_paren and self.peek.tag != .dot and self.peek.tag != .l_bracket and (self.findFunc(self.cur.text) != null or (self.findLocal(self.cur.text) == null and self.findState(self.cur.text) == null))) {
                const func_name = self.cur.text;
                self.advance();
                try self.emitCall(func_name, 0);
                _ = try self.emit(.halt, 0);
            } else {
                try self.parseExpression();
                _ = try self.emit(.halt, 0);
            }
            self.patchJump(skip_jmp, self.op_count);
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_fun)) {
            var name = self.cur.text;
            self.advance();
            var rec_sname: ?[]const u8 = null;
            if (self.match(.dot)) {
                rec_sname = name;
                if (self.cur.tag != .ident) return error.SyntaxError;
                name = self.cur.text;
                self.advance();
            }
            try self.parseFuncInternal(rec_sname, name);
            return;
        }

        if (self.cur.tag == .l_brace) {
            const has_val = try self.parseBlock();
            _ = self.match(.semicolon);
            if (has_val and self.cur.tag != .eof and self.cur.tag != .r_brace) {
                _ = try self.emit(.pop, 0);
                self.last_stmt_had_value = false;
            }
            return;
        }

        if (self.cur.tag == .ident and self.peek.tag == .l_bracket) {
            const saved_pos = self.lexer.pos;
            const saved_cur = self.cur;
            const saved_peek = self.peek;
            const saved_op_count = self.op_count;

            const name = self.cur.text;
            if (self.findArray(name)) |arr| {
                self.advance();
                var dim_idx: usize = 0;
                var ok = true;
                while (self.match(.l_bracket)) {
                    if (dim_idx >= arr.dim_count) { ok = false; break; }
                    const bound = arr.dims[dim_idx];
                    if (self.cur.tag == .number and self.peek.tag == .r_bracket) {
                        const idx_num = self.cur.num_val;
                        if (idx_num < 0 or idx_num >= @as(f64, @floatFromInt(bound))) {
                            return error.IndexOutOfBounds;
                        }
                    }
                    try self.parseExpression();
                    _ = try self.emit(.check_bounds, @intCast(bound));
                    if (!self.match(.r_bracket)) { ok = false; break; }

                    if (dim_idx == 0 and arr.dim_count > 1) {
                        const stride = arr.stride(dim_idx);
                        _ = try self.emit(.push_num, @bitCast(@as(f64, @floatFromInt(stride))));
                        _ = try self.emit(.mul, 0);
                    } else if (dim_idx > 0) {
                        _ = try self.emit(.add, 0);
                    }
                    dim_idx += 1;
                    if (self.cur.tag != .l_bracket) break;
                }

                const op_tok = self.cur.tag;
                if (ok and dim_idx == arr.dim_count and (op_tok == .equal or op_tok == .plus_equal or op_tok == .minus_equal or op_tok == .star_equal or op_tok == .slash_equal)) {
                    self.advance();
                    if (op_tok == .equal) {
                        try self.parseExpression();
                        if (arr.elem_type != .unknown and self.last_expr_type != .unknown and arr.elem_type != self.last_expr_type) {
                            return error.TypeMismatch;
                        }
                        if (arr.is_state) {
                            _ = try self.emit(.store_state_elem, @intCast(arr.base_slot));
                        } else {
                            _ = try self.emit(.store_local_elem, @intCast(arr.base_slot));
                        }
                    } else {
                        _ = try self.emit(.dup, 0);
                        if (arr.is_state) {
                            _ = try self.emit(.load_state_elem, @intCast(arr.base_slot));
                        } else {
                            _ = try self.emit(.load_local_elem, @intCast(arr.base_slot));
                        }
                        try self.parseExpression();
                        if (arr.elem_type != .unknown and self.last_expr_type != .unknown and arr.elem_type != self.last_expr_type) {
                            return error.TypeMismatch;
                        }
                        switch (op_tok) {
                            .plus_equal => _ = try self.emit(.add, 0),
                            .minus_equal => _ = try self.emit(.sub, 0),
                            .star_equal => _ = try self.emit(.mul, 0),
                            .slash_equal => _ = try self.emit(.div, 0),
                            else => {},
                        }
                        if (arr.is_state) {
                            _ = try self.emit(.store_state_elem, @intCast(arr.base_slot));
                        } else {
                            _ = try self.emit(.store_local_elem, @intCast(arr.base_slot));
                        }
                    }
                    _ = self.match(.semicolon);
                    return;
                } else {
                    self.op_count = saved_op_count;
                    self.lexer.pos = saved_pos;
                    self.cur = saved_cur;
                    self.peek = saved_peek;
                }
            }
        }

        if (self.cur.tag == .ident and self.peek.tag == .dot and self.findStructVar(self.cur.text) != null) {
            const saved_pos = self.lexer.pos;
            const saved_cur = self.cur;
            const saved_peek = self.peek;
            const saved_op_count = self.op_count;

            const name = self.cur.text;
            const svar = self.findStructVar(name).?;
            if (svar.is_const) return error.CannotAssignToConstant;
            const sdef = self.findStructDef(svar.struct_name) orelse return error.SyntaxError;
            self.advance();
            self.advance();
            if (self.cur.tag != .ident) return error.SyntaxError;
            var fname = self.cur.text;
            self.advance();
            var curr_sdef = sdef;
            const field_opt = curr_sdef.findField(fname);
            if (field_opt == null) {
                self.lexer.pos = saved_pos;
                self.cur = saved_cur;
                self.peek = saved_peek;
                self.op_count = saved_op_count;
            } else {
                var field = field_opt.?;
                var total_offset: usize = field.offset;
                var dot_ok = true;
                while (self.cur.tag == .dot) {
                    self.advance();
                    if (self.cur.tag != .ident) { dot_ok = false; break; }
                    fname = self.cur.text;
                    self.advance();
                    const child_sname = field.struct_name orelse { dot_ok = false; break; };
                    curr_sdef = self.findStructDef(child_sname) orelse { dot_ok = false; break; };
                    const child_f = curr_sdef.findField(fname);
                    if (child_f == null) { dot_ok = false; break; }
                    field = child_f.?;
                    total_offset += field.offset;
                }
                if (!dot_ok) {
                    self.lexer.pos = saved_pos;
                    self.cur = saved_cur;
                    self.peek = saved_peek;
                    self.op_count = saved_op_count;
                } else {
                const slot = svar.base_slot + total_offset;

            const op_tok = self.cur.tag;
            if (op_tok != .equal and op_tok != .plus_equal and op_tok != .minus_equal and op_tok != .star_equal and op_tok != .slash_equal) {
                self.lexer.pos = saved_pos;
                self.cur = saved_cur;
                self.peek = saved_peek;
                self.op_count = saved_op_count;
            } else {
                self.advance();

            if (svar.is_param_ref) {
                _ = try self.emit(.load_local, @intCast(svar.base_slot));
                if (op_tok != .equal) {
                    _ = try self.emit(.load_local, @intCast(svar.base_slot));
                    _ = try self.emit(.load_local_elem, @intCast(total_offset));
                    try self.parseExpression();
                    switch (op_tok) {
                        .plus_equal => _ = try self.emit(.add, 0),
                        .minus_equal => _ = try self.emit(.sub, 0),
                        .star_equal => _ = try self.emit(.mul, 0),
                        .slash_equal => _ = try self.emit(.div, 0),
                        else => return error.SyntaxError,
                    }
                } else {
                    try self.parseExpression();
                }
                _ = try self.emit(.store_local_elem, @intCast(total_offset));
                _ = self.match(.semicolon);
                return;
            }

            if (!svar.is_state) {
                if (op_tok == .plus_equal and self.cur.tag == .number and self.cur.num_val == 1.0 and (self.peek.tag == .semicolon or self.peek.tag == .r_brace)) {
                    if (field.data_type == .str) return error.TypeMismatch;
                    self.advance();
                    _ = self.match(.semicolon);
                    _ = try self.emit(.inc_local, @intCast(slot));
                    return;
                }
                if (op_tok == .minus_equal and self.cur.tag == .number and self.cur.num_val == 1.0 and (self.peek.tag == .semicolon or self.peek.tag == .r_brace)) {
                    if (field.data_type == .str) return error.TypeMismatch;
                    self.advance();
                    _ = self.match(.semicolon);
                    _ = try self.emit(.dec_local, @intCast(slot));
                    return;
                }
                if (op_tok == .plus_equal and self.cur.tag == .ident) {
                    var src_slot_opt: ?usize = null;
                    if (self.peek.tag == .dot) {
                        const saved_adv_pos = self.lexer.pos;
                        const saved_adv_cur = self.cur;
                        const saved_adv_peek = self.peek;
                        if (self.findStructVar(self.cur.text)) |rhs_svar| {
                            if (!rhs_svar.is_state) {
                                var curr_rhs_sdef = self.findStructDef(rhs_svar.struct_name).?;
                                var rhs_off: usize = 0;
                                var valid = true;
                                while (self.peek.tag == .dot) {
                                    self.advance();
                                    self.advance();
                                    if (self.cur.tag != .ident) { valid = false; break; }
                                    const rf = curr_rhs_sdef.findField(self.cur.text) orelse { valid = false; break; };
                                    rhs_off += rf.offset;
                                    if (rf.struct_name) |child_sn| {
                                        curr_rhs_sdef = self.findStructDef(child_sn) orelse { valid = false; break; };
                                    }
                                }
                                if (valid and (self.peek.tag == .semicolon or self.peek.tag == .r_brace)) {
                                    src_slot_opt = rhs_svar.base_slot + rhs_off;
                                }
                            }
                        }
                        if (src_slot_opt == null) {
                            self.lexer.pos = saved_adv_pos;
                            self.cur = saved_adv_cur;
                            self.peek = saved_adv_peek;
                        }
                    } else if (self.peek.tag == .semicolon or self.peek.tag == .r_brace) {
                        src_slot_opt = self.findLocal(self.cur.text);
                    }

                    if (src_slot_opt) |src_slot| {
                        if (self.local_types[slot] != .unknown and self.local_types[src_slot] != .unknown and self.local_types[slot] != self.local_types[src_slot]) {
                            return error.TypeMismatch;
                        }
                        self.advance();
                        _ = self.match(.semicolon);
                        const packed_arg: i64 = @bitCast(@as(u64, @intCast(slot)) | (@as(u64, @intCast(src_slot)) << 16));
                        _ = try self.emit(.add_local, packed_arg);
                        return;
                    }
                }
            }

            if (op_tok != .equal) {
                if (svar.is_state) {
                    _ = try self.emit(.load_state, @intCast(slot));
                } else {
                    _ = try self.emit(.load_local, @intCast(slot));
                }
            }

            try self.parseExpression();
            if (field.data_type != .unknown and self.last_expr_type != .unknown and field.data_type != self.last_expr_type) {
                return error.TypeMismatch;
            }

            switch (op_tok) {
                .plus_equal => _ = try self.emit(.add, 0),
                .minus_equal => _ = try self.emit(.sub, 0),
                .star_equal => _ = try self.emit(.mul, 0),
                .slash_equal => _ = try self.emit(.div, 0),
                else => {},
            }

            if (svar.is_state) {
                _ = try self.emit(.store_state, @intCast(slot));
            } else {
                _ = try self.emit(.store_local, @intCast(slot));
            }
                _ = self.match(.semicolon);
                return;
                }
                }
            }
        }

        if (self.cur.tag == .ident and self.peek.tag == .equal and self.findStructVar(self.cur.text) != null) {
            const dst_name = self.cur.text;
            self.advance();
            self.advance();
            var dst = self.findStructVarPtr(dst_name).?;
            if (dst.is_const) return error.CannotAssignToConstant;
            const sdef = self.findStructDef(dst.struct_name) orelse return error.SyntaxError;

            if (self.match(.pipe)) {
                if (self.cur.tag != .ident) return error.SyntaxError;
                const src_name = self.cur.text;
                const src = self.findStructVar(src_name) orelse return error.UndefinedVariable;
                if (!std.mem.eql(u8, src.struct_name, dst.struct_name)) return error.TypeMismatch;
                self.advance();
                if (!self.match(.pipe)) return error.SyntaxError;
                _ = self.match(.semicolon);

                var target_base = dst.base_slot;
                if (dst.owned_base_slot) |obs| {
                    target_base = obs;
                    dst.base_slot = obs;
                    dst.is_reference = false;
                } else {
                    target_base = self.local_count;
                    for (0..sdef.total_slots) |fi| {
                        const s = try self.addLocal("");
                        self.local_types[s] = if (fi < sdef.field_count) sdef.fields[fi].data_type else .num;
                    }
                    dst.owned_base_slot = target_base;
                    dst.base_slot = target_base;
                    dst.is_reference = false;
                }

                for (0..sdef.total_slots) |fi| {
                    if (src.is_state) {
                        _ = try self.emit(.load_state, @intCast(src.base_slot + fi));
                    } else {
                        _ = try self.emit(.load_local, @intCast(src.base_slot + fi));
                    }
                    if (dst.is_state) {
                        _ = try self.emit(.store_state, @intCast(target_base + fi));
                    } else {
                        _ = try self.emit(.store_local, @intCast(target_base + fi));
                    }
                }
                return;
            } else if (self.cur.tag == .ident and self.findStructVar(self.cur.text) != null and self.peek.tag != .dot and self.peek.tag != .l_brace) {
                const src_name = self.cur.text;
                const src = self.findStructVar(src_name).?;
                if (dst.is_const) return error.CannotAssignToConstant;
                if (!std.mem.eql(u8, src.struct_name, dst.struct_name)) return error.TypeMismatch;
                self.advance();
                _ = self.match(.semicolon);

                if (src.scope_depth > dst.scope_depth) {
                    return error.LifetimeError;
                }

                dst.base_slot = src.base_slot;
                dst.is_state = src.is_state;
                dst.is_reference = true;
                return;
            } else {
                try self.parseStructInit(sdef, dst.base_slot, dst.is_state, false);
                _ = self.match(.semicolon);
                return;
            }
        }

        if (self.cur.tag == .ident and (self.peek.tag == .equal or self.peek.tag == .plus_equal or self.peek.tag == .minus_equal or self.peek.tag == .star_equal or self.peek.tag == .slash_equal)) {
            const name = self.cur.text;
            self.advance();
            const op_tok = self.cur.tag;
            self.advance();

            const is_local = self.findLocal(name);
            const is_state = self.findState(name);

            if (is_local == null and is_state == null) {
                return error.UndefinedVariable;
            }
            if (is_local) |slot| {
                if (self.local_consts[slot]) {
                    return error.CannotAssignToConstant;
                }
            }

            if (is_local != null and (self.peek.tag == .semicolon or self.peek.tag == .r_brace)) {
                if (op_tok == .plus_equal and self.cur.tag == .number and self.cur.num_val == 1.0) {
                    if (self.local_types[is_local.?] == .str) return error.TypeMismatch;
                    self.advance();
                    _ = self.match(.semicolon);
                    _ = try self.emit(.inc_local, @intCast(is_local.?));
                    return;
                }
                if (op_tok == .minus_equal and self.cur.tag == .number and self.cur.num_val == 1.0) {
                    if (self.local_types[is_local.?] == .str) return error.TypeMismatch;
                    self.advance();
                    _ = self.match(.semicolon);
                    _ = try self.emit(.dec_local, @intCast(is_local.?));
                    return;
                }
                if (op_tok == .plus_equal and self.cur.tag == .ident) {
                    if (self.findLocal(self.cur.text)) |src_slot| {
                        if (self.local_types[is_local.?] != .unknown and self.local_types[src_slot] != .unknown and self.local_types[is_local.?] != self.local_types[src_slot]) {
                            return error.TypeMismatch;
                        }
                        self.advance();
                        _ = self.match(.semicolon);
                        const packed_arg: i64 = @bitCast(@as(u64, @intCast(is_local.?)) | (@as(u64, @intCast(src_slot)) << 16));
                        _ = try self.emit(.add_local, packed_arg);
                        return;
                    }
                }
            }

            if (op_tok != .equal) {
                if (is_local) |slot| {
                    _ = try self.emit(.load_local, @intCast(slot));
                } else if (is_state) |slot| {
                    _ = try self.emit(.load_state, @intCast(slot));
                }
            } else {
                var is_copy = false;
                if (self.cur.tag == .pipe) {
                    is_copy = true;
                }
                if (!is_copy and self.cur.tag == .ident and (self.peek.tag == .semicolon or self.peek.tag == .r_brace)) {
                    if (self.findLocal(self.cur.text)) |src_slot| {
                        const dst_type = if (is_local) |slot| self.local_types[slot] else if (is_state) |slot| self.state_types[slot] else DataType.unknown;
                        const src_type = self.local_types[src_slot];
                        if (src_type == .str or dst_type == .str) {
                            const dst_scope = if (is_local) |slot| self.local_scope_depth[slot] else 0;
                            if (self.local_scope_depth[src_slot] > dst_scope) {
                                return error.LifetimeError;
                            }
                        }
                    }
                }
            }

            try self.parseExpression();

            const target_type = if (is_local) |slot| self.local_types[slot] else if (is_state) |slot| self.state_types[slot] else DataType.unknown;
            if (target_type != .unknown and self.last_expr_type != .unknown and target_type != self.last_expr_type) {
                return error.TypeMismatch;
            }
            if (op_tok == .equal) {
                if (is_local) |slot| {
                    if (self.local_types[slot] == .unknown) self.local_types[slot] = self.last_expr_type;
                } else if (is_state) |slot| {
                    if (self.state_types[slot] == .unknown) self.state_types[slot] = self.last_expr_type;
                }
            }

            switch (op_tok) {
                .plus_equal => _ = try self.emit(.add, 0),
                .minus_equal => _ = try self.emit(.sub, 0),
                .star_equal => _ = try self.emit(.mul, 0),
                .slash_equal => _ = try self.emit(.div, 0),
                else => {},
            }

            if (is_local) |slot| {
                _ = try self.emit(.store_local, @intCast(slot));
            } else if (is_state) |slot| {
                _ = try self.emit(.store_state, @intCast(slot));
            }
            _ = self.match(.semicolon);
            return;
        }

        try self.parseExpression();
        _ = self.match(.semicolon);
        if (self.cur.tag != .eof and self.cur.tag != .r_brace) {
            _ = try self.emit(.pop, 0);
        } else {
            self.last_stmt_had_value = true;
        }
    }

    fn parseBlock(self: *Compiler) CompileError!bool {
        _ = self.match(.l_brace);
        self.scope_depth += 1;
        defer self.scope_depth -= 1;
        const saved_locals = self.local_count;
        const saved_struct_vars = self.struct_var_count;

        var had_expr = false;
        var block_has_value = false;
        while (self.cur.tag != .r_brace and self.cur.tag != .eof) {
            try self.parseStatement();
            had_expr = true;
            block_has_value = self.last_stmt_had_value;
        }
        _ = self.match(.r_brace);

        if (!had_expr) {
            _ = try self.emit(.push_0, 0);
            block_has_value = true;
        }
        self.local_count = saved_locals;
        self.struct_var_count = saved_struct_vars;
        self.last_stmt_had_value = block_has_value;
        return block_has_value;
    }

    fn parseIfStatement(self: *Compiler) CompileError!void {
        try self.parseExpression();
        const false_jmp = try self.emit(.jmp_if_zero, 0);

        _ = try self.parseBlock();
        const exit_jmp = try self.emit(.jmp, 0);
        self.patchJump(false_jmp, self.op_count);

        var end_jumps: [16]usize = undefined;
        var end_jump_count: usize = 0;
        end_jumps[end_jump_count] = exit_jmp;
        end_jump_count += 1;

        while (self.match(.kw_lf)) {
            try self.parseExpression();
            const next_false = try self.emit(.jmp_if_zero, 0);
            _ = try self.parseBlock();
            if (end_jump_count < 16) {
                end_jumps[end_jump_count] = try self.emit(.jmp, 0);
                end_jump_count += 1;
            }
            self.patchJump(next_false, self.op_count);
        }

        if (self.match(.kw_el)) {
            _ = try self.parseBlock();
        }

        for (end_jumps[0..end_jump_count]) |j| {
            self.patchJump(j, self.op_count);
        }
    }

    fn parseLoop(self: *Compiler) CompileError!void {
        var var1_name: ?[]const u8 = null;
        var var2_name: ?[]const u8 = null;
        if (self.match(.pipe)) {
            var1_name = self.cur.text;
            self.advance();
            if (self.match(.comma)) {
                var2_name = self.cur.text;
                self.advance();
            }
            _ = self.match(.pipe);
        }

        if (var1_name != null and self.cur.tag == .ident and self.findArray(self.cur.text) != null and self.peek.tag == .l_brace) {
            const arr_name = self.cur.text;
            const arr = self.findArray(arr_name).?;
            self.advance();

            const N = arr.dims[0];
            const v_name = var1_name.?;
            const idx_name = var2_name;

            const idx_slot = if (idx_name) |n| (try self.addLocal(n)) else (try self.addLocal(""));
            const v_slot = try self.addLocal(v_name);

            const limit_slot = try self.addLocal("");
            _ = try self.emit(.push_num, @bitCast(@as(f64, @floatFromInt(N))));
            _ = try self.emit(.store_local, @intCast(limit_slot));

            _ = try self.emit(.push_0, 0);
            _ = try self.emit(.store_local, @intCast(idx_slot));

            const loop_start_ip = self.op_count;
            self.loops[self.loop_depth] = .{ .continue_ip = loop_start_ip, .break_count = 0, .continue_count = 0 };
            self.loop_depth += 1;

            _ = try self.emit(.load_local, @intCast(idx_slot));
            _ = try self.emit(.load_local, @intCast(limit_slot));
            _ = try self.emit(.lt, 0);
            const exit_cond_jmp = try self.emit(.jmp_if_zero, 0);

            const loop_body_ip = self.op_count;

            _ = try self.emit(.load_local, @intCast(idx_slot));
            if (arr.is_state) {
                _ = try self.emit(.load_state_elem, @intCast(arr.base_slot));
            } else {
                _ = try self.emit(.load_local_elem, @intCast(arr.base_slot));
            }
            _ = try self.emit(.store_local, @intCast(v_slot));

            const had_val = try self.parseBlock();
            if (had_val) {
                _ = try self.emit(.pop, 0);
            }

            const continue_ip = self.op_count;
            const current_loop = self.loops[self.loop_depth - 1];
            for (current_loop.continues[0..current_loop.continue_count]) |cnt_jmp| {
                self.patchJump(cnt_jmp, continue_ip);
            }

            const packed_arg: i64 = @bitCast(
                @as(u64, @intCast(idx_slot)) |
                (@as(u64, @intCast(limit_slot)) << 16) |
                (@as(u64, @intCast(loop_body_ip)) << 32)
            );
            _ = try self.emit(.loop_step, packed_arg);
            const loop_end_ip = self.op_count;
            self.patchJump(exit_cond_jmp, loop_end_ip);

            self.loop_depth -= 1;
            for (current_loop.breaks[0..current_loop.break_count]) |brk_jmp| {
                self.patchJump(brk_jmp, loop_end_ip);
            }
            return;
        }

        var loop_var_slot: ?usize = if (var1_name) |n| (try self.addLocal(n)) else null;
        var is_infinite = false;
        var is_range = false;
        var limit_slot: usize = 0;

        if (self.match(.kw_tru)) {
            is_infinite = true;
        } else if (self.cur.tag == .number and self.cur.num_val == 1.0 and self.peek.tag == .l_brace) {
            self.advance();
            is_infinite = true;
        } else {
            const vslot = loop_var_slot orelse (try self.addLocal(""));
            loop_var_slot = vslot;
            limit_slot = try self.addLocal("");

            try self.parseExpression();
            if (self.match(.dot_dot_equal)) {
                is_range = true;
                _ = try self.emit(.store_local, @intCast(vslot));
                try self.parseExpression();
                _ = try self.emit(.push_1, 0);
                _ = try self.emit(.add, 0);
                _ = try self.emit(.store_local, @intCast(limit_slot));
            } else if (self.match(.dot_dot)) {
                is_range = true;
                _ = try self.emit(.store_local, @intCast(vslot));
                try self.parseExpression();
                _ = try self.emit(.store_local, @intCast(limit_slot));
            } else {
                _ = try self.emit(.store_local, @intCast(limit_slot));
                _ = try self.emit(.push_0, 0);
                _ = try self.emit(.store_local, @intCast(vslot));
            }
        }

        const loop_start_ip = self.op_count;
        const loop_ctx = LoopContext{ .continue_ip = loop_start_ip, .break_count = 0, .continue_count = 0 };
        self.loops[self.loop_depth] = loop_ctx;
        self.loop_depth += 1;

        var exit_cond_jmp: ?usize = null;
        if (!is_infinite) {
            const vslot = loop_var_slot.?;
            _ = try self.emit(.load_local, @intCast(vslot));
            _ = try self.emit(.load_local, @intCast(limit_slot));
            _ = try self.emit(.lt, 0);
            exit_cond_jmp = try self.emit(.jmp_if_zero, 0);
        }

        const loop_body_ip = self.op_count;

        const had_val = try self.parseBlock();
        if (had_val) {
            _ = try self.emit(.pop, 0);
        }

        const continue_ip = self.op_count;
        const current_loop = self.loops[self.loop_depth - 1];
        for (current_loop.continues[0..current_loop.continue_count]) |cnt_jmp| {
            self.patchJump(cnt_jmp, continue_ip);
        }

        if (!is_infinite) {
            const vslot = loop_var_slot.?;
            const packed_arg: i64 = @bitCast(
                @as(u64, @intCast(vslot)) |
                (@as(u64, @intCast(limit_slot)) << 16) |
                (@as(u64, @intCast(loop_body_ip)) << 32)
            );
            _ = try self.emit(.loop_step, packed_arg);
        } else {
            _ = try self.emit(.jmp, @intCast(loop_start_ip));
        }
        const loop_end_ip = self.op_count;

        if (exit_cond_jmp) |j| {
            self.patchJump(j, loop_end_ip);
        }

        self.loop_depth -= 1;
        for (current_loop.breaks[0..current_loop.break_count]) |brk_jmp| {
            self.patchJump(brk_jmp, loop_end_ip);
        }
    }

    pub fn parseExpression(self: *Compiler) CompileError!void {
        self.expr_depth += 1;
        defer self.expr_depth -= 1;
        try self.parseTernary();
    }

    fn parseTernary(self: *Compiler) CompileError!void {
        try self.parseOr();
        if (self.match(.question)) {
            const false_jmp = try self.emit(.jmp_if_zero, 0);
            try self.parseExpression();
            const exit_jmp = try self.emit(.jmp, 0);
            self.patchJump(false_jmp, self.op_count);
            _ = self.match(.colon);
            try self.parseExpression();
            self.patchJump(exit_jmp, self.op_count);
        }
    }

    fn parseOr(self: *Compiler) CompileError!void {
        try self.parseAnd();
        while (self.match(.or_or)) {
            _ = try self.emit(.dup, 0);
            const skip_jmp = try self.emit(.jmp_if_nonzero, 0);
            _ = try self.emit(.pop, 0);
            try self.parseAnd();
            self.patchJump(skip_jmp, self.op_count);
        }
    }

    fn parseAnd(self: *Compiler) CompileError!void {
        try self.parseBitOr();
        while (self.match(.and_and)) {
            _ = try self.emit(.dup, 0);
            const skip_jmp = try self.emit(.jmp_if_zero, 0);
            _ = try self.emit(.pop, 0);
            try self.parseBitOr();
            self.patchJump(skip_jmp, self.op_count);
        }
    }

    fn parseBitOr(self: *Compiler) CompileError!void {
        try self.parseBitXor();
        while (self.copy_depth == 0 and self.match(.pipe)) {
            try self.parseBitXor();
            _ = try self.emit(.bit_or, 0);
        }
    }

    fn parseBitXor(self: *Compiler) CompileError!void {
        try self.parseBitAnd();
        while (self.match(.caret)) {
            try self.parseBitAnd();
            _ = try self.emit(.bit_xor, 0);
        }
    }

    fn parseBitAnd(self: *Compiler) CompileError!void {
        try self.parseEquality();
        while (self.match(.amp)) {
            try self.parseEquality();
            _ = try self.emit(.bit_and, 0);
        }
    }

    fn parseEquality(self: *Compiler) CompileError!void {
        try self.parseRelational();
        while (true) {
            if (self.match(.equal_equal)) {
                try self.parseRelational();
                _ = try self.emit(.eq, 0);
            } else if (self.match(.bang_equal)) {
                try self.parseRelational();
                _ = try self.emit(.ne, 0);
            } else break;
        }
    }

    fn parseRelational(self: *Compiler) CompileError!void {
        try self.parseShift();
        while (true) {
            if (self.match(.less)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseShift();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.lt, 0);
                self.last_expr_type = .num;
            } else if (self.match(.less_equal)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseShift();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.le, 0);
                self.last_expr_type = .num;
            } else if (self.match(.greater)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseShift();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.gt, 0);
                self.last_expr_type = .num;
            } else if (self.match(.greater_equal)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseShift();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.ge, 0);
                self.last_expr_type = .num;
            } else break;
        }
    }

    fn parseShift(self: *Compiler) CompileError!void {
        try self.parseAddSub();
        while (true) {
            if (self.match(.less_less)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseAddSub();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.shl, 0);
                self.last_expr_type = .num;
            } else if (self.match(.greater_greater)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseAddSub();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.shr, 0);
                self.last_expr_type = .num;
            } else break;
        }
    }

    fn parseAddSub(self: *Compiler) CompileError!void {
        try self.parseMulDiv();
        while (true) {
            if (self.match(.plus)) {
                const lhs_type = self.last_expr_type;
                try self.parseMulDiv();
                const rhs_type = self.last_expr_type;
                _ = try self.emit(.add, 0);
                if (lhs_type == .str or rhs_type == .str) {
                    self.last_expr_type = .str;
                } else if (lhs_type == .num and rhs_type == .num) {
                    self.last_expr_type = .num;
                } else {
                    self.last_expr_type = .unknown;
                }
            } else if (self.match(.minus)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseMulDiv();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.sub, 0);
                self.last_expr_type = .num;
            } else break;
        }
    }

    fn parseMulDiv(self: *Compiler) CompileError!void {
        try self.parseUnary();
        while (true) {
            if (self.match(.star)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseUnary();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.mul, 0);
                self.last_expr_type = .num;
            } else if (self.match(.slash)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseUnary();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.div, 0);
                self.last_expr_type = .num;
            } else if (self.match(.percent)) {
                const lhs_type = self.last_expr_type;
                if (lhs_type == .str) return error.TypeMismatch;
                try self.parseUnary();
                if (self.last_expr_type == .str) return error.TypeMismatch;
                _ = try self.emit(.mod, 0);
                self.last_expr_type = .num;
            } else break;
        }
    }

    fn parseUnary(self: *Compiler) CompileError!void {
        if (self.match(.minus)) {
            try self.parseUnary();
            if (self.last_expr_type == .str) return error.TypeMismatch;
            _ = try self.emit(.neg, 0);
            self.last_expr_type = .num;
        } else if (self.match(.bang)) {
            try self.parseUnary();
            _ = try self.emit(.lnot, 0);
            self.last_expr_type = .num;
        } else if (self.match(.tilde)) {
            try self.parseUnary();
            if (self.last_expr_type == .str) return error.TypeMismatch;
            _ = try self.emit(.bit_not, 0);
            self.last_expr_type = .num;
        } else {
            try self.parsePrimary();
        }
    }

    fn parsePrimary(self: *Compiler) CompileError!void {
        if (self.cur.tag == .number) {
            const val = self.cur.num_val;
            self.advance();
            self.last_expr_type = .num;
            if (val == 0.0) {
                _ = try self.emit(.push_0, 0);
            } else if (val == 1.0) {
                _ = try self.emit(.push_1, 0);
            } else {
                _ = try self.emit(.push_num, @bitCast(val));
            }
            return;
        }

        if (self.match(.kw_tru)) {
            self.last_expr_type = .num;
            _ = try self.emit(.push_1, 0);
            return;
        }
        if (self.match(.kw_fls)) {
            self.last_expr_type = .num;
            _ = try self.emit(.push_0, 0);
            return;
        }

        if (self.cur.tag == .host_tag) {
            const name = self.cur.text;
            self.advance();
            const host_idx = try self.getOrAddHostTag(name);
            self.last_expr_type = .num;
            _ = try self.emit(.load_host, @intCast(host_idx));
            return;
        }

        if (self.cur.tag == .string) {
            const raw_str = self.cur.text;
            self.advance();
            try self.compileInterpolatedString(raw_str);
            self.last_expr_type = .str;
            return;
        }

        if (self.match(.l_paren)) {
            try self.parseExpression();
            _ = self.match(.r_paren);
            return;
        }

        if (self.match(.pipe)) {
            self.copy_depth += 1;
            defer self.copy_depth -= 1;
            try self.parseExpression();
            if (!self.match(.pipe)) return error.SyntaxError;
            return;
        }

        if (self.match(.kw_jmp)) {
            _ = try self.parseJmp(true);
            self.last_expr_type = .unknown;
            return;
        }

        if (self.cur.tag == .l_brace) {
            const has_val = try self.parseBlock();
            if (!has_val) {
                _ = try self.emit(.push_0, 0);
            }
            return;
        }

        if (self.cur.tag == .l_bracket) {
            var arr_info = ArrayInfo{};
            arr_info.base_slot = self.local_count;
            arr_info.is_state = false;
            try self.parseArrayLiteral(&arr_info);
            if (self.cur.tag == .l_bracket) {
                try self.emitArrayIndexing(arr_info);
                self.last_expr_type = if (arr_info.elem_type != .unknown) arr_info.elem_type else .num;
                return;
            }
            _ = try self.emit(.push_num, @bitCast(@as(f64, @floatFromInt(arr_info.dims[0]))));
            self.last_expr_type = .num;
            return;
        }

        if (self.cur.tag == .ident) {
            const name = self.cur.text;

            if (self.findStructVar(name)) |svar| {
                if (self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    if (self.cur.tag != .ident) return error.SyntaxError;
                    var fname = self.cur.text;
                    self.advance();
                    var curr_sdef = self.findStructDef(svar.struct_name) orelse return error.SyntaxError;
                    var total_offset: usize = 0;
                    var is_method = false;
                    var method_info: ?StructDef.StructMethod = null;

                    if (curr_sdef.findMethod(fname)) |m| {
                        if (self.cur.tag == .l_paren) {
                            is_method = true;
                            method_info = m;
                        }
                    }

                    if (!is_method) {
                        var field = curr_sdef.findField(fname) orelse return error.UndefinedVariable;
                        total_offset += field.offset;
                        var curr_dt: DataType = field.data_type;

                        while (self.cur.tag == .dot) {
                            self.advance();
                            if (self.cur.tag != .ident) return error.SyntaxError;
                            fname = self.cur.text;
                            self.advance();
                            const child_sname = field.struct_name orelse return error.SyntaxError;
                            curr_sdef = self.findStructDef(child_sname) orelse return error.SyntaxError;
                            if (curr_sdef.findMethod(fname)) |m| {
                                if (self.cur.tag == .l_paren) {
                                    is_method = true;
                                    method_info = m;
                                    break;
                                }
                            }
                            field = curr_sdef.findField(fname) orelse return error.UndefinedVariable;
                            total_offset += field.offset;
                            curr_dt = field.data_type;
                        }

                        if (!is_method) {
                            const slot = svar.base_slot + total_offset;
                            self.last_expr_type = curr_dt;
                            if (svar.is_param_ref) {
                                _ = try self.emit(.load_local, @intCast(svar.base_slot));
                                _ = try self.emit(.load_local_elem, @intCast(total_offset));
                            } else if (svar.is_state) {
                                _ = try self.emit(.load_state, @intCast(slot));
                            } else {
                                _ = try self.emit(.load_local, @intCast(slot));
                            }
                            return;
                        }
                    }

                    const m = method_info.?;
                    var recv = SlfRecv{
                        .struct_name = curr_sdef.name,
                        .svar_base = svar.base_slot,
                        .total_off = total_offset,
                        .is_param_ref = svar.is_param_ref,
                        .is_state = svar.is_state,
                    };
                    var call_arg_count: usize = 0;
                    if (m.uses_slf) {
                        try self.emitRecvPush(&recv);
                        call_arg_count += 1;
                    }

                    _ = self.match(.l_paren);
                    while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                        try self.parseExpression();
                        call_arg_count += 1;
                        if (!self.match(.comma)) break;
                    }
                    if (!self.match(.r_paren)) return error.SyntaxError;

                    try self.emitCall(m.func_name, call_arg_count);
                    if (self.expr_depth == 1 and m.uses_slf and self.methodReturnsSlf(m, recv.struct_name)) {
                        self.last_chain_recv = recv;
                    }
                    try self.maybeParseSlfChain(recv, m);
                    return;
                }
            }

            if (self.findStructDef(name)) |sdef| {
                if (self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    if (self.cur.tag != .ident) return error.SyntaxError;
                    const mname = self.cur.text;
                    self.advance();
                    if (sdef.findMethod(mname)) |m| {
                        _ = self.match(.l_paren);
                        var call_arg_count: usize = 0;
                        while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                            try self.parseExpression();
                            call_arg_count += 1;
                            if (!self.match(.comma)) break;
                        }
                        if (!self.match(.r_paren)) return error.SyntaxError;
                        try self.emitCall(m.func_name, call_arg_count);
                        return;
                    }
                }
            }

            if (self.findArray(name)) |arr| {
                if (self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    if (self.cur.tag == .ident and std.mem.eql(u8, self.cur.text, "len")) {
                        self.advance();
                        _ = try self.emit(.push_num, @bitCast(@as(f64, @floatFromInt(arr.dims[0]))));
                        self.last_expr_type = .num;
                        return;
                    }
                }
                if (self.peek.tag == .l_bracket) {
                    self.advance();
                    try self.emitArrayIndexing(arr);
                    if (self.match(.dot)) {
                        if (self.cur.tag == .ident and std.mem.eql(u8, self.cur.text, "len")) {
                            self.advance();
                            _ = try self.emit(.pop, 0);
                            _ = try self.emit(.push_num, @bitCast(@as(f64, @floatFromInt(arr.dims[1]))));
                            self.last_expr_type = .num;
                        }
                    } else {
                        self.last_expr_type = if (arr.elem_type != .unknown) arr.elem_type else .num;
                    }
                    return;
                }
            }

            if (self.findModule(name)) |mod| {
                if (mod == .std and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "math") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseMathMember();
                        self.last_expr_type = .num;
                        return;
                    }
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "dbg") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseDbgMember();
                        return;
                    }
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "fmt") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseFmtMember();
                        return;
                    }
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "rng") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseRngMember();
                        return;
                    }
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "str") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseStrMember();
                        return;
                    }
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "hsh") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseHshMember();
                        return;
                    }
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "nos") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseNosMember();
                        return;
                    }
                } else if (mod == .math and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseMathMember();
                    self.last_expr_type = .num;
                    return;
                } else if (mod == .dbg and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseDbgMember();
                    return;
                } else if (mod == .fmt and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseFmtMember();
                    return;
                } else if (mod == .rng and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseRngMember();
                    return;
                } else if (mod == .str and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseStrMember();
                    return;
                } else if (mod == .hsh and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseHshMember();
                    return;
                } else if (mod == .nos and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseNosMember();
                    return;
                }
            }

            self.advance();

            if (self.match(.l_paren)) {
                var arg_count: usize = 0;
                const fidx_opt = self.findFunc(name);
                while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                    var handled = false;
                    if (fidx_opt) |fi| {
                        if (arg_count < self.funcs[fi].param_count) {
                            const p_annot = self.func_param_annots[fi][arg_count];
                            if (p_annot != null and p_annot.?.struct_name != null) {
                                const sname = p_annot.?.struct_name.?;
                                const sdef = self.findStructDef(sname) orelse return error.UnknownType;
                                if (self.cur.tag == .ident and self.peek.tag != .dot and self.findStructVar(self.cur.text) != null) {
                                    const src_svar = self.findStructVar(self.cur.text).?;
                                    self.advance();
                                    if (src_svar.is_param_ref) {
                                        _ = try self.emit(.load_local, @intCast(src_svar.base_slot));
                                        const adj: f64 = @floatFromInt(-@as(i64, @intCast(self.local_count)));
                                        if (adj != 0.0) {
                                            _ = try self.emit(.push_num, @bitCast(adj));
                                            _ = try self.emit(.add, 0);
                                        }
                                        handled = true;
                                    } else {
                                        var base_slot = src_svar.base_slot;
                                        if (src_svar.is_state) {
                                            const tmp_base = self.local_count;
                                            for (0..sdef.total_slots) |si| {
                                                _ = try self.addLocal("");
                                                _ = try self.emit(.load_state, @intCast(src_svar.base_slot + si));
                                                _ = try self.emit(.store_local, @intCast(tmp_base + si));
                                            }
                                            base_slot = tmp_base;
                                        }
                                        const rel_off: f64 = @floatFromInt(@as(i64, @intCast(base_slot)) - @as(i64, @intCast(self.local_count)));
                                        _ = try self.emit(.push_num, @bitCast(rel_off));
                                        handled = true;
                                    }
                                }
                            }
                        }
                    }
                    if (!handled) {
                        try self.parseExpression();
                    }
                    arg_count += 1;
                    if (!self.match(.comma)) break;
                }
                _ = self.match(.r_paren);

                try self.emitCall(name, arg_count);
                return;
            }

            if (self.findLocal(name)) |slot| {
                self.last_expr_type = self.local_types[slot];
                _ = try self.emit(.load_local, @intCast(slot));
                return;
            }

            if (self.findState(name)) |slot| {
                self.last_expr_type = self.state_types[slot];
                _ = try self.emit(.load_state, @intCast(slot));
                return;
            }

            return error.UndefinedVariable;
        }

        return error.SyntaxError;
    }

    fn parseMathMember(self: *Compiler) CompileError!void {
        if (self.cur.tag != .ident) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        if (std.ascii.eqlIgnoreCase(member, "pi")) {
            _ = try self.emit(.push_num, @bitCast(@as(f64, std.math.pi)));
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "e")) {
            _ = try self.emit(.push_num, @bitCast(@as(f64, std.math.e)));
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "tau")) {
            _ = try self.emit(.push_num, @bitCast(@as(f64, std.math.tau)));
            return;
        }

        if (findBuiltin(member)) |b| {
            _ = self.match(.l_paren);
            var arg_count: u8 = 0;
            while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                try self.parseExpression();
                arg_count += 1;
                if (!self.match(.comma)) break;
            }
            _ = self.match(.r_paren);

            const packed_arg: i64 = @as(i64, @intFromEnum(b.id)) | (@as(i64, arg_count) << 8);
            _ = try self.emit(.call_builtin, packed_arg);
            return;
        }

        return error.SyntaxError;
    }

    fn emitBuiltinCall(self: *Compiler, id: Builtin, arg_count: u8) CompileError!void {
        const packed_arg: i64 = @as(i64, @intFromEnum(id)) | (@as(i64, arg_count) << 8);
        _ = try self.emit(.call_builtin, packed_arg);
    }

    fn parseDbgMember(self: *Compiler) CompileError!void {
        // NOTE: `out` lexes as kw_out, so match on text, not tag.
        if (self.cur.tag != .ident and self.cur.tag != .kw_out) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        if (std.ascii.eqlIgnoreCase(member, "out")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.dbg_out, 1);
            self.last_expr_type = .num;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "in")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.dbg_in, 0);
            self.last_expr_type = .str;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "asr")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            var arg_count: u8 = 1;
            if (self.match(.comma)) {
                try self.parseExpression();
                arg_count = 2;
            }
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.dbg_asr, arg_count);
            self.last_expr_type = .num;
            return;
        }
        return error.SyntaxError;
    }

    fn parseFmtMember(self: *Compiler) CompileError!void {
        if (self.cur.tag != .ident) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        // Fmt.f(fmtstr, args...): total operands capped at 8 (stack-based).
        if (std.ascii.eqlIgnoreCase(member, "f")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            var arg_count: u8 = 0;
            while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                if (arg_count >= 8) return error.TooManyLocals;
                try self.parseExpression();
                arg_count += 1;
                if (!self.match(.comma)) break;
            }
            if (!self.match(.r_paren)) return error.SyntaxError;
            if (arg_count < 1) return error.SyntaxError;
            try self.emitBuiltinCall(.fmt, arg_count);
            self.last_expr_type = .str;
            return;
        }
        return error.SyntaxError;
    }

    fn parseRngMember(self: *Compiler) CompileError!void {
        if (self.cur.tag != .ident) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        if (std.ascii.eqlIgnoreCase(member, "next")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.rng_next, 0);
            self.last_expr_type = .num;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "range")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.comma)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.rng_range, 2);
            self.last_expr_type = .num;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "seed")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.rng_seed, 1);
            self.last_expr_type = .num;
            return;
        }
        return error.SyntaxError;
    }

    fn parseStrMember(self: *Compiler) CompileError!void {
        if (self.cur.tag != .ident) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        if (std.ascii.eqlIgnoreCase(member, "len")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.str_len, 1);
            self.last_expr_type = .num;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "sub")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.comma)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.comma)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.str_sub, 3);
            self.last_expr_type = .str;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "find")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.comma)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.str_find, 2);
            self.last_expr_type = .num;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "num")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.str_num, 1);
            self.last_expr_type = .num;
            return;
        }
        return error.SyntaxError;
    }

    fn parseHshMember(self: *Compiler) CompileError!void {
        if (self.cur.tag != .ident) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        if (std.ascii.eqlIgnoreCase(member, "fnv")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.hsh_fnv, 1);
            self.last_expr_type = .num;
            return;
        }
        return error.SyntaxError;
    }

    fn parseNosMember(self: *Compiler) CompileError!void {
        if (self.cur.tag != .ident) return error.SyntaxError;
        const member = self.cur.text;
        self.advance();

        if (std.ascii.eqlIgnoreCase(member, "per")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.nos_per, 1);
            self.last_expr_type = .num;
            return;
        }
        if (std.ascii.eqlIgnoreCase(member, "per2")) {
            if (!self.match(.l_paren)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.comma)) return error.SyntaxError;
            try self.parseExpression();
            if (!self.match(.r_paren)) return error.SyntaxError;
            try self.emitBuiltinCall(.nos_per2, 2);
            self.last_expr_type = .num;
            return;
        }
        return error.SyntaxError;
    }

    fn compileInterpolatedString(self: *Compiler, raw: []const u8) CompileError!void {
        const content = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;

        var i: usize = 0;
        var seg_start: usize = 0;
        var parts: usize = 0;

        while (i < content.len) {
            if (content[i] == '{') {
                if (i + 1 < content.len and content[i + 1] == '{') {
                    i += 2;
                    continue;
                }

                if (i > seg_start) {
                    const s = content[seg_start..i];
                    const str_arg = try self.addStringUnescaped(s);
                    _ = try self.emit(.push_str, str_arg);
                    if (parts > 0) _ = try self.emit(.add, 0);
                    parts += 1;
                }

                i += 1;
                const expr_start = i;
                var depth: usize = 1;
                var in_expr_str = false;
                while (i < content.len and depth > 0) {
                    if (content[i] == '\\' and i + 1 < content.len and content[i + 1] == '"') {
                        i += 2;
                        continue;
                    }
                    if (content[i] == '"') {
                        in_expr_str = !in_expr_str;
                    } else if (!in_expr_str) {
                        if (content[i] == '{') depth += 1;
                        if (content[i] == '}') depth -= 1;
                    }
                    if (depth > 0) i += 1;
                }
                const expr_raw = content[expr_start..i];
                if (i < content.len) i += 1;
                seg_start = i;

                var expr_buf: [256]u8 = undefined;
                var expr_len: usize = 0;
                var ei: usize = 0;
                while (ei < expr_raw.len) {
                    if (expr_raw[ei] == '\\' and ei + 1 < expr_raw.len and expr_raw[ei + 1] == '"') {
                        if (expr_len < expr_buf.len) {
                            expr_buf[expr_len] = '"';
                            expr_len += 1;
                        }
                        ei += 2;
                    } else {
                        if (expr_len < expr_buf.len) {
                            expr_buf[expr_len] = expr_raw[ei];
                            expr_len += 1;
                        }
                        ei += 1;
                    }
                }
                const expr_src = expr_buf[0..expr_len];

                var sub_c = Compiler.init(expr_src, self.allocator);
                sub_c.string_bytes = self.string_bytes;
                sub_c.string_len = self.string_len;
                sub_c.locals = self.locals;
                sub_c.local_types = self.local_types;
                sub_c.local_consts = self.local_consts;
                sub_c.local_count = self.local_count;
                sub_c.states = self.states;
                sub_c.state_types = self.state_types;
                sub_c.state_count = self.state_count;
                sub_c.host_tags = self.host_tags;
                sub_c.host_tag_count = self.host_tag_count;
                sub_c.funcs = self.funcs;
                sub_c.func_count = self.func_count;
                sub_c.modules = self.modules;
                sub_c.module_count = self.module_count;
                sub_c.arrays = self.arrays;
                sub_c.array_count = self.array_count;

                try sub_c.parseExpression();
                self.string_bytes = sub_c.string_bytes;
                self.string_len = sub_c.string_len;

                const base_op = self.op_count;
                for (sub_c.ops[0..sub_c.op_count]) |op| {
                    if (op.code == .load_host) {
                        const hname = sub_c.host_tags[@intCast(op.arg)];
                        const hidx = try self.getOrAddHostTag(hname);
                        _ = try self.emit(.load_host, @intCast(hidx));
                    } else if (op.code == .jmp or op.code == .jmp_if_zero or op.code == .jmp_if_nonzero) {
                        _ = try self.emit(op.code, op.arg + @as(i64, @intCast(base_op)));
                    } else {
                        _ = try self.emit(op.code, op.arg);
                    }
                }

                for (sub_c.call_fixups[0..sub_c.call_fixup_count]) |cf| {
                    if (cf.func_name.len > 0) {
                        if (self.call_fixup_count >= 64) return error.TooManyCalls;
                        self.call_fixups[self.call_fixup_count] = .{
                            .op_idx = base_op + cf.op_idx,
                            .func_name = cf.func_name,
                            .frame_offset = cf.frame_offset,
                            .arg_count = cf.arg_count,
                        };
                        self.call_fixup_count += 1;
                    }
                }

                if (parts > 0) _ = try self.emit(.add, 0);
                parts += 1;
                continue;
            }

            if (content[i] == '}' and i + 1 < content.len and content[i + 1] == '}') {
                i += 2;
                continue;
            }

            i += 1;
        }

        if (seg_start < content.len or parts == 0) {
            const s = content[seg_start..content.len];
            const str_arg = try self.addStringUnescaped(s);
            _ = try self.emit(.push_str, str_arg);
            if (parts > 0) _ = try self.emit(.add, 0);
        }
    }
};

pub fn compileSource(src: []const u8, allocator: std.mem.Allocator) CompileError!*Prog {
    var c = Compiler.init(src, allocator);
    return try c.compile();
}

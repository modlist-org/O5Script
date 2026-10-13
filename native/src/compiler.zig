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

pub const CompileError = error{
    OutOfOps,
    OutOfMemory,
    StringPoolOverflow,
    TooManyHostTags,
    TooManyLocals,
    TooManyStates,
    SyntaxError,
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
    kw_fl,
    kw_el,
    kw_lop,
    kw_out,
    kw_skp,
    kw_fun,
    kw_ret,
    kw_tag,
    kw_tru,
    kw_fls,

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

    l_paren,
    r_paren,
    l_brace,
    r_brace,
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
                else if (std.mem.eql(u8, ident, "fl")) TokenType.kw_fl
                else if (std.mem.eql(u8, ident, "el")) TokenType.kw_el
                else if (std.mem.eql(u8, ident, "lop")) TokenType.kw_lop
                else if (std.mem.eql(u8, ident, "out")) TokenType.kw_out
                else if (std.mem.eql(u8, ident, "skp")) TokenType.kw_skp
                else if (std.mem.eql(u8, ident, "fun")) TokenType.kw_fun
                else if (std.mem.eql(u8, ident, "ret")) TokenType.kw_ret
                else if (std.mem.eql(u8, ident, "tag")) TokenType.kw_tag
                else if (std.mem.eql(u8, ident, "tru")) TokenType.kw_tru
                else if (std.mem.eql(u8, ident, "fls")) TokenType.kw_fls
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
                if (self.matchChar('.')) return .{ .tag = .dot_dot, .text = ".." };
                return .{ .tag = .dot, .text = "." };
            },
            '@' => return .{ .tag = .at, .text = "@" },
            '?' => return .{ .tag = .question, .text = "?" },
            ':' => return .{ .tag = .colon, .text = ":" },
            '(' => return .{ .tag = .l_paren, .text = "(" },
            ')' => return .{ .tag = .r_paren, .text = ")" },
            '{' => return .{ .tag = .l_brace, .text = "{" },
            '}' => return .{ .tag = .r_brace, .text = "}" },
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
    continue_ip: usize,
    breaks: [max_breaks]usize = undefined,
    break_count: usize = 0,
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
    local_count: usize = 0,

    states: [max_locals][]const u8 = undefined,
    state_inits: [max_locals]Value = undefined,
    state_count: usize = 0,

    host_tags: [max_host_tags][]const u8 = undefined,
    host_tag_count: usize = 0,

    tags: [max_tags]TagDef = undefined,
    tag_count: usize = 0,

    funcs: [max_funcs]FuncDef = undefined,
    func_count: usize = 0,

    modules: [16]ModuleBinding = undefined,
    module_count: usize = 0,

    loops: [max_loops]LoopContext = undefined,
    loop_depth: usize = 0,

    allocator: std.mem.Allocator,

    pub const ModuleKind = enum {
        std,
        math,
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
        const offset = self.string_len;
        const len = text.len;
        if (offset + len > self.string_bytes.len) return error.StringPoolOverflow;
        @memcpy(self.string_bytes[offset .. offset + len], text);
        self.string_len += len;
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
        self.local_count += 1;
        return idx;
    }

    fn findState(self: *Compiler, name: []const u8) ?usize {
        for (self.states[0..self.state_count], 0..) |state_name, i| {
            if (std.mem.eql(u8, state_name, name)) return i;
        }
        return null;
    }

    fn addState(self: *Compiler, name: []const u8) CompileError!usize {
        if (self.state_count >= max_locals) return error.TooManyStates;
        const idx = self.state_count;
        self.states[idx] = name;
        self.state_inits[idx] = Value.fromNum(0.0);
        self.state_count += 1;
        return idx;
    }

    fn findFunc(self: *Compiler, name: []const u8) ?usize {
        for (self.funcs[0..self.func_count], 0..) |f, i| {
            if (std.mem.eql(u8, f.name, name)) return i;
        }
        return null;
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

    pub fn compile(self: *Compiler) CompileError!*Prog {
        while (self.cur.tag != .eof) {
            try self.parseStatement();
        }
        _ = try self.emit(.halt, 0);

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

    fn skipTypeAnnotation(self: *Compiler) void {
        if (self.match(.colon)) {
            if (self.cur.tag == .ident) {
                self.advance();
            }
        }
    }

    fn parseStatement(self: *Compiler) CompileError!void {
        if (self.match(.kw_let)) {
            const name = self.cur.text;
            self.advance();
            self.skipTypeAnnotation();
            if (self.match(.equal)) {
                try self.parseExpression();
            } else {
                _ = try self.emit(.push_0, 0);
            }
            const slot = try self.addLocal(name);
            _ = try self.emit(.store_local, @intCast(slot));
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_sta)) {
            const name = self.cur.text;
            self.advance();
            self.skipTypeAnnotation();
            var init_val: f64 = 0.0;
            if (self.match(.equal)) {
                if (self.cur.tag == .number) {
                    init_val = self.cur.num_val;
                    self.advance();
                } else if (self.match(.minus) and self.cur.tag == .number) {
                    init_val = -self.cur.num_val;
                    self.advance();
                } else {
                    try self.parseExpression();
                }
            }
            const slot = try self.addState(name);
            self.state_inits[slot] = Value.fromNum(init_val);
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_con)) {
            const name = self.cur.text;
            self.advance();
            self.skipTypeAnnotation();
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
                    }
                }
            }

            try self.parseExpression();
            const slot = try self.addLocal(name);
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
            if (self.loop_depth > 0) {
                const jmp_idx = try self.emit(.jmp, 0);
                var loop = &self.loops[self.loop_depth - 1];
                if (loop.break_count < max_breaks) {
                    loop.breaks[loop.break_count] = jmp_idx;
                    loop.break_count += 1;
                }
            }
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_skp)) {
            if (self.loop_depth > 0) {
                const loop = self.loops[self.loop_depth - 1];
                _ = try self.emit(.jmp, @intCast(loop.continue_ip));
            }
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_ret)) {
            if (self.cur.tag != .semicolon and self.cur.tag != .r_brace) {
                try self.parseExpression();
            } else {
                _ = try self.emit(.push_0, 0);
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
                try self.parseBlock();
            } else {
                try self.parseExpression();
            }
            _ = try self.emit(.halt, 0);
            self.patchJump(skip_jmp, self.op_count);
            _ = self.match(.semicolon);
            return;
        }

        if (self.match(.kw_fun)) {
            const name = self.cur.text;
            self.advance();
            _ = self.match(.l_paren);

            var param_count: usize = 0;
            var param_names: [8][]const u8 = undefined;
            while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                param_names[param_count] = self.cur.text;
                param_count += 1;
                self.advance();
                self.skipTypeAnnotation();
                if (!self.match(.comma)) break;
            }
            _ = self.match(.r_paren);
            self.skipTypeAnnotation();

            const skip_jmp = try self.emit(.jmp, 0);
            const entry_ip = self.op_count;
            if (self.func_count < max_funcs) {
                self.funcs[self.func_count] = .{ .name = name, .entry_ip = entry_ip, .param_count = param_count };
                self.func_count += 1;
            }

            var p = param_count;
            while (p > 0) {
                p -= 1;
                const slot = try self.addLocal(param_names[p]);
                _ = try self.emit(.store_local, @intCast(slot));
            }

            if (self.match(.arrow)) {
                try self.parseExpression();
                _ = try self.emit(.ret, 0);
            } else if (self.cur.tag == .l_brace) {
                try self.parseBlock();
                _ = try self.emit(.ret, 0);
            }
            self.patchJump(skip_jmp, self.op_count);
            _ = self.match(.semicolon);
            return;
        }

        if (self.cur.tag == .l_brace) {
            try self.parseBlock();
            _ = self.match(.semicolon);
            if (self.cur.tag != .eof and self.cur.tag != .r_brace) {
                _ = try self.emit(.pop, 0);
            }
            return;
        }

        if (self.cur.tag == .ident and (self.peek.tag == .equal or self.peek.tag == .plus_equal or self.peek.tag == .minus_equal or self.peek.tag == .star_equal or self.peek.tag == .slash_equal)) {
            const name = self.cur.text;
            self.advance();
            const op_tok = self.cur.tag;
            self.advance();

            const is_local = self.findLocal(name);
            const is_state = self.findState(name);

            if (op_tok != .equal) {
                if (is_local) |slot| {
                    _ = try self.emit(.load_local, @intCast(slot));
                } else if (is_state) |slot| {
                    _ = try self.emit(.load_state, @intCast(slot));
                }
            }

            try self.parseExpression();

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
        }
    }

    fn parseBlock(self: *Compiler) CompileError!void {
        _ = self.match(.l_brace);
        const saved_locals = self.local_count;

        var had_expr = false;
        while (self.cur.tag != .r_brace and self.cur.tag != .eof) {
            try self.parseStatement();
            had_expr = true;
        }
        _ = self.match(.r_brace);

        if (!had_expr) {
            _ = try self.emit(.push_0, 0);
        }
        self.local_count = saved_locals;
    }

    fn parseIfStatement(self: *Compiler) CompileError!void {
        try self.parseExpression();
        const false_jmp = try self.emit(.jmp_if_zero, 0);

        try self.parseBlock();
        const exit_jmp = try self.emit(.jmp, 0);
        self.patchJump(false_jmp, self.op_count);

        var end_jumps: [16]usize = undefined;
        var end_jump_count: usize = 0;
        end_jumps[end_jump_count] = exit_jmp;
        end_jump_count += 1;

        while (self.match(.kw_fl)) {
            try self.parseExpression();
            const next_false = try self.emit(.jmp_if_zero, 0);
            try self.parseBlock();
            if (end_jump_count < 16) {
                end_jumps[end_jump_count] = try self.emit(.jmp, 0);
                end_jump_count += 1;
            }
            self.patchJump(next_false, self.op_count);
        }

        if (self.match(.kw_el)) {
            try self.parseBlock();
        }

        for (end_jumps[0..end_jump_count]) |j| {
            self.patchJump(j, self.op_count);
        }
    }

    fn parseLoop(self: *Compiler) CompileError!void {
        var loop_var_slot: ?usize = null;
        if (self.match(.pipe)) {
            const var_name = self.cur.text;
            self.advance();
            _ = self.match(.pipe);
            loop_var_slot = try self.addLocal(var_name);
        }

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
            if (self.match(.dot_dot)) {
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
        const loop_ctx = LoopContext{ .continue_ip = loop_start_ip };
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

        try self.parseBlock();

        const continue_ip = self.op_count;
        self.loops[self.loop_depth - 1].continue_ip = continue_ip;

        if (!is_infinite) {
            const vslot = loop_var_slot.?;
            _ = try self.emit(.load_local, @intCast(vslot));
            _ = try self.emit(.push_1, 0);
            _ = try self.emit(.add, 0);
            _ = try self.emit(.store_local, @intCast(vslot));
        }

        _ = try self.emit(.jmp, @intCast(loop_start_ip));
        const loop_end_ip = self.op_count;

        if (exit_cond_jmp) |j| {
            self.patchJump(j, loop_end_ip);
        }

        self.loop_depth -= 1;
        const current_loop = self.loops[self.loop_depth];
        for (current_loop.breaks[0..current_loop.break_count]) |brk_jmp| {
            self.patchJump(brk_jmp, loop_end_ip);
        }
    }

    pub fn parseExpression(self: *Compiler) CompileError!void {
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
        while (self.match(.pipe)) {
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
                try self.parseShift();
                _ = try self.emit(.lt, 0);
            } else if (self.match(.less_equal)) {
                try self.parseShift();
                _ = try self.emit(.le, 0);
            } else if (self.match(.greater)) {
                try self.parseShift();
                _ = try self.emit(.gt, 0);
            } else if (self.match(.greater_equal)) {
                try self.parseShift();
                _ = try self.emit(.ge, 0);
            } else break;
        }
    }

    fn parseShift(self: *Compiler) CompileError!void {
        try self.parseAddSub();
        while (true) {
            if (self.match(.less_less)) {
                try self.parseAddSub();
                _ = try self.emit(.shl, 0);
            } else if (self.match(.greater_greater)) {
                try self.parseAddSub();
                _ = try self.emit(.shr, 0);
            } else break;
        }
    }

    fn parseAddSub(self: *Compiler) CompileError!void {
        try self.parseMulDiv();
        while (true) {
            if (self.match(.plus)) {
                try self.parseMulDiv();
                _ = try self.emit(.add, 0);
            } else if (self.match(.minus)) {
                try self.parseMulDiv();
                _ = try self.emit(.sub, 0);
            } else break;
        }
    }

    fn parseMulDiv(self: *Compiler) CompileError!void {
        try self.parseUnary();
        while (true) {
            if (self.match(.star)) {
                try self.parseUnary();
                _ = try self.emit(.mul, 0);
            } else if (self.match(.slash)) {
                try self.parseUnary();
                _ = try self.emit(.div, 0);
            } else if (self.match(.percent)) {
                try self.parseUnary();
                _ = try self.emit(.mod, 0);
            } else break;
        }
    }

    fn parseUnary(self: *Compiler) CompileError!void {
        if (self.match(.minus)) {
            try self.parseUnary();
            _ = try self.emit(.neg, 0);
        } else if (self.match(.bang)) {
            try self.parseUnary();
            _ = try self.emit(.lnot, 0);
        } else if (self.match(.tilde)) {
            try self.parseUnary();
            _ = try self.emit(.bit_not, 0);
        } else {
            try self.parsePrimary();
        }
    }

    fn parsePrimary(self: *Compiler) CompileError!void {
        if (self.cur.tag == .number) {
            const val = self.cur.num_val;
            self.advance();
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
            _ = try self.emit(.push_1, 0);
            return;
        }
        if (self.match(.kw_fls)) {
            _ = try self.emit(.push_0, 0);
            return;
        }

        if (self.cur.tag == .host_tag) {
            const name = self.cur.text;
            self.advance();
            const host_idx = try self.getOrAddHostTag(name);
            _ = try self.emit(.load_host, @intCast(host_idx));
            return;
        }

        if (self.cur.tag == .string) {
            const raw_str = self.cur.text;
            self.advance();
            try self.compileInterpolatedString(raw_str);
            return;
        }

        if (self.match(.l_paren)) {
            try self.parseExpression();
            _ = self.match(.r_paren);
            return;
        }

        if (self.cur.tag == .l_brace) {
            try self.parseBlock();
            return;
        }

        if (self.cur.tag == .ident) {
            const name = self.cur.text;

            if (self.findModule(name)) |mod| {
                if (mod == .std and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    if (self.cur.tag == .ident and std.ascii.eqlIgnoreCase(self.cur.text, "math") and self.peek.tag == .dot) {
                        self.advance();
                        self.advance();
                        try self.parseMathMember();
                        return;
                    }
                } else if (mod == .math and self.peek.tag == .dot) {
                    self.advance();
                    self.advance();
                    try self.parseMathMember();
                    return;
                }
            }

            self.advance();

            if (self.match(.l_paren)) {
                var arg_count: u8 = 0;
                while (self.cur.tag != .r_paren and self.cur.tag != .eof) {
                    try self.parseExpression();
                    arg_count += 1;
                    if (!self.match(.comma)) break;
                }
                _ = self.match(.r_paren);

                if (self.findFunc(name)) |fidx| {
                    const func = self.funcs[fidx];
                    _ = try self.emit(.call, @intCast(func.entry_ip));
                } else {
                    _ = try self.emit(.push_0, 0);
                }
                return;
            }

            if (self.findLocal(name)) |slot| {
                _ = try self.emit(.load_local, @intCast(slot));
                return;
            }

            if (self.findState(name)) |slot| {
                _ = try self.emit(.load_state, @intCast(slot));
                return;
            }

            _ = try self.emit(.push_0, 0);
            return;
        }

        _ = try self.emit(.push_0, 0);
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
                    const str_arg = try self.addString(s);
                    _ = try self.emit(.push_str, str_arg);
                    if (parts > 0) _ = try self.emit(.add, 0);
                    parts += 1;
                }

                i += 1;
                const expr_start = i;
                var depth: usize = 1;
                while (i < content.len and depth > 0) {
                    if (content[i] == '{') depth += 1;
                    if (content[i] == '}') depth -= 1;
                    if (depth > 0) i += 1;
                }
                const expr_src = content[expr_start..i];
                if (i < content.len) i += 1;
                seg_start = i;

                var sub_c = Compiler.init(expr_src, self.allocator);
                sub_c.locals = self.locals;
                sub_c.local_count = self.local_count;
                sub_c.states = self.states;
                sub_c.state_count = self.state_count;
                sub_c.host_tags = self.host_tags;
                sub_c.host_tag_count = self.host_tag_count;
                sub_c.modules = self.modules;
                sub_c.module_count = self.module_count;

                try sub_c.parseExpression();

                for (sub_c.ops[0..sub_c.op_count]) |op| {
                    if (op.code == .load_host) {
                        const hname = sub_c.host_tags[@intCast(op.arg)];
                        const hidx = try self.getOrAddHostTag(hname);
                        _ = try self.emit(.load_host, @intCast(hidx));
                    } else {
                        _ = try self.emit(op.code, op.arg);
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
            const str_arg = try self.addString(s);
            _ = try self.emit(.push_str, str_arg);
            if (parts > 0) _ = try self.emit(.add, 0);
        }
    }
};

pub fn compileSource(src: []const u8, allocator: std.mem.Allocator) CompileError!*Prog {
    var c = Compiler.init(src, allocator);
    return try c.compile();
}

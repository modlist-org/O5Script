const std = @import("std");
const compiler = @import("compiler.zig");
const vm = @import("vm.zig");

// zig build bench -- [label]: ns per vm.run for HUD-style workloads.
// Each case asserts its result so a faster-but-wrong VM can't pass.
const Case = struct {
    name: []const u8,
    src: []const u8,
    host: []const f64 = &.{},
    expect: f64,
    runs: usize,
};

const cases = [_]Case{
    .{ .name = "host_expr", .src = "#Acc * 2 + #Combo / 10", .host = &.{ 97.5, 40 }, .expect = 199, .runs = 2_000_000 },
    .{ .name = "loop_10k", .src =
    \\let s = 0;
    \\lop |i| 0..10000 { s += i * 2 - 1; }
    \\s
    , .expect = 99980000, .runs = 2_000 },
    .{ .name = "fib_20", .src =
    \\fun fib(n: num): num {
    \\    if n < 2 { ret n; }
    \\    ret fib(n - 1) + fib(n - 2);
    \\}
    \\fib(20)
    , .expect = 6765, .runs = 200 },
    .{ .name = "struct_method_5k", .src =
    \\stu Counter {
    \\    val: num,
    \\    step: num,
    \\    add() { slf.val += slf.step; },
    \\}
    \\let c = Counter { val: 0, step: 3 };
    \\lop 5000 { c.add(); }
    \\c.val
    , .expect = 15000, .runs = 2_000 },
    .{ .name = "fmt_str", .src =
    \\con Fmt = @("std.fmt");
    \\Fmt.f("{{}} / {{}}", #Acc, #Combo) + "!"
    , .host = &.{ 97.5, 40 }, .expect = -1, .runs = 500_000 },
};

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    for (cases) |c| {
        const prog = try compiler.compileSource(c.src, allocator);
        defer prog.deinit();
        if (std.c.getenv("O5_DUMP") != null) {
            std.debug.print("== {s}\n", .{c.name});
            for (prog.ops, 0..) |op, i| std.debug.print("{d:>4} {s} {d}\n", .{ i, @tagName(op.code), op.arg });
        }
        const first = try vm.run(prog, 0, c.host);
        if (c.expect >= 0 and first.num != c.expect) {
            std.debug.print("{s}: WRONG result {d} (expected {d})\n", .{ c.name, first.num, c.expect });
            return error.WrongResult;
        }
        if (c.expect < 0 and !std.mem.eql(u8, first.toSlice(), "97.5 / 40!")) {
            std.debug.print("{s}: WRONG result '{s}'\n", .{ c.name, first.toSlice() });
            return error.WrongResult;
        }
        var best: u64 = std.math.maxInt(u64);
        for (0..5) |_| {
            const start = nowNs();
            for (0..c.runs) |_| std.mem.doNotOptimizeAway(try vm.run(prog, 0, c.host));
            best = @min(best, nowNs() - start);
        }
        std.debug.print("{s:<18} {d:>10.1} ns/run\n", .{ c.name, @as(f64, @floatFromInt(best)) / @as(f64, @floatFromInt(c.runs)) });
    }
}

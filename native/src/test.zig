const std = @import("std");
const compiler = @import("compiler.zig");
const vm = @import("vm.zig");

test "basic arithmetic" {
    const allocator = std.testing.allocator;
    const prog = try compiler.compileSource("1 + 2 * 3", allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 7.0), res.num);
}

test "variables and blocks" {
    const allocator = std.testing.allocator;
    const src =
        \\{
        \\    let a = 10;
        \\    let b = 20;
        \\    a + b
        \\}
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 30.0), res.num);
}

test "conditionals if fl el" {
    const allocator = std.testing.allocator;
    const src =
        \\let x = 15;
        \\if x < 10 {
        \\    100
        \\} fl x == 15 {
        \\    200
        \\} el {
        \\    300
        \\}
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 200.0), res.num);
}

test "loops count and range" {
    const allocator = std.testing.allocator;
    const src =
        \\let sum = 0;
        \\lop |i| 1..11 {
        \\    sum += i;
        \\}
        \\sum
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 1+2+3+4+5+6+7+8+9+10 = 55
    try std.testing.expectEqual(@as(f64, 55.0), res.num);
}

test "loop with out and skp" {
    const allocator = std.testing.allocator;
    const src =
        \\let sum = 0;
        \\lop |i| 100 {
        \\    if i == 5 {
        \\        out;
        \\    }
        \\    sum += i;
        \\}
        \\sum
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 0 + 1 + 2 + 3 + 4 = 10
    try std.testing.expectEqual(@as(f64, 10.0), res.num);
}

test "state persistence across runs" {
    const allocator = std.testing.allocator;
    const src =
        \\sta counter = 0;
        \\counter += 1;
        \\counter
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    var res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 1.0), res.num);

    res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 2.0), res.num);

    res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 3.0), res.num);
}

test "host tags" {
    const allocator = std.testing.allocator;
    const src = "#CurBpm * 2 + #CamRot";
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    try std.testing.expectEqual(@as(usize, 2), prog.host_tags.len);
    try std.testing.expectEqualStrings("CurBpm", prog.host_tags[0]);
    try std.testing.expectEqualStrings("CamRot", prog.host_tags[1]);

    const host_vars = [_]f64{ 150.0, 3.5 };
    const res = try vm.run(prog, 0, &host_vars);
    try std.testing.expectEqual(@as(f64, 303.5), res.num);
}

test "string concatenation and interpolation" {
    const allocator = std.testing.allocator;
    const src =
        \\let bpm = 180;
        \\"Current BPM: {bpm}"
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(vm.ValueType.str, res.val_type);
    try std.testing.expectEqualStrings("Current BPM: 180", res.toSlice());
}

test "tag definition and execution" {
    const allocator = std.testing.allocator;
    const src =
        \\tag Rot => #CamRotRad * 0.5;
        \\tag Speed => #CurBpm * 2;
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    try std.testing.expectEqual(@as(usize, 2), prog.tags.len);
    try std.testing.expectEqualStrings("Rot", prog.tags[0].name);
    try std.testing.expectEqualStrings("Speed", prog.tags[1].name);

    const host_vars = [_]f64{ 10.0, 150.0 };
    // Rot uses #CamRotRad (host index 0)
    const rot_res = try vm.run(prog, prog.tags[0].entry_ip, &host_vars);
    try std.testing.expectEqual(@as(f64, 5.0), rot_res.num);

    // Speed uses #CurBpm (host index 1)
    const speed_res = try vm.run(prog, prog.tags[1].entry_ip, &host_vars);
    try std.testing.expectEqual(@as(f64, 300.0), speed_res.num);
}

test "bitwise and shift operators" {
    const allocator = std.testing.allocator;
    const src = "(5 & 3) + (4 | 2) + (10 ^ 6) + (1 << 3) + (16 >> 2)";
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    // 1 + 6 + 12 + 8 + 4 = 31
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 31.0), res.num);
}

test "math builtins through module imports" {
    const allocator = std.testing.allocator;
    const src =
        \\con Std = @("std");
        \\con Math = Std.Math;
        \\Math.pow(2, 4) + Math.clamp(15, 0, 10) + Math.lerp(0, 100, 0.5)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    // 16 + 10 + 50 = 76
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 76.0), res.num);
}

test "direct submodule import and constants" {
    const allocator = std.testing.allocator;
    const src =
        \\con Math = @("std.math");
        \\Math.sin(0) + Math.pi
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, std.math.pi), res.num);
}

test "function definition and calls" {
    const allocator = std.testing.allocator;
    const src =
        \\fun add(a, b) => a + b;
        \\add(25, 75)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 100.0), res.num);
}

test "SPEC Moon_CRot tag with persistent state" {
    const allocator = std.testing.allocator;
    const src =
        \\sta rot = 0;
        \\tag Moon_CRot => {
        \\    let diff = #CamRotRad - rot;
        \\    rot += diff * 0.5;
        \\    rot
        \\}
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    // Host tag #CamRotRad is 10.0
    const host_vars = [_]f64{ 10.0 };
    var res = try vm.run(prog, prog.tags[0].entry_ip, &host_vars);
    // rot was 0, diff = 10, rot += 5 -> rot is 5.0
    try std.testing.expectEqual(@as(f64, 5.0), res.num);

    // 2nd run: #CamRotRad is 10.0, rot was 5, diff = 5, rot += 2.5 -> rot is 7.5
    res = try vm.run(prog, prog.tags[0].entry_ip, &host_vars);
    try std.testing.expectEqual(@as(f64, 7.5), res.num);
}

test "array literal, indexing, and length" {
    const allocator = std.testing.allocator;
    const src =
        \\let a = [10, 20, 30];
        \\a[1] + a.len
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 23.0), res.num);
}

test "typed array literal and element assignment" {
    const allocator = std.testing.allocator;
    const src =
        \\let a: [3]num = [3]num{ 10, 20, 30 };
        \\a[1] = 99;
        \\a[1] += 1;
        \\a[0] + a[1] + a[2]
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 140.0), res.num);
}

test "array loop with item and index" {
    const allocator = std.testing.allocator;
    const src =
        \\let a = [1, 2, 3, 4, 5];
        \\let sum = 0;
        \\lop |v, i| a {
        \\    sum += v * i;
        \\}
        \\sum
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 40.0), res.num);
}

test "multi-dimensional array" {
    const allocator = std.testing.allocator;
    const src =
        \\let m = [[10, 20], [30, 40]];
        \\m[1][0] + m[0][1] + m.len
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 52.0), res.num);
}

test "array out of bounds check" {
    const allocator = std.testing.allocator;
    // Static out of bounds fails compile
    try std.testing.expectError(error.IndexOutOfBounds, compiler.compileSource("let a = [1, 2, 3]; a[10]", allocator));

    // Dynamic out of bounds fails vm run
    const prog = try compiler.compileSource("let a = [1, 2, 3]; let i = 10; a[i]", allocator);
    defer prog.deinit();
    try std.testing.expectError(error.OutOfBounds, vm.run(prog, 0, &[_]f64{}));
}

test "string maximum length compile limit" {
    const allocator = std.testing.allocator;
    // 257 byte string literal exceeds 256 byte max_str_len limit
    var long_src: [300]u8 = undefined;
    @memcpy(long_src[0..5], "let s");
    long_src[5] = '=';
    long_src[6] = '"';
    @memset(long_src[7..270], 'a');
    long_src[270] = '"';
    long_src[271] = ';';
    try std.testing.expectError(error.StringLiteralTooLong, compiler.compileSource(long_src[0..272], allocator));
}

test "block function with mandatory ret and type annotations" {
    const allocator = std.testing.allocator;
    const src =
        \\fun add(a: num, b: num): num {
        \\    let sum = a + b;
        \\    ret sum;
        \\}
        \\add(100, 200)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 300.0), res.num);
}

test "block function without ret fails compile with MissingReturn" {
    const allocator = std.testing.allocator;
    const src =
        \\fun bad(a: num, b: num): num {
        \\    a + b
        \\}
        \\bad(1, 2)
    ;
    try std.testing.expectError(error.MissingReturn, compiler.compileSource(src, allocator));
}

test "recursive function factorial and fibonacci" {
    const allocator = std.testing.allocator;
    const src =
        \\fun fact(n: num): num {
        \\    if n <= 1 { ret 1; }
        \\    ret n * fact(n - 1);
        \\}
        \\fact(5)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 120.0), res.num);
}

test "forward declared functions" {
    const allocator = std.testing.allocator;
    const src =
        \\fun caller(x) => helper(x) + 1;
        \\fun helper(x) => x * 2;
        \\caller(10)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 21.0), res.num);
}

test "tag function delegate" {
    const allocator = std.testing.allocator;
    const src =
        \\fun compute_rot() => #CamRotRad * 0.5;
        \\tag Moon_CRot => compute_rot;
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    try std.testing.expectEqual(@as(usize, 1), prog.tags.len);
    try std.testing.expectEqualStrings("Moon_CRot", prog.tags[0].name);

    const host_vars = [_]f64{ 40.0 };
    const res = try vm.run(prog, prog.tags[0].entry_ip, &host_vars);
    try std.testing.expectEqual(@as(f64, 20.0), res.num);
}

test "tag blocks with and without ret" {
    const allocator = std.testing.allocator;
    const src =
        \\tag ExplicitRet => {
        \\    let a = 10;
        \\    ret a * 2;
        \\}
        \\tag ImplicitRet => {
        \\    let a = 10;
        \\    a * 3
        \\}
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const r1 = try vm.run(prog, prog.tags[0].entry_ip, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 20.0), r1.num);

    const r2 = try vm.run(prog, prog.tags[1].entry_ip, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 30.0), r2.num);
}

test "undefined function and argument mismatch errors" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UndefinedFunction, compiler.compileSource("non_existent(1)", allocator));
    try std.testing.expectError(error.ArgumentCountMismatch, compiler.compileSource("fun f(a, b) => a + b; f(1)", allocator));
}




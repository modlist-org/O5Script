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


test "conditionals if lf el" {
    const allocator = std.testing.allocator;
    const src =
        \\let a = 100;
        \\if a >= 200 {
        \\    "eq 200 or ov 200"
        \\} lf a >= 100 {
        \\    "eq 100 or ov 100"
        \\} el {
        \\    "el"
        \\}
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("eq 100 or ov 100", res.toSlice());
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

test "loop with skp continue" {
    const allocator = std.testing.allocator;
    const src =
        \\let sum = 0;
        \\lop |i| 5 {
        \\    if i == 2 {
        \\        skp;
        \\    }
        \\    sum += i;
        \\}
        \\sum
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 0 + 1 + 3 + 4 = 8
    try std.testing.expectEqual(@as(f64, 8.0), res.num);
}

test "array loop with skp continue" {
    const allocator = std.testing.allocator;
    const src =
        \\let a = [10, 20, 30, 40];
        \\let sum = 0;
        \\lop |v| a {
        \\    if v == 20 {
        \\        skp;
        \\    }
        \\    sum += v;
        \\}
        \\sum
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 10 + 30 + 40 = 80
    try std.testing.expectEqual(@as(f64, 80.0), res.num);
}


test "string interpolation with ternary and brace escaping" {
    const allocator = std.testing.allocator;
    const src =
        \\let a = 1;
        \\"val: {a > 0 ? 10 : 20}, literal: {{100}}"
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("val: 10, literal: {100}", res.toSlice());
}

test "compile error undefined variable" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UndefinedVariable, compiler.compileSource("let x = foo + 1;", allocator));
    try std.testing.expectError(error.UndefinedVariable, compiler.compileSource("bar = 10;", allocator));
}

test "compile error cannot assign to constant" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.CannotAssignToConstant, compiler.compileSource("con MAX = 100; MAX = 200;", allocator));
    try std.testing.expectError(error.CannotAssignToConstant, compiler.compileSource("con MAX = 100; MAX += 5;", allocator));
}

test "compile error break or continue outside loop" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.BreakOutsideLoop, compiler.compileSource("out;", allocator));
    try std.testing.expectError(error.ContinueOutsideLoop, compiler.compileSource("skp;", allocator));
    try std.testing.expectError(error.BreakOutsideLoop, compiler.compileSource("fun f() { out; ret 0; }", allocator));
}

test "compile error unknown type annotation" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UnknownType, compiler.compileSource("let x: int = 10;", allocator));
    try std.testing.expectError(error.UnknownType, compiler.compileSource("let y: bool = tru;", allocator));
}

test "compile error type mismatch" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x: num = \"hello\";", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x: str = 123;", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("sta s: num = \"hello\";", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("con c: num = \"hello\";", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let arr: [3]num = [1, \"foo\", 3];", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("fun f(): num { ret \"bar\"; }", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("fun f(): num => \"bar\";", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x = \"str\" * 2;", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x = -\"str\";", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x = \"str\" - 1;", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x = \"str\" >> 1;", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x = \"str\" > 0;", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource("let x: num = 1; x = \"str\";", allocator));
}

test "type annotations valid execution" {
    const allocator = std.testing.allocator;
    const src =
        \\let x: num = 10;
        \\let s: str = "hello";
        \\sta count: num = 5;
        \\con STEP: num = 2;
        \\fun add(a: num, b: num): num => a + b;
        \\add(x, count) + STEP
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 17.0), res.num);
}

test "in-place increment and decrement" {
    const allocator = std.testing.allocator;
    const src =
        \\let a = 10;
        \\a += 1;
        \\a += 1;
        \\a -= 1;
        \\a
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    var has_inc = false;
    var has_dec = false;
    for (prog.ops) |op| {
        if (op.code == .inc_local) has_inc = true;
        if (op.code == .dec_local) has_dec = true;
    }
    try std.testing.expect(has_inc);
    try std.testing.expect(has_dec);

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 11.0), res.num);
}

test "struct definition and basic access" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Vec2 {
        \\    x: num,
        \\    y: num,
        \\}
        \\let p: Vec2 = Vec2 { x: 10, y: 20 };
        \\p.x + p.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 30.0), res.num);
}

test "struct instantiation forms" {
    const allocator = std.testing.allocator;
    // Test positional, array style, default zero, inferred type
    const src =
        \\stu Vec2 {
        \\    x: num,
        \\    y: num,
        \\}
        \\let a = Vec2 { 3, 4 };
        \\let b: Vec2 = [5, 6];
        \\let c: Vec2;
        \\a.x + a.y + b.x + b.y + c.x + c.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 3 + 4 + 5 + 6 + 0 + 0 = 18
    try std.testing.expectEqual(@as(f64, 18.0), res.num);
}

test "struct mutation and inc_local optimization" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Vec2 {
        \\    x: num,
        \\    y: num,
        \\}
        \\let p: Vec2 = Vec2 { x: 10, y: 20 };
        \\p.x += 1;
        \\p.x += 1;
        \\p.x -= 1;
        \\p.y *= 2;
        \\p.x + p.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    var has_inc = false;
    var has_dec = false;
    for (prog.ops) |op| {
        if (op.code == .inc_local) has_inc = true;
        if (op.code == .dec_local) has_dec = true;
    }
    try std.testing.expect(has_inc);
    try std.testing.expect(has_dec);

    const res = try vm.run(prog, 0, &[_]f64{});
    // p.x: 10 + 1 + 1 - 1 = 11; p.y: 20 * 2 = 40; sum = 51
    try std.testing.expectEqual(@as(f64, 51.0), res.num);
}

test "struct reference and copy assignment" {
    const allocator = std.testing.allocator;
    const src_ref =
        \\stu Vec2 {
        \\    x: num,
        \\    y: num,
        \\}
        \\let a = Vec2 { x: 100, y: 200 };
        \\let b: Vec2 = a;
        \\b.x += 5;
        \\b.x + b.y + a.x
    ;
    const prog_ref = try compiler.compileSource(src_ref, allocator);
    defer prog_ref.deinit();
    const res_ref = try vm.run(prog_ref, 0, &[_]f64{});
    // Reference semantics: mutating b.x also mutates a.x => 105 + 200 + 105 = 410
    try std.testing.expectEqual(@as(f64, 410.0), res_ref.num);

    const src_copy =
        \\stu Vec2 {
        \\    x: num,
        \\    y: num,
        \\}
        \\let a = Vec2 { x: 100, y: 200 };
        \\let b: Vec2 = |a|;
        \\b.x += 5;
        \\b.x + b.y + a.x
    ;
    const prog_copy = try compiler.compileSource(src_copy, allocator);
    defer prog_copy.deinit();
    const res_copy = try vm.run(prog_copy, 0, &[_]f64{});
    // Copy semantics: mutating b.x leaves a.x unchanged => 105 + 200 + 100 = 405
    try std.testing.expectEqual(@as(f64, 405.0), res_copy.num);
}

test "struct and string lifetime error on scope escape" {
    const allocator = std.testing.allocator;
    // Struct reference escape must fail with LifetimeError
    try std.testing.expectError(error.LifetimeError, compiler.compileSource(
        \\stu Vec2 { x: num, y: num }
        \\let a = Vec2 { x: 1, y: 2 };
        \\{
        \\    let b = Vec2 { x: 3, y: 4 };
        \\    a = b;
        \\}
    , allocator));

    // Struct explicit copy escape is allowed
    const src_stu_copy =
        \\stu Vec2 { x: num, y: num }
        \\let a = Vec2 { x: 1, y: 2 };
        \\{
        \\    let b = Vec2 { x: 3, y: 4 };
        \\    a = |b|;
        \\}
        \\a.x + a.y
    ;
    const prog_stu_copy = try compiler.compileSource(src_stu_copy, allocator);
    defer prog_stu_copy.deinit();
    const res_stu_copy = try vm.run(prog_stu_copy, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 7.0), res_stu_copy.num);

    // String reference escape must fail with LifetimeError
    try std.testing.expectError(error.LifetimeError, compiler.compileSource(
        \\let s: str = "init";
        \\{
        \\    let inner: str = "inner";
        \\    s = inner;
        \\}
    , allocator));

    // String explicit copy escape is allowed
    const src_str_copy =
        \\let s: str = "init";
        \\{
        \\    let inner: str = "inner";
        \\    s = |inner|;
        \\}
        \\s
    ;
    const prog_str_copy = try compiler.compileSource(src_str_copy, allocator);
    defer prog_str_copy.deinit();
    const res_str_copy = try vm.run(prog_str_copy, 0, &[_]f64{});
    try std.testing.expectEqualStrings("inner", res_str_copy.toSlice());
}

test "jmp statement numbers and fallthrough" {
    const allocator = std.testing.allocator;
    const src =
        \\fun test_jmp(n: num): num {
        \\    let r = 0;
        \\    jmp n {
        \\        1:
        \\            r = 10;
        \\            skp;
        \\        2:
        \\        3:
        \\            r = 20;
        \\            skp;
        \\        4: {
        \\            r = 40;
        \\            skp;
        \\        }
        \\        _:
        \\            r = 99;
        \\    }
        \\    ret r;
        \\}
        \\test_jmp(1) + test_jmp(2) + test_jmp(3) + test_jmp(4) + test_jmp(5)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    // 10 + 20 + 20 + 40 + 99 = 189
    try std.testing.expectEqual(@as(f64, 189.0), res.num);

    // Fallthrough without skp
    const src_fallthrough =
        \\let r = 0;
        \\jmp 1 {
        \\    1:
        \\        r += 1;
        \\    2:
        \\        r += 10;
        \\        skp;
        \\}
        \\r
    ;
    const prog_ft = try compiler.compileSource(src_fallthrough, allocator);
    defer prog_ft.deinit();
    const res_ft = try vm.run(prog_ft, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 11.0), res_ft.num);
}

test "jmp statement strings" {
    const allocator = std.testing.allocator;
    const src =
        \\fun check_fruit(s: str): num {
        \\    let r = 0;
        \\    jmp s {
        \\        "apple":
        \\            r = 1;
        \\            skp;
        \\        "banana": {
        \\            r = 2;
        \\            skp;
        \\        }
        \\        _:
        \\            r = 3;
        \\    }
        \\    ret r;
        \\}
        \\check_fruit("apple") + check_fruit("banana") * 10 + check_fruit("other") * 100
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    // 1 + 20 + 300 = 321
    try std.testing.expectEqual(@as(f64, 321.0), res.num);
}

test "go statement and labels" {
    const allocator = std.testing.allocator;
    // Forward jump
    const src_fwd =
        \\let x = 1;
        \\go $target;
        \\x = 999;
        \\$target:
        \\x
    ;
    const prog_fwd = try compiler.compileSource(src_fwd, allocator);
    defer prog_fwd.deinit();
    const res_fwd = try vm.run(prog_fwd, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 1.0), res_fwd.num);

    // Backward jump (loop)
    const src_bwd =
        \\let x = 0;
        \\$start:
        \\x += 1;
        \\if x < 10 {
        \\    go $start;
        \\}
        \\x
    ;
    const prog_bwd = try compiler.compileSource(src_bwd, allocator);
    defer prog_bwd.deinit();
    const res_bwd = try vm.run(prog_bwd, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 10.0), res_bwd.num);

    // Undefined label compile error
    try std.testing.expectError(error.UndefinedVariable, compiler.compileSource("go $missing;", allocator));
}

test "state struct persistence" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Counter {
        \\    val: num,
        \\    step: num,
        \\}
        \\sta c: Counter = Counter { val: 0, step: 2 };
        \\c.val += c.step;
        \\c.val
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    var res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 2.0), res.num);

    res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 4.0), res.num);
}

test "struct loop performance pattern" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Particle {
        \\    x: num,
        \\    v: num,
        \\}
        \\let p = Particle { x: 0, v: 3 };
        \\lop 1000 {
        \\    p.x += p.v;
        \\}
        \\p.x
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 3000.0), res.num);
}

test "struct compile-time type errors" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UnknownType, compiler.compileSource("let p: NonExistent;", allocator));
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource(
        \\stu Vec2 { x: num, y: num }
        \\let p: Vec2 = Vec2 { x: "hello", y: 2 };
    , allocator));
    try std.testing.expectError(error.UndefinedVariable, compiler.compileSource(
        \\stu Vec2 { x: num, y: num }
        \\let p = Vec2 { x: 1, y: 2 };
        \\p.z = 10;
    , allocator));
}





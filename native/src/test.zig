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

test "mat builtins through module imports" {
    const allocator = std.testing.allocator;
    const src =
        \\con Std = @("std");
        \\con Mat = Std.Mat;
        \\Mat.pow(2, 4) + Mat.clamp(15, 0, 10) + Mat.lerp(0, 100, 0.5)
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
        \\con Mat = @("std.mat");
        \\Mat.sin(0) + Mat.pi
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

test "pattern matching jmp with arrow ranges singles and or" {
    const allocator = std.testing.allocator;
    const src =
        \\let num = 2;
        \\let res = 0;
        \\jmp num {
        \\    0..1 => { res = 10; }
        \\    10 => { res = 20; }
        \\    2 | 3 => { res = 30; }
        \\    _ => { res = 99; }
        \\}
        \\res
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 30.0), res.num);
}

test "jmp expression mode" {
    const allocator = std.testing.allocator;
    const src =
        \\let number = 1;
        \\let result = jmp number {
        \\    1 => "숫자는 1입니다.",
        \\    2 => "숫자는 2입니다.",
        \\    _ => "1 또는 2가 아닙니다."
        \\};
        \\result
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("숫자는 1입니다.", res.toSlice());
}

test "nested structs and chained dot access" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Point { x: num, y: num }
        \\stu Rect { tl: Point, br: Point }
        \\let r = Rect {
        \\    tl: Point { x: 10, y: 20 },
        \\    br: Point { x: 100, y: 200 }
        \\};
        \\r.tl.x = 15;
        \\r.br.y += 50;
        \\r.tl.x + r.br.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 265.0), res.num);
}

test "struct pass-by-ref vs pass-by-copy" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Vec2 { x: num, y: num }
        \\fun mutate_ref(v: Vec2) {
        \\    v.x = 999;
        \\    ret 0;
        \\}
        \\fun mutate_copy(v: |Vec2|) {
        \\    v.x = 111;
        \\    ret 0;
        \\}
        \\let a = Vec2 { x: 1, y: 2 };
        \\mutate_copy(a);
        \\let after_copy = a.x;
        \\mutate_ref(a);
        \\let after_ref = a.x;
        \\after_copy * 1000 + after_ref
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 1999.0), res.num);
}

test "function static variable sta persistence" {
    const allocator = std.testing.allocator;
    const src =
        \\fun ticker() {
        \\    sta c = 0;
        \\    c += 1;
        \\    ret c;
        \\}
        \\let x = ticker();
        \\let y = ticker();
        \\let z = ticker();
        \\x * 100 + y * 10 + z
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 123.0), res.num);
}

test "const parameter con compile error on mutation" {
    const allocator = std.testing.allocator;
    const valid_src =
        \\fun read_only(con a: num) {
        \\    ret a + 10;
        \\}
        \\read_only(5)
    ;
    const prog = try compiler.compileSource(valid_src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 15.0), res.num);

    const invalid_src =
        \\fun mutate_con(con a: num) {
        \\    a = 20;
        \\    ret 0;
        \\}
    ;
    try std.testing.expectError(error.CannotAssignToConstant, compiler.compileSource(invalid_src, allocator));
}

test "struct reference vs value copy and lifetime check" {
    const allocator = std.testing.allocator;
    const ref_src =
        \\stu Point { x: num, y: num }
        \\let p1 = Point { x: 10, y: 20 };
        \\let p2 = p1;
        \\p2.x = 99;
        \\p1.x
    ;
    const prog1 = try compiler.compileSource(ref_src, allocator);
    defer prog1.deinit();
    const res1 = try vm.run(prog1, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 99.0), res1.num); // Reference alias: mutating p2 mutates p1

    const copy_src =
        \\stu Point { x: num, y: num }
        \\let p1 = Point { x: 10, y: 20 };
        \\let p2: Point;
        \\p2 = |p1|;
        \\p2.x = 99;
        \\p1.x
    ;
    const prog2 = try compiler.compileSource(copy_src, allocator);
    defer prog2.deinit();
    const res2 = try vm.run(prog2, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 10.0), res2.num); // Deep copy: p1 unaffected

    const lifetime_src =
        \\stu Point { x: num, y: num }
        \\let p_outer: Point;
        \\{
        \\    let p_inner = Point { x: 1, y: 2 };
        \\    p_outer = p_inner;
        \\}
    ;
    try std.testing.expectError(error.LifetimeError, compiler.compileSource(lifetime_src, allocator));
}

test "dense jump table dispatch table_jmp" {
    const allocator = std.testing.allocator;
    const src =
        \\fun test_switch(x: num) {
        \\    let r = jmp x {
        \\        10 => 100,
        \\        11 => 200,
        \\        12 => 300,
        \\        13 => 400,
        \\        _ => -1,
        \\    };
        \\    ret r;
        \\}
        \\test_switch(12) + test_switch(10) + test_switch(99)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    // Verify table_jmp opcode was emitted
    var has_table_jmp = false;
    for (prog.ops) |op| {
        if (op.code == .table_jmp) {
            has_table_jmp = true;
            break;
        }
    }
    try std.testing.expect(has_table_jmp);

    const res = try vm.run(prog, 0, &[_]f64{});
    // 300 + 100 + (-1) = 399
    try std.testing.expectEqual(@as(f64, 399.0), res.num);
}

test "jmp inclusive and half-open ranges" {
    const allocator = std.testing.allocator;
    const src =
        \\fun test_ranges(x: num): num {
        \\    ret jmp x {
        \\        0..1 => 10,
        \\        1 => 20,
        \\        2..=5 => 30,
        \\        _ => 40
        \\    };
        \\}
        \\test_ranges(0) + test_ranges(1) + test_ranges(3) + test_ranges(5) + test_ranges(6)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 10 + 20 + 30 + 30 + 40 = 130
    try std.testing.expectEqual(@as(f64, 130.0), res.num);
}

test "lop inclusive range 0..=10 vs half-open 0..10" {
    const allocator = std.testing.allocator;
    const src =
        \\let s1 = 0;
        \\lop |i| 0..10 {
        \\    s1 += i;
        \\}
        \\let s2 = 0;
        \\lop |i| 0..=10 {
        \\    s2 += i;
        \\}
        \\s1 * 100 + s2
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // s1 = 45, s2 = 55 -> 4500 + 55 = 4555
    try std.testing.expectEqual(@as(f64, 4555.0), res.num);
}

test "stu methods with slf and state mutation" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Counter {
        \\    val: num,
        \\    step: num,
        \\    add() {
        \\        slf.val += slf.step;
        \\    },
        \\    get(): num {
        \\        ret slf.val;
        \\    }
        \\}
        \\let c = Counter { val: 10, step: 5 };
        \\c.add();
        \\c.add();
        \\c.get()
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 20.0), res.num);
}

test "stu methods without slf and external method definition" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Point {
        \\    x: num,
        \\    y: num,
        \\    dist_sq_zero(px: num, py: num): num {
        \\        ret px * px + py * py;
        \\    }
        \\}
        \\fun Point.translate(dx: num, dy: num) {
        \\    slf.x += dx;
        \\    slf.y += dy;
        \\}
        \\let pt = Point { x: 3, y: 4 };
        \\let d = pt.dist_sq_zero(pt.x, pt.y);
        \\pt.translate(1, 2);
        \\d * 100 + (pt.x + pt.y)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // d = 25; pt.x = 4, pt.y = 6; 2500 + 10 = 2510
    try std.testing.expectEqual(@as(f64, 2510.0), res.num);
}

test "stu chained methods and slf calling another method" {
    const allocator = std.testing.allocator;
    const src =
        \\stu SubEngine {
        \\    power: num,
        \\    boost() {
        \\        slf.power += 10;
        \\    }
        \\}
        \\stu Car {
        \\    engine: SubEngine,
        \\    turbo() {
        \\        slf.engine.boost();
        \\        slf.engine.boost();
        \\    }
        \\}
        \\let c = Car { engine: SubEngine { power: 100 } };
        \\c.engine.boost();
        \\c.turbo();
        \\c.engine.power
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 100 + 10 (boost) + 20 (turbo) = 130
    try std.testing.expectEqual(@as(f64, 130.0), res.num);
}

test "slf return with explicit ret slf and chaining" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Point {
        \\    x: num,
        \\    y: num,
        \\    move(dx: num, dy: num): slf {
        \\        slf.x += dx;
        \\        slf.y += dy;
        \\        ret slf;
        \\    }
        \\}
        \\let p = Point { x: 1, y: 2 };
        \\p.move(10, 20).move(100, 200);
        \\p.x + p.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // x = 111, y = 222
    try std.testing.expectEqual(@as(f64, 333.0), res.num);
}

test "slf implicit return and bare ret" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Counter {
        \\    val: num,
        \\    add(n: num): slf {
        \\        slf.val += n;
        \\    },
        \\    add2(n: num): slf {
        \\        slf.val += n;
        \\        ret;
        \\    }
        \\}
        \\let c = Counter { val: 0 };
        \\c.add(5).add2(7).add(3);
        \\c.val
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 15.0), res.num);
}

test "slf let alias" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Point {
        \\    x: num,
        \\    y: num,
        \\    move(dx: num, dy: num): slf {
        \\        slf.x += dx;
        \\        slf.y += dy;
        \\        ret slf;
        \\    }
        \\}
        \\let p = Point { x: 1, y: 2 };
        \\let q = p.move(10, 20);
        \\q.x = 99;
        \\p.x + p.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // q aliases p: p.x = 99, p.y = 22
    try std.testing.expectEqual(@as(f64, 121.0), res.num);
}

test "slf annotated let alias and field after call" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Point {
        \\    x: num,
        \\    y: num,
        \\    move(dx: num, dy: num): slf {
        \\        slf.x += dx;
        \\        slf.y += dy;
        \\        ret slf;
        \\    }
        \\}
        \\let p = Point { x: 0, y: 0 };
        \\let q: Point = p.move(3, 4).move(1, 1);
        \\q.x + q.y + p.move(0, 0).x
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // q aliases p: x = 4, y = 5; p.move(0,0).x = 4
    try std.testing.expectEqual(@as(f64, 13.0), res.num);
}

test "slf external method and slf-internal chain" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Engine {
        \\    power: num,
        \\    boost(n: num): slf {
        \\        slf.power += n;
        \\        ret slf;
        \\    }
        \\}
        \\stu Car {
        \\    engine: Engine,
        \\    turbo(): slf {
        \\        slf.engine.boost(10).boost(20);
        \\        ret slf;
        \\    }
        \\}
        \\fun Engine.over(n: num): slf {
        \\    slf.power += n;
        \\    ret slf;
        \\}
        \\let c = Car { engine: Engine { power: 100 } };
        \\c.turbo().turbo();
        \\c.engine.over(5).over(5);
        \\c.engine.power
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 100 + 30 + 30 + 5 + 5 = 170
    try std.testing.expectEqual(@as(f64, 170.0), res.num);
}

test "slf chain in loop stays stack-balanced" {
    const allocator = std.testing.allocator;
    const src =
        \\stu P {
        \\    x: num,
        \\    bump(n: num): slf {
        \\        slf.x += n;
        \\        ret slf;
        \\    }
        \\}
        \\let p = P { x: 0 };
        \\lop 300 {
        \\    p.bump(1).bump(2);
        \\}
        \\p.x
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 900.0), res.num);
}

test "nested multi-slot struct frame allocation" {
    const allocator = std.testing.allocator;
    const src =
        \\stu Point {
        \\    x: num,
        \\    y: num,
        \\    move(dx: num, dy: num): slf {
        \\        slf.x += dx;
        \\        slf.y += dy;
        \\        ret slf;
        \\    }
        \\}
        \\stu Car {
        \\    engine: Point,
        \\    run(n: num): slf {
        \\        slf.engine.move(n, n);
        \\        ret slf;
        \\    }
        \\}
        \\let c = Car { engine: Point { x: 0, y: 0 } };
        \\c.run(5).run(3);
        \\c.engine.x + c.engine.y
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 16.0), res.num);
}

test "std.dbg out buffer and take" {
    const allocator = std.testing.allocator;
    var drain: [256]u8 = undefined;
    _ = vm.dbgTake(drain[0..]); // isolate from other tests
    const src =
        \\con Dbg = @("std.dbg");
        \\Dbg.out("hi");
        \\Dbg.out(42);
        \\0
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 0.0), res.num);
    const n = vm.dbgTake(drain[0..]);
    try std.testing.expectEqualStrings("hi\n42\n", drain[0..n]);
    // drained: second take is empty
    try std.testing.expectEqual(@as(usize, 0), vm.dbgTake(drain[0..]));
}

test "std.dbg in feed consume and empty trap" {
    const allocator = std.testing.allocator;
    _ = vm.dbgFeed("abc");
    const src =
        \\con Dbg = @("std.dbg");
        \\Dbg.in()
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("abc", res.toSlice());
    // consumed: second read traps InputEmpty
    try std.testing.expectError(error.InputEmpty, vm.run(prog, 0, &[_]f64{}));
}

test "std.dbg out overflow traps StringTooLong" {
    const allocator = std.testing.allocator;
    var drain: [256]u8 = undefined;
    _ = vm.dbgTake(drain[0..]);
    const src =
        \\con Dbg = @("std.dbg");
        \\Dbg.out("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        \\Dbg.out("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        \\0
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    try std.testing.expectError(error.StringTooLong, vm.run(prog, 0, &[_]f64{}));
    _ = vm.dbgTake(drain[0..]);
}

test "std.fmt mini printf" {
    const allocator = std.testing.allocator;
    const src =
        \\con Fmt = @("std.fmt");
        \\Fmt.f("x={{}} y={{d}} lit={{literal}} miss={{}}!", 1.5, 2.7)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("x=1.5 y=2 lit={literal} miss=!", res.toSlice());
}

test "std.fmt arg cap" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.TooManyLocals, compiler.compileSource(
        \\con Fmt = @("std.fmt");
        \\Fmt.f("{{}}", 1, 2, 3, 4, 5, 6, 7, 8)
    , allocator));
}

test "std.rng sequence range reseed" {
    const allocator = std.testing.allocator;
    const src =
        \\con Rng = @("std.rng");
        \\Rng.seed(7);
        \\let a = Rng.next();
        \\let b = Rng.next();
        \\let r = Rng.range(10, 20);
        \\Rng.seed(7);
        \\let a2 = Rng.next();
        \\(a != b) + (a == a2) * 2 + (r >= 10 && r < 20) * 4
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // distinct draws, deterministic reseed, range bounds
    try std.testing.expectEqual(@as(f64, 7.0), res.num);
}

test "std.str len sub find num" {
    const allocator = std.testing.allocator;
    const src =
        \\con Str = @("std.str");
        \\Str.len("hello") + Str.find("hello", "ll") * 10 + Str.find("hello", "z") * 100
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 5 + 2*10 + (-1)*100 = -75
    try std.testing.expectEqual(@as(f64, -75.0), res.num);

    const src2 =
        \\con Str = @("std.str");
        \\Str.sub("hello", 1, 4) + "|" + Str.num("12.5")
    ;
    const prog2 = try compiler.compileSource(src2, allocator);
    defer prog2.deinit();

    const res2 = try vm.run(prog2, 0, &[_]f64{});
    try std.testing.expectEqualStrings("ell|12.5", res2.toSlice());

    // invalid num parses to NaN (NaN != NaN)
    const prog3 = try compiler.compileSource(
        \\con Str = @("std.str");
        \\Str.num("abc") != Str.num("abc")
    , allocator);
    defer prog3.deinit();
    const v3 = try vm.run(prog3, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 1.0), v3.num);
}

test "std.str sub bounds trap" {
    const allocator = std.testing.allocator;
    const trap_srcs = [_][]const u8{
        \\con Str = @("std.str");
        \\Str.sub("hi", 0, 5)
        ,
        \\con Str = @("std.str");
        \\Str.sub("hi", 2, 1)
        ,
        \\con Str = @("std.str");
        \\Str.sub("hi", 0.5, 1)
        ,
    };
    for (trap_srcs) |src| {
        const prog = try compiler.compileSource(src, allocator);
        defer prog.deinit();
        try std.testing.expectError(error.OutOfBounds, vm.run(prog, 0, &[_]f64{}));
    }
}

test "std.hsh fnv vectors" {
    const allocator = std.testing.allocator;
    const src =
        \\con Hsh = @("std.hsh");
        \\Hsh.fnv("") + Hsh.fnv("foobar")
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // FNV-1a 32: "" = 2166136261, "foobar" = 3214735720
    try std.testing.expectEqual(@as(f64, 5380871981.0), res.num);
}

test "std.nos deterministic range" {
    const allocator = std.testing.allocator;
    const src =
        \\con Nos = @("std.nos");
        \\let a = Nos.per(1.5);
        \\let b = Nos.per(1.5);
        \\let c = Nos.per2(3.25, -7.5);
        \\(a == b) + (a >= -1 && a <= 1) * 2 + (c >= -1 && c <= 1) * 4 + (Nos.per(0/0) != Nos.per(0/0)) * 8 + (a != Nos.per(0.0)) * 16
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 31.0), res.num);
}

test "dbg.asr pass trap and note" {
    const allocator = std.testing.allocator;
    var drain: [256]u8 = undefined;
    _ = vm.dbgTake(drain[0..]);
    const prog = try compiler.compileSource(
        \\con Dbg = @("std.dbg");
        \\Dbg.asr(1, "unreached")
    , allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 0.0), res.num);
    try std.testing.expectEqual(@as(usize, 0), vm.dbgTake(drain[0..]));

    const prog2 = try compiler.compileSource(
        \\con Dbg = @("std.dbg");
        \\Dbg.asr(1 > 2, "boom")
    , allocator);
    defer prog2.deinit();
    try std.testing.expectError(error.AssertionFailed, vm.run(prog2, 0, &[_]f64{}));
    const n = vm.dbgTake(drain[0..]);
    try std.testing.expectEqualStrings("assert failed: boom\n", drain[0..n]);
}

test "ub array index NaN traps" {
    const allocator = std.testing.allocator;
    const prog = try compiler.compileSource(
        \\let a = [10, 20, 30];
        \\let i = 0/0;
        \\a[i]
    , allocator);
    defer prog.deinit();
    // Must be OutOfBounds, never a safety panic / UB.
    try std.testing.expectError(error.OutOfBounds, vm.run(prog, 0, &[_]f64{}));
}

test "ub jmp NaN and huge hit default" {
    const allocator = std.testing.allocator;
    // NOTE: bare `jmp ...` is a statement (no value); bind it to read arms.
    const src =
        \\let r = jmp 0/0 {
        \\    1 => 10,
        \\    2 => 20,
        \\    _ => 99
        \\};
        \\r
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 99.0), res.num);

    const prog2 = try compiler.compileSource(
        \\let r = jmp 1000000000000000000000000000000 {
        \\    1 => 10,
        \\    2 => 20,
        \\    _ => 99
        \\};
        \\r
    , allocator);
    defer prog2.deinit();
    const res2 = try vm.run(prog2, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 99.0), res2.num);
}

test "ub bitwise saturate like cvttsd2si" {
    const allocator = std.testing.allocator;
    const src =
        \\let nan_and = (0/0) & 255;
        \\let inf_or = (1/0) | 0;
        \\let huge_and = 1000000000000000000000000000000 & 255;
        \\let frac = 5.5 & 3;
        \\(nan_and == 0) + (inf_or == -9223372036854775808) * 2 + (huge_and == 0) * 4 + (frac == 1) * 8
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 15.0), res.num);
}

test "ub fmt hostile inputs" {
    const allocator = std.testing.allocator;
    // lone brace arrives via runtime slice (compile-time {{}} -> {})
    const prog = try compiler.compileSource(
        \\con Fmt = @("std.fmt");
        \\con Str = @("std.str");
        \\Fmt.f(Str.sub("{{}}", 0, 1))
    , allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("{", res.toSlice());

    // {d} on NaN renders NaN, missing arg renders ""
    const prog2 = try compiler.compileSource(
        \\con Fmt = @("std.fmt");
        \\Fmt.f("{{d}}|{{}}", 0/0)
    , allocator);
    defer prog2.deinit();
    const res2 = try vm.run(prog2, 0, &[_]f64{});
    try std.testing.expectEqualStrings("NaN|", res2.toSlice());

    // output over 256B traps (200 + 100 > 256)
    const prog3 = try compiler.compileSource(
        \\con Fmt = @("std.fmt");
        \\Fmt.f("{{}}{{}}", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    , allocator);
    defer prog3.deinit();
    try std.testing.expectError(error.StringTooLong, vm.run(prog3, 0, &[_]f64{}));
}

test "ub str hostile inputs" {
    const allocator = std.testing.allocator;
    const prog = try compiler.compileSource(
        \\con Str = @("std.str");
        \\(Str.num("") != Str.num("")) + (Str.find("", "") == 0) * 2
    , allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 3.0), res.num);

    // overlong feed truncates to 256, no crash
    var big: [300]u8 = undefined;
    @memset(big[0..], 'z');
    try std.testing.expectEqual(@as(usize, 256), vm.dbgFeed(big[0..]));
    const prog2 = try compiler.compileSource(
        \\con Str = @("std.str");
        \\con Dbg = @("std.dbg");
        \\Str.len(Dbg.in())
    , allocator);
    defer prog2.deinit();
    const res2 = try vm.run(prog2, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 256.0), res2.num);
}

test "ub rng hostile inputs" {
    const allocator = std.testing.allocator;
    const prog = try compiler.compileSource(
        \\con Rng = @("std.rng");
        \\Rng.seed(0/0);
        \\let a = Rng.next();
        \\let r = Rng.range(5, 5);
        \\(a >= 0 && a < 1) + (r == 5) * 2
    , allocator);
    defer prog.deinit();
    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqual(@as(f64, 3.0), res.num);
}

test "ub bad array dimension" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DimensionMismatch, compiler.compileSource(
        \\let a: [100000000000000000000]num = [1];
    , allocator));
}

test "std declaration stubs compile" {
    const allocator = std.testing.allocator;
    // Stubs live in <repo>/std/ (mirrors the @("std.x") namespace).
    // Tests run with native/ as CWD via `zig build test`; read via libc
    // like main.zig (std.fs was reworked in 0.17).
    const stubs = [_][]const u8{
        "../std/mat.o5s",
        "../std/dbg.o5s",
        "../std/fmt.o5s",
        "../std/rng.o5s",
        "../std/str.o5s",
        "../std/hsh.o5s",
        "../std/nos.o5s",
        "../std/std.o5s",
    };
    for (stubs) |relpath| {
        var path_buf: [1024]u8 = undefined;
        if (relpath.len >= path_buf.len) return error.OutOfMemory;
        @memcpy(path_buf[0..relpath.len], relpath);
        path_buf[relpath.len] = 0;
        const fd = open(path_buf[0..relpath.len :0], 0, 0);
        if (fd < 0) return error.FileNotFound;
        defer _ = close(fd);
        const buf = try allocator.alloc(u8, 65536);
        defer allocator.free(buf);
        const n = read(fd, buf.ptr, buf.len);
        if (n <= 0) return error.FileNotFound;
        const prog = try compiler.compileSource(buf[0..@intCast(n)], allocator);
        prog.deinit();
    }
}

extern "c" fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;

test "enm auto explicit negative" {
    const allocator = std.testing.allocator;
    const src =
        \\enm Color {
        \\    Red,
        \\    Green = 10,
        \\    Blue,
        \\    Dark = -3,
        \\    Black,
        \\}
        \\Color.Red + Color.Green * 100 + Color.Blue * 10000 + Color.Dark * 1000000 + Color.Black * 100000000
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 0 + 1000 + 110000 - 3000000 - 200000000 = -202889000
    try std.testing.expectEqual(@as(f64, -202889000.0), res.num);
}

test "enm str values and annotation" {
    const allocator = std.testing.allocator;
    const src =
        \\enm Level {
        \\    Low = "low",
        \\    High = "high",
        \\}
        \\let l: Level = Level.High;
        \\l + "|" + Level.Low
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    try std.testing.expectEqualStrings("high|low", res.toSlice());
}

test "enm jmp labels with table" {
    const allocator = std.testing.allocator;
    const src =
        \\enm Op {
        \\    Add = 1,
        \\    Sub = 2,
        \\    Mul = 3,
        \\}
        \\fun apply(op: num, a: num, b: num): num {
        \\    ret jmp op {
        \\        Op.Add => a + b,
        \\        Op.Sub | Op.Mul => a - b,
        \\        _ => 0
        \\    };
        \\}
        \\apply(Op.Add, 10, 4) * 100 + apply(Op.Mul, 10, 4) + apply(9, 10, 4)
    ;
    const prog = try compiler.compileSource(src, allocator);
    defer prog.deinit();

    const res = try vm.run(prog, 0, &[_]f64{});
    // 1400 + 6 + 0 = 1406
    try std.testing.expectEqual(@as(f64, 1406.0), res.num);
}

test "enm errors" {
    const allocator = std.testing.allocator;
    // mixed num/str
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource(
        \\enm E { A, B = "b" }
    , allocator));
    // fractional value
    try std.testing.expectError(error.TypeMismatch, compiler.compileSource(
        \\enm E { A = 1.5 }
    , allocator));
    // duplicate member
    try std.testing.expectError(error.DuplicateVariable, compiler.compileSource(
        \\enm E { A, A }
    , allocator));
    // unknown variant
    try std.testing.expectError(error.UndefinedVariable, compiler.compileSource(
        \\enm E { A }
        \\E.B
    , allocator));
    // bare name stays unbound (Zero Pollution)
    try std.testing.expectError(error.UndefinedVariable, compiler.compileSource(
        \\enm E { A }
        \\A
    , allocator));
    // struct/enm name collision both ways
    try std.testing.expectError(error.DuplicateVariable, compiler.compileSource(
        \\stu Color { x: num }
        \\enm Color { Red }
    , allocator));
    try std.testing.expectError(error.DuplicateVariable, compiler.compileSource(
        \\enm Color { Red }
        \\stu Color { x: num }
    , allocator));
}

test "slf compile errors" {
    const allocator = std.testing.allocator;
    // slf outside a stu method
    try std.testing.expectError(error.UnknownType, compiler.compileSource(
        \\fun f(): slf {
        \\    ret 0;
        \\}
    , allocator));
    // slf as variable annotation
    try std.testing.expectError(error.UnknownType, compiler.compileSource(
        \\let x: slf = 1;
    , allocator));
    // chaining onto a num-returning method
    try std.testing.expectError(error.SyntaxError, compiler.compileSource(
        \\stu Point {
        \\    x: num,
        \\    y: num,
        \\    get(): num {
        \\        ret slf.x;
        \\    },
        \\    move(dx: num, dy: num): slf {
        \\        slf.x += dx;
        \\        ret slf;
        \\    }
        \\}
        \\let p = Point { x: 1, y: 2 };
        \\p.get().move(1, 1);
    , allocator));
}


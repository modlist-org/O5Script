using System;
using System.Diagnostics;
using O5Script.Common;
using Xunit;

namespace O5Script.Tests;

public class O5ScriptEngineTests {
    [Fact]
    public void NativeLibrary_IsAvailable() {
        Assert.True(O5ScriptEngine.IsAvailable, "Native Zig O5Script library must be loaded and available.");
    }

    [Fact]
    public void BasicArithmetic_EvaluatesCorrectly() {
        double result = O5ScriptEngine.EvalNum("1 + 2 * 3");
        Assert.Equal(7.0, result);
    }

    [Fact]
    public void BlockWithLocals_ReturnsLastExpression() {
        string src = """
        {
            let a = 15;
            let b = 25;
            a + b
        }
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(40.0, result);
    }


    [Fact]
    public void Conditionals_IfLfEl() {
        string src = """
        let x = 15;
        if x < 10 {
            100
        } lf x == 15 {
            200
        } el {
            300
        }
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(200.0, result);
    }

    [Fact]
    public void RangeLoop_AccumulatesSum() {
        string src = """
        let sum = 0;
        lop |i| 1..11 {
            sum += i;
        }
        sum
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(55.0, result);
    }

    [Fact]
    public void Loop_BreakAndContinue() {
        string srcBreak = """
        let sum = 0;
        lop |i| 100 {
            if i == 5 {
                out;
            }
            sum += i;
        }
        sum
        """;
        Assert.Equal(10.0, O5ScriptEngine.EvalNum(srcBreak));

        string srcContinue = """
        let sum = 0;
        lop |i| 5 {
            if i == 2 {
                skp;
            }
            sum += i;
        }
        sum
        """;
        Assert.Equal(8.0, O5ScriptEngine.EvalNum(srcContinue));
    }


    [Fact]
    public void PersistentState_RetainsAcrossEvaluations() {
        string src = """
        sta counter = 0;
        counter += 1;
        counter
        """;
        using var prog = O5ScriptEngine.Compile(src);

        Assert.Equal(1.0, prog.ExecuteNum());
        Assert.Equal(2.0, prog.ExecuteNum());
        Assert.Equal(3.0, prog.ExecuteNum());

        prog.ResetState();
        Assert.Equal(1.0, prog.ExecuteNum());
    }

    [Fact]
    public void HostTags_MapCorrectlyAndEvaluate() {
        string src = "#CurBpm * 2 + #CamRotRad";
        using var prog = O5ScriptEngine.Compile(src);

        Assert.Equal(2, prog.HostTags.Count);
        Assert.Equal("CurBpm", prog.HostTags[0]);
        Assert.Equal("CamRotRad", prog.HostTags[1]);

        Span<double> hostVars = stackalloc double[] { 150.0, 3.5 };
        double result = prog.ExecuteNum(hostVars);
        Assert.Equal(303.5, result);
    }

    [Fact]
    public void StringInterpolation_FormatsNumbersAndTags() {
        string src = """
        let bpm = 180;
        "Current BPM: {bpm}, Literal: {{bpm}}, Level: {bpm > 150 ? 1 : 0}"
        """;
        string result = O5ScriptEngine.EvalString(src);
        Assert.Equal("Current BPM: 180, Literal: {bpm}, Level: 1", result);
    }

    [Fact]
    public void TagDefinition_CanEvaluateIndividually() {
        string src = """
        sta rot = 0;
        tag Moon_CRot => {
            let diff = #CamRotRad - rot;
            rot += diff * 0.5;
            rot
        }
        tag Moon_Speed => #CurBpm * 1.5;
        """;
        using var prog = O5ScriptEngine.Compile(src);

        Assert.Equal(2, prog.Tags.Count);
        Assert.Equal("Moon_CRot", prog.Tags[0]);
        Assert.Equal("Moon_Speed", prog.Tags[1]);

        Span<double> hostVars = stackalloc double[] { 10.0, 200.0 }; // CamRotRad=10, CurBpm=200

        // Moon_CRot: tick 1
        double rot1 = prog.EvalTagNum("Moon_CRot", hostVars);
        Assert.Equal(5.0, rot1);

        // Moon_CRot: tick 2
        double rot2 = prog.EvalTagNum("Moon_CRot", hostVars);
        Assert.Equal(7.5, rot2);

        // Moon_Speed
        double speed = prog.EvalTagNum("Moon_Speed", hostVars);
        Assert.Equal(300.0, speed);
    }

    [Fact]
    public void MatBuiltins_WorkAccuratelyThroughModules() {
        string src = """
        con Std = @("std");
        con Mat = Std.Mat;
        Mat.pow(2, 4) + Mat.clamp(15, 0, 10) + Mat.lerp(0, 100, 0.5)
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(76.0, result);
    }

    [Fact]
    public void Mat_DirectSubmoduleImportAndConstants() {
        string src = """
        con Mat = @("std.mat");
        Mat.sin(0) + Mat.pi
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(Math.PI, result);
    }

    [Fact]
    public void PerformanceBenchmark_HighThroughputZeroAlloc() {
        string src = "10.0 + #CurBpm * 0.5";
        using var prog = O5ScriptEngine.Compile(src);

        Span<double> hostVars = stackalloc double[] { 120.0 };

        // Warmup
        for (int i = 0; i < 1000; i++) {
            _ = prog.ExecuteNum(hostVars);
        }

        var sw = new Stopwatch();
        long initialMemory = GC.GetAllocatedBytesForCurrentThread();
        sw.Start();
        const int iterations = 1_000_000;
        double sum = 0;

        for (int i = 0; i < iterations; i++) {
            sum += prog.ExecuteNum(hostVars);
        }
        sw.Stop();
        long allocated = GC.GetAllocatedBytesForCurrentThread() - initialMemory;

        // Zero GC allocation
        Assert.Equal(0, allocated);
        Assert.Equal(iterations * 70.0, sum);

        double nsPerOp = (sw.Elapsed.TotalMilliseconds * 1_000_000.0) / iterations;
        // In native Zig, 1 million ops should complete in < 200ms (~50-150ns per op)
        Assert.True(sw.ElapsedMilliseconds < 500, $"1M executions took {sw.ElapsedMilliseconds}ms ({nsPerOp:F1} ns/op)");
    }

    [Fact]
    public void Function_BlockAndLambda_WithRecursion() {
        string src = """
        fun fact(n: num): num {
            if n <= 1 { ret 1; }
            ret n * fact(n - 1);
        }
        fun square(x: num): num => x * x;
        fact(5) + square(10)
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(220.0, result); // 120 + 100 = 220
    }

    [Fact]
    public void Tag_FunctionDelegateAndBlockReturn() {
        string src = """
        fun compute_bpm() => #CurBpm * 2;
        tag DoubleBpm => compute_bpm;
        tag QuadBpm => {
            let bpm = #CurBpm;
            ret bpm * 4;
        }
        tag HalvedBpm => {
            let bpm = #CurBpm;
            bpm * 0.5
        }
        """;
        using var prog = O5ScriptEngine.Compile(src);
        Assert.Equal(3, prog.Tags.Count);

        Span<double> hostVars = stackalloc double[] { 120.0 };
        Assert.Equal(240.0, prog.EvalTagNum("DoubleBpm", hostVars));
        Assert.Equal(480.0, prog.EvalTagNum("QuadBpm", hostVars));
        Assert.Equal(60.0, prog.EvalTagNum("HalvedBpm", hostVars));
    }

    [Fact]
    public void Function_MandatoryRet_Enforcement() {
        string badSrc = """
        fun bad(a: num, b: num): num {
            a + b
        }
        bad(1, 2)
        """;
        Assert.Throws<InvalidOperationException>(() => O5ScriptEngine.Compile(badSrc));
    }

    [Fact]
    public void Array_Literal_Indexing_Length() {
        double result = O5ScriptEngine.EvalNum("let a = [10, 20, 30]; a[1] + a.len");
        Assert.Equal(23.0, result);
    }

    [Fact]
    public void Array_Typed_Assignment() {
        string src = """
        let a: [3]num = [3]num{ 10, 20, 30 };
        a[1] = 99;
        a[1] += 1;
        a[0] + a[1] + a[2]
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(140.0, result);
    }

    [Fact]
    public void Array_Loop() {
        string src = """
        let a = [1, 2, 3, 4, 5];
        let sum = 0;
        lop |v, i| a {
            sum += v * i;
        }
        sum
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(40.0, result);
    }

    [Fact]
    public void Array_MultiDimensional() {
        string src = """
        let m = [[10, 20], [30, 40]];
        m[1][0] + m[0][1] + m.len
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(52.0, result);
    }

    [Fact]
    public void Bitwise_Operators() {
        double result = O5ScriptEngine.EvalNum("(5 & 3) + (4 | 2) + (10 ^ 6) + (1 << 3) + (16 >> 2)");
        Assert.Equal(31.0, result);
    }

    [Fact]
    public void Struct_SlfChainingAndAlias() {
        string src = """
        stu Point {
            x: num,
            y: num,
            move(dx: num, dy: num): slf {
                slf.x += dx;
                slf.y += dy;
                ret slf;
            }
        }
        let p = Point { x: 1, y: 2 };
        p.move(10, 20).move(100, 200);
        let q = p.move(1, 1);
        q.x = 0;
        p.x + p.y
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(223.0, result); // x: 112 -> 0 (aliased), y: 223
    }

    [Fact]
    public void StdDbg_Out_DrainsInOrder() {
        string src = """
        con Dbg = @("std.dbg");
        Dbg.out("hi");
        Dbg.out(1.5);
        0
        """;
        Assert.Equal(0.0, O5ScriptEngine.EvalNum(src));
        Assert.Equal("hi\n1.5\n", O5ScriptEngine.DrainDebugOutput());
        Assert.Equal(string.Empty, O5ScriptEngine.DrainDebugOutput());
    }

    [Fact]
    public void StdDbg_In_Feed() {
        O5ScriptEngine.FeedDebugInput("hey");
        string result = O5ScriptEngine.EvalString("""
        con Dbg = @("std.dbg");
        Dbg.in()
        """);
        Assert.Equal("hey", result);
    }

    [Fact]
    public void StdFmt_MiniPrintf() {
        string result = O5ScriptEngine.EvalString("""
        con Fmt = @("std.fmt");
        Fmt.f("x={{}} d={{d}}", 1.5, 2.7)
        """);
        Assert.Equal("x=1.5 d=2", result);
    }

    [Fact]
    public void StdRng_SeededRange() {
        O5ScriptEngine.SeedRng(7);
        double r = O5ScriptEngine.EvalNum("""
        con Rng = @("std.rng");
        Rng.range(10, 20)
        """);
        Assert.InRange(r, 10.0, 20.0);
        O5ScriptEngine.SeedRng(7);
        double r2 = O5ScriptEngine.EvalNum("""
        con Rng = @("std.rng");
        Rng.range(10, 20)
        """);
        Assert.Equal(r, r2);
    }

    [Fact]
    public void StdStr_LenSubFindNum() {
        double n = O5ScriptEngine.EvalNum("""
        con Str = @("std.str");
        Str.len("hello") + Str.find("hello", "ll") * 10
        """);
        Assert.Equal(25.0, n); // 5 + 2*10
        string s = O5ScriptEngine.EvalString("""
        con Str = @("std.str");
        Str.sub("hello", 1, 4) + Str.num("12.5")
        """);
        Assert.Equal("ell12.5", s);
    }

    [Fact]
    public void StdHsh_FnvVectors() {
        double n = O5ScriptEngine.EvalNum("""
        con Hsh = @("std.hsh");
        Hsh.fnv("") + Hsh.fnv("foobar")
        """);
        Assert.Equal(5380871981.0, n);
    }

    [Fact]
    public void StdNos_DeterministicRange() {
        double n = O5ScriptEngine.EvalNum("""
        con Nos = @("std.nos");
        let a = Nos.per(1.5);
        (a == Nos.per(1.5)) + (a >= -1 && a <= 1) * 2 + (a != Nos.per(0.0)) * 4
        """);
        Assert.Equal(7.0, n);
    }

    [Fact]
    public void Dbg_Asr_PassAndTrap() {
        double ok = O5ScriptEngine.EvalNum("""
        con Dbg = @("std.dbg");
        Dbg.asr(1, "unreached")
        """);
        Assert.Equal(0.0, ok);
        double bad = O5ScriptEngine.EvalNum("""
        con Dbg = @("std.dbg");
        Dbg.asr(1 > 2, "boom")
        """);
        Assert.True(double.IsNaN(bad));
        Assert.Equal("assert failed: boom\n", O5ScriptEngine.DrainDebugOutput());
    }
}


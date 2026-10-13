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
    public void Conditionals_IfFlEl() {
        string src = """
        let x = 15;
        if x < 10 {
            100
        } fl x == 15 {
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
        string src = """
        let sum = 0;
        lop |i| 100 {
            if i == 5 {
                out;
            }
            sum += i;
        }
        sum
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(10.0, result);
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
        "Current BPM: {bpm}"
        """;
        string result = O5ScriptEngine.EvalString(src);
        Assert.Equal("Current BPM: 180", result);
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
    public void MathBuiltins_WorkAccuratelyThroughModules() {
        string src = """
        con Std = @("std");
        con Math = Std.Math;
        Math.pow(2, 4) + Math.clamp(15, 0, 10) + Math.lerp(0, 100, 0.5)
        """;
        double result = O5ScriptEngine.EvalNum(src);
        Assert.Equal(76.0, result);
    }

    [Fact]
    public void Math_DirectSubmoduleImportAndConstants() {
        string src = """
        con Math = @("std.math");
        Math.sin(0) + Math.pi
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
}

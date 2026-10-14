using System;
using System.Text;
using O5Script.Common;
using O5Script.Native;

namespace O5Script;

public static class O5ScriptEngine {
    public static bool IsAvailable => NativeO5Script.IsAvailable;

    public static unsafe O5ScriptProgram Compile(string source) {
        if (source == null) throw new ArgumentNullException(nameof(source));

        int maxByteCount = Encoding.UTF8.GetMaxByteCount(source.Length);
        if (maxByteCount <= 4096) {
            byte* stackBytes = stackalloc byte[maxByteCount];
            fixed (char* pChars = source) {
                int written = Encoding.UTF8.GetBytes(pChars, source.Length, stackBytes, maxByteCount);
                long handle = NativeO5Script.o5s_compile(stackBytes, (nuint)written);
                if (handle == 0) throw new InvalidOperationException("Failed to compile O5Script: syntax or compilation error.");
                return new O5ScriptProgram(handle);
            }
        }

        byte[] bytes = Encoding.UTF8.GetBytes(source);
        fixed (byte* pBytes = bytes) {
            long handle = NativeO5Script.o5s_compile(pBytes, (nuint)bytes.Length);
            if (handle == 0) throw new InvalidOperationException("Failed to compile O5Script: syntax or compilation error.");
            return new O5ScriptProgram(handle);
        }
    }

    public static unsafe O5ScriptProgram Compile(ReadOnlySpan<byte> utf8Source) {
        fixed (byte* p = utf8Source) {
            long handle = NativeO5Script.o5s_compile(p, (nuint)utf8Source.Length);
            if (handle == 0) throw new InvalidOperationException("Failed to compile O5Script: syntax or compilation error.");
            return new O5ScriptProgram(handle);
        }
    }

    public static double EvalNum(string source, ReadOnlySpan<double> hostVars = default) {
        using var prog = Compile(source);
        return prog.ExecuteNum(hostVars);
    }

    public static string EvalString(string source, ReadOnlySpan<double> hostVars = default) {
        using var prog = Compile(source);
        return prog.ExecuteString(hostVars);
    }

    public static O5Value Eval(string source, ReadOnlySpan<double> hostVars = default) {
        using var prog = Compile(source);
        return prog.Execute(hostVars);
    }

    /// <summary>Drains the Dbg.out buffer accumulated by the last run. VM-side buffer is fixed at 256B.</summary>
    public static unsafe string DrainDebugOutput() {
        byte[] buf = new byte[256];
        fixed (byte* pBuf = buf) {
            nuint len = NativeO5Script.o5s_dbg_take(pBuf, (nuint)buf.Length);
            return Encoding.UTF8.GetString(pBuf, (int)len);
        }
    }

    /// <summary>Feeds one Dbg.in line (truncated to 256B). Returns bytes stored.</summary>
    public static unsafe int FeedDebugInput(string line) {
        if (line == null) return 0;
        int maxByteCount = Math.Min(Encoding.UTF8.GetMaxByteCount(line.Length), 256);
        byte* stackBytes = stackalloc byte[maxByteCount];
        int written;
        fixed (char* pChars = line) {
            written = Encoding.UTF8.GetBytes(pChars, line.Length, stackBytes, maxByteCount);
        }
        return (int)NativeO5Script.o5s_dbg_feed(stackBytes, (nuint)written);
    }

    /// <summary>Seeds the Rng state. 0 selects the default seed.</summary>
    public static void SeedRng(ulong seed) {
        NativeO5Script.o5s_rng_seed(seed);
    }
}

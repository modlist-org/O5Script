using System;
using System.Collections.Generic;
using System.Text;
using O5Script.Common;
using O5Script.Native;

namespace O5Script;

/// <summary>
/// Compiled high-performance O5Script executable instance.
/// </summary>
public sealed class O5ScriptProgram : IDisposable {
    private long _handle;
    private readonly string[] _hostTags;
    private readonly string[] _tags;
    private readonly Dictionary<string, int> _tagLookup;

    public IReadOnlyList<string> HostTags => _hostTags;
    public IReadOnlyList<string> Tags => _tags;
    public bool IsValid => _handle != 0;

    internal unsafe O5ScriptProgram(long handle) {
        _handle = handle;

        // 1. Read Host Tags
        nuint hostCount = NativeO5Script.o5s_host_tag_count(handle);
        _hostTags = new string[hostCount];
        byte[] buf = new byte[256];
        fixed (byte* pBuf = buf) {
            for (nuint i = 0; i < hostCount; i++) {
                nuint len = NativeO5Script.o5s_host_tag_name(handle, i, pBuf, (nuint)buf.Length);
                _hostTags[i] = Encoding.UTF8.GetString(pBuf, (int)len);
            }
        }

        // 2. Read Defined Tags
        nuint tagCount = NativeO5Script.o5s_tag_count(handle);
        _tags = new string[tagCount];
        _tagLookup = new Dictionary<string, int>((int)tagCount, StringComparer.Ordinal);
        fixed (byte* pBuf = buf) {
            for (nuint i = 0; i < tagCount; i++) {
                nuint len = NativeO5Script.o5s_tag_name(handle, i, pBuf, (nuint)buf.Length);
                string name = Encoding.UTF8.GetString(pBuf, (int)len);
                _tags[i] = name;
                _tagLookup[name] = (int)i;
            }
        }
    }

    public unsafe double ExecuteNum(ReadOnlySpan<double> hostVars = default) {
        if (_handle == 0) return double.NaN;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run(_handle, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return double.NaN;
            return res.Num;
        }
    }

    public unsafe string ExecuteString(ReadOnlySpan<double> hostVars = default) {
        if (_handle == 0) return string.Empty;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run(_handle, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return string.Empty;
            return res.ToValue().ToString();
        }
    }

    public unsafe O5Value Execute(ReadOnlySpan<double> hostVars = default) {
        if (_handle == 0) return O5Value.Zero;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run(_handle, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return O5Value.Zero;
            return res.ToValue();
        }
    }

    public unsafe double EvalTagNum(int tagIndex, ReadOnlySpan<double> hostVars = default) {
        if (_handle == 0 || (uint)tagIndex >= (uint)_tags.Length) return double.NaN;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run_tag(_handle, (nuint)tagIndex, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return double.NaN;
            return res.Num;
        }
    }

    public double EvalTagNum(string tagName, ReadOnlySpan<double> hostVars = default) {
        if (_tagLookup.TryGetValue(tagName, out int idx)) {
            return EvalTagNum(idx, hostVars);
        }
        return double.NaN;
    }

    public unsafe string EvalTagString(string tagName, ReadOnlySpan<double> hostVars = default) {
        if (!_tagLookup.TryGetValue(tagName, out int idx)) return string.Empty;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run_tag(_handle, (nuint)idx, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return string.Empty;
            return res.ToValue().ToString();
        }
    }

    public unsafe O5Value EvalTag(string tagName, ReadOnlySpan<double> hostVars = default) {
        if (!_tagLookup.TryGetValue(tagName, out int idx)) return O5Value.Zero;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run_tag(_handle, (nuint)idx, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return O5Value.Zero;
            return res.ToValue();
        }
    }

    public void ResetState() {
        if (_handle != 0) {
            NativeO5Script.o5s_reset_state(_handle);
        }
    }

    public void Dispose() {
        if (_handle != 0) {
            NativeO5Script.o5s_free(_handle);
            _handle = 0;
        }
        GC.SuppressFinalize(this);
    }

    ~O5ScriptProgram() {
        if (_handle != 0) {
            NativeO5Script.o5s_free(_handle);
            _handle = 0;
        }
    }
}

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using O5Script.Common;
using O5Script.Native;

namespace O5Script;

public sealed class O5ScriptProgram : IDisposable {
    private long _handle;
    private readonly string[] _hostTags;
    private readonly string[] _tags;
    private readonly Dictionary<string, int> _tagLookup;
    // Last result per entry point (tags, then the main program). HUD scripts
    // mostly return the same value every frame, so reuse its decoded text.
    private readonly ResultMemo?[] _memos;

    private sealed class ResultMemo(byte[]? bytes, long numBits, string text) {
        public readonly byte[]? Bytes = bytes;
        public readonly long NumBits = numBits;
        public readonly string Text = text;
    }

    public IReadOnlyList<string> HostTags => _hostTags;
    public IReadOnlyList<string> Tags => _tags;
    public bool IsValid => _handle != 0;

    internal unsafe O5ScriptProgram(long handle) {
        _handle = handle;

        nuint hostCount = NativeO5Script.o5s_host_tag_count(handle);
        _hostTags = new string[hostCount];
        byte[] buf = new byte[256];
        fixed (byte* pBuf = buf) {
            for (nuint i = 0; i < hostCount; i++) {
                nuint len = NativeO5Script.o5s_host_tag_name(handle, i, pBuf, (nuint)buf.Length);
                _hostTags[i] = Encoding.UTF8.GetString(pBuf, (int)len);
            }
        }

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
        _memos = new ResultMemo?[tagCount + 1];
    }

    private int MainSlot => _tags.Length;

    private static unsafe bool IsString(in O5NativeResult res) =>
        res.ValType == (byte)O5Type.Str && res.StrPtr != null && res.StrLen > 0;

    private unsafe string StringOf(int slot, in O5NativeResult res) {
        var bytes = new ReadOnlySpan<byte>(res.StrPtr, (int)res.StrLen);
        var memo = _memos[slot];
        if (memo?.Bytes != null && bytes.SequenceEqual(memo.Bytes)) return memo.Text;
        string text = Encoding.UTF8.GetString(res.StrPtr, (int)res.StrLen);
        _memos[slot] = new ResultMemo(bytes.ToArray(), 0, text);
        return text;
    }

    private string TextOf(int slot, in O5NativeResult res) {
        if (IsString(res)) return StringOf(slot, res);
        long bits = BitConverter.DoubleToInt64Bits(res.Num);
        var memo = _memos[slot];
        if (memo != null && memo.Bytes == null && memo.NumBits == bits) return memo.Text;
        string text = res.Num.ToString(CultureInfo.InvariantCulture);
        _memos[slot] = new ResultMemo(null, bits, text);
        return text;
    }

    private O5Value ValueOf(int slot, in O5NativeResult res) =>
        IsString(res) ? O5Value.FromStr(StringOf(slot, res)) : O5Value.FromNum(res.Num);

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
            return TextOf(MainSlot, res);
        }
    }

    public unsafe O5Value Execute(ReadOnlySpan<double> hostVars = default) {
        if (_handle == 0) return O5Value.Zero;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run(_handle, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return O5Value.Zero;
            return ValueOf(MainSlot, res);
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
            return TextOf(idx, res);
        }
    }

    public unsafe O5Value EvalTag(string tagName, ReadOnlySpan<double> hostVars = default) {
        if (!_tagLookup.TryGetValue(tagName, out int idx)) return O5Value.Zero;
        fixed (double* p = hostVars) {
            int rc = NativeO5Script.o5s_run_tag(_handle, (nuint)idx, p, (nuint)hostVars.Length, out var res);
            if (rc < 0) return O5Value.Zero;
            return ValueOf(idx, res);
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

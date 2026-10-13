using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using O5Script.Common;

namespace O5Script.Native;

[StructLayout(LayoutKind.Sequential)]
public unsafe struct O5NativeResult {
    public double Num;
    public byte* StrPtr;
    public uint StrLen;
    public byte ValType;
    private fixed byte _pad[3];

    public readonly O5Value ToValue() {
        if (ValType == (byte)O5Type.Str && StrPtr != null && StrLen > 0) {
            string s = Encoding.UTF8.GetString(StrPtr, (int)StrLen);
            return O5Value.FromStr(s);
        }
        return O5Value.FromNum(Num);
    }
}

internal static unsafe class NativeO5Script {
    private const string LibName = "o5script";
    private static readonly bool Available;

    public static bool IsAvailable => Available;

    static NativeO5Script() {
#if NETCOREAPP || NET5_0_OR_GREATER || NET6_0_OR_GREATER
        try {
            NativeLibrary.SetDllImportResolver(typeof(NativeO5Script).Assembly, (name, asm, path) => {
                if (name == LibName) {
                    foreach (string candidate in CandidatePaths()) {
                        if (File.Exists(candidate) && NativeLibrary.TryLoad(candidate, out var handle)) {
                            return handle;
                        }
                    }
                }
                return IntPtr.Zero;
            });
        } catch {
        }
#endif
        Available = TryLoad();
    }

    private static bool TryLoad() {
        try {
            foreach (string path in CandidatePaths()) {
                if (string.IsNullOrEmpty(path) || !File.Exists(path)) continue;
                if (Preload(path)) return true;
            }
        } catch {
        }
        return false;
    }

    private static IEnumerable<string> CandidatePaths() {
        var paths = new List<string>();
        void Add(string? p) {
            if (!string.IsNullOrEmpty(p) && !paths.Contains(p)) paths.Add(p);
        }

        string[] names = FileNames();

        try {
            Add(Environment.GetEnvironmentVariable("O5SCRIPT_PATH"));
            string? dir = Environment.GetEnvironmentVariable("O5SCRIPT_DIR");
            if (!string.IsNullOrEmpty(dir)) {
                foreach (string n in names) Add(Path.Combine(dir, n));
            }
        } catch {
        }

        try {
            string? self = typeof(NativeO5Script).Assembly.Location;
            if (!string.IsNullOrEmpty(self)) {
                string? selfDir = Path.GetDirectoryName(self);
                if (!string.IsNullOrEmpty(selfDir)) {
                    foreach (string n in names) {
                        Add(Path.Combine(selfDir, n));
                        Add(Path.Combine(selfDir, "runtimes", n));
                        Add(Path.Combine(selfDir, "UserLibs", n));
                    }
                }
            }
        } catch {
        }

        try {
            string cwd = Directory.GetCurrentDirectory();
            if (!string.IsNullOrEmpty(cwd)) {
                foreach (string n in names) {
                    Add(Path.Combine(cwd, n));
                    Add(Path.Combine(cwd, "native", "zig-out", "lib", n));
                    Add(Path.Combine(cwd, "..", "native", "zig-out", "lib", n));
                    Add(Path.Combine(cwd, "..", "..", "native", "zig-out", "lib", n));
                    Add(Path.Combine(cwd, "UserLibs", n));
                }
            }
        } catch {
        }

        try {
            string? baseDir = AppDomain.CurrentDomain.BaseDirectory;
            if (!string.IsNullOrEmpty(baseDir)) {
                foreach (string n in names) {
                    Add(Path.Combine(baseDir, n));
                    Add(Path.Combine(baseDir, "runtimes", n));
                    Add(Path.Combine(baseDir, "native", "zig-out", "lib", n));
                    Add(Path.Combine(baseDir, "..", "..", "..", "..", "native", "zig-out", "lib", n));
                    Add(Path.Combine(baseDir, "UserLibs", n));
                }
            }
        } catch {
        }

        return paths;
    }

    private static string[] FileNames() {
        if (Path.DirectorySeparatorChar == '\\') return new[] { "o5script.dll", "O5ScriptNative.win.dll" };
        if (File.Exists("/System/Library/CoreServices/SystemVersion.plist")) return new[] { "libo5script.dylib", "O5ScriptNative.mac.dylib" };
        return new[] { "libo5script.so", "O5ScriptNative.linux.so" };
    }

    private static bool Preload(string fullPath) {
        try {
            if (Path.DirectorySeparatorChar == '\\') {
                return LoadLibraryW(fullPath) != IntPtr.Zero;
            }
            const int RtldNow = 2;
            const int RtldGlobal = 0x100;
            try {
                if (DlopenLibDl2(fullPath, RtldNow | RtldGlobal) != IntPtr.Zero) return true;
            } catch {
            }
            try {
                if (DlopenLibDl(fullPath, RtldNow | RtldGlobal) != IntPtr.Zero) return true;
            } catch {
            }
        } catch {
        }
        return false;
    }

    [DllImport("libdl.so.2", EntryPoint = "dlopen", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr DlopenLibDl2(string fileName, int flags);

    [DllImport("libdl", EntryPoint = "dlopen", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr DlopenLibDl(string fileName, int flags);

    [DllImport("kernel32", EntryPoint = "LoadLibraryW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryW(string lpFileName);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern long o5s_compile(byte* src, nuint len);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void o5s_free(long h);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int o5s_run(long h, double* host_vars, nuint host_count, out O5NativeResult out_res);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int o5s_run_tag(long h, nuint tag_idx, double* host_vars, nuint host_count, out O5NativeResult out_res);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern nuint o5s_tag_count(long h);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern nuint o5s_tag_name(long h, nuint tag_idx, byte* out_buf, nuint max_buf);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern int o5s_tag_find(long h, byte* name_ptr, nuint name_len);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern nuint o5s_host_tag_count(long h);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern nuint o5s_host_tag_name(long h, nuint host_idx, byte* out_buf, nuint max_buf);

    [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
    public static extern void o5s_reset_state(long h);
}

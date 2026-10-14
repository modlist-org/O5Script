const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = true,
    });

    const lib = b.addLibrary(.{
        .name = "o5script",
        .root_module = mod,
        .linkage = .dynamic,
        .use_llvm = true,
    });
    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = true,
    });
    const exe = b.addExecutable(.{
        .name = "o5s",
        .root_module = exe_mod,
        .use_llvm = true,
    });
    b.installArtifact(exe);

    const bench_exe = b.addExecutable(.{
        .name = "o5s-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
        .use_llvm = true,
    });
    const bench_step = b.step("bench", "Run VM benchmarks (ReleaseFast)");
    bench_step.dependOn(&b.addRunArtifact(bench_exe).step);

    const test_step = b.step("test", "Run unit tests");
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit_tests = b.addTest(.{
        .name = "o5script-test",
        .root_module = test_mod,
        .use_llvm = true,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);
}

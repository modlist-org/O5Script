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
    mod.addAssemblyFile(b.path("src/vm_x86_64.S"));

    const lib = b.addLibrary(.{
        .name = "o5script",
        .root_module = mod,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = true,
    });
    exe_mod.addAssemblyFile(b.path("src/vm_x86_64.S"));
    const exe = b.addExecutable(.{
        .name = "o5s",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addAssemblyFile(b.path("src/vm_x86_64.S"));
    const unit_tests = b.addTest(.{
        .name = "o5script-test",
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);
}

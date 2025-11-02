const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests for the library (lightweight smoke)
    const run_root = b.addRunArtifact(b.addTest(.{ .root_module = root_mod }));
    const step_test = b.step("test", "Run ZSnapshot tests");
    step_test.dependOn(&run_root.step);

    // Make installable as a module
    const lib = b.addLibrary(.{
        .name = "zsnapshot",
        .root_module = root_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- Build options (exported via @import("build_options")) -------------
    const version = b.option([]const u8, "version", "Semantic version") orelse "0.1.0";
    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", version);

    // ---- Modules ------------------------------------------------------------
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_mod.addOptions("build_options", build_opts);

    const api_mod = b.createModule(.{
        .root_source_file = b.path("src/api.zig"),
        .target = target,
        .optimize = optimize,
    });

    const errors_mod = b.createModule(.{
        .root_source_file = b.path("src/errors.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bitset_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/bitset.zig"),
        .target = target,
        .optimize = optimize,
    });

    const crc64_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/crc64.zig"),
        .target = target,
        .optimize = optimize,
    });

    const container_mod = b.createModule(.{
        .root_source_file = b.path("src/internal/container.zig"),
        .target = target,
        .optimize = optimize,
    });
    container_mod.addImport("errors", errors_mod);

    const tbl1_mod = b.createModule(.{
        .root_source_file = b.path("src/formats/tbl1.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tbl2_mod = b.createModule(.{
        .root_source_file = b.path("src/formats/tbl2.zig"),
        .target = target,
        .optimize = optimize,
    });

    const registry_mod = b.createModule(.{
        .root_source_file = b.path("src/formats/registry.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ---- Wiring -------------------------------------------------------------
    // api
    api_mod.addImport("errors", errors_mod);
    api_mod.addImport("container", container_mod);
    api_mod.addImport("tbl1", tbl1_mod);
    api_mod.addImport("tbl2", tbl2_mod);
    api_mod.addImport("registry", registry_mod);

    // root
    root_mod.addImport("errors", errors_mod);
    root_mod.addImport("bitset", bitset_mod);
    root_mod.addImport("container", container_mod);
    root_mod.addImport("tbl1", tbl1_mod);
    root_mod.addImport("tbl2", tbl2_mod);
    root_mod.addImport("registry", registry_mod);
    root_mod.addImport("api", api_mod);

    // tbl1 deps
    tbl1_mod.addImport("errors", errors_mod);
    tbl1_mod.addImport("bitset", bitset_mod);
    tbl1_mod.addImport("crc64", crc64_mod);
    tbl1_mod.addImport("container", container_mod);

    // tbl2 deps (mirrors tbl1 + needs tbl1 for ColumnView reuse)
    tbl2_mod.addImport("errors", errors_mod);
    tbl2_mod.addImport("bitset", bitset_mod);
    tbl2_mod.addImport("crc64", crc64_mod);
    tbl2_mod.addImport("container", container_mod);
    tbl2_mod.addImport("tbl1", tbl1_mod); // <- fixes @import("tbl1") in tbl2.zig

    // registry deps
    registry_mod.addImport("errors", errors_mod);
    registry_mod.addImport("container", container_mod);
    registry_mod.addImport("tbl1", tbl1_mod);
    registry_mod.addImport("tbl2", tbl2_mod);

    // ---- Installable static lib ---------------------------------------------
    const lib = b.addLibrary(.{
        .name = "zsnapshot",
        .root_module = root_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // ---- Unit tests ---------------------------------------------------------
    const unit = b.step("test", "Run unit tests");
    inline for (&[_]*std.Build.Step{
        &b.addRunArtifact(b.addTest(.{ .root_module = root_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = api_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = errors_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = bitset_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = crc64_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = container_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = tbl1_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = tbl2_mod })).step,
        &b.addRunArtifact(b.addTest(.{ .root_module = registry_mod })).step,
    }) |s| unit.dependOn(s);

    // ---- Integration aggregator --------------------------------------------
    const have_integration = blk: {
        _ = std.fs.cwd().statFile("tests/test_all_integration.zig") catch break :blk false;
        break :blk true;
    };
    const integ = b.step("test-integration", "Run integration tests");
    if (have_integration) {
        const mod = b.createModule(.{
            .root_source_file = b.path("tests/test_all_integration.zig"),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("zsnapshot", root_mod);
        const run = b.addRunArtifact(b.addTest(.{ .root_module = mod }));
        integ.dependOn(&run.step);
    }

    // ---- E2E aggregator -----------------------------------------------------
    const have_e2e = blk: {
        _ = std.fs.cwd().statFile("tests/test_all_e2e.zig") catch break :blk false;
        break :blk true;
    };
    const e2e = b.step("test-e2e", "Run end-to-end tests");
    if (have_e2e) {
        const mod = b.createModule(.{
            .root_source_file = b.path("tests/test_all_e2e.zig"),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("zsnapshot", root_mod);
        const run = b.addRunArtifact(b.addTest(.{ .root_module = mod }));
        e2e.dependOn(&run.step);
    }

    // ---- Aggregate ----------------------------------------------------------
    const all = b.step("test-all", "Run unit + integration + e2e tests");
    all.dependOn(unit);
    all.dependOn(integ);
    all.dependOn(e2e);

    b.default_step = all;
}

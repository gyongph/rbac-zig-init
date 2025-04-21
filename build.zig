const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    const utils_mod = b.createModule(.{
        .root_source_file = b.path("lib/utils/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const type_utils_mod = b.createModule(.{
        .root_source_file = b.path("lib/type-utils.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rbac_mod = b.createModule(.{
        .root_source_file = b.path("lib/rbac/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    rbac_mod.addImport("httpz", httpz.module("httpz"));
    rbac_mod.addImport("pg", pg.module("pg"));
    rbac_mod.addImport("utils", utils_mod);
    rbac_mod.addImport("type-utils", type_utils_mod);

    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("httpz", httpz.module("httpz"));
    exe_mod.addImport("pg", pg.module("pg"));
    exe_mod.addImport("rbac", rbac_mod);
    exe_mod.addImport("utils", utils_mod);
    exe_mod.addImport("type-utils", type_utils_mod);

    const exe = b.addExecutable(.{
        .name = "template",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

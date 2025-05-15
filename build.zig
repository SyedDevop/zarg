const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose the zarg package as a module
    const zargPkg = b.addModule("zarg", .{
        .root_source_file = b.path("src/zarg.zig"),
    });

    // Build static library for zarg
    const lib = b.addStaticLibrary(.{
        .name = "zarg",
        .root_source_file = b.path("src/zarg.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Unit tests for the library
    const libTests = b.addTest(.{
        .root_source_file = b.path("src/zarg.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runLibTests = b.addRunArtifact(libTests);

    const testStep = b.step("test", "Run unit tests");
    testStep.dependOn(&runLibTests.step);

    // Generate and install documentation
    const installDocs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docsStep = b.step("docs", "Generate documentation");
    docsStep.dependOn(&installDocs.step);

    // Example executable that uses the zarg library
    const simple = b.addExecutable(.{
        .name = "simple",
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple.root_module.addImport("zarg", zargPkg);
    b.installArtifact(simple);

    // Define run step for the example
    const runSimple = b.addRunArtifact(simple);
    runSimple.step.dependOn(b.getInstallStep());
    if (b.args) |args| runSimple.addArgs(args);

    const runStep = b.step("run", "Run the simple example app");
    runStep.dependOn(&runSimple.step);
}

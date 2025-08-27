const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose the zarg package as a module
    const zargPkg = b.addModule("zarg", .{
        .root_source_file = b.path("src/zarg.zig"),
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/zarg.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Build static library for zarg
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zarg",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // Unit tests for the library
    const libTests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zarg.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/simple.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    simple.root_module.addImport("zarg", zargPkg);
    b.installArtifact(simple);

    // Define run step for the example
    const runSimple = b.addRunArtifact(simple);
    runSimple.step.dependOn(b.getInstallStep());
    if (b.args) |args| runSimple.addArgs(args);

    const runStep = b.step("run", "Run the simple example app");
    runStep.dependOn(&runSimple.step);

    const ter = b.addExecutable(.{
        .name = "terminal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/terminal.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    ter.root_module.addImport("zarg", zargPkg);
    b.installArtifact(ter);

    // Define run step for the example
    const runTerminal = b.addRunArtifact(ter);
    runTerminal.step.dependOn(b.getInstallStep());
    if (b.args) |args| runTerminal.addArgs(args);

    const runStepT = b.step("runt", "Run the terminal example app");
    runStepT.dependOn(&runTerminal.step);
}

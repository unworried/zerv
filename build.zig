const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zerv = b.addModule("zerv", .{
        .root_source_file = b.path("src/zerv.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example = b.addExecutable(.{
        .name = "basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    example.root_module.addImport("zerv", zerv);

    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run", "Run the basic example");
    run_step.dependOn(&run_example.step);

    const install_example = b.step("install-example", "Install the basic example");
    install_example.dependOn(&b.addInstallArtifact(example, .{}).step);
}

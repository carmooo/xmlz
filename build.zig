const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("xml", .{
        .root_source_file = b.path("src/XML.zig"),
        .target = target,
    });
    const exe = b.addExecutable(.{
        .name = "xml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/XML.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "xml", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

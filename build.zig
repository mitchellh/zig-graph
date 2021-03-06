const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("graph", "src/graph.zig");
    lib.setBuildMode(mode);

    var main_tests = b.addTest("src/graph.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    b.default_step.dependOn(&lib.step);
    b.installArtifact(lib);
}

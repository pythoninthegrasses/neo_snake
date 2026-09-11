const std = @import("std");

// Tier-A build for the pure-Zig core (docs/build-layout.md): one root module
// per doc-concern (rng.zig, canon.zig), one test step each, both under the
// single `test` step so `zig build test` runs them together. No libc is linked
// (modules omit link_libc) and no allocator is used, so this code can later
// target freestanding/WASM (TASK-047) without relinking. core/corpus.zig is
// generated data and is deliberately not in the graph.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run Tier-A unit tests for the core modules");

    const rng = b.createModule(.{
        .root_source_file = b.path("rng.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rng_test = b.addTest(.{ .root_module = rng });
    test_step.dependOn(&b.addRunArtifact(rng_test).step);

    const canon = b.createModule(.{
        .root_source_file = b.path("canon.zig"),
        .target = target,
        .optimize = optimize,
    });
    const canon_test = b.addTest(.{ .root_module = canon });
    test_step.dependOn(&b.addRunArtifact(canon_test).step);
}

const std = @import("std");

// Tier-A build for the pure-Zig core (docs/build-layout.md): one root module
// per doc-concern (rng.zig, canon.zig, world.zig), one test step each, all
// under the single `test` step so `zig build test` runs them together. No
// libc is linked (modules omit link_libc) and no allocator is used, so this
// code can later target freestanding/WASM (TASK-047) without relinking.
// core/corpus.zig is generated data and is deliberately not in the graph.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run Tier-A unit tests for the core modules");

    // rng/canon/world carry `.pic = true` because they're also compiled
    // into abi_lib below (via addImport), which the GDExtension shim
    // (extension/SConstruct, TASK-026) links into a shared library --
    // non-PIC relocations in that static archive fail at that final
    // `ld -shared` step. Harmless for their own plain test binaries here.
    const rng = b.createModule(.{
        .root_source_file = b.path("rng.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    const rng_test = b.addTest(.{ .root_module = rng });
    test_step.dependOn(&b.addRunArtifact(rng_test).step);

    const canon = b.createModule(.{
        .root_source_file = b.path("canon.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    const canon_test = b.addTest(.{ .root_module = canon });
    test_step.dependOn(&b.addRunArtifact(canon_test).step);

    // world.zig consumes the RNG stream and the canonical POD types, so it
    // imports both modules directly (the "more than one of these together"
    // case docs/build-layout.md anticipates — imports, not an aggregator).
    const world = b.createModule(.{
        .root_source_file = b.path("world.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    world.addImport("rng", rng);
    world.addImport("canon", canon);
    const world_test = b.addTest(.{ .root_module = world });
    test_step.dependOn(&b.addRunArtifact(world_test).step);

    // fuzz_seeds is Tier-B (docs/build-layout.md): 256 committed seeds
    // checked against structural invariants rather than a recorded oracle
    // trace, driving rng/canon/world directly — same no-allocator, no-libc
    // constraints, so it belongs in `test_step` alongside them, not in the
    // difftest/corpus executable below.
    const fuzz_seeds = b.createModule(.{
        .root_source_file = b.path("fuzz_seeds.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_seeds.addImport("rng", rng);
    fuzz_seeds.addImport("canon", canon);
    fuzz_seeds.addImport("world", world);
    const fuzz_seeds_test = b.addTest(.{ .root_module = fuzz_seeds });
    test_step.dependOn(&b.addRunArtifact(fuzz_seeds_test).step);

    // difftest replays the committed JSONL corpus against world.zig
    // (TASK-020) — a separate executable/step, not folded into `test`,
    // since it needs an allocator and file I/O that rng/canon/world
    // themselves must stay free of (see difftest.zig's header comment).
    const corpus = b.createModule(.{
        .root_source_file = b.path("corpus.zig"),
        .target = target,
        .optimize = optimize,
    });
    const difftest = b.createModule(.{
        .root_source_file = b.path("difftest.zig"),
        .target = target,
        .optimize = optimize,
    });
    difftest.addImport("rng", rng);
    difftest.addImport("canon", canon);
    difftest.addImport("world", world);
    difftest.addImport("corpus", corpus);
    const difftest_exe = b.addExecutable(.{ .name = "difftest", .root_module = difftest });
    const run_difftest = b.addRunArtifact(difftest_exe);
    const difftest_step = b.step("difftest", "Replay the committed JSONL corpus against core/world.zig");
    difftest_step.dependOn(&run_difftest.step);

    // abi.zig (TASK-024) is the only Zig file in the project with `export`
    // symbols, wrapping rng/canon/world behind include/neo_snake.h's exact
    // surface. Built as a static library so a C/C++ consumer (the
    // GDExtension shim, TASK-025's Tier-C conformance tests) can link
    // against it without touching Zig's own module system. Attached to the
    // default "install" step (unlike fuzzrun below) since it's the actual
    // deliverable, not a dev-only tool.
    const abi = b.createModule(.{
        .root_source_file = b.path("abi.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    abi.addImport("rng", rng);
    abi.addImport("canon", canon);
    abi.addImport("world", world);
    const abi_lib = b.addLibrary(.{
        .name = "neo_snake",
        .linkage = .static,
        .root_module = abi,
    });
    b.installArtifact(abi_lib);
    const abi_step = b.step("abi", "Build the static library exporting the C ABI (core/abi.zig)");
    abi_step.dependOn(&b.addInstallArtifact(abi_lib, .{}).step);

    // abitest (TASK-025) is the Tier-C conformance suite: it reaches abi_lib
    // exclusively through @cImport(include/neo_snake.h) — no addImport of
    // rng/canon/world/corpus at all, enforced separately at the source level
    // by tools/validate_abi_test_purity.py. link_libc is required for
    // @cImport's generated bindings; linking abi_lib supplies the actual
    // ns_* symbol implementations behind those declarations.
    const abitest = b.createModule(.{
        .root_source_file = b.path("abitest.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    abitest.addIncludePath(b.path("../include"));
    abitest.linkLibrary(abi_lib);
    const abitest_exe = b.addTest(.{ .root_module = abitest });
    const run_abitest = b.addRunArtifact(abitest_exe);
    const abitest_step = b.step("abitest", "Run the Tier-C ABI conformance tests (core/abitest.zig)");
    abitest_step.dependOn(&run_abitest.step);

    // fuzzrun is oracle:fuzz's (TASK-022) live Zig half: unlike difftest, it
    // takes a *fresh*, non-committed command-log path at runtime (built by
    // reference/oracle/fuzz.mjs), so it's installed to a stable path
    // (zig-out/bin/fuzzrun) rather than run here — fuzz.mjs invokes the
    // binary directly once per generated seed. Deliberately not attached to
    // the default "install" step; only `zig build fuzzrun` builds it.
    const fuzzrun = b.createModule(.{
        .root_source_file = b.path("fuzzrun.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzzrun.addImport("canon", canon);
    fuzzrun.addImport("world", world);
    const fuzzrun_exe = b.addExecutable(.{ .name = "fuzzrun", .root_module = fuzzrun });
    const install_fuzzrun = b.addInstallArtifact(fuzzrun_exe, .{});
    const fuzzrun_step = b.step("fuzzrun", "Build the live fuzz-runner executable used by task oracle:fuzz");
    fuzzrun_step.dependOn(&install_fuzzrun.step);
}

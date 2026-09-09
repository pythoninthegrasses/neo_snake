---
id: m-4
title: "Phase 4: C ABI, godot-cpp shim, Tier-C/D"
---

## Description

Hand-written include/neo_snake.h as the frozen contract, core/abi.zig as the only file with `export`, Tier-C @cImport-only conformance tests plus the ABI-test-purity validator, the extension/ SConstruct + godot-cpp shim, game/simulation/world.gd, and Tier-D corpus replay through the real GDExtension — the load-bearing checksum-across-four-implementations assertion. Also the inverted simulation-boundary validator and .gdextension platform-key check.

---
id: decision-030
title: 'Web GDExtension: nothreads dlink needs no COOP/COEP headers (Go)'
date: '2026-09-13 19:09'
status: Accepted
---
## Context

TASK-047 is a spike proving the Zig+godot-cpp WASM toolchain end to end (AC#1/#2) and settling an
apparent contradiction in Godot 4.7's own docs (AC#3): "Exporting for the Web" states that enabling
Extensions Support "requires the use of cross-origin isolation headers," unqualified — yet a
`web_dlink_nothreads_*` export template variant exists specifically to combine GDExtension support
with threading *disabled*. If the docs' blanket claim were true, that variant's whole reason for
existing (avoiding COOP/COEP, since itch.io/GitHub Pages hosting can't set custom response headers)
would be pointless. Both readings can't be fully true, and the answer determines whether this repo
can ship a web build to itch.io/GitHub Pages at all without a custom-header-capable host.

**Toolchain chain proven (AC#1/#2).** `task web:bootstrap` (new `taskfiles/web.yml`) runs `mise
install emsdk@4.0.11` — confirmed absent from `.tool-versions` (task-002's rationale: emsdk is
heavy/on-demand, activated per-invocation via `mise exec emsdk@4.0.11 -- ...`, never `mise use`).
A trivial Zig source (`export fn hello_value() i32 { return 42; }`) built cleanly via `zig build-lib
-target wasm32-emscripten --sysroot $EMSDK/upstream/emscripten -OReleaseSmall`. A minimal
`WebSpikeHello : RefCounted` GDExtension (godot-cpp bindings, one bound method wrapping
`hello_value()`) built via `scons platform=web arch=wasm32 threads=no lto=none
target=template_release` against `third_party/godot-cpp` produced
`libwebspike.web.template_release.wasm32.nothreads.wasm` (1.04 MB).

**Root-caused the docs contradiction by reading Godot engine source, not just docs/forum posts.**
`platform/web/detect.py` (engine repo, 4.7-stable) shows `dlink_enabled` (GDExtension support) and
`threads` are two entirely independent SCons flags: `dlink_enabled` only adds `-sSIDE_MODULE=2`,
`-fvisibility=hidden`, and a `WEB_DLINK_ENABLED` define; `-sUSE_PTHREADS=1` /
`SharedArrayBuffer`-dependent flags are gated solely on `env["threads"]`. Nothing in the WASM-level
build ties GDExtension loading to thread support. Separately,
`platform/web/export/export_plugin.h`'s `_get_template_name(extension, thread_support, debug)`
confirms `web_dlink_nothreads_release.zip` is exactly what `variant/extensions_support=true` +
`variant/thread_support=false` + release selects — so this spike's export preset genuinely exercised
the named template, not a lookalike.

The one place cross-origin-isolation headers get *self-injected* regardless of hosting is a
generated service worker (`misc/dist/html/service-worker.js`'s `ensureCrossOriginIsolationHeaders`)
— but that file is only emitted when `progressive_web_app/enabled=true`
(`export_plugin.cpp::get_export_options`, default `false`). It is unrelated to
`variant/extensions_support` and was left disabled for this spike's preset specifically to rule out
the service worker masking the answer.

**Empirically verified in a real browser, not asserted from reading source alone.** Exported the
spike project headlessly (`godot --headless --export-release "Web"`) with
`variant/extensions_support=true`, `variant/thread_support=false`,
`progressive_web_app/enabled=false`. Served the output with plain `python3 -m http.server` (no
custom headers of any kind) and loaded it with Playwright/Chromium
(`chromium-1243`, downloaded via `npx playwright install chromium` — this host's RHEL 10 base has no
`apt-get`, so `--with-deps` failed and was skipped; the browser binary alone was sufficient headless).
Result: `crossOriginIsolated: false` in the page, zero `pageerror`s, and the console shows `Build
configuration: Emscripten 4.0.20, single-threaded, GDExtension support.` followed by `hello_value=42`
— the GDExtension loaded, and its FFI call through to the Zig-compiled `hello_value()` returned the
correct value, entirely without cross-origin isolation.

## Decision

**Go.** A nothreads + dlink (`web_dlink_nothreads_release`) web build does not require COOP/COEP
headers — Godot's docs statement is correct only for the threaded case and is misleadingly
unqualified as written; the godot-rust book's troubleshooting note ("Godot 4.3 games exported without
Thread Support are not subject to this restriction") is the accurate one. This repo can ship its web
build to itch.io/GitHub Pages (or any static host with no custom-header support) using
`web_dlink_nothreads_release`/`_debug`, with `progressive_web_app/enabled=false` (or, if a PWA is
wanted later, with `progressive_web_app/ensure_cross_origin_isolation_headers=false` to avoid the
service worker forcing headers a nothreads build doesn't need).

Since this is a Go, the GDScript-reimplementation fallback plan (AC#4's "if no-go" branch) was not
exercised and is not needed — noted here only to close out AC#4's requirement explicitly.

## Consequences

- The eventual "ship the real web build" task can build `neo_snake`'s actual core/GDExtension the
  same way this spike did — `web.py`'s SCons flags and the export preset options are unaffected by
  which GDExtension is being built — and can target itch.io/GitHub Pages directly, no reverse proxy
  or custom-header CDN config needed.
- If a future requirement calls for Thread Support (e.g. a performance need this repo doesn't
  currently have), that reintroduces the real COOP/COEP requirement and this decision's Go does not
  carry over to that variant — re-verify empirically rather than assuming.
- The throwaway hello-world GDExtension, its Zig stub, and the scratch Godot project used for this
  spike were built entirely outside the repo (session scratchpad) per the task's own framing and are
  not part of this change; only `taskfiles/web.yml`, this decision, and the accompanying docs update
  land.

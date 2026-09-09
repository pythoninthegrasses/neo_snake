---
id: decision-012
title: Focus-out pause covering Android
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` pauses on window `blur` (line 620:
`addEventListener("blur", () => { if (S.status === "playing") togglePause(); })`),
which reliably fires on desktop browsers when focus leaves the tab/window,
but is not a dependable signal on Android, where backgrounding an app/webview
does not always deliver a `blur` event the same way (or at all, depending on
browser/webview implementation) before the app is suspended.

## Decision

Cover the focus-out-pause behavior with the platform-appropriate
lifecycle/visibility signal on each target, explicitly including Android
(e.g. an application-pause/visibility-change notification), not solely a
`blur`-equivalent event, so backgrounding reliably pauses simulation on every
supported platform.

## Consequences

Pause-on-background is more robust than the oracle across platforms; this
is a behavior a differential oracle-vs-Godot test cannot meaningfully cover
(it depends on OS-level lifecycle events the oracle has no concept of), so
correctness here relies on manual/platform testing rather than the
oracle-parity corpus.


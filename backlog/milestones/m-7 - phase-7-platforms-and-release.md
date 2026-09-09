---
id: m-7
title: "Phase 7: Platforms and release"
---

## Description

macOS arm64 first (native build, then signing/notarization) as the primary platform per ~/git/mt; Linux x86_64 via Docker; Windows x86_64 via mingw cross or native runner; the web spike (highest-risk item) and real web build; thin CI wired entirely through taskfiles/ci.yml one-liners with a self-hosted macOS runner, verifiable locally with act; and release asset publishing plus the README download table.

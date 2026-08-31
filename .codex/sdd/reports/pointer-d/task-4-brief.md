# Pointer D Task 4 Brief — Persistent Chrome and Common Path

Implement only Task 4 of `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`.

## Baseline and scope

- Immutable baseline: commit `caa2bd0` (accepted B-core, immediately before C product-surface work).
- Candidate: current HEAD after reconciled C and D Tasks 1–3.
- Create `Tests/PointerAppKitTests/ChromeFrictionTests.swift`; modify D-owned render/guide tests only if needed for inventory assertions.
- Do not edit C-owned palette/menu/controller production. If honest measurements fail the required reduction, report the smallest concrete redundant persistent-chrome finding for a C worker; do not alter counts, hide accessibility controls, or manufacture a deletion in D.

## Required inventory

Record exact baseline/candidate identities and counts for always-visible controls, palette rows, visible status elements, focus stops, and the fresh-launch Arrow → draw → standby path’s required clicks, keys, and semantic steps. List additions/removals and explain how counts are derived from source/runtime metadata. The candidate must not increase any persistent dimension or common-path interaction count and must decrease at least one persistent dimension.

The first-use guide is nonpersistent and must not be counted as permanent chrome; its availability may not add a required common-path step. Essential keyboard/accessibility routes remain intact.

## Verification and handoff

Use strict RED/GREEN TDD. Run `ChromeFrictionTests`, related render/guide tests, full `swift test`, build, and `git diff --check`. Write `.codex/sdd/reports/pointer-d/task-4-report.md` with exact counts, commands, results, and any C-owned finding. Do not commit.

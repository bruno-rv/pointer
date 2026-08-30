# Pointer D Task 1 Brief — Render Plan

Implement only Task 1 of `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`.

## Scope

- Create `Sources/PointerAppKit/Rendering/RenderPlan.swift`.
- Create `Sources/PointerAppKit/Rendering/HandleInventory.swift`.
- Modify `Sources/PointerAppKit/MarkRenderer.swift`.
- Create `Tests/PointerAppKitTests/RenderPlanTests.swift`.
- Create `Tests/PointerAppKitTests/VisualFixtures.swift`.
- Do not edit `CanvasView.swift`, guide/help files, assets, package/build files, or other phase paths.

## Required outcome

The public top-level render plan preserves committed marks in standby while removing drafts, selection, hover, resize handles, and contextual delete. Annotation restores only explicit inventories. Offscreen pixel evidence uses the exact plan geometry, sentinel rules, and literal digest in the D plan. The accepted handoff must state the exact later B `CanvasView` integration sequence and must not claim live integration.

## Verification

Use strict RED/GREEN TDD. Run the Task 1 focused tests, related renderer/canvas tests, full `swift test`, `swift build`, and `git diff --check`. Write the evidence report to `.codex/sdd/reports/pointer-d/task-1-report.md`. Do not commit.

# Pointer D Task 2 Brief — First-Use Guide

Implement only Task 2 of `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`.

## Scope

- Consume, never redeclare, `Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift` and `FirstUseGuidePresenting.swift`.
- Create `UserDefaultsFirstUseGuideStateStore.swift`, `FirstUseGuideController.swift`, `FirstUseGuideViewController.swift`, and `GuideAssetCatalog.swift`.
- Create `FirstUseGuideTests.swift` and `FirstUseGuideTestFixtures.swift`.
- Do not edit C controller/composition files, `main.swift`, rendering files, assets, package/build files, or other phase paths.

## Required outcome

Implement the catalog-injected, non-modal, accessible guide state machine. `GuidePresentationResult.shown` is valid only after an actually visible panel; `.failed` and `.notNeeded` remain distinct. Display-loss hiding is non-committing and retryable; application stop clears transient restore intent. The guide never mutates mode, tool, selection, or canvas. Every example resolves only through the injected catalog. `GuideAssetCatalogEnvelope` includes exact `schemaVersion`, stable `catalogIdentifier = pointer.first-use-guide.v1`, and `entries`; no default bundle/image lookup or protocol redeclaration.

## Verification

Use strict RED/GREEN TDD. Run focused guide/source-contract tests, full `swift test`, `swift build`, and `git diff --check`. Write the evidence report to `.codex/sdd/reports/pointer-d/task-2-report.md`. Do not commit.

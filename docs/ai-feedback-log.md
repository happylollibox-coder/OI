# AI Feedback Log

Opus maintains this log to track Composer's performance patterns and planning trust. This drives two decisions:
1. **Spec detail**: How much detail Opus puts into its own plan (lighter where Composer excels).
2. **Delegation**: Which task patterns Composer can own end-to-end (skip Phases 3-5 of the workflow).

Opus reads this file BEFORE every planning session.

---

## How to Read This File

- **Planning Trust Scores**: Per-task-pattern confidence that Composer can plan correctly. Starts at 0%. Delegation threshold: 80% over 3+ tasks.
- **Delegated Patterns**: Task types where Composer skips the competition protocol and plans independently. Opus still reviews.
- **Strengths / Weak Spots**: Implementation-level patterns (not planning).
- **Task Observations**: Per-task notes including plan comparison results.

---

## Planning Trust Scores

Trust is earned per task pattern. Score reflects how close Composer's blind plan was to the optimal plan.

| Task Pattern | Score | Tasks Scored | Trend | Delegated? | Notes |
|---|---|---|---|---|---|
| Multi-file config extraction | 0% | 0 | -- | No | Cycle 1 used old workflow (no blind comparison). Re-score on next occurrence. |
| Component extraction (React) | 0% | 0 | -- | No | Same — re-score on next occurrence. |
| Import refactors / find-and-replace | 0% | 0 | -- | No | Expected to score high based on implementation quality. |
| CI/CD pipeline setup | 0% | 0 | -- | No | Expected to score low — architecture-heavy. |
| BigQuery migration runner | 0% | 0 | -- | No | Expected to score low — novel design. |
| New CRUD entity generation | 0% | 0 | -- | No | Expected to score low — multi-layer pattern. |

### Scoring Guide

After each blind comparison (Phase 4), Opus scores Composer's plan:

| Score Range | Meaning | Action |
|---|---|---|
| **90-100%** | Composer's plan was essentially correct; minor differences only | Strong delegation candidate |
| **70-89%** | Plan was mostly right but missed important details or risks | Keep in competition protocol; note specific gaps |
| **50-69%** | Significant gaps — missed steps, wrong patterns, or missed risks | Opus plan is clearly better; keep detailed specs |
| **0-49%** | Major gaps — would have caused implementation failures | Opus must provide heavy-detail specs |

### Delegation Rules

- **To delegate**: Score >= 80% on 3+ consecutive tasks of that pattern. Opus writes a delegation entry below.
- **To revoke**: Any task where Composer's independent plan scores < 60%, OR implementation of a delegated task fails. Opus writes a revocation entry.

## Delegated Patterns

*None yet — all patterns currently go through the full competition protocol.*

<!-- Template:
| Pattern | Delegated Date | Reason | Conditions |
|---|---|---|---|
| [pattern] | YYYY-MM-DD | [3+ tasks scored 80%+, examples: ...] | Revoke if score drops below 60% |
-->

## Revoked Delegations

*None yet.*

<!-- Template:
| Pattern | Revoked Date | Reason | Original Delegation Date |
|---|---|---|---|
| [pattern] | YYYY-MM-DD | [what went wrong] | YYYY-MM-DD |
-->

---

## Strengths (Composer implementation — does well)

| Area | Notes | Confidence |
|------|-------|------------|
| Multi-file find-and-replace refactors | Followed 11-step config extraction across 10 files flawlessly. Import patterns, variable removal, and BASE_* tuple replacements all correct. | High |
| Shared component extraction (React) | Created 4 new files, removed inline duplicates from 4 pages, updated imports in 7 pages. Zero TypeScript errors introduced. | High |
| Following explicit skip lists | When told to skip 4 pages for PageHeader, did so correctly without touching them. | High |
| Defensive TypeScript patterns | Proactively added `(meta.fmtShort ?? meta.fmt)(v)` fallback when centralized type made `fmtShort` optional. Correct and not an architecture deviation. | Medium |
| Test execution and reporting | Ran all test scripts verbatim, pasted full output, correctly identified pre-existing vs. new failures. | High |

## Weak Spots (Composer implementation — needs extra detail)

| Area | Typical failure | Mitigation for specs |
|------|----------------|---------------------|
| *No weak spots observed yet* | First cycle was clean | Continue monitoring with more complex tasks (CI/CD, migration runner) |

---

## Task Classification Guide

Quick reference for Composer's self-assessment in Phase 2. Based on actual results + trust scores.

### Likely Composer-Ready (pending trust score confirmation)

| Task Pattern | Example | Expected Score |
|---|---|---|
| Single-file or multi-file config extraction | Shared `config.py` across 10 Python files | High |
| Component extraction (React) | Extract `Section.tsx` from 4 pages, update imports | High |
| Import refactors / find-and-replace | Replace inline constants with imports across files | High |
| Creating standalone components from spec | `PageSelect.tsx`, `PageHeader.tsx` from provided code | High |
| Centralizing shared constants | `MEASURE_META` into `constants.ts`, update 2 consumers | High |

### Likely Needs Opus

| Task Pattern | Why | Example |
|---|---|---|
| CI/CD pipeline setup | Multi-system, new infrastructure, architecture decisions | GitHub Actions for BigQuery + Cloud Run + Cloud Functions |
| BigQuery migration runner | New tool design, data model decisions | Python script with `_MIGRATION_HISTORY` table |
| New CRUD entity generation | Architecture decisions, multi-layer pattern (DDL + routes + templates) | Adding a new entity to Flask data-entry app |
| Unified deploy command | Multi-system orchestration, error handling design | `make deploy-all` composing 6+ scripts |
| New dashboard page agent | Template design decisions, registration across files | Cursor skill/rule for scaffolding pages |
| New BigQuery object agent | Template design, config.yaml integration | Cursor skill/rule for scaffolding SQL + config |

### Unclassified (needs data from competition protocol)

| Task Pattern | Last Attempted | Result |
|---|---|---|
| Pre-commit hooks setup (husky + lint-staged + ruff + sqlfluff) | Not yet | -- |
| Fixing pre-existing lint/build errors across multiple files | Not yet | -- |
| Adding URL-based routing (React Router) | Not yet | -- |
| Refactoring monolithic `app.py` into service layer | Not yet | -- |

---

## Task Observations

### Cycle 1: Shared Config Module + Extract Shared Components

**Task**: Task Spec A (Shared Config Module) + Task Spec B (Extract Shared Frontend Components)
**Date**: 2025-03-05
**Status**: COMPLETE
**Planning comparison**: N/A — used old workflow (no blind competition). Composer did not produce an independent plan for this cycle.
**Spec quality**: High. Numbered steps with exact file paths, line numbers, reference code, acceptance criteria, and test scripts. Pre-made architecture decisions (which pages to skip for PageHeader) eliminated ambiguity. Test scripts caught pre-existing issues cleanly.
**Composer performance**:
- What it did well: Executed all 19 steps (11 + 8) across 20+ files with zero introduced errors. Correctly handled edge cases called out in the spec (DATASET vs DATASET_ID, BASE_* tuples, dynamic PageHeader titles). Added a smart defensive pattern for optional fmtShort. Test reporting was thorough and honest (flagged pre-existing failures without claiming them as new).
- What it missed or got wrong: Nothing. Clean execution.
- Root cause: N/A — no failures.
**Action**: Next time these patterns appear, run the full competition protocol to establish trust scores. Based on implementation quality, expect Composer to score well on mechanical refactors.

### [Template — copy for each reviewed task]

<!--
**Task**: [title]
**Date**: YYYY-MM-DD
**Status**: COMPLETE | PARTIAL | BLOCKED
**Planning comparison**:
- Composer plan score: [0-100%]
- What Composer got right:
- What Composer missed:
- What Composer added that Opus didn't think of:
- Final decision: [Composer's plan / Opus's plan / merged]
**Spec quality**: [How good was the winning plan?]
**Composer performance**:
- What it did well:
- What it missed or got wrong:
- Root cause (plan gap vs. model limitation):
**Trust score update**: [pattern] moved from X% to Y%
**Action**: [How to adjust future handling]
-->

---

*This file is maintained by Opus after each task review cycle. Do not edit manually unless correcting an error.*

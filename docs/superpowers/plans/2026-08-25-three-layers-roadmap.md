# Three Layers — the roadmap

The two-minute version of `docs/superpowers/plans/2026-08-25-three-layers-gap-closure.md` (88 tasks,
14 phases, ~530 hours). **Work from this; that document is the reference.** Doctrine:
`architecture/THREE_LAYERS.md`. Baseline and queries: `docs/superpowers/specs/2026-08-24-three-layers-baseline.md`.

Each phase ships on its own and leaves the system working. The order is set by four rules in priority:
**memory first, then safety, then dependency, then money** — with the season's calendar allowed to pull
one phase earlier.

## Out of sequence, by Ori's call: the weekly book (2026-08-25)

Ori: *"I want to be able to deliver a working product as soon as possible and then enhance it (maybe
priority will change after trying it)"* — and, asked what that meant: *"you can create bulksheet that
support the 3 tiers and can explain each action."*

So `tools/build_weekly_book.py` was built ahead of every phase below. It is deliberately **not** a
phase: it closes no violation and decides nothing. It assembles what the nine existing builders already
decide into one workbook, ranks conflicting rows under Catalog > Brain > Pacing, and gives every row
three sentences naming the layer that produced each one. SOP: `architecture/WEEKLY_BOOK.md`.

**Why this ordering is right rather than a detour.** The phases below are ordered for *correctness*;
this is ordered for *feedback*. Until the decisions are visible in one place, a priority change after
trying it — which is what Ori asked for the option to do — has nothing to act on. It also makes the
phases below arguable row by row instead of in the abstract: the first build showed CATALOG 2, BRAIN 42,
PACING 17, which says on its face that the Brain's budget arm is carrying nearly everything and the
Catalog is barely speaking. That is a finding no plan document produced in a week of work.

**It also found a live defect in its own first build**: 3 of 42 campaign budget rows carried a blank
`Portfolio ID`, which on a Campaign Update row does not mean *unchanged* — it **detaches** the campaign
from its portfolio. Preflight now refuses rather than warns.

## The phases

| # | phase | closes | size | why it sits here |
|---|---|---|---|---|
| **0** | **Start both clocks** | 6, 13 (recording) | **1–2 days** | Moves no money on purpose. Every night without it is history that can never be recovered — and nothing later can be shown to have helped. |
| **1** | **Precedence, and a ceiling that binds** | 15 | 2–4 days | Pure safety, and the doctrine's own motivating failure: a known-correct price sat unexecuted for 20 days while a mechanics rule filled the vacuum. Must precede anything that speeds execution up. |
| **2** | **Everything that spends is judged** | 4 (coverage) | 4–7 days | The largest survivor by current spend: **$132.71/day at 0.528 GP-ROAS** on rows no layer can see. |
| **3** | **Join campaign history on the id** | 23 | 2–3 days | Cheap, independent, and a hard prerequisite for both seasonal phases. **53 real campaign ids carry more than one name, covering 46.7 % of real-id lifetime spend** ($258,178 of $552,602), plus 6 names each shared by two ids, merging $68,126. (The 54-ids / 61 % first stated here counted the `-1` sentinel as a campaign — see the sentinel note below.) |
| **4** | **The campaign becomes a subject** | 22 (OPEN) | 1.5–2.5 wk | ⏰ **Dated.** Ten paused campaigns hold **$127,352** of last-season sales at 1.49 GP-ROAS, none with a reopen date. |
| **5** | **Seasonality reaches the verdict** | 2 | 2–3 wk | ⏰ **Dated.** The doctrine's most expensive mistake — collapsing *not now* into *never*. |
| **6** | **The Brain stops saying "nothing to do"** | 7, 8, 9, 11, 14 | 3–4 wk | Five violations, one file pair, one change window. |
| **7** | **Confidence, and the door that only opens on it** | 19, 20, 22 (CLOSE) | 1.5–2 wk | §5's irreversibility rule is unenforceable until confidence is computed. Gates every one-way action. |
| **8** | **The four-field contract, and the first lean-in** | 1, 10 | 1.5–2 wk | Deliberately late: publishing `verdict` before seasonality and confidence existed would be a rename, not a fix. |
| **9** | **Negatives get an owner, a book and an expiry** | 24, 25 | 1–1.5 wk | Independent; can slip without stalling anything. |
| **10** | **The response curve, and Pacing graded** | 3, 17, 13 (grading) | 2–3 wk | The only phase gated by *elapsed time* — it needs weeks of the clock started in Phase 0. |
| **11** | **Demand data enters on probation** | 4 (demand), 21 | 1–1.5 wk | Market volume and headroom. |
| **12** | **`rank()`, and the Brain becomes proactive** | 5 | 1.5–2 wk | Needs the ceiling (10), confidence (7) and volume (11) first. |
| **13** | **The vehicle** | 18 | 2–3 wk | Last, and gated on data availability rather than effort. |

Violations **12** and **16** need no phase — the baseline corrected them (§10.3).

## The `-1` sentinel — a hole in last season's evidence that Phase 3 does NOT close

Measured 2026-08-25 while scoping Phase 3. `campaign_id = -1` is not a campaign; it is the absence of
one, and it appears twice in this system with different urgencies:

- **Campaign grain — historical, unfixable forward.** Spend arrived under `-1` until **2025-10-27** and
  never since. In last season alone (2025-09-01..12-31) that is **$32,773 of spend and $91,733 of sales
  across 29 campaign names — 10.8 % of the season's sales with no campaign identity at all.** Real ids
  begin 2025-10-28. Joining on the id rather than the name does not recover this: there is no id to
  join to. Phases 4 and 5 must therefore treat the first ~8 weeks of last season as evidence that
  exists at the account and family grain but **not** at the campaign grain, and say so rather than
  reading a campaign's season record as thin.
- **Target grain — live today.** The same sentinel makes 48 SB product targets unpriceable, spending as
  recently as 2026-08-23. That is Phase 2's `$64.38/day`, and it IS fixable forward.

Both were found by looking at the same `-1`. Neither is a rename, which is why Phase 3 leaves both standing.

## The deadline that shapes everything

**Phases 4 and 5 are dated; the rest are not.** Ten paused campaigns carry $127,352 of last-season sales
and nothing holds a reopen date, so if they are to run this season they must be reopened **before** it —
and §4.1 requires lead time, because a campaign enabled on day one of its season has not been running
when the season starts. Phase 3 is a hard prerequisite for both. That chain — **3 → 4 → 5** — is the only
part of this roadmap with a date attached, and it is the argument for doing the cheap Phase 3 early rather
than when its dependency order alone would suggest.

## Shape of the work

The first four phases are **days, not weeks** — roughly 2–3 weeks together — and they cover the memory,
the safety fix, the $132/day, and the rename trap. Everything from Phase 4 on is measured in weeks.

## What each phase must produce

Not just code: a phase is done when it is **deployed, verified against live data, and demonstrably
measurable** — which is what Phase 0 exists to make possible. Where a phase carries one of Ori's open
rulings (§6.4), it ships the setting as a declared constant and a §6.1 experiment, never a silent default.

## Open rulings carried through (§6.4)

The park re-test cadence · the boost allowance share (0.50, unproven) · rule-4's volume floor for coverage
tests · the park-price source (channel floor vs the engine's `bid_park`, differing 2.5x on some rows).
The agreement-tier ranking stays deferred until a real case appears. **No phase may decide these.**

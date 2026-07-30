# Implementation plan — Intent campaign grid + date-precise coacher

Spec: `docs/superpowers/specs/2026-07-25-intent-campaign-grid-design.md`
Date: 2026-07-25 · Status: Reviewed — QA traceability (8 PASS/6 PARTIAL→remediated), UX layout review (3.2 reworked), Analyst CONDITIONALLY APPROVED with 12 conditions, all applied 2026-07-25

Conventions that bind every phase: every new BQ object registered in `config.yaml`; SOPs in
`architecture/` updated before code; all decision logic in BigQuery SQL / Python, never React;
Cube reads `T_` tables; dashboard commits need `--no-verify` (64 pre-existing tsc errors);
`deploy_all.sh` ships the working tree — stash WIP before deploying.

---

## Phase 0 — Model hardening (blocks everything downstream)

The bid engine must be correct and fast before campaigns or plans consume it.

### 0.1 Season quarantine in the CVR curve
- File: `scripts/bigquery/views/V_INTENT_CVR_CURVE.sql`
- In `obs`, join first-sale date per product (MIN(date) with units>0 from `V_UNIFIED_DAILY`,
  or `FACT_AMAZON_PERFORMANCE_DAILY`) and EXCLUDE products <90 days old **from the `season`
  CTE only** (they keep their own `base_cvr` and consume the pooled index).
- Verify: LolliBall's Jun–Jul clicks no longer contribute to `season_index` for
  `tween-girl-gift`; July index for that intent shifts measurably; no other month moves >±0.02.

### 0.2 Three bands + thresholds in the bid view
- Files: `scripts/bigquery/views/V_INTENT_BID_BASE.sql`,
  `scripts/bigquery/migrations/2026-07-25_intent_band_thresholds.sql`
- New `DE_COACH_THRESHOLDS` rows (`strategy_id='INTENT'`): `VELOCITY_ROAS` = 0.7 AND
  `INTENT_HOPELESS_ROAS` = 0.5 — **all four band boundaries are threshold rows, none
  hard-coded** (spec band table is the ratified source: RUN ≥1.1 / VELOCITY 0.7–1.1 /
  MARGINAL 0.5–0.7 = OFF-unless-PROBE / OFF <0.5).
- Replace the hard-coded 1.0 breakeven action with band assignment reading those rows.
  Emit `max_cpc_run = value/1.1`, `max_cpc_velocity = value/0.7`.
- Hysteresis is **stateful** and does NOT belong in this stateless view — it lives in the
  plan generator (2.1) and checkpoint (4.1), which see the previous period's state.
- Verify: White Lollibox × tween-girl-gift Jun = VELOCITY (0.93), not OFF; **Mint LolliME ×
  tween-girl-gift = RUN in all 12 months**; `journal-diary` cells unchanged RUN.

### 0.3 Materialize the model (kills the 30–50 s reads) — engineering enabler, no owner requirement; required by the "Cube reads T_ tables" convention and panel usability
- New: `T_INTENT_CVR_CURVE`, `T_INTENT_BID_BASE` tables; extend
  `SP_REFRESH_SEARCH_TERM_INTENT` (or new `SP_REFRESH_INTENT_MODEL`) to rebuild them after
  the DE merge; wire into the orchestration (`LOG_PIPELINE_RUNS` stamp pattern, same as the
  28 stamp-refresh cubes).
- Repoint the Flask popup endpoint (`/api/admin/intent-monthly`) and everything in Phase 2+
  at the `T_` tables.
- Verify: popup opens <3 s; T_ row counts match V_ counts on refresh day.

### 0.4 Gate: coacher QA findings
- The parallel coacher bug-hunt report (`.tmp/coacher_qa_findings.md`) is triaged; CRITICAL/
  HIGH findings in `V_COACH_APPLY`, cooldown, or launch-rule paths are fixed **before Phase 4**
  wires the checkpoint into the coacher. Phases 1–3 are not blocked by it.

---

## Phase 1 — Registry + Tier A build

### 1.1 `DE_INTENT_CAMPAIGN` registry
- Files: `scripts/bigquery/tables/DE_INTENT_CAMPAIGN.sql`, config.yaml entry.
- Columns: `campaign_id` (STRING, PK once known), `campaign_name_at_creation`,
  `product_short_name`, `intent_key`, `rung`
  (**`BROAD_SP|EXACT|PHRASE|BROAD_VIDEO|BROAD_SPOTLIGHT` — matches CoveragePage's
  `STRAT_LABEL` keys exactly so label maps are shared**), `tier` (`A|B|LAUNCH`),
  `state` (`PENDING_UPLOAD|ACTIVE|PAUSED_BAND|PAUSED_DEMOTED|RETIRED`),
  `admitted_reason`, `created_at`, `updated_at`, `updated_by`.
- Reconciliation rule: rows are inserted `PENDING_UPLOAD` with the name; a scheduled check
  matches the name against `FACT_AMAZON_ADS` first-sight and **locks the numeric
  campaign_id** — from then on the name is display-only (renamed-campaign trap).

### 1.2 Absorb existing campaigns
- Script: `tools/intent_grid/absorb_existing.py` — propose (campaign_id → product, intent,
  rung) for existing EXACT_BOOST / seasonal / BTS campaigns by keyword-set majority vote
  through `V_ADS_SEARCH_TERM_FACETS`; write proposals to `.tmp/` CSV for Ori's review; apply
  confirmed rows to the registry. Back-to-school campaigns from 2026-07-24 are seed members.

### 1.3 Tier A selection + build bulksheet
- Script: `tools/intent_grid/build_tier_a.py` (reuse the validated back-to-school workbook
  generator: SP headers from DoPage, `Campaign ID` = name placeholder on Create, ad-group IDs
  on every child row, `negativeExact` only, token-boundary conflict check vs
  `V_PRODUCT_PHRASE_NEGATIVES`).
- Input: the 24 Tier-A (product×intent) pairs; per pair 2 campaigns (SP Broad seed 3–5
  phrasings from research+harvest; Exact top-10 by SQP volume, rank>75 gate, CVR posterior).
  Bids from `T_INTENT_BID_BASE` current month `target_bid`. Standard negatives on all;
  Exact keywords negativeExact'd into the pair's Broad.
- Build-time self-competition enforcement: before emitting keywords, resolve term ownership
  per (intent, term) by best-ASIN score; a term ships in exactly one product's Exact, with
  negativeExact rows emitted for the losers' Exact campaigns in the same workbook.
- Registry rows inserted PENDING_UPLOAD in the same run.
- Verify: workbook passes Amazon validation upload (the BTS sheet's error classes are the
  regression list); registry count = campaigns in sheet; zero negative-vs-keyword conflicts.

### 1.4 SOP
- `architecture/INTENT_CAMPAIGN_GRID.md` — the operating manual: grid rules, rung earn/demote
  criteria, registry lifecycle, naming. (Supersedes the campaign portion of
  INTENT_CAMPAIGN_MODEL.md; mark that doc accordingly.)

---

## Phase 2 — Month-plan engine

### 2.1 `SP_GENERATE_INTENT_MONTH_PLAN(plan_month DATE)` → `T_INTENT_MONTH_PLAN`
- Grain: one row per `(campaign_id, trigger_date, row_type, payload_key)` — payload_key =
  keyword/term for ADD_KEYWORD/PAUSE_KEYWORD/NEGATE_TERM, NULL for BID/STATE (multiple
  keyword rows per campaign-date must not collide).
- Row lifecycle (`row_status`): model rows DRAFT → APPROVED in bulk by monthly approval;
  checkpoint rows appended post-approval enter PENDING_REVIEW and are accepted/rejected
  individually via the existing coach-action flow; `/due` emits APPROVED|ACCEPTED only.
  Terminal: APPLIED | REJECTED | EXPIRED. ADD_KEYWORD + paired PAUSE_KEYWORD share `pair_id`;
  rejecting either cancels both.
- Row types: `BID` (target_bid, max_cpc, tos_pct, daily_budget), `STATE` (pause/resume +
  band), `ADD_KEYWORD` (keyword, match, bid, paired `PAUSE_KEYWORD` of worst incumbent when
  cell full), `NEGATE_TERM`.
- Trigger dates: month start for GENERIC; `DIM_US_HOLIDAYS` boost_start / peak_start /
  holiday−2 / cooldown_end intersecting the month for the cell's holiday facet; no weekly
  rows here (checkpoint adds those live in Phase 4).
- Band assignment with hysteresis: compare to previous plan/actual state; flip only past
  floor±0.1, and resume also on **two consecutive checkpoints above the floor** (spec rule).
- Velocity floor: `units_floor = GREATEST(badge_tier_defense, plan_units ×
  VELOCITY_PACE_PCT)`; `badge_tier_defense` = lower bound of the tier held last calendar
  month ({50,100,500,1000}); plan_units from **`V_PLAN_FORECAST` adjusted monthly units**
  (folds `DE_PLAN_STRATEGY`); **launch-population products substitute the `V_LAUNCH_RAMP`
  donor curve as plan_units**. VELOCITY cells open only while product below pro-rata pace,
  cheapest-marginal-GP/click-first ordering recorded in `reason_trace`.
- **Budget allocation (the objective's mechanism):** the family pool is defined as
  trailing-28d actual family ad spend × (plan-month units ÷ trailing-28d units), overridden by
  `DE_PRODUCT_BUDGET` where a row exists (Weekly Run waterfall integration remains future
  scope). After band assignment, distribute the pool across cells by expected marginal net
  profit per dollar
  (`(value_per_click − expected_cpc) / expected_cpc`, expected_cpc = trailing market CPC
  capped at band max): floors first (VELOCITY caps honored), then greedy equal-marginal fill;
  write per-cell `daily_budget`. This is what corrects the BOX-vs-ME asymmetry
  ($9.28 vs $3.18 NP/unit) instead of one ROAS bar.
- **Self-competition ownership:** per (intent, term), exactly one product's Exact may own a
  term — owner = best-ASIN score (proven orders × conversion advantage, the
  `V_SEARCH_TERM_SEGMENT` pattern); the generator emits NEGATE_TERM rows for the losers'
  Exact campaigns and the 1.3 builder enforces it at creation.
- Inventory gate: veto boost/velocity rows when `V_PLAN_FORECAST.days_until_oos` < horizon
  runway; `reason_trace='OOS_VETO'` rows still emitted (visible, not silent).
- ADD_KEYWORD sources (two, matching spec §4): **research** — `FACT_RESEARCH_RECOMMENDATIONS`
  (status NEW, latest week) ∩ rank>75 ∩ SQP ≥ `PROMOTE_MIN_SQP_VOLUME` ∩ not running
  (reconcile like `V_COVERAGE_KEYWORD`), reason `RESEARCH_ADD`; **harvest** — converting
  broad/auto terms with ≥15 clicks AND CVR ≥ cell posterior AND SQP ≥ threshold, reason
  `HARVEST_ADD` (evidence substitutes for rank). Launch cells flagged PROBE.
- Approval: `DE_INTENT_MONTH_APPROVAL` (plan_month, status DRAFT|APPROVED, approved_by/at,
  row_count, notes).
- Verify — golden fixtures:
  (a) plan_month=2026-08-01: BTS cells carry Aug 1 + Aug 10 rows and a Sep 28 end row;
      White Lollibox tween-girl-gift emits Aug resume; an OOS-vetoed row appears for any
      product with runway < horizon; budget sums per family equal the pool.
  (b) **12-month band sweep, both example cells** (generate all 12 plan months):
      Mint × tween-girl-gift = RUN every month with Dec target $1.11;
      White Lollibox × tween-girl-gift = VELOCITY in Jun+Jul, RUN otherwise, Dec carries the
      peak bid + TOS row. Owner's stated calendars are the assertion, not a spot-check.

### 2.2 Registered objects
- `T_INTENT_MONTH_PLAN`, `DE_INTENT_MONTH_APPROVAL`, `SP_GENERATE_INTENT_MONTH_PLAN` in
  config.yaml; orchestration entry to auto-generate DRAFT at M−3.

---

## Phase 3 — Cockpit panel + dated bulksheet emission

### 3.0 Fixes to shipped surfaces (from the UX review — before any new UI)
- `IntentMapping.tsx` light-mode violations: replace hardcoded `bg-zinc-800/40`,
  `bg-zinc-700 text-white`, `focus:border-zinc-600` with CSS-var tokens (the exact bug class
  dashboard-react/CLAUDE.md bans).
- Popup stale-response guard in `openIntent` (request id or AbortController) — with slow
  loads, opening intent B mid-flight must not render A's months under B's header.
- A11y: aria-labels on the ✓/⃠ verify buttons; `role="dialog"` + Escape + focus handling on
  the popup; visible focus styles instead of bare `focus:outline-none`.
- `actionColor` must not default unknown actions to emerald — explicit colors per band
  (VELOCITY amber, MARGINAL muted, OFF muted+⏸ glyph), unknown = muted.
- RECHECK row tint keyed on `verification_status` (not `is_stale`) and raised above
  `amber-500/[.04]` to be perceptible; AdminPage section subtitle updated from
  "Keyword → Intent Theme" to composed-intent wording.
- **Popup rollout gate**: the 12-month popup stays admin-gated until Phase 0.3 lands
  (endpoint reads the slow view today); interim: progressive "this takes ~30s" message +
  per-intent client cache.

### 3.1 Flask endpoints (data-entry-app/app.py — no @login_required, Bearer pattern)
- `GET /api/intent-month?month=` → plan rows grouped cell→dates + approval status + summary
  (cells, planned spend, velocity flags, OOS vetoes).
- `POST /api/intent-month/approve` → flips DE_INTENT_MONTH_APPROVAL, stamps user.
- `GET /api/intent-month/due?date=` → approved rows due on a date (DoPage feed).
- `POST /api/intent-month/applied` → marks rows applied → inserts FACT_PPC_CHANGE_LOG using
  the ONE canonical reason enum (spec §4): `MODEL_MONTH | MODEL_WINDOW | CHECKPOINT_RAISE |
  CHECKPOINT_BRAKE | VELOCITY_DEFEND | PROBE | RESEARCH_ADD | HARVEST_ADD | NEGATE`
  — same list validated by the generator (2.1) and the checkpoint (4.1). `OOS_VETO` is a
  generation-time reason_trace value only; vetoed rows are never applied and never reach the
  change log.

### 3.2 Intent Month panel (new page `intent-month`, System/Strategy group, admin-gated)
Layout — REWORKED per UX review (the shared date-column matrix rendered mostly empty and the
approve button was ungated):
1. Header: month selector ‹ Aug 2026 › · approval state chip (DRAFT amber / APPROVED green)
   · "Approve month" primary button — **disabled while unreviewed ADD_KEYWORD rows remain**
   (badge shows the count) and always behind a **confirmation dialog summarizing rows by
   type, planned spend Δ vs last month, and OOS vetoes**. Un-approve affordance appears
   after approval (blocks further emission; already-uploaded dates stand).
2. Summary strip, 4 metric cards: cells active / paused · planned spend Δ · velocity-defend
   cells (count + $cap) · OOS vetoes (count, red when >0).
3. Main list: **collapsible product groups → one row per intent cell**, with that cell's
   dated changes as **inline chips in its own row** (`Aug 1 $0.88 · Aug 10 TOS 500% ·
   Sep 28 ⏸`) — no shared date columns. "Changed only" filter on by default. Band rendering
   pairs **color + glyph** (RUN emerald ✓, VELOCITY amber ⚡, MARGINAL muted, OFF muted ⏸,
   PROBE purple ◌) — never color alone, and OFF is deliberate-muted, NOT red (red = "to do"
   on Coverage tiles; don't overload it). Click chip → drawer with reason_trace + the 12-month popup content rendered
   INLINE in the drawer (no modal-on-modal stacking). The panel doubles as the mid-month
   view: chips show APPLIED / pending state, and the header carries a staleness stamp
   (plan generated_at · last checkpoint run) plus DRAFT provenance when unapproved.
4. ADD_KEYWORD review table sits ABOVE the approve path visually (its gating makes it
   unmissable): keyword · cell · SQP vol · rank/evidence · proposed bid · swap-out incumbent;
   per-row accept/reject (rejects drop from plan).
5. Empty/edge states: no plan yet (generate CTA), approved-and-past (read-only), Flask down
   (Coverage-style retry card).
- File: `dashboard-react/src/pages/IntentMonthPage.tsx` + route in App.tsx + Sidebar entry
  (admin view-mode gated). ≤130 cells — no virtualization needed.

### 3.3 DoPage "Due today" card
- Reads `/api/intent-month/due`; one click emits the dated bulksheet (same generators as 1.3;
  Update rows for bids/state, Create rows for keywords, SB rows routed to the SB sheet).
  **Dependency: the isSB routing fix (commit 6384deb) must be DEPLOYED before this ships** —
  committed but undeployed today.
- Card has three states per trigger date: DUE → EMITTED (sheet downloaded; re-download guarded
  by a confirm since Amazon may have half of it) → APPLIED. `/applied` accepts a subset of
  row_ids so partial application is recorded honestly, not all-or-nothing.
- Verify: golden Aug 1 emission contains exactly the Aug 1 rows; SB campaign rows land on
  the SB sheet; FACT_PPC_CHANGE_LOG rows appear with correct reasons; 3-day cooldown then
  suppresses re-suggestions for touched keys.

---

## Phase 4 — Weekly checkpoint + launch admission

### 4.1 Checkpoint SP (`SP_INTENT_CHECKPOINT`)
- Cadence: weekly; twice-weekly when any active holiday window overlaps (orchestration
  schedule reads DIM_US_HOLIDAYS).
- Reads actuals through orders watermark −2d, freshness keyed on `__TABLES__`
  last_modified_time. Emits CHECKPOINT_RAISE / CHECKPOINT_BRAKE / NEGATE / VELOCITY open-close
  rows AND mid-month `HARVEST_ADD` ADD_KEYWORD rows (same evidence gate as 2.1) into
  T_INTENT_MONTH_PLAN. All checkpoint-appended rows enter `PENDING_REVIEW` (per the 2.1
  lifecycle) and reach `/due` only after acceptance in the coach-action flow. Overrides expire
  at next model date (expiry_date column; emitter ignores expired).
- Launch pairs: PROBE rules only (no loss cuts inside 20-day window; probe +5%; negation
  allowed). Respect the 3-day cooldown per key.
- Surfaces exactly where coach actions surface today (Actions/Weekly Run cards) — implement
  as additional rows in the coach actions feed tagged `INTENT_GRID`, so no new review UI.
- Gate: Phase 0.4 coacher findings resolved first.

### 4.2 Launch flows

**4.2a — New-variation day-0 build.** Trigger: a new product appears in an existing family
(launch-population membership). Same run generates SP Broad + Exact pairs for the family's
Tier-A intents: keywords = family's proven top-10 per intent, **bid = family-prior target**
(`family_cvr × gp × 0.70`), band PROBE, registry `tier='LAUNCH'`. This is creation-by-
inheritance and is NOT evidence-gated (4.2b is).

**4.2b — New-family admission job.** Weekly: (product,intent) pairs of launch-population
products clearing ≥100 clicks AND CVR ≥ intent prior → emit build rows (1.3 generator, PROBE
band) + registry `tier='LAUNCH'`. **Admission bid = the pair's own posterior**
(`(orders + k·prior)/(clicks + k)`, k = `INTENT_CVR_BASE_PRIOR_CLICKS`) × gp_per_order,
where gp_per_order falls back to **planned price − landed COGS (BOM)** until ≥30 attributed
orders exist. Rejected intents (conclusive + below floor) → NEGATE_TERM rows.
- Tier B graduation uses the same job with the 1k-click + profitable bar, `tier='B'`.

**4.2c — Day-0 research keywords into the launch controller.** Task the `NEW_LAUNCH`
template/DoPage launch generator to source day-0 Exact keywords from `V_RESEARCH_RANKED`
(top by rank × SQP volume for the family) — verify whether the current launch flow already
does this; if it does, document it in the SOP, if not, wire it.

### 4.3 Rung earn/demote job
- Monthly, inside plan generation: evaluate earn rules (Phrase ≥3 converting phrasings;
  Video GP threshold + asset exists; Spotlight ≥2 products converge) → emits CREATE
  recommendations (needs Ori approval in the ADD table, ≥4-day SB lead) and PAUSE demotions.

---

## Phase 5 — Outcomes + tuning

- Extend `V_PPC_ACTION_OUTCOMES` to score by reason code; new cut: VELOCITY_DEFEND cells vs
  organic-share trajectory (did defended months hold organic %?), MODEL_WINDOW vs
  CHECKPOINT timing wins.
- Monthly threshold-review query pack feeding DE_COACH_THRESHOLDS suggested_value column
  (already exists in schema).
- Verify after first full month: every applied change has an outcome row; a written verdict
  on the velocity thesis with numbers.

---

## Test strategy
- SQL: golden-month fixtures in `.tmp/` asserted by a pytest module `tools/intent_grid/tests/`
  (bq dry-run + SELECT assertions; no DML in tests).
- UI: vitest for plan-grouping helpers; the panel verified in-browser against local Flask
  (the session's verification workflow); Playwright smoke for approve→due→applied optional.
- Bulksheets: every generator run re-checks the Amazon error-report regression list from the
  BTS upload (parent IDs, Bid Optimization value, Video Ad entity, SB tab routing).

## Rollout / rollback
- Phase 1 campaigns upload paused-until-approved? No — they carry Start Date and low budgets;
  rollback = bulk pause by registry list (one generated sheet).
- Plan rows are advisory until approved; approval is per month; un-approve endpoint blocks
  further emission (already-uploaded dates stand — Amazon is the source of truth for what ran).
- Existing Hunter/AUTO untouched throughout; worst case the grid runs alongside legacy
  exactly as the BTS campaigns do today.

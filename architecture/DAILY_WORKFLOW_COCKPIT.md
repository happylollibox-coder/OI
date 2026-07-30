# Daily Workflow Cockpit — Spec

**Date:** 2026-07-21 · **Owner:** Ori · **Author:** Claude (spec for review, not yet built)
**Status:** 🔲 Draft for Ori's review. Nothing here is built. Marked ❓ = real open question.

**Supersedes/extends:** evolves the read-only [`CoveragePage.tsx`](../dashboard-react/src/pages/CoveragePage.tsx) +
`/api/coverage` scan into a single daily cockpit. Reads from — does not replace —
[`INTENT_CAMPAIGN_MODEL.md`](INTENT_CAMPAIGN_MODEL.md), [`STRATEGY_AND_WORKFLOW.md`](STRATEGY_AND_WORKFLOW.md),
[`ADS_COACH_DECISION_MATRIX.md`](ADS_COACH_DECISION_MATRIX.md), [`RESEARCH_PAGE.md`](RESEARCH_PAGE.md).

---

## 1. The governing principle — a trust ladder, not a fixed action model

Ori (2026-07-21): *"I want first to understand what is missing high level. Then check in detail per
action what is done, until I trust the system (no bugs). Then I will run it automatically."*

The cockpit is built in trust-earning rungs. Each rung is **shippable on its own** and is a
precondition for the next. The action layer is designed once, with a seam that lets the *same*
decisions run in **observe → explain → manual-apply → auto** modes without a rebuild.

| Rung | Mode | What Ori does | What the system does |
|---|---|---|---|
| **1. SEE** | `observe` | Glance: what's defined vs missing, by strategy | Reconcile target vs live; roll up MISSING/OK/REDUNDANT |
| **2. VERIFY** | `explain` | Drill any cell → read the reason + evidence | Emit per-action decision-trace (reuse coach trace) |
| **3. APPLY** | `manual_apply` | Approve each action → export bulksheet | Build the action envelope; queue → Do page |
| **4. AUTOMATE** | `auto` | Flip a per-strategy switch | SP writes/queues actions unattended, confidence-gated |

**Design rule:** every row the cockpit produces — at every grain — emits one **Action Envelope**
(§5). Rungs 1–4 differ only in *who consumes the envelope and when*. Rung 4 is a toggle, never a
rewrite. Do **not** build rung 4's automation now; only leave its seam.

---

## 2. Where it lives

**Evolve `CoveragePage.tsx` into the cockpit** (Ori's call, 2026-07-21). It already reconciles target
roles vs live campaigns and renders status + metrics — it is the correct scaffold. Actions and
WeeklyRun pages stay as-is for now; the cockpit deep-links to them until rung 3 absorbs their apply path.

Rename intent: the page graduates from "🩺 Ad Coverage Scan" to the daily operating surface. Keep the
route stable to avoid nav churn.

---

## 3. The organizing lens — Ori's 6 strategies

The cockpit's top axis is Ori's 6 strategies, which **already exist** as the `strategy_category` column
at the bottom of [`V_CAMPAIGN_ROLE.sql`](../scripts/bigquery/views/V_CAMPAIGN_ROLE.sql):

`AUTO · INTENT · EXACT_BOOST · COMPETITOR · BRAND_DEFENSE · PRODUCT_DEFENSE`

| Strategy | Grain | Target source (what SHOULD exist) | Live source (what DOES exist) |
|---|---|---|---|
| **Auto** | per variation (ASIN) | every sellable ASIN should have 1 Auto | `V_CAMPAIGN_ROLE` role=AUTO |
| **Intent** | family × match-type × intent | [`V_INTENT_KEYWORDS`](../scripts/bigquery/views/V_INTENT_KEYWORDS.sql) (relevant intents + top-10 kw) | role∈{EXACT,BROAD,PHRASE} mapped to intent |
| **Exact Boost** | family × intent | Intent winners with `margin_per_click ≥ 1.30` **AND** `research_rank > 75` | role=EXACT flagged boost |
| **Competitor** | family × competitor ASIN | competitor ASINs in `DIM_PRODUCT` (`parent_name IS NULL`) ranked by fit | role=COMPETITOR ASIN targets |
| **Brand Defense** | per family | as-is (brand terms; only place they live) | role=BRAND_DEFENSE |
| **Product Defense** | store (cross-family) | own-brand ASINs for cross-sell ([`V_ADS_COACH_CROSSSELL`](../scripts/bigquery/views/V_ADS_COACH_CROSSSELL.sql)) | role=PRODUCT_DEFENSE |

> **Exact Boost gate (Ori, 2026-07-21) — profit-per-click, not flat ROAS.** Gate on **absolute margin
> earned per click**, so a boosted keyword survives its higher bid:
>
> ```
> margin_per_ad_dollar = (Sales − landed COGS) / ad_spend     -- OI "Net ROAS" (margin-per-ad-$), NOT adsNetRoas
> cpc                  = ad_spend / clicks
> margin_per_click     = margin_per_ad_dollar × cpc           -- = (Sales − COGS) / clicks  (bid-independent)
> Exact Boost eligible ⟺ margin_per_click ≥ 1.30  AND  research_rank > 75
> ```
>
> Rationale: `margin_per_click` is the margin each click generates (`margin_per_order × CVR`) and does
> **not** move when you raise the bid — only CPC does. So `≥ 1.30` means every click nets positive even
> after boosting the bid toward $1 (keeps ~$0.30/click). Replaces the flat `promote_min_roas = 1.5`.
> **Must use margin-per-ad-$**, not `adsNetRoas` (which already nets out ad cost → would double-count CPC).
> ❓ Is 1.30 a fixed floor, or should it track the boost target (`≥ boost_bid × 1.3`)? ❓ Keep `rank > 75` AND?

---

## 4. Three grains of "missing" — the reconciliation core

Ori wants **all campaigns AND keywords** shown as defined or missing. That is three nested reconcilers,
each the same shape (target set ⟕ live set → status), one grain deeper than the last:

```
Strategy (6)                     ← rollup only
  └─ Campaign cell               ← reconciler A  (exists today, campaign-level)
       └─ Keyword / ASIN target  ← reconciler B  (NEW — the hard part Ori wants)
```

### Reconciler A — campaign presence (extend what exists)
Today `/api/coverage` emits per (product × role): `ok` / `missing` / `redundant`. Re-lens it from the
8 coverage roles to the **6-strategy lens** (`V_CAMPAIGN_ROLE.strategy_category`).

> **Grain finding (spike, 2026-07-21): intent cells DEFERRED to S1b.** There is NO campaign→intent_key
> linkage in the live account — a campaign only knows `strategy_id='INTENT'`, not *which* intent. So S1
> reconciles at **`parent_name × strategy_category`**, not per-intent. Per-intent cells (INTENT_CAMPAIGN_MODEL
> §F "Phase 2") need a campaign→intent_key tagging step (extend `DIM_EXPERIMENT_CAMPAIGN`) first — that is S1b.

**Expected-set (Ori, 2026-07-21) — what counts as MISSING when absent:**
`AUTO` (per ASIN), `INTENT` (per family), `BRAND_DEFENSE` (per family), `PRODUCT_DEFENSE` (store) are
**baseline-expected** → absence = `missing`. `COMPETITOR` and `EXACT_BOOST` are **informational-only**
→ shown where present, never flagged `missing` (Exact Boost is an *earned* promotion, not a baseline campaign).

### Reconciler B — keyword / ASIN-target presence (NEW)
The genuinely new build. For each live campaign that *should* carry a target set:

- **Target keywords** = `V_INTENT_KEYWORDS` top-10 for that (family × match-type × intent) +
  net-new recs from `V_RESEARCH_RECOMMENDATION_CANDIDATES`.
- **Target ASINs** (Competitor / Product Defense) = ranked competitor ASINs / `V_ADS_COACH_CROSSSELL`.
- **Live targets** = keywords/ASINs actually in the campaign (`FACT_AMAZON_ADS` / `DIM_CAMPAIGN` targeting).
- **Diff** at (campaign × target × match_type):
  - `MISSING_TARGET` — a target keyword/ASIN that should be in this campaign but isn't → *add*.
  - `ORPHAN_TARGET` — a live target not in the current target set → *review / negate / pause*.
  - `OK` — present and expected.

Reconciler B is the missing muscle: today the coach only acts on **existing** keywords and never says
"this keyword should exist but doesn't."

### Trustworthy "missing" — the opt-out table
`DE_COVERAGE_EXPECTATION` (designed in INTENT_CAMPAIGN_MODEL §F, **not built**) must ship with
Reconciler A so Ori can mark a (family/strategy/intent) cell "not expected" and suppress false MISSING.
Without it, rung 1 cries wolf and never earns trust. One row per suppressed cell: `{scope_grain,
scope_key, strategy, reason, is_active}`.

---

## 5. The Action Envelope — the seam that makes automation a toggle

Every reconciled row, at every grain, emits one uniform record. The page renders it; the apply path
consumes it; automation later consumes the *same* record. This is the single most important design
decision — it is what lets rung 4 be a switch, not a rebuild.

```
ActionEnvelope {
  grain          : 'strategy' | 'campaign' | 'target'
  entity_key     : { family, strategy, intent?, campaign?, target?, match_type? }
  status         : 'OK' | 'MISSING' | 'ORPHAN' | 'REDUNDANT' | 'DRIFTED'
  action         : 'NONE' | 'CREATE_CAMPAIGN' | 'ADD_TARGET' | 'NEGATE' | 'BID_UP' | 'BID_DOWN' | 'PAUSE'
  target_state   : { bid?, budget?, keywords?[], asins? }    -- what it SHOULD be
  current_state  : { ... }                                    -- what it IS ( null if missing )
  reason         : string        -- plain English, reuse V_ADS_COACH_DECISION.reason style
  trace          : json[]        -- decision chips, reuse term_decision_trace format
  confidence     : 'HIGH'|'MEDIUM'|'LOW'
  apply_status   : 'observe' | 'queued' | 'applied' | 'auto'  -- rung marker
}
```

- **Rung 1** renders `status` + counts. **Rung 2** renders `reason` + `trace`. **Rung 3** turns
  `action` + `target_state` into a Do-queue item → bulksheet. **Rung 4** lets an SP emit
  `apply_status='auto'` for envelopes above a per-strategy confidence threshold.
- Reuse, do not reinvent: `reason` / `trace` / `confidence` already exist in
  [`V_ADS_COACH_DECISION.sql`](../scripts/bigquery/views/V_ADS_COACH_DECISION.sql). Extend that
  vocabulary to CREATE/ADD_TARGET actions rather than inventing a parallel one.

> ❓ **Coach reads campaign names, not the intent model.** INTENT_CAMPAIGN_MODEL §E lists "teach
> `V_ADS_COACH` the match-type×intent model" as pending. The envelope for bid/negate actions depends on
> **Resolved (Ori, 2026-07-21):** keep bid/negate on the Actions page; the coach is not reworked to read
> the intent model in this project. The cockpit owns coverage/missing (S1–S3), not bid/negate decisions.

---

## 6. Backend spine

Per "all logic in backend," the page is pure presentation over one contract. Build bottom-up:

1. **`V_COVERAGE_KEYWORD`** (new) — Reconciler B. Target vs live at (campaign × target × match_type).
2. **`V_COVERAGE_CAMPAIGN`** (evolve `/api/coverage`'s query) — Reconciler A on the 6-strategy lens +
   intent cell, reading `DE_COVERAGE_EXPECTATION` for suppression.
3. **`V_DAILY_WORKFLOW`** (new) — unions A + B into the Action Envelope shape, LEFT JOINs the coach's
   existing `reason`/`trace` for DRIFTED (bid/negate) rows, and rolls up MISSING/OK counts per strategy.
4. **`DE_COVERAGE_EXPECTATION`** (new DE table) — the opt-out.
5. New `/api/daily-workflow` endpoint (or extend `/api/coverage`) serving the envelope tree.

All new objects register in [`config.yaml`](../config.yaml). Confirm every payload shape against real
`FACT_AMAZON_ADS` / `V_INTENT_KEYWORDS` rows before writing SQL (data-first rule).

### 6a. Time-window selector (2026-07-22)

The page's metric window is user-selectable via a segmented control under the title
(**Today · Yesterday · 7 days (default) · 30 days · 90 days · 12 months · Peak**), mirroring HomeBrief's
`DateToggle`. The window is not cosmetic — it governs **every** measure on the page: coverage counts,
status, AND metrics. Semantics chosen: the *whole* view reflects the window (so **Peak** = "how was
coverage + performance *at* peak", **12 months** = the year's view), rather than freezing coverage to
"now" and only moving the numbers.

Implementation: the four window-bearing coverage views were converted to **table functions**
`FN_COVERAGE_CAMPAIGN` / `_DETAIL` / `_UNMAPPED` / `_CAMPAIGN_PROFIT` — each takes
`(win_start DATE, win_end DATE, peak_only BOOL)`. The original `V_COVERAGE_*` views are left in place
(unused by the cockpit now, but non-breaking). The metric gate became "served impressions in the window"
(replacing the fixed last-30d recency gate); `peak_only=TRUE` additionally restricts to gift-season days
(`DIM_US_HOLIDAYS.category='gift_season'`). `FN_COVERAGE_CAMPAIGN_PROFIT` at `win=7d` reproduces the old
`V_COVERAGE_CAMPAIGN_PROFIT7D` exactly.

`/api/daily-workflow?window=<key>` maps the 7 keys → `(win_start, win_end, peak_only)` (UTC `date.today()`,
matching the old `CURRENT_DATE()`), passes them to the four TVFs + the inline unmapped-profit query, and
echoes `window` / `window_start` / `window_end` back. The `*_MONTHLY` drill endpoints
(`/api/campaign-months`, `/api/keyword-months`, `/api/campaign-keyword-months`) are **separate and stay at
12 months** — the toggle does not touch them. Endpoint cache key already folds `request.query_string`, so
each window caches independently.

---

## 7. Page information architecture

```
DAILY WORKFLOW                                        last 60d · [Observe ▾]  ← mode selector
┌──────────────────────────────────────────────────────────────────────┐
│ 6 strategy tiles (rollup):  Auto  Intent  Exact Boost  Competitor …    │  ← rung 1
│   each tile:  ✓ 12 defined · ✗ 3 to do · ⚠ 1 redundant  · net ROAS     │
├──────────────────────────────────────────────────────────────────────┤
│ click a tile → family × intent cell grid (Reconciler A)                │
│   click a cell → campaign → keyword/ASIN rows (Reconciler B)           │
│     each row:  status pill · perf (net ROAS/clk/units) · reason ▸      │  ← rung 2
│       reason ▸ expands the decision-trace chips                        │
│       [Approve] appears only in manual_apply mode                      │  ← rung 3
└──────────────────────────────────────────────────────────────────────┘
```

Keep today's colour language (`✓ defined` emerald / `✗ to do` red / `⚠ redundant` amber). Add ORPHAN
(slate) and DRIFTED (amber) at the keyword grain.

---

## 8. Staged rollout (each stage ships independently)

| Stage | Delivers | Rung | Depends on |
|---|---|---|---|
| **S1** | `V_COVERAGE_CAMPAIGN` on 6-strategy + intent cell; `DE_COVERAGE_EXPECTATION`; tiles + cell grid, read-only | SEE | intent model (built) |
| **S2** | reason/trace surfaced per cell + campaign (reuse coach trace) | VERIFY | S1 |
| **S3** | `V_COVERAGE_KEYWORD` (Reconciler B) — keyword/ASIN MISSING/ORPHAN | SEE (deeper) | S1 |
| **S4** | Action Envelope + manual apply → Do bulksheet (`CREATE_CAMPAIGN`, `ADD_TARGET`) | APPLY | S3, research→plan wiring |
| **S5** | per-strategy `auto` toggle, confidence-gated SP | AUTOMATE | S4 + trust |

**Start with S1.** It is the "understand what's missing, high level" rung Ori asked to see first, and
everything else hangs off its contract.

---

## 9. Decisions & open questions

**Resolved (Ori, 2026-07-21):**
1. ✅ **Exact Boost gate** — `margin_per_click = margin_per_ad_$ × cpc ≥ 1.30` **AND** `research_rank > 75`
   (§3). **1.30 is a fixed floor** (not `boost_bid × 1.3`). Eligibility also needs a minimum click count
   (reuse the coach's min-clicks threshold) so a low-sample fluke can't qualify.
2. ✅ **Coach × intent model** — **keep bid/negate on the Actions page** for now; the cockpit owns
   coverage/missing (S1–S3) only. Coach is not reworked to read the intent model in this project.
3. ✅ **Auto** — runs **separately and in parallel**. Auto *does* discover search terms (expected, fine),
   but those discoveries **stay within the Auto track** — the cockpit does NOT flag an Auto-discovered
   term as `MISSING_TARGET` in an Intent/Exact campaign (no back-door graduation). Intent's target
   keyword set comes only from research (`V_INTENT_KEYWORDS`). Auto's junk-term negation stays on the
   Actions/coach side. In the cockpit, Auto is just a per-ASIN coverage row (Auto campaign exists / missing).

**Still open:**
4. **ORPHAN keywords** (S3) — default action: review-only, or auto-propose NEGATE? (§4 Reconciler B)
5. **Redundant campaigns** — cockpit shows them; propose a merge/pause action or leave to Ori?

(4–5 don't block S1; decide at S3/S4.)

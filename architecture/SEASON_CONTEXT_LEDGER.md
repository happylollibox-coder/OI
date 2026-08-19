# SEASON CONTEXT LEDGER — spec of record

**Status:** Phase 3 WIRED 2026-08-08 (tag **v27.42**), allowance hardened same day (tag
**v27.43**, §5.5), LOSS dead-band same day (tag **v27.44**, §5.6), guard batch 2026-08-09 (tag
**v27.46**, §5.7 — two-tier allowance, winner-exemption doctrine, seasonal_now precedence,
STOP→negate surface). `V_KEYWORD_CONTEXT_GATE` is
live and both engines (`V_KEYWORD_LIFT`, `V_OOB_KEYWORD`) read it at their OUTPUT layer —
BLOCK_CUT and ENTRY_BLOCK (half-allowance re-probe) act; PARK_CONTEXT is ADVISORY-ONLY
(calibration FAIL — it may never move an action or bid). v27.43: the ENTRY_BLOCK allowance runs
on NEAR-SETTLED spend (anchor−3) with a 90d escape hatch, and the engines clamp re-probe funding
to the remaining allowance. v27.44: LOSS verdicts require REAL money clearly under breakeven
(net ≤ −$5 AND GP-ROAS < 0.95); near-breakeven / small-dollar outcomes get the new NEUTRAL
label, which carries NO memory. Timestamped `.bak` copies of both engine files taken before each
wiring pass (`*.sql.bak.v27.42.*`, `*.sql.bak.v27.43.*`). See §5 for the wiring spec and §6 for
the calibration record.

## The doctrine (Ori, 2026-08-07, approved "THE WHOLE CHAIN")

> "I want not to lose money on the same keyword for the same period. The same keyword can react
> differently in off season or different peaks."

A verdict belongs to **(keyword × season-context occurrence)**, never to the keyword alone.
Off-season history must never veto peak funding, and vice versa.

**Measured premise:** of 168 keywords with ≥30 clicks in both Sep15–Nov14 2025 (off) and
Nov15–Dec24 2025 (peak), 26 flipped loser→winner into peak ($13,461 peak spend) and 14 flipped
winner→loser. 24% flip rate. Blended-90d windows are wrong at every season boundary.

## Objects

| Object | Kind | Role |
|---|---|---|
| `V_SEASON_CONTEXT` | view | Context calendar: one row per date, 2024-09-05 → anchor+180d |
| `V_KEYWORD_CONTEXT_LEDGER` | view | Settled per-(keyword, occurrence) money ledger |
| `FACT_KEYWORD_SEASON_VERDICT` | table | Append-only WIN/LOSS/INSUFFICIENT record per closed occurrence |
| `SP_SNAPSHOT_SEASON_VERDICT` | procedure | Idempotent MERGE of closed-occurrence verdicts; orchestrator step v27.41 |
| `V_KEYWORD_CONTEXT_GATE` | view | LIVE 2026-08-08 — contradiction gate read by both engines' output layers (§5) |
| `V_SEASON_NEGATE_CANDIDATES` | view | LIVE 2026-08-09 (v27.46) — ADVISORY-ONLY: STOP re-probes → search-term negate candidates (§5.7 A6) |

## 1. Context calendar (`V_SEASON_CONTEXT`)

Every date from **2024-09-05** (first ads data) to **anchor + 180d** maps to exactly one context
occurrence. Future dates included — the engines need to know *today's* context.
Anchor = `LEAST(MAX(date) FROM FACT_AMAZON_ADS, FN_ADS_ANCHOR_CAP())`.

**Peak set** — `DIM_US_HOLIDAYS` (LIVE table is authority, repo DDL is stale) rows with
`category IN ('gift_season','prime_event','back_to_school')`, window
`boost_start .. COALESCE(cooldown_end, holiday_date)`.

- `gift_season` + `prime_event` with `boost_start..cooldown_end` is exactly the engines' `in_peak`
  rule (`V_KEYWORD_LIFT` season CTE) — stay consistent with it.
- **Documented extension:** `back_to_school` is added. It is a first-class season for this account
  (BTS window fix: boost Aug 1 / peak Aug 10 / anchor Sep 14) but its rows carry NULL
  `cooldown_end`, hence the `COALESCE(cooldown_end, holiday_date)` window end. The engines' own
  `in_peak` flag is NOT changed by this.
- `category='seasonal'` (Halloween, New Year) stays excluded, matching the engines. Halloween's
  dates fall inside the Christmas boost window and are owned by XMAS.

**Precedence (documented choice):** when holiday windows overlap, the row with the **earliest
`boost_start`** owns the date (tie-break: earlier `holiday_date`, then name). Consequences, all
intentional:
- Black Friday and Cyber Monday are fully absorbed into the Christmas occurrence (XMAS boost starts
  Oct 1, before both) — Q4 belongs to XMAS, which is then split in two (next bullet).
- **XMAS split (2026-08-08, calibration-driven):** every XMAS context is TWO occurrences:
  `XMAS_EARLY_<yr>` (Oct 1 – Nov 14) and `XMAS_PEAK_<yr>` (Nov 15 – Dec 28, the cooldown end the
  calendar already used). Rationale, measured: PARK_CONTEXT auto-park failed **all 40** calibration
  settings under the coarse single-occurrence Q4 (doctrine-default allowance = **−$109k**; best
  cell still −$15.1k) BECAUSE the Oct 1..Dec 28 occurrence contains the real flip boundary
  (~Nov 15): October losses vetoed December funding and 25 of 26 flip winners were re-parked.
  Splitting at Nov 15 puts pre-peak testing and peak harvest in separate ledgers, so an EARLY loss
  verdict can never veto PEAK funding. Applies to 2024, 2025 and future occurrences alike.
- Fathers Day 2025 is fully absorbed by Graduation 2025 (GRAD boost Apr 20 predates FDAY May 18 and
  GRAD's window outlasts FDAY's). In 2026 FDAY surfaces only Jun 21–24, after GRAD ends.
- A holiday's owned days are always a contiguous suffix of its window, so occurrence = contiguous
  run of owned days.

**OFF runs:** contiguous gaps between peak-owned dates. Each contiguous run is its own occurrence.

**Keys:** `context_label` = short code + holiday year (`XMAS_EARLY_2025`, `XMAS_PEAK_2025`,
`BTS_2026`, `PRIME_2026`) or `OFF`. `occurrence_key` = `context_label || '_' ||
FORMAT_DATE('%Y%m%d', occurrence_start)` — unique per occurrence for peaks AND for recurring OFF
runs. There is no combined `XMAS_<yr>` label anymore; cross-occurrence memory matches
`XMAS_EARLY` to `XMAS_EARLY` and `XMAS_PEAK` to `XMAS_PEAK`.

**2024 backfill (2026-08-08, closes the known gap):** `DIM_US_HOLIDAYS` originally had **no 2024
rows**, so 2024-09-05 → 2025-01-26 was a single OFF occurrence and XMAS_2024 / BF_2024 did not
exist as contexts — Christmas cross-occurrence memory was blind for Q4. Fixed via **targeted
INSERTs against the LIVE table only** (Prime-Day-BLITZ precedent: live table ≠ repo DDL; never
`CREATE OR REPLACE` it). Inserted the five 2024 rows whose `boost_start..cooldown` window
intersects the ads-data era (≥ 2024-09-05), mirroring the 2025 rows' structure with the holidays'
real 2024 calendar dates, categories identical
(migration: `scripts/bigquery/migrations/MIGRATE_DIM_US_HOLIDAYS_2024_BACKFILL.sql`):

| holiday | date | category | boost_start | cooldown_end |
|---|---|---|---|---|
| Back to School | 2024-09-14 | back_to_school | 2024-08-01 | NULL (window end = holiday_date) |
| Halloween | 2024-10-31 | seasonal | 2024-10-10 | NULL — still excluded from contexts |
| Black Friday | 2024-11-29 | gift_season | 2024-10-18 | 2024-12-02 — absorbed by XMAS |
| Cyber Monday | 2024-12-02 | gift_season | 2024-10-21 | 2024-12-05 — absorbed by XMAS |
| Christmas | 2024-12-25 | gift_season | 2024-10-01 | 2024-12-28 |

Earlier-2024 holidays (VDAY..PRIME 2024) end before 2024-09-05 and stay absent. The engines'
`in_peak` reads CURRENT_DATE against gift_season/prime_event windows — 2024 windows can never
contain a current date, so `in_peak` is unaffected by construction (verified at deploy: the
CURRENT_DATE window set was empty before and after). The old single OFF run splits into
BTS_2024 (truncated to 2024-09-05..09-14), OFF, XMAS_2024, OFF. Note `mature_at_start` is
FALSE for every keyword in BTS_2024 and XMAS(_EARLY)_2024 — their starts are < 30d after the
first ads data day; XMAS_PEAK_2024 (starts Nov 15) can carry mature verdicts.

## 2. Settled per-context ledger (`V_KEYWORD_CONTEXT_LEDGER`)

Grain: `(keyword_text, occurrence_key)` where `keyword_text = LOWER(TRIM(targeting))` from
`FACT_AMAZON_ADS` (all targeting: keywords, auto clauses, product targets; rows with empty
targeting dropped; rows kept only when clicks > 0 OR spend > 0 in the occurrence).

Measures per occurrence, **over SETTLED days only** — `date <= anchor − 7`:
- `clicks, spend (Ads_cost), sales (Ads_sales), orders, units`
- `gross_profit = SUM(Ads_sales − IFNULL(TOTAL_COST_PER_UNIT,0) × Ads_units)` (doctrine formula,
  verbatim — NOT the tier-COGS variant the engines use; keep the ledger self-contained)
- `net = gross_profit − spend`

**Settled-window rule (the settle-curve trap):** spend settles ~D+3 but sales accrue to D+7 (SP) /
D+14 (SB). Judging a window younger than D−7 manufactures false loss verdicts. D−7 is the floor;
the SB tail slack (D+8..D+14) is absorbed by the loss allowance. Never judge profitability on
younger data.

Per-keyword columns: `first_click_date` (first ever date with a click, full history — not
settled-capped) and per-(keyword, occurrence): `mature_at_start` =
`first_click_date <= occurrence_start − 30d`.

**Thin-evidence trap:** 1–3 clicks at high ROAS is noise, never a winner. The account's bars are
4 clicks (day-goal) and 15 clicks (`tested_clk`). The ledger exposes raw clicks; consumers must
gate on them.

## 3. Loss allowance + context-scoped park (semantics; enforcement is phase 3)

A keyword may lose up to its **allowance within the CURRENT occurrence**. Past that, AND at
≥ 15 settled clicks (the existing `tested_clk` bar), it is parked **to its per-format floor for the
REST OF THE OCCURRENCE — not permanently**. A new occurrence resets the meter.

Allowance default: `15 × COALESCE(target_cpc, band)` floored at $5 — **placeholder**. Phase 2
CALIBRATES this against the verdict table before anything enforces it. Floors are the existing
per-format floors: SP $0.20 / SB video $0.25 / SB collection+spotlight $0.10 / SB NULL creative
$0.25.

## 4. Cross-occurrence memory (`FACT_KEYWORD_SEASON_VERDICT`)

When the same `context_label` recurs (next BTS, next XMAS):
- A prior-occurrence **LOSS** verdict blocks automatic seasonal entry/funding — at most an
  evidence-scaled re-probe (v27.46: half allowance when the deepest same-family LOSS prior is
  ≥ 40 clicks, full allowance at 15–39 — see §5.1/§5.7).
- A prior **WIN** feeds the existing `seasonal_now` revival.
- **MATURITY GUARD:** only trust a prior verdict if `mature_at_start` is TRUE for that occurrence —
  the keyword's first-ever click was ≥ 30 days before the occurrence started. Ads data begins
  2024-09-05 and most keywords' early history is launch ramp (proven today); a verdict earned while
  a keyword was still finding its bid is not a verdict on the season.

**Verdict rule** (written by `SP_SNAPSHOT_SEASON_VERDICT`, only for CLOSED occurrences —
`occurrence_end <= anchor − 7`, i.e. every day of the occurrence is settled). **v27.44
(2026-08-08) — LOSS dead-band:** the original `LOSS = net < 0` had no breakeven dead-band and a
thin-evidence dollar tail — a 190-click BTS_2025 prior at net **−$0.10** (GP-ROAS 0.9984) was
blocked identically to a GP-ROAS-0 disaster, and 6 of the 54 then-current ENTRY_BLOCKs rode
priors with GP-ROAS ≥ 0.95. A LOSS must now be REAL money AND clearly under breakeven:

| verdict | condition |
|---|---|
| `INSUFFICIENT` | settled clicks < 15 — UNCHANGED; the invariant "INSUFFICIENT is EXACTLY the <15-settled-clicks set" is preserved |
| `WIN` | settled clicks ≥ 15 AND net ≥ 0 — UNCHANGED (net ≥ 0 is exactly GP-ROAS ≥ 1.0: verified 0 disagreements, no zero-spend rows at ≥ 15c) |
| `LOSS` | settled clicks ≥ 15 AND net ≤ −$5.00 AND GP-ROAS < 0.95 |
| `NEUTRAL` | settled clicks ≥ 15 AND neither WIN nor LOSS — **NEW v27.44 label, the dead-band**: near-breakeven or small-dollar outcomes carry NO memory. Deliberately NOT folded into INSUFFICIENT (that would break the invariant). The gate acts only on `'LOSS'`, so NEUTRAL is inert by construction — verified no consumer treats unknown verdict labels as LOSS (the gate matches `prior_verdict = 'LOSS'` positively; the engines match `gate_action`/`entry_state` strings positively; no other object reads the table) |

The row stores clicks/spend/sales/gross_profit/net/orders so calibration can split LOSS by
depth (vs allowance) without re-reading history. Idempotent MERGE on
`(occurrence_key, keyword_text)`; re-runs refresh closed rows in place (also absorbs any late
restatement tail). Partitioned by `occurrence_end`, clustered by `(context_label, keyword_text)`.
Orchestrator: Task 20.5d, tag **v27.41**, after `SP_SNAPSHOT_ADS_RESTATEMENT` (i.e. after
`SP_FACT_AMAZON_ADS` has loaded the day).

**Calendar-change regeneration rule (first applied 2026-08-08):** when the context calendar
changes shape (2024 backfill + XMAS split), verdict rows keyed to occurrences that no longer exist
in `V_SEASON_CONTEXT` are stale and must be DELETEd (this is our own derived table; the MERGE never
removes vanished keys on its own). Applied 2026-08-08: deleted `OFF_20240905` (422 rows — the old
2024-09-05..2025-01-26 mega-OFF) and `XMAS_2025_20251001` (571 rows — the old combined Q4), then
one `CALL SP_SNAPSHOT_SEASON_VERDICT()` re-backfilled the replacement keys (BTS_2024, OFF splits,
XMAS_EARLY/PEAK 2024+2025). The SP itself needed no change — it reads whatever the ledger view
emits.

## 5. Context-scoped contradiction gate (`V_KEYWORD_CONTEXT_GATE`) — WIRED v27.42, 2026-08-08

Wired strictly per the 2026-08-08 re-calibration on the split calendar (§6): **BLOCK_CUT PASS**
(wired), **PARK_CONTEXT FAIL** (advisory-only, never acts), **ENTRY_BLOCK PASS with the
half-allowance re-probe** (wired; never a hard block).

### 5.1 The gate view

One row per `keyword_text`, **keyword grain only** — auto clauses
(`close-match/loose-match/substitutes/complements`), `asin%`/`category%` targets and `'*'` are
excluded up front: the ledger pools text account-wide and those texts pool meaninglessly across
campaigns. Population = keywords with a current-occurrence settled ledger row ∪ keywords carrying a
prior same-family mature verdict.

- **Current-occurrence stats** = the LEDGER's current-occurrence slice (today's `occurrence_key`
  from `V_SEASON_CONTEXT`), computed **directly from FACT_AMAZON_ADS** over
  `[occurrence_start, LEAST(occurrence_end, anchor−7)]` with the doctrine GP formula verbatim —
  parity-verified against `V_KEYWORD_CONTEXT_LEDGER` on closed BTS_2025 (keyed FULL OUTER JOIN,
  2-cent tolerance: 0 mismatches). Reading the ledger VIEW inside the gate dragged its
  full-history FACT × calendar subtree into both engine plans (V_OOB_KEYWORD re-plans
  V_KEYWORD_LIFT via `lift_probes`, so it appeared twice) and pushed V_OOB_KEYWORD ~25s → ~176s;
  the direct slice restored it (~14s; V_KEYWORD_LIFT ~24s). Settled days only — an occurrence's
  first ~7 days always read zero, so the gates **arm as the occurrence settles** (at wiring time,
  BTS_2026 started 2026-08-01 with settled_through 2026-07-31: every current stat was 0, all gates
  armed-but-quiet — 0 action transitions at deploy, by construction, and that is correct).
- **Prior-occurrence memory** from `FACT_KEYWORD_SEASON_VERDICT`: the most recent CLOSED occurrence
  of the same **season family** (`context_label` minus the year: `BTS`, `XMAS_EARLY`, `XMAS_PEAK`,
  `VDAY`, …), **mature verdicts only** (§4 maturity guard). `OFF` runs carry **no** entry memory —
  never calibrated; the engines' existing 90d machinery owns OFF-to-OFF.
- **tcpc proxy** = the keyword's settled CPC over the 90d before occurrence start (≥4 clicks), else
  the median keyword CPC of that same window (band). Deliberately NOT the engines' `target_cpc`
  (v27.40: target_cpc is CPC-units consumed as bid; realized CPC avoids the unit hazard).
- **probe_cap** (ENTRY_BLOCK re-probe allowance) — **v27.46 two-tier, evidence-scaled:**
  `probe_cap = m × GREATEST(15 × COALESCE(tcpc, band), $5)` where `m` depends on the DEEPEST
  same-family mature LOSS prior of the text (MAX(clicks) across all such priors — most evidence
  governs, exposed as `loss_prior_max_clicks`):
  `m = 0.5` when MAX(clicks) ≥ 40 (**tier `DEEP`** — the original half allowance) ·
  `m = 1.0` when 15–39 (**tier `THIN`** — full allowance). Exposed as `loss_evidence_tier`
  (`DEEP`/`THIN`, NULL when no LOSS prior). Rationale (measured 2026-08-08): a healthy ~6%-CVR
  keyword shows 0 orders in 20 clicks ~29% of the time — a 15–39-click LOSS is weak evidence and
  its re-probe deserves the full allowance; ≥40 clicks is a real verdict and keeps the half.
  LOSS label thresholds unchanged; BLOCK_CUT untouched; the tier flows into
  `probe_cap`/`remaining_allowance` so both engines pick it up with ZERO engine changes.

`gate_action` precedence inside the view: **BLOCK_CUT > ENTRY_BLOCK > PARK_CONTEXT > NONE**
(current-context winner evidence outranks last year's loss — the flip release; a wired action
outranks an advisory).

| gate | rule |
|---|---|
| `BLOCK_CUT` | current occurrence **SETTLED** clicks ≥ 15 AND GP-ROAS ≥ 1.0 (settled = anchor−7, unchanged by v27.43) |
| `ENTRY_BLOCK` | prior same-family MATURE verdict = LOSS, and not RELEASED. **v27.43:** `entry_state` is evaluated on the **NEAR-SETTLED** occurrence record (`ns_spend`/`ns_gp` over `[occurrence_start, anchor−3]` — spend settles ~D+3): `PROBING` (ns_spend < probe_cap — the re-probe runs; engines clamp funding bids to `remaining_allowance = GREATEST(probe_cap − ns_spend, 0)`), `STOP` (ns_spend ≥ cap AND ns_gp < ns_spend — stop funding, **unless the 90d hatch releases it**), `RELEASED` (ns paid back — ns_gp ≥ ns_spend at cap — **or** the 90d hatch: trailing-90d `[anchor−89, anchor]` GP-ROAS ≥ 1.0 on ≥ 100 clicks, flagged `released_by_90d`, reason "90d: Nc at R.RRx - proven earner, released") |
| `PARK_CONTEXT` | **ADVISORY ONLY**, SETTLED numbers — best calibration cell: clicks ≥ 15 AND net ≤ −$25 AND GP-ROAS < 0.6, and **suppressed inside XMAS_PEAK occurrences** (the +$2,694 shape). May never move an action or a bid |

v27.43 rationale (replaces the v27.42 D−7 approximation note): the settled ledger left the
allowance blind to money already out the door — at BTS_2026 D+7 all 54 ENTRY_BLOCK caps read
"$0.00 spent" while raw FACT showed **$733.68** spent Aug 1–7 against **$261.00** of total caps
(15 of 19 spending texts over cap, worst 39.8×). The near-settled read closes that window to ~3
days. Sales still accrue to D+7/D+14, so the early ns_gp read biases verdicts **toward STOP — the
conservative direction — and the 90d hatch protects proven earners from exactly that bias** (at
100+ clicks the unsettled tail only understates GP; a keyword clearing 1.0× there clears it
settled too). BLOCK_CUT deliberately stays fully settled: protecting a winner on unsettled
evidence is the unsafe direction.

### 5.2 Engine wiring (OUTPUT layer of both engines)

Gates apply **only to keyword rows**: the gate LEFT JOIN carries `AND NOT is_auto AND NOT is_pt`
in the ON clause, so autos/PTs read NULL gates by construction. Both engines publish
`context_gate` + `context_gate_reason` columns — PARK_CONTEXT appears ONLY there.

`V_KEYWORD_LIFT` (final guard-wrapper CASE, SP + SB rows):
- **BLOCK_CUT** → `HOLD`, reason `this context (<label>): <N>c at <R>x settled — cut vetoed`, when
  the pre-gate action is a cut/park — `PARK, PARK_WAIT, EASE_TO_TARGET, CUT_TO_TARGET,
  CUT_TO_BREAKEVEN, RESEARCH_EASE` — **or** the row is in v27.34's input set (≥4 window clicks
  < 0.6x on `PROBE_ADJUST/PROBE_WAIT/NUDGE_UP/VOLUME_LIFT/PROBE_START`, i.e. about to be parked).
- **ENTRY_BLOCK, `entry_state='STOP'` only** → `PARK` $0.25 (`HOLD` if already ≤ $0.25) when the
  pre-gate action funds the keyword — `PROBE_ADJUST, PROBE_WAIT, NUDGE_UP, VOLUME_LIFT,
  PROBE_START, RAISE_TO_TARGET` — **unless** the current window says winner (≥4 clicks AND ≥1.0x,
  the v27.28 bar): a flip winner is released, season memory never pulls down a live winner.

`V_OOB_KEYWORD` (new `outp` wrapper over the seat-model SELECT):
- **BLOCK_CUT** → `HOLD` when `bid_action IN (DARK_BRAKE, PARK, PARK_WAIT, TRIM_BID, EASE,
  FIT_CPC)`.
- **ENTRY_BLOCK STOP** → `HOLD` when `bid_action = 'ACTIVATE'` (never fund a stopped re-probe into
  darkness; ACTIVATE is OOB's only new-spend action).

**v27.43 — ENTRY_BLOCK PROBING allowance clamp (both engines, output layer).** On
ENTRY_BLOCK/PROBING rows, funding/entry actions — LIFT: `PROBE_START, PROBE_ADJUST, NUDGE_UP,
VOLUME_LIFT`, seasonal `RAISE_TO_TARGET` (the v27.36 KEEP→RAISE winner raise is exempt via the
v27.28 winner bar); OOB: `ACTIVATE` — respect the remaining allowance:
- `remaining_allowance ≥ bid_floor` (v27.33 per-format floors — LIFT SP $0.20, SB per-creative;
  OOB rows carry `bid_floor`): `suggested_bid` clamped to `LEAST(bid, remaining_allowance)`
  (LIFT clamps the v27.37 #3b anchored `probe_bid` when that is the effective entry). The clamp
  branch fires only when it BINDS; `GREATEST(bid_floor, …)` keeps v27.33 intact.
- `remaining_allowance < bid_floor`: action resolves to `HOLD` — reason "re-probe allowance
  exhausted ($X.XX of $Y.YY near-settled) — holds until context ends or record turns". A clamp
  that lands on the current bid is no real move (v27.29) → `HOLD` too.
- Ladder position (LIFT): the HOLD branch sits directly below ENTRY_BLOCK STOP (above v27.36/
  v27.37); the bid clamp sits BELOW the v27.37 pace branch — a queued probe raise stays queued
  and unpriced — and ABOVE the #3b probe_bid branch. Window winners (≥4c ≥1.0×) are never
  clamped. STOP behavior unchanged; STOP reasons now show the near-settled numbers.

### 5.3 Precedence (documented choice, v27.42)

`V_KEYWORD_LIFT` output-guard ladder order:
**v27.28 winner shield → BLOCK_CUT (v27.42) → APPLIED_HOLD → v27.34 loser-park → ENTRY_BLOCK stop
(v27.42) → v27.36 underpriced-winner raise → v27.37 probe pace → v27.33/v27.29 floor + no-op
guards.** PARK_CONTEXT holds NO ladder position (advisory-only).

- **v27.26 wave-veto:** resolves in the INNER action ladder — a wave row reaches the gate already
  `HOLD`, so BLOCK_CUT finds no cut to veto. Outcome is identical (HOLD, no bid) either way; the
  wave reason is kept deliberately, it names the more specific evidence state.
- **BLOCK_CUT vs v27.34, resolved in favour of the SAME-CONTEXT evidence:** a BLOCK_CUT gate only
  exists when THIS context's settled record is ≥15 clicks at ≥1.0x — that outranks a 4-click
  window read, so the park is vetoed (HOLD). The mirror case cannot occur: a same-context LOSS
  record can never mint a BLOCK_CUT gate (GP-ROAS ≥ 1.0 required), so BLOCK_CUT never protects a
  keyword its own context calls a loser — v27.34's park stands there, exactly as required.
- **ENTRY_BLOCK sits BELOW v27.34:** both park decided losers; when both fire, the window evidence
  (more current) names the row; entry-stop catches the rows v27.34 cannot see (0–3 window clicks
  but a breached settled half-allowance).
- **Open knob (measured 2026-08-08, NOT wired):** BLOCK_CUT protection is net-negative at
  occurrence-TAIL anchors (Dec-22 −$225 into cooldown, Sep-05 BTS −$170, OFF −$4/−$81) — consider
  suspending protection in the last ~7 days of an occurrence at the next calibration pass.

### 5.4 Deploy verification (2026-08-08, real measured numbers)

Both engines redeployed ("Replaced" × 2), `.bak` copies `V_KEYWORD_LIFT.sql.bak.v27.42.1458` +
`V_OOB_KEYWORD.sql.bak.v27.42.1458`. Before/after full-row diff:
- **V_KEYWORD_LIFT:** 663 rows → 663, **0 action/bid transitions** (expected: no settled BTS_2026
  days yet). Gate columns live: 40 rows ENTRY_BLOCK (all PROBING, $575.60 W-window spend on 27
  distinct keywords), 75 NONE, 548 NULL (autos/PTs/no gate row). 0 gates on auto/PT rows;
  v27.28 invariant 0 violations.
- **V_OOB_KEYWORD:** 121 rows → 121, **0 transitions**. 6 rows ENTRY_BLOCK (all PROBING, $35.78
  yesterday spend), 17 NONE, 98 NULL. 0 gates on auto/PT rows.
- Gate view: 128 keywords — 54 ENTRY_BLOCK/PROBING (BTS_2025 mature LOSS memory; probe caps
  $2.50–$8.92, avg $4.83), 0 BLOCK_CUT, 0 PARK_CONTEXT, 74 NONE.
- The BLOCK_CUT / ENTRY_BLOCK-STOP branches cannot fire on 2026-08-08 data (nothing settled
  in-occurrence); their CASE precedence was proven with a 9-case mocked-row test (winner shield
  outranks BLOCK_CUT; BLOCK_CUT pre-empts the v27.34 park; ungated v27.34 park stands; STOP parks
  a funded probe at >$0.25 else HOLD; window winner released from STOP; PROBING untouched).
- Runtimes after the §5.1 plan-cost fix: V_KEYWORD_LIFT ~24s (was ~7s pre-wiring — the gate adds
  ~17s), V_OOB_KEYWORD ~14s (was ~25s pre-wiring). Follow-up lever if LIFT cost grows: point
  V_OOB_KEYWORD's `lift_probes` at `T_LIFT_PROBES` (the sanctioned anti-inline snapshot; content
  differed from live by 1 stale keyword_id at check time) — NOT done, it changes probe-freshness
  semantics and is outside the calibration verdict.

Out of scope still: budget-engine membership (D5), OOB-vs-LIFT applied-hold override (D3),
DARK_BRAKE sizing (D4), budget floor no-ops (D6).

### 5.5 v27.43 deploy verification (2026-08-08, anchor 2026-08-07, real measured numbers)

Gate view redeployed ("Replaced"), then both engines ("Replaced" × 2) with `.bak` copies
`V_KEYWORD_LIFT.sql.bak.v27.43.1659` + `V_OOB_KEYWORD.sql.bak.v27.43.1659`.

- **entry_state before → after** (BTS_2026, near-settled through Aug 4, settled through Jul 31):
  54 ENTRY_BLOCK/PROBING at $0.00 settled ($733.68 raw Aug 1–7 behind them) →
  **39 PROBING** ($13.28 ns spend vs $191.60 caps, $178.32 remaining; $14.42 raw Aug 1–7),
  **8 STOP** ($269.62 ns vs $38.86 caps; $348.62 raw),
  **2 RELEASED** occurrence-paid-back ($36.24 ns; 'gift for 14 year old girl' $61.89 GP on
  $22.61, 'gift for tween girls 11-14'),
  **5 RELEASED via 90d hatch** ($137.72 ns; $313.95 raw). 0 PROBING rows with ns_spend ≥ cap
  remain — the $733.68-vs-$261 blindness is closed (all 15 over-cap texts read STOP or RELEASED).
- **Hatch releases (the 4 protected + 1):** 'tween birthday gifts for girls' 3,862c at 1.17×,
  '9 year old girl gifts' 1,316c at 1.09×, 'journal for girls' 940c at 1.01×, 'young adult girls
  gift ideas' 209c at 1.62× (combined $212.46/wk — none may ever STOP), plus
  'gift for 9 year old girl' 379c at 1.03× (the 39.8×-over-cap worst case: $22.22 ns vs $2.55 cap).
  90d window = FACT `[anchor−89, anchor]` — reproduces the verifier's numbers exactly.
- **Engine transitions:** gate A+B flipped exactly **1 LIFT row** ('birthday gift for 12 year old
  girl', PROBE_START → HOLD via the existing STOP branch, $32.96 near-settled at 0.00× against a
  $7.80 cap); the other STOP-text rows were already cut/parked on their own window evidence
  (v27.34 / CUT_TO_BREAKEVEN / KEEP_TAIL), which the gate rightly leaves alone. FIX C caused
  **0 transitions today** — full-row diff pre/post C: 663 → 663 (LIFT) and 125 → 125 (OOB)
  identical on (action, suggested_bid, context_gate); every live PROBING funding bid (2 NUDGE_UP,
  1 VOLUME_LIFT, 1 OOB ACTIVATE at $1.00 vs $3.15 remaining) is under its remaining allowance, so
  the clamp correctly does not bind. OOB carries no STOP rows today.
- **Determinism (v27.42.1):** two back-to-back full-gate pulls, **byte-identical** (128 rows).
  PERCENTILE_CONT band untouched; the new ns/r90 CTEs are plain SUMs over fixed windows.
- **Guards, all 0 violations:** LIFT — winner shelved 0, winner pulled down 0 (v27.27/28),
  empty promises 0 (v27.29), below-floor bids 0 (v27.33), funded proven losers 0 (v27.34),
  gates on auto/PT rows 0 (v27.42). OOB — below-floor 0, empty promises 0, gates on auto/PT 0.
  Gate — PROBING-over-cap 0, entry_state-without-LOSS-memory 0 (v27.42.1), ENTRY_BLOCK-with-
  RELEASED leak 0. v27.26/v27.38/v27.39 layers untouched (0 action/bid diffs on all non-gated
  rows). The 2 OOB winner-ease rows are the approved v27.16 winner-concentrated EASE, unchanged.
- **Runtimes:** V_KEYWORD_LIFT ~12s, V_OOB_KEYWORD ~24s (one 77s outlier on a full-row CSV
  export; count-only re-run 24s — watch it, the §5.4 T_LIFT_PROBES lever remains available).
- **Semantics note:** with anchor at BTS D+7, ns covers Aug 1–4 ($456.86 of the $733.68); the
  Aug 5–7 tail enters as the anchor advances. First fully-settled BTS day lands Aug 14 — the
  deadline this fix pre-empts.

### 5.6 v27.44 deploy verification (2026-08-08, anchor 2026-08-07, real measured numbers)

LOSS dead-band (§4 verdict rule). Only `SP_SNAPSHOT_SEASON_VERDICT` changed ("Replaced"); the
gate and both engines were NOT redeployed — the new labels flow through the existing
`prior_verdict = 'LOSS'` predicate.

- **Regeneration (fully-derived table):** snapshot to `TMP_V2744_VERDICT_BEFORE`, then
  `DELETE FROM FACT_KEYWORD_SEASON_VERDICT WHERE TRUE` (**5,739 rows deleted**, table read 0),
  then ONE `CALL SP_SNAPSHOT_SEASON_VERDICT()` → **5,739 rows rewritten**. Keyed FULL OUTER JOIN
  vs the snapshot: 0 key drift, 0 metric changes.
- **Migration matrix (old → new):** INSUFFICIENT→INSUFFICIENT 2,563 · WIN→WIN 1,405 ·
  LOSS→LOSS 1,599 · **LOSS→NEUTRAL 172** — no other cell is populated; WIN and INSUFFICIENT
  bit-stable as required. LOSS→NEUTRAL by label: OFF 56, BTS_2025 15, XMAS_EARLY_2025 13,
  XMAS_PEAK_2025 12, EASTER_2025 12, FDAY_2026 8, EASTER_2026 7, XMAS_PEAK_2024 7, VDAY_2025 6,
  PRIME_2025 6, PRIME_2026 6, GRAD_2026 4, XMAS_EARLY_2024 4, VDAY_2026 4, GRAD_2025 4,
  BTS_2024 4, MDAY_2025 2, MDAY_2026 2 (= 172).
- **Named rows:** 'birthday gift for 12 year old girl' BTS_2025 (190c, net −$0.10, GP-ROAS
  0.9984) → **NEUTRAL** (was the wrongful STOP). 'sweet 16 gifts for girls' BTS_2025 (16c, net
  −$13.51, GP-ROAS 0.0000) → **stays LOSS** (meets BOTH bars: net ≤ −$5 AND GP-ROAS < 0.95) —
  the one-order-flips-it concern remains a live edge; revisit if it blocks wrongly in BTS_2026.
- **Idempotency:** 2nd CALL = zero change (keyed join, all non-FLOAT columns exact, FLOAT within
  2¢ — the only deltas were 2 sub-cent `net` wobbles on deep-WIN rows, the documented FLOAT-sum
  aggregation-order noise; verdicts identical). Orchestrator Task 20.5d green (step body is the
  same CALL; today's logged run OK).
- **Gate impact (gated texts 54 → 44):** entry_state 39 PROBING / 8 STOP / 7 RELEASED →
  **32 PROBING / 7 STOP / 5 RELEASED**; gate_action ENTRY_BLOCK 47 → 39, NONE 74 → 84;
  population 128 → 128. **10 texts dissolved**, every prior in the dead-band (all BTS_2025):
  STOP: 'birthday gift for 12 year old girl' (190c, −$0.10, 1.00). PROBING: 'girls gifts 10-12'
  (838c, −$2.03, 0.99), 'birthday gifts for teen girls' (748c, −$9.69, 0.96 — fails the ROAS
  bar), '12 year old girl birthday gifts' (140c, −$2.59, 0.96), 'gifts for 7 year old girl'
  (75c, −$4.42, 0.90), 'gifts for teen girls 12-14' (49c, −$3.28, 0.81), 'gift for 7 year old
  girl' (39c, −$4.77, 0.81), 'slumber party' (32c, −$1.91, 0.88). RELEASED: 'young adult girls
  gift ideas' (723c, −$2.76, 0.99), 'gift for tween girls 11-14' (75c, −$0.36, 0.98). The
  29 sub-0.5 legitimate LOSS priors all survive (0 dead-band leaks among the 44).
- **Engine transitions:** V_KEYWORD_LIFT 663 → 663 rows; **1 action transition** — 'birthday
  gift for 12 year old girl' (FRESH-VIDEO/EXACT SB): HOLD → **PROBE_START $1.00** ($0.00 W-window
  spend), the exact row the v27.43 STOP had parked; 6 more rows only dissolved their
  context_gate column, actions stand on their own window evidence (PARK $0.25 at $4.88 W-spend,
  KEEP_TAIL $3.14, PROBE_WAIT $0.00, IDLE ×3 $0.00). V_OOB_KEYWORD 121 → 121, **0 transitions**
  (no dissolved text has an OOB row). Budget suggestions 0 changes.
- **Machinery unchanged (before/after gate join, 128 rows):** BLOCK_CUT inputs (cur_*) 0 diffs;
  near-settled (ns_*) 0; 90d hatch (r90_*) 0; probe_cap 0; remaining_allowance 0; prior
  occurrence keys 0. Only verdict labels moved.
- **Determinism:** two back-to-back full-gate pulls **byte-identical** (128 rows; note
  `bq query` truncates at 100 rows without `--max_rows` — a truncated pull is not a diff).
- **Guards, all 0:** gate — ENTRY_BLOCK-with-RELEASED leak 0, entry_state-without-LOSS-memory 0,
  PROBING-over-cap 0, NEUTRAL-treated-as-LOSS 0, BLOCK_CUT-rule violations 0, auto/PT rows 0.
  LIFT — gates on auto/PT 0, winner shelved 0, winner pulled down 0, empty promises 0,
  below-floor SP bids 0. OOB — gates on auto/PT 0, below-floor 0, empty promises 0,
  ENTRY_BLOCK-STOP ACTIVATE 0 (the one ENTRY_BLOCK ACTIVATE is the sanctioned §5.5 PROBING
  re-probe 'gifts for 7 year old girls' at $1.00 vs $3.15 remaining allowance).
- **Q4 arming forecast restated** (gate's prior logic replayed per family, mature only,
  keyword-grain exclusions): **Oct 1 (XMAS_EARLY): 101 → 90** ENTRY_BLOCKs arm (−11).
  **Nov 15 (XMAS_PEAK): 65 → 58** (−7). The before-side replay reproduces the ~101/~65 baseline
  exactly.
- Scratch objects `OI.TMP_V2744_*` (verdict/gate/engine before-after snapshots) dropped after
  verification.

### 5.7 v27.46 guard batch (2026-08-09) — A1 two-tier allowance · A2 winner-exemption doctrine · A3 seasonal_now precedence · A6 negate surface

**A1 — thin-LOSS two-tier allowance (gate view only, zero engine edits).** See the §5.1
`probe_cap` definition. Deploy notes: the multiplier is applied to the SAME `GREATEST(...)` base
(rounding once, after `m`), so DEEP rows are bit-identical to the pre-v27.46 caps and THIN rows
carry exactly the doubled cap. The engines' and gate's older reason strings said "half-allowance
re-probe" unconditionally; the gate's own reasons now say "half-allowance"/"full-allowance" by
tier — the ENGINE reason strings were deliberately NOT touched (A1 is a no-engine-edit item), so
an engine reason may still say "half allowance" on a THIN row; the dollar numbers it prints come
from the gate and are correct. Cosmetic; fix at the next engine pass.

**A2 — winner-exemption doctrine (formalized, no code change).** The LIFT probe-clamp winner
exemption is DOCTRINE, not an accident of wiring: **current-window conversion outranks
prior-season memory** — a row with `clicks_w >= 4 AND roas_w >= 1.0` (which implies an in-window
order) is **never allowance-clamped** and never STOP-parked. This is consistent with the 90d STOP
escape hatch (recent proven record outranks the occurrence-window read) and with the v27.28
winner shield (winners never pulled down), and it is conservative because unsettled ROAS
UNDERSTATES: a row clearing 1.0× on partially-settled sales clears it settled too. Ori decided
KEEP (2026-08-08). The OOB analog of the in-window winner is `converting`
(roas_1d ≥ 1.0 OR roas_prev2 ≥ 1.0 — OOB's own winner test; it has no W-window).

**A3 — seasonal_now vs gate precedence (output-layer guard, both engines).** Where a row has a
mature same-context LOSS prior AND gate `entry_state IN ('PROBING','STOP')` and is NOT
winner-exempt (A2 bars; BLOCK_CUT rows are also exempt — an occurrence-level settled winner
outranks entry memory by gate precedence): **seasonal_now loses its authority** — it may not
seat-jump the row and may not RAISE beyond the allowance-clamped bid; `STOP` → no seasonal raise
at all. WIN/NEUTRAL/INSUFFICIENT priors: seasonal_now untouched. The winner exemption outranks
this guard — an in-window winner regains full seasonal authority. Implementation (v27.46):
- The emitted-instruction surface was ALREADY fully guarded by v27.42/43: LIFT STOP blocks
  `RAISE_TO_TARGET` (+ all funding actions) and PROBING clamps them to `remaining_allowance`
  (winner-exempt); OOB STOP blocks `ACTIVATE` and PROBING clamps it. v27.46 adds the
  **published `seasonal_now` column neutralization** in both engines' output layers — a gated
  row (LOSS prior + PROBING/STOP, not winner-exempt, not BLOCK_CUT) now PUBLISHES
  `seasonal_now = FALSE`, so every downstream consumer (dashboard badges, cubes, other views)
  treats it as non-seasonal.
- **Honest limitation (documented, not hidden):** the INTERNAL seat/candidate ORDERING
  (`seat_rank`/`cand_rank` keys in the engines' inner CTEs) still reads the raw seasonal_now —
  the gate's entry_state cannot reach those CTEs without re-planning the gate subtree inside
  both engines (the exact plan-cost mistake §5.1 documents, ~25s → ~176s; V_OOB_KEYWORD is at
  the planner ceiling — no new inner joins). Consequence: a gated seasonal row can still hold a
  seat ahead of a better candidate, but everything it is ALLOWED TO DO in that seat is
  allowance-clamped/blocked, so it cannot overspend its re-probe allowance. Revisit only if a
  measured case shows a displaced candidate losing real money.

**A6 — STOP → negate surface (`V_SEASON_NEGATE_CANDIDATES`, ADVISORY-ONLY).** One row per
(keyword_text, campaign) where a gate `ENTRY_BLOCK`/`STOP` text (mature LOSS prior; failed its
re-probe; the 90d hatch structurally precedes STOP, so every row here is hatch-ineligible — the
`r90_*` columns prove it) is CURRENTLY TARGETED by an enabled campaign: campaign, channel,
match types, prior-occurrence evidence (clicks/net/GP-ROAS), current-occurrence near-settled
re-probe spend, `suggested_scope = 'SEARCH_TERM_NEGATE'`. **Defense campaigns excluded
entirely** (never negate in defense); auto/PT rows excluded (the gate does not govern them).
This is an advisory surface for the negatives workflow — `DE_NEGATIVE_KEYWORDS` is the
authority, NOTHING auto-uploads (coacher no-auto-fill doctrine). Registered in `config.yaml`.

A4 (DARK_BRAKE scaled by 90d reality) and A5 (budget no-op guard) live in
`architecture/OOB_BUDGET_PHASE.md` §v27.46 guard batch.

## 6. Calibration record (2026-08-08, split calendar, read-only)

Keyword rows only (auto/PT/star excluded — the grain hazard); GP = doctrine formula; anchors
first-anchor-deduped, forward windows fully settled; tcpc proxy = realized pre-occurrence CPC.

- **BLOCK_CUT — PASS, bar stays 15 clicks.** Strict split frame: bar 15 = 87 protected (5.0%),
  fwd $10,281 at 1.202, **net +$2,080**; wrong-protection 37.7% of spend but protected winners earn
  ~3× what wrong protections lose (+$3,176 vs −$1,096). Bar 10 adds only +$107 (noise risk), bar 30
  costs −$228 and 16% coverage. Wide (yesterday-comparable) frame: +$21,386 at 1.354. Under the
  split, XMAS_PEAK coverage INVERTED upward (11/10/6 protections vs coarse 6/6/2; Nov-29 anchor
  +$1,120 vs +$175) — the coarse Oct-1-cumulative ROAS had dragged in-peak winners under 1.0.
- **PARK_CONTEXT — FAIL, wire nothing.** Only 2 of 28 grid cells positive; best (flat $25 +
  GP-ROAS<0.6) = +$1,274 but **−$1,420 inside XMAS_PEAK_2025 = 111% of aggregate net** (parks core
  gift terms in early December on 8 days of early-peak data). Doctrine default 15×tcpc ungated =
  −$10,935 (was −$109k coarse). Flip test PASSES under the best cell (26/26 flip winners free in
  peak vs 25/26 RE-parked coarse) — the calendar fix worked; the cell still fails on money. With
  XMAS_PEAK-internal parks excluded: **+$2,694**, positive 8 of 10, worst residual −$29 — that
  shape needs its own re-calibration (incl. XMAS_PEAK_2026) before PARK_CONTEXT may ever act.
- **ENTRY_BLOCK — PASS only WITH the half-allowance re-probe.** Block+reprobe **+$551** across 67
  entered keywords, 13 stops / 12 correct (92%); hard block **−$6,578** — XMAS_PEAK 2024→2025 alone:
  hard block forfeits **+$5,103** that the re-probe releases (10 of 12 released). EASTER fully
  rescued by the probe ($0 vs −$1,346 hard). The mechanism is asymmetric insurance, not a profit
  engine. BTS_2026 note: BTS_2025 carries 54 mature LOSS keyword verdicts — that IS the live entry
  memory; the 2024→2025 validation pair was blind (all-immature 2024), so this specific pair is
  wired on doctrine + cross-season evidence, not a same-season backtest.

## 7. Settle doctrine + revival machinery (`V_PARK_REVERDICT` / `FACT_PARK_REVERDICT`) — WIRED v27.48, 2026-08-09

**Ori's rule (approved 2026-08-09): "no condemnation before settle, re-judgment at settle."**
Spend settles ~D+3; sales accrue to **D+7 (SP)** / **D+14 (SB)**. Any engine window whose tail is
younger than the settle horizon UNDERSTATES GP — a verdict made on it biases toward condemnation.
Iteration-6 audit: 238 of 245 logged parks were applied Aug 2-6 judging windows whose tails sat
inside D+7; **~20% of the wave flipped to settled condemning-window GP-ROAS >= 1.0** ('diy journal
kit for girls 8-14': 566 condemning clicks now 1.16x; 'gifts for 12 year old girls': 1,252c 1.97x).

### Objects
| object | role |
|---|---|
| `V_PARK_REVERDICT` | settled re-judgment of every parked/STOPped/recently-revived keyword (DIM_KEYWORD config — carries BOTH SP and SB keyword config; 26 of the 33 calibrated revives sit in SB campaigns) |
| `FACT_PARK_REVERDICT` | snapshot the ENGINES read (planner-ceiling doctrine — the view's FACT+gate subtree must never enter an engine plan). Written by `SP_SNAPSHOT_PARK_REVERDICT`, orchestrator **Task 20.5e** (after 20.5d — the reverdict reads season verdicts + the context gate) |

### Reverdict (calibrated 2026-08-09 on the 551-row parked stock; grid in the batch record)
- **REVIVE** — settled-90d ([settle_cut-89, settle_cut], **(campaign_id, keyword_id) FACT grain**
  — was (campaign, targeting TEXT) until v27.52, see §7.12 — tier-COGS GP) **clicks >= 10 AND
  GP-ROAS >= 1.0, or >= 0.8 with a season-WIN verdict** for the text. 33 revives / bench $6,126
  settled GP on $5,364 settled spend. Bar flat 10-15; bar 5 adds only 3 tiny rows.
- **CONFIRM_PARK** — >= 10 settled clicks failing the bar (60 rows at blended 0.34x validate the
  floor), gate STOP without a current-occurrence settled release (guard 4 — the 2 blend-conflicted
  texts are FLAGGED for gate re-audit, never auto-released), or a re-park after a revive inside
  the same occurrence (guard 3: **one revive per season occurrence**, keyed on the current
  V_SEASON_CONTEXT occurrence). Never resurfaces: engines block $1 ACTIVATE / probe promotion.
- **PENDING_SETTLE** — < 10 settled clicks and the last pre-park click younger than the channel's
  settle horizon (settle_due = last pre-park click + 7 SP / + 14 SB) — re-judged at settle.
- **INSUFFICIENT** — < 10 settled clicks, nothing pending; normal candidate queue.

The BAR window deliberately stays on the calibrated settle_cut = today-7 for every row: the SB
day-8..14 tail only understates GP, so the error direction is a missed revive / early
CONFIRM_PARK that self-heals on a later daily snapshot — never a false revive.

### Revive bid (calibrated)
`clamp( min(pre-park bid, 1.10 x settled-90d CPC), $0.31, $1.50 )`; unknown-era (no logged park):
`clamp(1.10 x settled CPC, $0.31, $1.50)`. Median $0.40. The $0.31 floor clears both engines'
bid > 0.30 park-detection threshold AND repaces the cheap proven winners (Cause 4: 'gift for
girls' $0.186 CPC at 1.98x -> +67% pressure). **NEVER the $1 probe entry** — proven records have
anchors; $1 entries on sub-$0.30-CPC winners is Cause-2 behavior in reverse.

### Engine wiring (v27.48 — V_OOB_KEYWORD in-place, V_KEYWORD_LIFT output layer, both arms)
1. **Seat priority** — REVIVE joins the proven tier of the seat ordering and ranks above fresh
   unproven inside it; CONFIRM_PARK sinks with the tested losers and is skipped by LIFT's probe
   cand_rank.
2. **ACTIVATE_REVIVE** — seated + uncapped/darkness-gated + paced (20% rule) at the calibrated
   revive bid. LIFT defers to the gate when ENTRY_BLOCK is armed (season-gate precedence); OOB's
   gated layer clamps/blocks ACTIVATE_REVIVE exactly like ACTIVATE (STOP -> HOLD, PROBING ->
   allowance clamp). Queue-stuck REVIVE rows HOLD with the queue reason — their remedy is a
   **BUDGET line** (+$4/day per seat, slots = budget/$4), never a PARK_WAIT re-park (v27.29).
3. **Settle veto** (`engine_immune` / REVIVE_SETTLE_HOLD) — a keyword revived off a proven settled
   record (>= 10 settled clicks + >= 1 settled order BEFORE the revive; a fresh $1 probe has
   neither and keeps its 20-click discipline) is immune to PARK / PARK_WAIT / CUT_TO_* and the
   v27.34 window-loss re-park until **10 NEW settled clicks** accrue. DARK_BRAKE / EASE / TRIM /
   FIT_CPC stay live same-day — dark is never a hold; the veto blocks only condemnations.
   Earliest legitimate re-condemnation lands ~2-3 weeks post-revival, by construction.
4. **Manual hold** (Cause 3) — any keyword whose last applied change is source=MANUAL is
   engine-immune for 14 days, both directions: no condemnation over Ori's raise, no auto-revival
   or $1 activation over Ori's park (the advisory sweep may still list it — Ori decides).
5. **APPLIED_HOLD interplay** — an uploaded revival holds (applied-today / unsynced-config test)
   until Amazon syncs; the reverdict's LIVE rows then carry the settle veto. No-change actions
   REVIVE_SETTLE_HOLD / holds join the v27.29 exempt set; ACTIVATE_REVIVE always carries a bid.

### One-time sweep (2026-08-09)
`OI/.tmp/park_revival_sweep_20260809.xlsx` — ADVISORY bulksheet (coacher no-auto-fill: nothing
auto-uploads): the 33 REVIVE rows with evidence, seated rows as bid lines, queue-stuck rows as
campaign BUDGET lines, gate-audit flags for the 2 STOP conflicts.

### 7.6 General settle veto (v27.48 part 2, Cause 1) — `SETTLE_HOLD`, both engines
The part-1 veto protected only revived rows; part 2 generalizes Ori's rule to EVERY keyword:
a condemnation — LIFT `PARK` / `CUT_TO_BREAKEVEN` / `CUT_TO_TARGET` + the v27.34 window-loss
re-park; OOB the tested-loser `PARK` (this engine's only condemnation) — may fire only if

1. **(a) the condemning clicks are fully settled** — guard `settle_ok`: no clicks in the last
   D+7 (SP) / D+14 (SB), i.e. `last_click <= anchor - settle_days`; or
2. **(b) the settled record corroborates** — channel-aware settled-90d GP-ROAS < 1.0 on
   **>= 10 settled clicks** (the reverdict's evidence bar; fewer settled clicks = no
   corroboration), **and no season WIN prior** (any mature-frame WIN verdict for the text —
   "a keyword with settled 90d >= 1.0 or a season WIN prior is never condemned on unsettled
   clicks").

Else the row holds as `SETTLE_HOLD` with the honest reason: "wave — sales not yet attributed
(last click D, settles D+7/14) … re-judge at settle". Deliberate boundaries:
- **PARK_WAIT is NOT vetoed** — the seat queue is budget mechanics, not a verdict; vetoing it
  would break the v27.24 park-for-activation swap.
- **DARK_BRAKE / EASE / TRIM / FIT_CPC / AUTO_* / RESEARCH_EASE stay live** — dark is never a
  hold.
- **ENTRY_BLOCK rows are exempt** — season-gate precedence unchanged (STOP parks and PROBING
  allowance economics own their rows); BLOCK_CUT and the v27.28 winner shield sit above anyway.
- **Season-WIN breadth**: 174/625 texts carry a WIN prior, so during a season window a daily-
  clicking WIN-prior keyword can stay vetoed indefinitely (its last click keeps advancing).
  This is the approved doctrine (season memory + v27.26 wave rule); the remaining levers are
  the OOB dark machinery (capped campaigns), budget cuts and search-term negation.
- OOB wiring note: the veto lives at the GATED layer (small-table join on the final rowset —
  the planner-ceiling seat CTEs are untouched), BELOW BLOCK_CUT, and **defers to a pending
  applied change** so an uploaded row still surfaces as APPLIED_HOLD, never SETTLE_HOLD.
2026-08-09 deploy day: LIFT 17 rows vetoed (13 SP + 4 SB — all of yesterday's PARK/CUT stock
except 3 corroborated survivors), OOB 1 ('gifts for 12 year old girl', tested-loser park on 0
settled clicks, settles 2026-08-22).

### 7.7 Probe reads the record (v27.48 part 2, Cause 2) — entry caps + settled-first ordering
"No recent data" is not "never tested". Identity per the 2026-08-09 pace calibration:
keyword_ids do not survive campaign recreations, so the record is **SCOPE-grain** — keyword
text account-wide, auto clauses pooled per dominant-family (`V_KEYWORD_GUARD` `life_*`).
- **Entry caps** (LIFT `PROBE_START`, OOB generic `ACTIVATE`; `ACTIVATE_REVIVE` exempt — its
  bid is part-1-calibrated): lifetime >= 30 clicks -> entry <= **lifetime conv CPC x 1.2**;
  gate `ENTRY_BLOCK` (prior same-family mature LOSS) -> entry <= **LY conv CPC x 0.8**. Both
  COMPOSE with the v27.43 remaining-allowance clamp (min of all), floor = per-format platform
  floor. A cap landing on the current bid is no real move (v27.29) -> HOLD.
- **Lifetime loser** (>= 30 clicks < 0.6x GP-ROAS scope-wide) is NOT untested: PROBE_START /
  ACTIVATE -> HOLD — the loser path owns it, never a $1 entry.
- **Settled-first ordering**: `IF(settled_winner, 0, 1)` extends the v27.38 profit ordering
  (LIFT probe_rank), the LIFT seat_rank proven tier (below the part-1 `is_revive` key — revived
  winners stay on top; live window earners above both — the v27.20 lesson stands) and
  cand_rank; `record_loser` rows leave the candidate pool. KNOWN LIMIT (v27.46-A3 precedent):
  V_OOB_KEYWORD's INNER seat ordering cannot read the guard without adding the subtree to the
  ceiling plan — its proven tier already ranks by roas90; documented, not wired.

### 7.8 Manual-override hold (v27.48 part 2, Cause 3) — `MANUAL_HOLD`, both engines
`FACT_PPC_CHANGE_LOG.source` values (inspected 2026-08-09): `COACH` = engine batch uploads,
`MANUAL` = Ori's hand via the Do page, `REUPLOAD` = the re-upload flow (engine-class). A row
whose LAST bid change is source=MANUAL and < **7 days** old gets `MANUAL_HOLD` (no suggestion)
— unless the settled record is **catastrophic** (< 0.6x on >= 10 settled clicks: a keyword
losing money now is not protected). Sits directly BELOW `APPLIED_HOLD` in both engines (the
applied doctrine outranks; tomorrow's uploaded rows still show APPLIED_HOLD). Interplay with
part 1: the reverdict's 14-day manual immunity (condemnations + auto-revival, parked stock)
still stands — 7d full-quiet, 8-14d condemnation/revival-immune only.
**COVERAGE HOLE (not pretended fixed): changes made directly in the Amazon console never land
in FACT_PPC_CHANGE_LOG and cannot be held.** Only OI-flow uploads are protected.

### 7.9 LY-pacing raise (v27.48 part 2, Cause 4) — `PACE_RAISE`, V_KEYWORD_LIFT only
The only signal that reaches starved winners: cheap proven keywords pacing far below their LY
volume never generate the recent-window data every other raise rule needs. Calibration
2026-08-09 (queries preserved; ~10 rows, est. $56-74/wk net GP): **fire at instance 28d click
pace < 25% of the LY same-28d window (weekday-aligned, date-364d) AND bid < LY conv CPC**,
gated on settled 90d >= 1.2x (>= 10 settled clicks, calibration frame wm-96..wm-7), scope
lifetime >= 100 clicks, LY window >= 20 clicks, bid unchanged >= 7d (never fight a fresh park
— the revival check owns those), campaign NOT OOB-owned/capped (PHASE = budget authority;
PACE_RAISE deliberately does not exist in V_OOB_KEYWORD). Target =
`GREATEST(bid, LEAST(band ALL/ALL cpc_max [season cell], settled GP-per-click / 1.2,
1.5 x LY conv CPC))` capped $2.00 — glide +10%/day (RAISE_TO_TARGET pacing), floor at the
current bid (winners never pulled down). Engine-side: fires only on otherwise-idle rows
(KEEP / KEEP_TAIL / HOLD / IDLE / PROBE_START), seated, uncapped, gate != ENTRY_BLOCK, not
CONFIRM_PARK, not window-losing, applied-self-test, and DEFERS to the part-1 revive path
unless that path is manually blocked (manual park 7-14d old: pace is its only recovery path).
`pace_watch` (25-40% band) is display-only. Canonical row 'gift for girls' kw 321268702442172:
pace 0.086 (244 vs 2833 LY clicks), settled 609c at 2.0x, target $0.31 — flagged; on deploy
day Ori's own 06:00 MANUAL raise ($0.20 -> $0.28) had already absorbed it (stability gate +
applied doctrine correctly keep the engine quiet; counterfactual on yesterday's change log:
pace_flag TRUE, PACE_RAISE $0.25 day-1).

### 7.10 Part-2 objects + snapshot flow
`V_KEYWORD_GUARD` -> `SP_SNAPSHOT_KEYWORD_GUARD` (orchestrator **Task 20.5f**, after 20.5e) ->
`FACT_KEYWORD_GUARD` (~625 rows, (campaign_id, keyword_id), SP+SB). Engines read the SNAPSHOT
only. Missing rows fail OPEN (pre-guard behavior); stale directions bounded by the 1-day
cooldown + APPLIED_HOLD. `SETTLE_HOLD` / `MANUAL_HOLD` join the v27.29 no-change exempt set;
`PACE_RAISE` always carries a real bid.

### 7.11 Revivals surface on the Weekly Run page (2026-08-12)
The reverdict has been running since v27.48 but had **no surface** — 29 REVIVE rows sat in a view
nobody opens. Ori initiates his real changes from the Weekly Run page, so that is where the
revival evidence has to live.

| piece | where |
|---|---|
| cube | `cube/schema/ParkReverdict.js` over `V_PARK_REVERDICT` (live read, 15-min TTL — same convention as `KeywordLift` / `OobBudget` / `PausedHistory`) |
| panel | `dashboard-react/src/pages/RevivalsPhase.tsx`, mounted in **step 4 · Actions** of `WeeklyRunPage.tsx`, directly under the coach flowchart and above the engine phases |

`V_PARK_REVERDICT` carries no `campaign_name` / `family` (it is keyed on DIM_KEYWORD config), so
the **cube SQL** left-joins `V_DIM_CAMPAIGN_CURRENT` and `V_CAMPAIGN_FAMILY_MAP` for those two
labels — the same two joins `V_CHANGE_SCORECARD` uses. Label lookup only; **the view itself is not
rebuilt and no decision moves into the cube.**

What the panel shows, and where every number comes from:
- **REVIVE** (primary list, count visible while collapsed) — keyword/target · campaign · family ·
  channel · when it was parked (`park_date`, `park_source`, `park_era`, `n_park_events`) · the
  settled record that earned the revival (`s90_clk` / `s90_sp` / `s90_ord` / `s90_gp_roas` /
  `s90_cpc`, settled through `settled_through`) · the calibrated `revive_bid` against
  `current_bid` and `pre_park_bid` · the anti-churn guard state (`re_parked_this_occ`,
  `manual_parked_recent`, `stop_released`, `engine_immune` + `immune_reason`, `revive_settling`,
  `context_label` / `occurrence_key`) · and `reverdict_reason` verbatim.
- **CONFIRM_PARK** and **PENDING_SETTLE** — two secondary sub-lists inside the same panel,
  collapsed, so a parked keyword's state is knowable without hunting. `PENDING_SETTLE` shows
  `settle_due` (when it will be re-judged); `INSUFFICIENT` (the normal candidate queue, ~450 rows)
  is deliberately NOT surfaced — it is the null state, not news.

**Advisory only.** The panel is display-only: it does not write to the DO queue and does not
generate bulksheet rows. Reviving is Ori's decision; the one-time sweep pattern (§7 "One-time
sweep") remains how a revive batch gets prepared. No verdict, threshold or bid math exists in the
TypeScript — every label, bid and sentence is read from the view.

### 7.12 v27.52 FIX 2 (2026-08-12) — the reverdict's evidence is keyed on `keyword_id`, not on text

The v27.48 build joined `FACT_AMAZON_ADS` to the population on **(campaign_id, targeting TEXT)**,
discarding `keyword_id` on both sides. Text is not a key. Two measured consequences, both live on
the Weekly Run Revivals panel until this deploy:

1. **Phantom evidence.** A campaign can carry the same target text in more than one ad group, and
   FACT keeps the record of retired/paused siblings forever. 22 of the 618 population
   (campaign, text) pairs resolved to more than one `keyword_id` in FACT (44 ids); every colliding
   row read the SUM of the whole group. Campaign `341550011573799` carries `asin="B0CQ896SQT"`
   twice — `357926511307572` (live $0.72, 2,318 lifetime clicks) and `304857473067279` (parked
   $0.24, **zero clicks of its own**). The parked one reverdicted REVIVE on 20 borrowed settled
   clicks and was priced **$0.75 from $0.24 (3.1x)** off its sibling's $0.681 CPC.
2. **Category targets 100% invisible.** `DIM_KEYWORD` stores a category target as its category ID
   (`category="166073011"`); `FACT_AMAZON_ADS` — and every text-keyed memory built downstream of
   it, `FACT_KEYWORD_SEASON_VERDICT` included — stores the **NAME**
   (`category="Kids' Scrapbooking Kits"`). Text never matched, so a real
   **503-click / $370.78 / 0.868x** settled record read as zero evidence, and the target's nine
   season verdicts (4 WIN) were unreachable.

**The fix.** `keyword_id` is the one key both sides agree on — non-NULL on 100% of FACT rows in
the window (all four `source_table`s) and the same id space as `DIM_KEYWORD` — so keying on it
resolves ID <-> NAME by construction.

| CTE | role |
|---|---|
| `fd_raw` | evidence at (campaign_id, keyword_id, targeting, date), joined on the id pair |
| `tgt_name` | the ID <-> NAME resolver: FACT-reported name per (campaign, keyword_id), max-clicks pick, fully tie-broken |
| `pop_txt` / `solo` | (campaign, text) pairs — DIM text **or** resolved FACT name — that map to exactly ONE target |
| `fd_noid` | text fallback, restricted to `solo` and to FACT rows with `keyword_id IS NULL`. **Current stock: 0 rows** — a safety valve, not a live path. Attributing an id-less row to an ambiguous text is the defect being fixed |

The season lookup now resolves through `tgt_name` too (`COALESCE(fact_tgt, keyword_text)`), so a
category target reaches its own season memory. The context-gate join takes the same COALESCE; the
gate holds no asin/category/expanded rows today, so that is a no-op guard. Two new output columns:
**`fact_targeting`** (the FACT-reported name) and **`evidence_join`**
(`KEYWORD_ID` / `TEXT_FALLBACK` / `KEYWORD_ID+TEXT_FALLBACK` / `NONE`).

Implementation note: BigQuery rejects "aggregations of aggregations" once these CTEs are inlined,
so `tgt_name` picks with `ROW_NUMBER` rather than `ARRAY_AGG` and `solo` counts ambiguity with an
analytic `COUNT(*) OVER` rather than `HAVING COUNT(DISTINCT ...)`. Determinism is unchanged —
`targeting` is unique inside `(campaign_id, keyword_id)`, so the tie-break is total.

**Measured effect (2026-08-12, 619 rows, two pulls byte-identical, md5
`a9046ca0a00f866beac28bbf16d0654a`):** REVIVE stays at 29 but is a different 29 — the phantom
`asin="B0CQ896SQT"` row leaves (REVIVE -> INSUFFICIENT, its 20 clicks / $13.63 / 0.909x were never
its own), the category target enters (INSUFFICIENT -> REVIVE on 503c / $370.78 / 0.868x + 4 season
WINs). No surviving REVIVE re-prices. 31 rows changed at least one number; settled-90d evidence
net **+481 clicks / +$355.89 spend**, lifetime settled clicks **-10,453** (borrowed sibling
history removed).

**Left standing on purpose (defect 5, NOT approved for fix):** the 0.8x season relaxation is
neither occurrence-scoped nor recency-bounded. After this fix **6 REVIVE rows sit below 1.0x**,
carrying a settled **-$321.16** on $2,114.99 spend (0.848x blended) — and **none of the six has a
WIN inside the current occurrence (BTS_2026)**. Worst: `15 year old girl gift ideas`, relaxed by a
WIN from 2024-12-29 (**20 months old**) whose most recent verdict is a LOSS. 4 of the 6 carry a
LOSS more recent than the WIN that relaxed them. See the v27.52 report.

### 7.13 v27.52 FIX 1 (2026-08-12) — the season amnesty was permanent, account-wide and unbounded

`V_KEYWORD_GUARD.season_win_prior` was `COUNTIF(verdict = 'WIN')` over the **whole**
`FACT_KEYWORD_SEASON_VERDICT` table, matched on the lowercase keyword **text**: any WIN ever
recorded, any season, any year, back to 2024-09 (452 WIN texts). §7.6(b) is the settle veto's only
escape hatch — "no corroboration **and no season WIN prior**" — so that flag decided whether a
keyword could be condemned at all on unsettled clicks. Three things were wrong with it at once:

1. **It contradicted the ledger's founding doctrine.** §4: a verdict belongs to
   (keyword × season-context occurrence), never to the keyword alone. A VDAY win licensed a BTS
   loss.
2. **It ignored the §4 maturity guard.** §7.6(b) says "any **mature-frame** WIN verdict for the
   text". The code never filtered on `mature_at_start`.
3. **It had no ceiling.** No amount of settled counter-evidence could overcome it.

Measured on the 2026-08-12 standing population (606 enabled targets): **332 carried a WIN prior;
123 were settled-corroborated losers with unsettled clicks and therefore structurally
un-condemnable; 68 of those were catastrophic** (< 0.6x on ≥ 10 settled clicks) — a settled 90d
record of **$5,178.60 spend → $1,852.69 GP = 0.358x, −$3,325.91 already spent**.

**The fix, two bounds, both in `V_KEYWORD_GUARD`:**

- **(a) `settle_amnesty` (NEW column) = `season_win_prior AND NOT catastrophic`.** A < 0.6x record
  on ≥ 10 SETTLED clicks overrides the amnesty entirely. This is the same escape `manual_hold`
  already carries (Cause 3, §7.8): the season amnesty must not outrank Ori's own hand. **Both
  engines now read `settle_amnesty` in the settle veto — never `season_win_prior`.**
  `season_win_prior` stays published as a display/audit fact in both engines.
- **(b) `season_win_prior` is OCCURRENCE-SCOPED.** The `seas` CTE now mirrors
  `V_KEYWORD_CONTEXT_GATE`'s `prior` CTE **verbatim**: same family match
  (`REGEXP_REPLACE(context_label, r'_\d{4}$', '')` against today's occurrence), same
  closed-prior-occurrence test (`v.occurrence_end < cur.occurrence_start`), same `mature_at_start`
  guard, same `family != 'OFF'` exclusion. The WIN amnesty and the LOSS entry block finally read
  the **same memory**. New dependency: `V_SEASON_CONTEXT`.

**Documented consequence of (b):** during an `OFF` run nobody carries a WIN amnesty, so the settle
veto's escape hatch is closed for everyone. That is the gate's own rule ("OFF runs carry no entry
memory", §5.1) and it errs toward condemning losers, not protecting them. Today's occurrence is
`BTS_2026` (`BTS_2026_20260801`), so only mature BTS_2024 / BTS_2025 WINs count.

**Impact 2026-08-12:** WIN priors **332 → 126**; structurally un-condemnable **123 → 22**;
**101 rows released** (68 by the catastrophic override, 33 by occurrence-scoping); **0 rows newly
protected**. Released settled-90d record: **$17,652.63 spend → $12,671.95 GP = 0.718x, −$4,980.68**.
Still amnestied: 22 rows, $8,072.04 → $6,162.64 = 0.763x.

**Verification (no prior guard moved):** the pre-fix view text and the post-fix view were run in
ONE query at one instant and compared column-by-column on all 39 shared columns. 206 rows differ;
**excluding `season_win_prior`, 0 rows differ in either direction.** Every other guard signal
(`settle_ok`, `settled_*`, `settled_winner`, `corroborated_loser`, `catastrophic`, `record_loser`,
`manual_recent7`, `manual_hold`, `pace_flag`, `pace_watch`, `pace_target_bid`) is byte-identical.

### 7.14 v27.52 FIX 3 (2026-08-12) — the record cap was wired to the wrong entry actions

v27.48 §7.7 capped probe entry bids by the keyword's own record (scope-lifetime ≥ 30 clicks →
entry ≤ lifetime conv CPC × 1.2; gate `ENTRY_BLOCK` → entry ≤ LY conv CPC × 0.8) and blocked the
$1 entry outright on a scope-lifetime LOSER (≥ 30 clicks < 0.6x). **The cap logic works — it bound
correctly at $0.41 on a `PROBE_START` row.** It was simply attached to the entry actions that issue
the fewest entries. Measured 2026-08-12:

- **`PROBE_ADJUST` was uncapped and issues most of the entries: 5 of 5 live rows landed on the flat
  $1.00**, 3 above their record cap, and 2 were record losers (43c at 0.00x, 33c at 0.00x).
- **`ACTIVATE_REVIVE` was explicitly exempt** (§7.7: "its bid is part-1-calibrated"). That
  calibration reads the **settled-90d CPC only** — it cannot see a scope-lifetime record saying the
  keyword has never cleared that price, which is the entry-price defect itself.

**The fix:** the same cap is now wired to `PROBE_ADJUST` (V_KEYWORD_LIFT) and `ACTIVATE_REVIVE`
(both engines), at every ladder that already carried it — the record-loser HOLD, the "cap lands on
the current bid → no real move" HOLD, the `ENTRY_BLOCK`/PROBING composed allowance clamp, the
standalone cap, and the matching reason strings.

Two deliberate boundaries:
- **`PROBE_ADJUST` is capped/blocked only when it RAISES.** A `PROBE_ADJUST` that LOWERS a bid
  commits no new spend (the v27.37 #3a principle) and must never be turned into a HOLD. The
  effective entry bid it is measured on is the v27.37 #3b anchored `probe_bid` where that applies,
  else the ladder's own suggestion.
- **`ACTIVATE_REVIVE` gets the PRICE cap but NOT the record-LOSER HOLD.** The reverdict (≥ 10
  settled clicks at ≥ 1.0x, or ≥ 0.8x with a season WIN) owns the decision to revive; this cap only
  prices it. The real-move test now reads the CAPPED bid, so a capped-to-current revival is not
  emitted as an `ACTIVATE_REVIVE` that moves nothing (v27.29).

### 7.15 v27.53 FIX (2026-08-12) — the reverdict's season relaxation is occurrence-scoped and age-bounded

**This was defect 5 of the iteration-6 audit — the last thing standing between Ori and acting on
the Revivals panel.** v27.52 FIX 1 bounded the season amnesty in `V_KEYWORD_GUARD`. It did not
touch `V_PARK_REVERDICT`, which carries its **own copy** of the same lookup, with the same defect,
feeding a decision that is arguably sharper: the guard's amnesty only *delays* a condemnation,
whereas the reverdict's `≥ 0.8 + season WIN` arm is the **only way a keyword whose SETTLED record
loses money gets its bid put back up**.

The licence was `COUNTIF(verdict = 'WIN')` over the **whole** `FACT_KEYWORD_SEASON_VERDICT` table,
matched on lowercase text: any WIN, any season, any year, mature or not, forever.

**Measured on the 2026-08-12 population:** 6 of the 29 `REVIVE` rows were sub-1.0 rows riding the
relaxation — 7,415 settled clicks, **$2,114.99 settled spend → $1,793.83 settled GP = −$321.16**.

| keyword | settled 90d | what licensed the revival |
|---|---|---|
| `spa kit for girls ages 12-14` | 267c 0.821x −$35.53 | a BTS_2025 WIN that **fails the §4 maturity guard** (first click 2025-07-19, 13d before that occurrence began) |
| `15 year old girl gift ideas` | 188c 0.827x −$8.65 | a **XMAS_PEAK_2024** WIN — occurrence ended 2024-12-28, **twenty months** before today's BTS peak |
| `girls journal kit` | 1,474c 0.835x −$92.46 | 7 WINs, **none of them BTS** (OFF / PRIME / EASTER / VDAY / XMAS) |
| `category="Kids' Scrapbooking Kits"` | 503c 0.868x −$49.02 | 4 WINs, **none BTS** (GRAD / MDAY / EASTER + an immature XMAS_PEAK_2025) |
| `gifts for tween girls` | 4,929c 0.853x −$135.19 | **BTS_2025, 1,017 clicks, +$62.57, mature** — a real licence |
| `gifts for teen girls` | 54c 0.978x −$0.31 | **BTS_2025, 51 clicks, +$3.21, mature** — a real licence |

**The fix (all of it inside the `seas` CTE of `V_PARK_REVERDICT`):** the WIN must now come from a
**closed prior occurrence of the SAME context family as today's occurrence**, must be
`mature_at_start`, and carries **no memory during an `OFF` run** — V_KEYWORD_CONTEXT_GATE's `prior`
selection discipline verbatim, exactly as v27.52 FIX 1(b) applied it to the guard — **plus the age
bound this defect specifically calls for**: `k.win_max_age_days = 400`, i.e. the prior occurrence
must have **ended within one cycle** of the current occurrence's start (BTS_2025 ended 321d before
BTS_2026 began; BTS_2024, 686d). The WIN amnesty, the LOSS entry block and the guard now read the
**same memory**.

FIX 1(a)'s catastrophic override needs **no mirror here**: this bar's season floor is 0.80, already
above the 0.60 catastrophic line, so a catastrophic row can never be revived by construction.

**New columns** (the snapshot is `SELECT *`, so no DDL change): `season_relax_applied` — TRUE
exactly when a row is `REVIVE` **only** because of the relaxation, i.e. its own settled record
loses money (Ori's read-this-first flag on the panel); `win_prior_end` — dates the licence;
`occurrence_family`; and `n_win_any` / `win_labels_any` — the OLD unscoped count, **display/audit
only, nothing may branch on them** (the panel can still say "11 wins overall, 1 of them in this
season"). `n_win` / `win_labels` now carry the **scoped** memory and are what the bar reads.

**Impact 2026-08-12:** `REVIVE` **29 → 25**. Four rows move to `CONFIRM_PARK` on 2,432 settled
clicks, **$1,178.49 spend → $992.83 GP (−$185.66)**. Two sub-1.0 rows **keep** their revival on a
real mature BTS_2025 WIN. **0 rows newly revived. No `revive_bid` changed** — the bid formula never
read the season memory.

The 400-day bound removes **0 additional rows today**: BTS_2024 ran 2024-09-05..09-14, inside the
first ten days of all ads history, so it carries **zero mature verdicts**. It is installed as the
structural guarantee for the next cycle, not as today's saving — say so rather than claiming it.

**Verification (keyed parity, old view text vs new, one query at one instant, 619 rows, 0 added /
0 dropped):** exactly six columns move — `n_win` + `win_labels` (154 rows, the memory itself),
`passes_bar` (6), `reverdict` (4), `reverdict_reason` (7), `stop_released` (2). The other **53
columns are byte-identical**. Of the 6 `passes_bar` moves, **2 are on LIVE rows where `passes_bar`
is inert** (`reverdict` is NULL for LIVE); **both `stop_released` moves are on rows with
`entry_state != 'STOP'`, where it is inert** (the 4 rows that do carry `entry_state = 'STOP'` were
unaffected). So: **4 verdicts moved and nothing else in the view did.** Deterministic: two full
pulls byte-identical, md5 `3e20a72df412863d36d31c969a3daa81` on 619 rows.

`FACT_PARK_REVERDICT` was refreshed via `CALL SP_SNAPSHOT_PARK_REVERDICT()` immediately after the
deploy — **the engines read the snapshot, not the view**, so leaving it stale would have left
`V_OOB_KEYWORD` / `V_KEYWORD_LIFT` able to `ACTIVATE_REVIVE` the four keywords this fix just
condemned. The Weekly Run Revivals panel reads the view live (cube, 15-min TTL) and needs no
rebuild.

---

## §7.16 v27.53 — the settle veto becomes a real deferral, the cut gate learns its window, and the condemnation grows a second leg (2026-08-12, Ori approved "do all engine work")

Five audit items landed together in `V_KEYWORD_GUARD` / `V_KEYWORD_LIFT` / `V_OOB_KEYWORD`. Three of
them (2, 3, 4) change how OFTEN the engines condemn, so they were measured **together**, not one at
a time — the combined table is at the end of this section.

### Item 2 — settle days split by channel, and the deferral now expires

Two things were wrong with the v27.48 settle veto, and only the first was known.

**The wait was priced for the wrong channel.** Measured fresh-data understatement on the JUDGED
window: SP −3% to −6%, SB −17.5%. On SP the seven-day wait bought almost nothing and blocked correct
cuts — 14 rows, $344.10 per 7 days of run-rate; 4 of the 6 SP holds were WRONG on the settled 90-day
record ($120.58 of $155.76 = 77% of blocked SP spend). The worst row, `gifts for 12 year old girl`,
was held at 47 clicks / 0.86× while its settled 66-click record read 0.700× — arithmetically unable
to reach 1.0, so waiting could never change the verdict. **SP settle_days 7 → 3. SB stays 14.**

**The veto was permanent, not a deferral.** `settle_ok = last_click <= anchor − settle_days` is
unsatisfiable for a keyword that clicks every day, and 193 of 344 unsettled rows clicked on the
anchor date itself. The reason string promised a re-judge on `settle_due`, a date that arrives only
if the keyword goes quiet. Two fixes:

- the SP corroboration frame moved from `[wm−96, wm−7]` to `[wm−92, wm−3]`, so it now reaches the
  recent past — a loss that *starts* inside the last week can accrue settled evidence in three days
  instead of never (before, such rows had `settled_clk90 = 0` and could not corroborate at all);
- new `settle_deferral_expired`: once a keyword has been clicking for **2 × settle_days**, a full
  settle_days of its clicks is settled and readable, the wait has been served, and the row is judged
  on what it has. Hard ceiling on any single deferral: **6 days SP, 28 days SB.** The reason string
  now publishes that real date.

Standing population (606 targets, 2026-08-12): unsettled SP 191 → 146; rows structurally unable to
be judged (unsettled AND uncorroborated AND un-expired) **195 → 28**.

### Item 3 — the cut gate is scaled to the window it judges (`cut_gate`)

The condemnation branches fired at a bar chosen by *tier and season* (13 low-tier/peak, 30 otherwise)
while the window they measure is chosen *independently* (3 days low-tier, else
`V_PEAK_WINDOW_RULE.w_days`). Nothing wired the two together, so moving the window silently moved how
often the engine acts. The backtest (n = 11,019) is unambiguous: hold the gate constant and every
apparent 7-day advantage disappears — zero peaks favour 7 days, and the dollars flip to the short
window by +$6,876.

`cut_gate = max(4, ceil(13 × eff_days / 7))`, `eff_days = 3` for low-budget non-defense rows else
`w_days` → **6 at 3 days, 13 at 7 days**. One definition in `base`, shared by the action, bid and
reason ladders (the three ladders drifting apart is this file's own repeat failure mode — v27.30
through v27.32). Every peak currently resolves to 3 days, so this binds today.

### Item 4 — `LONG_LEG_HOLD`: both windows must agree before a condemnation

`V_OOB_BUDGET_PHASE` has always required a short **and** a long settled window to agree before it
cuts a budget, and that requirement does real work. `V_KEYWORD_LIFT`'s `PARK` and
`CUT_TO_BREAKEVEN` condemned on the short window alone — the least complete data the engine holds.
The same rule now applies: the condemnation is vetoed when the **8-28d window** (≥ 4 clicks; settled
by construction, it ends at `wm−7`) reads ≥ 1.0×.

**Measured and rejected:** a first draft also let the guard's settled-90d record veto. It over-braked
— it held three cuts that the *recent settled window itself* condemned (`teen girl essentials kit`
369c at 0.83×, `journal for girls` 188c at 0.90×, `journal kit for girls ages 8-12` 24c at 0.48×). A
ninety-day-old record is not a rebuttal when the recent settled window agrees with the short one.
Both windows must **agree** — that is the whole rule, and it is exactly PHASE's.

Deliberately narrower than PHASE in one place: PHASE's `COALESCE(x, 0)` treats *no data* as a licence
to cut. Here no long-window data simply fails to contradict, so a genuinely new keyword still
condemns on its short window — the settle veto is what guards that case, and stacking both would
freeze new keywords entirely. `ENTRY_BLOCK` rows keep season-gate precedence and are exempt.

### Item 7 — the $1.00 wake grows its second half (`WAKE_STEP`)

The `$1.00` ACTIVATE entry is a deliberate on-ramp — "wake it, then price it" — and the wake half
works. The step-down was never built: of 24 keywords woken since 2026-06-01, only 11 were later
repriced (average 2.7 days) and 13 are still sitting at the flat entry price. Nothing scheduled the
repricing; it happened only when some branch of the ladder happened to catch the row.

`wake_due` fires at **10 clicks since the wake, or 7 days, whichever comes first**. `wake_step_bid`
prices the keyword from its own numbers: its GP-per-click since the wake if it earned; else the price
it has historically cleared at (lifetime conv CPC, capped $0.60); else $0.25 if the wake bought no
clicks at all. Never a raise, floor $0.20. Both engines emit it — **4 of the 5 currently-due rows sit
in OOB-owned campaigns**, where `V_KEYWORD_LIFT` can only ever say `DEFER_OOB`, so the step had to
live in `V_OOB_KEYWORD` as well.

### Item 8 — the small ones

| | fix | measured today |
|---|---|---|
| 8a | `pace_kw` divided an **instance** numerator by a **scope** denominator; keyword_ids do not survive campaign recreations, so pace was understated | all 3 live `PACE_RAISE` rows were already at 66-226% of LY pace. `PACE_RAISE` 3 → 0. `pace_kw_instance` keeps the old form for audit only |
| 8b | the band-ceiling join spoke the wrong vocabulary — `DIM_KEYWORD` says AUTOMATIC / ASIN / ASIN EXPANDED, the profile says AUTO / PRODUCT | rows with no ceiling **234 of 606 (38.6%) → 30**; profile `OTHER` cell is now the fallback |
| 8c | a `CONFIRM_PARK` row could resurface as `WINNER_FOUND` through **two** doors — the outer 4-click winner shield and the inner `probe_done` verdict | `teenager girl gift ideas`, a settled-verified retirement, was emitting `WINNER_FOUND` off **one** click at 14.27×. Both doors closed |
| 8d | the manual hold only ever read `INCREASE_BID` / `REDUCE_BID`, so Ori's manual **budget** changes got no hold at all | new campaign-grain `manual_budget_hold` (7d). 9 MANUAL `BUDGET_CHANGE` rows, most recent 2026-08-11 — it binds |
| 8e | **NOT FIXED HERE.** Park detection (`new_bid <= 0.26` with no direction test) lives in `V_PARK_REVERDICT`, which another agent owns this pass | see "what did not land" below |
| 8f | `MANUAL_HOLD` sat above the dark brakes and swallowed them | `AUTO_BRAKE` (LIFT) and `DARK_BRAKE` (OOB) now outrank it — dark is never a hold. Binds nothing today (0 collisions); preventive |

### The combined effect on condemnation — items 2, 3 and 4 together

644-row standing population, 2026-08-12, `in_peak = TRUE`, `w_days = 3`. Stage B is the old engines
reading the new guard, which isolates the guard-side items.

| stage | eligible to condemn | eligible $ (window) | **emitted PARK/CUT** | **emitted $** | emitted clicks | SETTLE_HOLD | LONG_LEG_HOLD |
|---|---|---|---|---|---|---|---|
| **A** v27.52 (before) | 23 | $318.84 | **5** | **$59.77** | 71 | 8 | 0 |
| **B** + items 2 / 8a / 8b | 22 | $318.84 | **5** | **$59.77** | 71 | 7 | 0 |
| **C** + items 3 / 4 / 7 / 8c / 8f | 28 | $345.81 | **8** | **$145.10** | 162 | 2 | 7 ($39.85) |

**Say it plainly: this is a real increase in cutting.** Emitted condemnations go 5 → 8 rows (+60%)
and $59.77 → $145.10 of window spend (+143%). Items 2 and 3 alone would have emitted **15 rows /
~$185** — item 4 is what holds it to 8, catching 7 rows worth $39.85 that the long settled window
says are earning. Shipping 3 without 4 would have tripled cutting on the least complete data the
engine uses. **Items 3 and 4 must ship together, and did.**

The single biggest new cut is `gifts for 12 year old girl` — $56.94 / 47 clicks, the exact row the
audit named as arithmetically unable to clear 1.0. The single removed cut is
`birthday gift for 20 year old girl` (was `PARK`, now `LONG_LEG_HOLD`: 8-28d 90 clicks at 1.17×).

`V_OOB_KEYWORD`, 281 rows: `PARK` 0 → 1 (one `SETTLE_HOLD` released), `SETTLE_HOLD` 1 → 0,
`WAKE_STEP` 0 → 4, `DARK_BRAKE` 27 → 27, rows carrying a bid 40 → 45.

### Every prior guard, recounted

Nothing was zeroed by accident. `DEFER_OOB` 278 → 278 · winner shield 9 → 8 (the one `CONFIRM_PARK`
removal, item 8c) · `REVIVE_SETTLE_HOLD` 2 → 2 · `MANUAL_HOLD` 1 → 1 · `ACTIVATE_REVIVE` 7 → 7 ·
`DEFENSE` 28 → 28 · `BLOCK_CUT` 11 → 12 · `PARK_WAIT` 1 → 1 · `APPLIED_HOLD` 0 → 0 (none pending
today) · `AUTO_BRAKE` 0 → 0 (no dark rows in LIFT today; `DARK_BRAKE` 27 → 27 in OOB).
`SETTLE_HOLD` 8 → 2 and `PACE_RAISE` 3 → 0 are the **intended** item-2 and item-8a corrections.

### Deploy order and the snapshot

`V_KEYWORD_GUARD` → `CALL SP_SNAPSHOT_KEYWORD_GUARD()` → `V_KEYWORD_LIFT` → `V_OOB_KEYWORD`. The
snapshot **must** be re-run before either engine can compile against `settle_deferral_expired`,
`wake_due`, `wake_step_bid`, `first_click_60d` or `manual_budget_hold` — the engines read
`FACT_KEYWORD_GUARD`, never the view (planner-ceiling doctrine, §7.6).

### What did NOT land, and why

- **Item 8e (park detection has no direction test).** `V_PARK_REVERDICT`'s `park` CTE selects any
  applied bid change with `new_bid <= 0.26` and no `new_bid < old_bid` test, so a *raise* into the
  park band is recorded as a park (3 rows). The sibling `raise_ev` CTE already has the direction test
  the `park` CTE is missing. That file is owned by the item-1 agent this pass and was not touched, to
  avoid two writers on one file. **One line, and it is still open.**
- **`manual_budget_hold` is published but not yet consumed.** The signal exists on every guard row;
  wiring it into the budget ladders (`V_OOB_BUDGET_PHASE` owns the budget authority, not these three
  files) is the follow-up.
- **Known pre-existing divergence, unchanged:** `V_KEYWORD_GUARD` and `V_OOB_KEYWORD` still run the
  pre-v27.49 season predicate and read `in_peak = FALSE` today while `V_KEYWORD_LIFT` reads TRUE
  (already recorded against `V_SEASON_PEAK_GATE`). It selects the OFF band ceiling instead of the
  PEAK one for the pace target. Out of scope here; it should be closed next.

### A determinism failure the check actually caught (v27.53)

The mandated "pull twice, byte-identical" gate failed on `V_KEYWORD_GUARD` — **one row, one column**:
`gift for tween girls 11-14` returned `life_conv_cpc` 0.383 on one pull and 0.382 on the next.

Not a logic bug, and not introduced by v27.53. `FLOAT64` addition is not associative, BigQuery
reshuffles the aggregation between runs, and a `SUM` over the **full FACT history** (1.18M rows) can
therefore move in its last bits — this one happened to sit on a 3-decimal rounding boundary. It is
the same family as the `EXCEPT DISTINCT` float-parity noise already on record.

It was fixed rather than waived because **this column prices bids**: the OOB record-priced entry cap
and the item-7 wake step-down both read `life_conv_cpc`. A coin-flip in it is not acceptable even at
a tenth of a cent. The lifetime and LY conv-CPC / ROAS ratios now sum in `NUMERIC` (fixed-point —
exact and order-independent) and cast back to `FLOAT64`, so the published schema is unchanged.
Verified **4 consecutive byte-identical pulls**, md5 `f3989b44d03500373c4eab8de9b6fab3`, 606 rows.
The short instance windows are deliberately left as `FLOAT64` — they aggregate at most 104 days per
keyword and have never flipped.

**Also worth recording, because it will happen again:** an earlier `V_OOB_KEYWORD` determinism run
mismatched, and the cause was not the SQL — `FACT_PARK_REVERDICT`, `FACT_KEYWORD_SEASON_VERDICT` and
`FACT_KEYWORD_GUARD` were all re-snapshotted by a parallel deploy *between* the two pulls. A
determinism check on these engines is only meaningful with an upstream fence: read
`__TABLES__.last_modified_time` for the snapshot tables before and after, and only trust the
comparison if the fence is unchanged. Re-run fenced, `V_OOB_KEYWORD` was byte-identical.

## §7.12 Sibling evidence (v27.68, Task 2.4 — Ori 2026-08-16)

Ori: "you can check the general performance of the product keyword in other campaign and decide if
it worth to lift it again." A parked keyword generates zero data — its own record can only re-read
old clicks. The SAME TERM in the family's OTHER campaigns is our own conversions on our own
listing: the one signal that moves without our clicks, and PROMOTE_TO_EXACT's inference run in the
other direction. Two arms, evaluated ONLY where the own-record verdict would say CONFIRM_PARK
(own-record arms rank first, untouched):

- **SIBLING_REVIVE** — a sibling clears THE revival bar (≥1.0× at ≥10 settled clicks; the one bar,
  reused) AND this instance would serve the term BETTER or ADDITIONALLY: parked EXACT vs a
  non-EXACT sibling (exact serves what broad finds, cheaper), or the sibling is budget-capped.
  Revive bid prices off the SIBLING's CPC — min(pre-park bid, 1.1 × sibling settled CPC), clamped
  [0.31, 1.50] — because the own CPC belongs to the record that failed. Tested losers (≥15c, 0
  orders — the DEAD class) need the DOUBLED sibling bar (≥20 settled sibling clicks): a keyhole,
  not a hinge. Panel: hand-queue only (read-this-first class, like season-relax); engines do NOT
  auto-activate it (SIBLING_REVIVE ≠ REVIVE in every engine predicate, deliberately).
- **REDUNDANT** — a sibling clears the bar but already serves the term (same match, uncapped):
  stay parked, reason names the sibling — reviving would double-bid against ourselves (the
  intent-grid legacy double-bid class). Engines treat REDUNDANT exactly as CONFIRM_PARK
  (both engines' confirm_park flags and LIFT's 8c resurface shield read the IN-list).

Evidence surface: V_TERM_FAMILY_EVIDENCE — (family, term, campaign) contribution grain with family
rollup windows, from FACT_KEYWORD_GUARD + FACT_PANEL_OWNERSHIP only (snapshot tables; ≤1d stale,
harmless at 90d grain). First live run 2026-08-16: 1 SIBLING_REVIVE ("diy journal kit for girls
8-14" EXACT, own 496c @ 0.97×, sibling broad 61c @ 2.47×) + 5 REDUNDANT — including the SAME term's
broad instance staying parked because an exact sibling serves it: the rule cuts both directions on
one keyword. SQP market share remains the fallback eye for terms with zero own traffic anywhere
(fully negated families) — engine-finalization plan Task 4.4.

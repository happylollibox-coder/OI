# PEAK WINDOW RULE — spec of record

**Status:** LIVE 2026-08-12, tag **v27.50**. `DE_PEAK_WINDOW_OVERRIDE` (12 rows) +
`V_PEAK_WINDOW_RULE` (1 row) are deployed and `V_KEYWORD_LIFT` reads both. Backup of the engine
file taken before the wiring pass: `scripts/bigquery/views/V_KEYWORD_LIFT.sql.bak.v27.50.1258`.

---

## 1. The rule (Ori, 2026-08-12)

> "The algorithm should switch from 7 days to 3 days [in peak] UNLESS it has examined last year's
> same peak and proved that 7 days is better than 3."

**The burden of proof sits on the SLOWER window.**

| Situation | Judged window `w_days` |
|---|---|
| Off peak | **7** — unchanged, and NOT overridable |
| In peak, no measurement row | **3** |
| In peak, measured but 7 NOT proven | **3** |
| In peak, measured and 7 **proven** better | **7** (or whatever the row says) |

No evidence, thin evidence, ambiguous evidence and **conflicting** evidence all resolve to **3**.
This is deliberately not "when in doubt use 7" — that inverts the instruction.

An override is granted only where **the same occurrence type in a prior year** demonstrably
produced better decisions at 7. Not a similar season, not the account as a whole — the same
occurrence.

---

## 2. Objects

| Object | Kind | Role |
|---|---|---|
| `V_SEASON_PEAK_GATE` | view (0..n rows) | **THE gate predicate, written once.** One row per `DIM_US_HOLIDAYS` occurrence active today; zero rows = off peak. |
| `DE_PEAK_WINDOW_OVERRIDE` | data-entry table | The proof. One active row per occurrence type: window, verdict, occurrences tested, n, the deciding metric, robustness count, measurement date, re-measure date, plain-language comment. |
| `V_PEAK_WINDOW_RULE` | view (exactly 1 row) | Resolves *today* → `in_peak`, `occurrence_type`, `w_days`, `w_days_source`, `w_days_reason`, plus the whole evidence record. |
| `V_KEYWORD_LIFT` | engine view | `season` CTE counts `V_SEASON_PEAK_GATE`; `cap` CTE reads `w_days` from `V_PEAK_WINDOW_RULE`. |

**The evidence lives in DATA, never in a CASE expression.** Next year's re-measurement updates a
row; the engine SQL does not change. Anyone can read `V_PEAK_WINDOW_RULE.w_days_reason` and see
why the window is what it is.

### Wiring (the entire engine change, `V_KEYWORD_LIFT` ~line 153)

```sql
-- BEFORE (v27.49)
WITH season AS ( SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start
                   AND COALESCE(cooldown_end, DATE_ADD(holiday_date, INTERVAL 3 DAY))) > 0 AS in_peak
                 FROM DIM_US_HOLIDAYS
                 WHERE category IN ('gift_season','prime_event','back_to_school','seasonal') ),
cap AS (SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_cap, IF(in_peak, 3, 7) AS w_days FROM season),

-- AFTER (v27.50)
WITH season AS ( SELECT COUNT(*) > 0 AS in_peak FROM V_SEASON_PEAK_GATE ),
cap    AS ( SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_cap, w_days FROM V_PEAK_WINDOW_RULE ),
```

That is the **whole** diff against `V_KEYWORD_LIFT.sql.bak.v27.50.1258` — two CTEs, nothing else.
The v27.49 gate predicate moved **verbatim** into `V_SEASON_PEAK_GATE` (parity verified over 1,827
days, 2024-01-01 → 2028-12-31: **0 divergent days**). `in_peak` is unchanged, `low_cap` is
unchanged, the 20/40% exploration allowance, probe slots, the budget floor, the click bars and the
CPC band are all unchanged. Only `w_days` acquired a data source.

**Why the gate is a separate view from the rule.** `V_KEYWORD_LIFT` expands its `season` CTE about
thirty times — every `(SELECT IF(in_peak, …) FROM season)` site — and each reference re-plans the
body. Pointing those thirty sites at the full rule view made BigQuery refuse to plan the engine at
all (*"Not enough resources for query planning — too many subqueries"*). The gate view is a single
filtered scan of a ~40-row table, exactly what the v27.49 inline expression cost. **Keep it
trivial: no joins, aggregates or subqueries in `V_SEASON_PEAK_GATE`, and never point `season` at
`V_PEAK_WINDOW_RULE`.**

An earlier cut of `V_PEAK_WINDOW_RULE` resolved the override with a `LEFT JOIN` + `ARRAY_AGG`.
That shape stopped BigQuery folding `in_peak`/`w_days` to constants inside the `FACT_AMAZON_ADS`
window scans and the engine went from **25.6M slot-ms / 45s to 753M slot-ms / 717s**. Uncorrelated
scalar subqueries fold; joins do not — **do not reintroduce a join into the rule view**. After both
fixes the engine runs 24s / 11.3M slot-ms and 26s / 9.7M slot-ms on two consecutive pulls.

### Occurrence type resolution

`V_PEAK_WINDOW_RULE` mirrors `V_SEASON_CONTEXT` so the ledger and the engine agree about which
occurrence today belongs to:

- candidate set = `DIM_US_HOLIDAYS` in the **engine's** in-peak categories
  (`gift_season`, `prime_event`, `back_to_school`, `seasonal`), window
  `boost_start .. COALESCE(cooldown_end, holiday_date + 3 days)`;
- **precedence:** earliest `boost_start` owns the date (tie-break earlier `holiday_date`, then
  name) — so Black Friday, Cyber Monday and Halloween are absorbed into Christmas, and Father's
  Day is absorbed into Graduation;
- **XMAS split:** Christmas dates before Nov 15 of the holiday year → `XMAS_EARLY`, else
  `XMAS_PEAK` (the same boundary the ledger uses; the ~Nov 15 flip is real).

Safety: `w_days` is clamped to `[1, 28]`. A typo in the table cannot make the engine judge on a
zero-day or year-long window. The view is guaranteed to return exactly one row (both source CTEs
are aggregates without `GROUP BY`), which matters because the engine `CROSS JOIN`s it.

### Resolved calendar, 2026-08-01 → 2027-12-31

| Window | Occurrence types | Days |
|---|---|---|
| **7 days** | XMAS_EARLY, XMAS_PEAK, EASTER, and all OFF-peak days | 308 |
| **3 days** | BTS, VDAY, MDAY, GRAD, FDAY, PRIME | 210 |

---

## 3. The verdict table (measured 2026-08-12)

| Occurrence type | `w_days` | Verdict | Prior occurrences | 7 granted in |
|---|---|---|---|---|
| **XMAS_PEAK** | **7** | PROVEN_7 | 2024 + 2025 | 9/10 specs |
| **EASTER** | **7** | PROVEN_7 | 2025 + 2026 | 10/10 specs |
| **XMAS_EARLY** | **7** | PROVEN_7 | 2024 + 2025 | 8/10 specs |
| BTS | 3 | NOT_PROVEN | 2025 only (2024 is a 10-day stub) | 1/10 |
| VDAY | 3 | NOT_PROVEN | 2025 + 2026 | 2/10 |
| MDAY | 3 | NOT_PROVEN | 2025 + 2026 | 3/10 |
| GRAD | 3 | **CONFLICTING** | 2025 + 2026 | 0/10 |
| PRIME | 3 | NOT_PROVEN (window > occurrence) | 2025 + 2026 | 0/10 |
| FDAY | 3 | NO_EVIDENCE | 2026 only (4 days) | 0/10 |
| HALLOWEEN / BF / CM | 3 | NO_EVIDENCE (inert) | none — absorbed by precedence | 0/10 |

Method, in one paragraph: 17 closed prior peak occurrences (2024-09-05 → 2026-06-29), 34,688 SP
decisions over 524 occurrence-days and $234,461 of in-window spend. Each historical keyword-day was
deflated to what was **visible that morning** using the measured `V_ADS_SETTLE_CURVE` accrual,
integer counts thinned by seeded stochastic rounding; the engine's own cut tree (class gates, wave
veto, `PARK`, `CUT_TO_BREAKEVEN`) was simulated at both windows and scored against **settled**
forward-7d GP-ROAS at ≥20 forward clicks. The primary dollar metric is **skill** — edge over a
random policy spending the identical cut-mass — so mean reversion is controlled. Holm-Bonferroni
within family; clustered bootstrap by keyword (2,000 reps, seed 20260812). Defense excluded, launch
families excluded, GP-ROAS = gross profit / ad spend with tier COGS charged.

`GRAD` is the instructive row: accuracy significantly favours 7 (p_holm = 0.011), dollars favour 3,
and reaction lag favours 3 decisively (p_holm = 0.006). Conflicting evidence is ambiguous evidence,
and ambiguous means **3**.

Full per-occurrence numbers live in the `evidence_metric` column of each row — that is the
authority, not this table.

---

## 3a. What it does — measured, not argued

### Today (2026-08-12), the live season is Back to School

`V_PEAK_WINDOW_RULE` returns `in_peak = TRUE`, `occurrence_type = BTS`, **`w_days = 3`**,
`w_days_source = PEAK_DEFAULT_NOT_PROVEN`.

> peak (BTS) — 3-day judged window: measured 2026-08-12 — verdict NOT_PROVEN, 7 granted in 1/10
> specifications, so the 3-day default stands

BTS runs 3 **because the burden of proof was not discharged**, not because 3 won. It has one usable
prior occurrence (BTS_2024 is a 10-day stub — the ads feed starts mid-window), and thin evidence
resolves to 3.

**Before/after action diff on the live engine: ZERO.** 644 rows / 108 campaigns, byte-identical
output before and after the deploy (md5 `5f87b9be917fa097793895937601ced7` on a 21-column pull, and
again on the determinism re-pull). That is the expected result: the old hardcode gave 3 in peak, and
BTS resolves to 3. **No row changed action, bid, class, role or budget today.**

### What it does when an override IS in force

Because today's diff is empty, the behaviour change was measured with a temporary shadow of the
engine forced to `w_days = 7` (in-peak, everything else identical), diffed against the live 3-day
output over the same 644 rows. This is the mechanism that switches on for `XMAS_EARLY` on
**2026-10-01**, `XMAS_PEAK` on **2026-11-15**, and `EASTER` on **2027-02-08**.

| Measure | 3-day (live) | 7-day (override) |
|---|---|---|
| **CUT-family** actions emitted | **6** | **5** |
| **RAISE-family** actions emitted | **36** | **41** |
| Rows whose class differs | 46 of 644 | |
| ↳ **3-day harsher** (LOSER@3 → WINNER/MARGINAL@7, MARGINAL@3 → WINNER@7) | **28** | |
| ↳ 7-day harsher (the reverse error) | **6** | |
| Rows whose action differs | 16 | |

Per channel in the `w_days`-governed tier (budget > $30, not defense, n = 146): SP 6 harsher-at-3d
vs 4 harsher-at-7d; **SB 21 vs 2**. SB carries most of the exposure — its sales accrue to D+14, so a
3-day SB window is the least-complete number the engine holds (~17% ROAS understatement vs ~6% for
SP).

**Plainly: the rule does not make the engine cut more during peak. It makes it cut slightly less,
and only in Q4 and at Easter.** Where a 7-override is granted the engine emits one fewer CUT and
five more RAISE actions on this population, and the class asymmetry runs 28:6 against the short
window — i.e. the 3-day read condemns keywords that a 7-day read calls winners about 4.7× more often
than the reverse. Everywhere else (BTS, VDAY, MDAY, GRAD, FDAY, PRIME, and all off-peak days) the
engine behaves exactly as it did under v27.49.

The 16 changed actions are all of this shape — `KEEP_TAIL → RAISE_TO_TARGET`,
`AUTO_TRIM → AUTO_RAISE`, `HOLD → WINNER_FOUND` — plus two in the opposite direction
(`AUTO_RAISE → HOLD`, `PROBE_ADJUST → SETTLE_HOLD`). The single largest is
`ME-SP/AUTO (Purple) / complements`: `AUTO_TRIM` at 33 clicks / 0.62 GP-ROAS over 3 days becomes
`AUTO_RAISE` at 57 clicks / 1.89 over 7.

**Caveat, stated:** this shadow runs the 7-day window over *today's Back-to-School traffic*, not
over October's. It demonstrates the mechanism and its direction, it is not a forecast of the Q4
dollar effect.

---

## 4. How to re-measure (do this every year)

1. Wait until the next occurrence of the type is **closed and settled** —
   `V_SEASON_CONTEXT.occurrence_closed = TRUE` (every day ≤ anchor − 7). The
   `remeasure_after` column on each row already carries that date, and
   `V_PEAK_WINDOW_RULE.remeasure_due` flips TRUE once it passes.
2. Re-run the 3-vs-7 study over **all** prior occurrences of that type, not just the new one.
3. `UPDATE` the existing row to `is_active = FALSE`, then `INSERT` the new verdict row.
   **Never edit a row in place** — the history is the point of the table.
4. The burden of proof does not reset in favour of the incumbent. A type currently on 7 must
   **re-prove** 7 against the enlarged evidence base, or it drops back to 3.

Re-measure dates already loaded: BTS 2026-10-01 · XMAS_EARLY 2026-11-28 · XMAS_PEAK 2027-01-11 ·
VDAY 2027-03-03 · EASTER 2027-04-14 · MDAY 2027-05-26 · GRAD 2027-07-04 · FDAY 2027-07-07 ·
PRIME 2027-08-01.

---

## 5. The confound, recorded on purpose

Every one of the three 7-grants traces to the same mechanism, and it is **not** data quality.

The engine's cut branch requires `clk_w >= 13`. Over 3 days that is 4.3 clicks/day; over 7 days it
is 1.9. Flipping `w_days` to 3 without touching the gate does not make the engine judge on worse
data — **it makes the engine judge less often**. Two controls remove the 7-advantage entirely:

- **matched population** (only decisions where both windows clear 13 clicks, n = 11,019): zero
  types grant 7; dollar-skill flips to 3-day by **+$6,876** pooled, significantly for EASTER
  (+$2,182) and XMAS_PEAK (+$4,711);
- **window-scaled gate** (K₃ = 6 ≈ 13 × 3/7): zero types grant 7; pooled delta **+$717** for 3-day,
  accuracy 0.574 vs 0.577.

The genuine, measurable difference between the windows is the tradeoff, and both halves are real:

- **3-day reacts ~3 days sooner** — across 278 detected regime turns, median lag 4.0 d vs 7.0 d;
  on 242 paired turns 3-day is faster 164 times vs 46 (p = 9.8e-17);
- **3-day over-cuts winners** — on matched decisions it cuts 40.3% of keywords that settle
  profitable vs 32.2% for 7-day.

Also worth keeping straight: the brief's premise that a fresh day understates ROAS by ~20% is
**wrong for SP**. Spend lags almost as much as sales at age 1 (79.5% vs 76.6%), so the ROAS
understatement is ~3.6% at age 1 — 6.2% over a 3-day window vs 3.1% over a 7-day one. A 3.2-point
gap. **SB is different**: sales at age 1 = 61.8% vs spend 82.6%, so a 3-day SB window understates
ROAS by ~17%.

**Consequence for maintenance:** if the click gate is ever scaled to the window, every row in
`DE_PEAK_WINDOW_OVERRIDE` must be re-measured, because the confound that produced the three 7s
disappears and every type reverts to 3.

---

## 6. Open recommendations — NOT applied in v27.50

### 6.1 `V_OOB_BUDGET_PHASE` carries its own 3-vs-7 switch — recommend bringing it under the rule

`scripts/bigquery/views/V_OOB_BUDGET_PHASE.sql` lines 278 / 292 / 314:

```sql
WHEN COALESCE(IF(b.in_peak, b.r3, b.r7), 0) < 0.6
 AND COALESCE(IF(b.in_peak, b.r4_14, b.r8_28), 0) < 0.6
 AND NOT b.is_defense THEN 'CUT'
```

Not governed by `w_days`, but it is the same question about the same data: same season gate, same
3-vs-7 choice, at budget grain. It was deliberately left alone this pass.

**Recommendation: bring it under the rule, but measure it first, and do not treat it as urgent.**
Two properties make it materially safer than the keyword engine today:

1. it requires **both** legs — the short window **and** a long, fully-settled one (4–14d in peak,
   8–28d off). A fresh-data understatement on the short leg alone cannot produce a cut;
2. it is campaign-grain, so the numbers are 10–50× larger and proportionally less noisy.

Measured on 2026-08-12: of 9 working-tier campaigns in PHASE, **2 have `roas_3d < 0.6` but
`roas_7d ≥ 0.6`** — the short leg flips on 22% of them, zero flip the other way, and none actually
CUT because the settled long leg vetoes it. That corroboration requirement is doing real work.

If a 7-day override is ever applied to PHASE it **must** be applied together with the keyword
engine for the same occurrence type, or the two engines will disagree about the same campaign's
window on the same day. Reading `V_PEAK_WINDOW_RULE.w_days` is the way to guarantee that.

Also unfixed there: the separate `today AND prev-2d` 3-day cut construct at lines 136–139.

### 6.2 `V_KEYWORD_LIFT` condemns on the short window alone — no corroboration leg

`PARK` (`clk_w >= 13 AND gp_w_raw <= 0`) and `CUT_TO_BREAKEVEN` (`clk_w >= 13 AND roas_w < 1.0`)
read the W window and nothing else. `V_OOB_BUDGET_PHASE` requires a settled second window before it
cuts; the keyword engine does not, and the v27.48.2 settle guard is its only backstop. This is an
independent risk from the window length and is the single change most likely to matter more than
3-vs-7. Not in scope here.

### 6.3 Two engines still run the PRE-v27.49 season gate

v27.49 fixed the gate in `V_KEYWORD_LIFT`, `V_OOB_BUDGET_PHASE` and `V_LAUNCH_POPULATION`. It did
not fix:

- `scripts/bigquery/views/V_KEYWORD_GUARD.sql:66`
- `scripts/bigquery/views/V_OOB_KEYWORD.sql:257`

Both still use `category IN ('gift_season','prime_event')` with no `COALESCE` on `cooldown_end`, so
today they read **`in_peak = FALSE` while the engine reads TRUE**. Live consequences: `V_OOB_KEYWORD`
prices bids off the OFF CPC band while `V_KEYWORD_LIFT` prices off PEAK (on Lollibox BROAD the two
engines target $0.45 and $0.25 for the same keyword), and `V_KEYWORD_GUARD` resolves `band_ceil` to
`ceil_off` during a live season. **Recommendation: point both at
`V_PEAK_WINDOW_RULE.in_peak`** — the view now exists precisely so there is one definition. Out of
scope for v27.50 because it moves bids, not windows.

### 6.4 The gate rescale is the change the evidence actually argues for

§5 shows the three 7-grants are an artefact of the fixed 13-click bar. The change the data supports
is: **scale the click gate with the window (13 → 6 for a 3-day window), then run 3 days
everywhere.** Accuracy is unchanged, dollars tilt slightly to 3, and the engine reacts a full four
days sooner (95% of true regime turns caught vs 88%). That is a separate decision and needs Ori's
sign-off, because it changes how often the engine acts, not just what it looks at.

Until then, the override table above is the correct implementation of the rule as asked, and
**flipping `w_days` to 3 everywhere with the gate left at 13 is the one combination the evidence
rejects** (measured −$5.4k of peak-season dollar-skill).

### 6.5 Two calendar divergences, recorded not fixed

- The engines (and `V_PEAK_WINDOW_RULE`) end a season at
  `COALESCE(cooldown_end, holiday_date + 3)`; `V_SEASON_CONTEXT` ends it at
  `COALESCE(cooldown_end, holiday_date)`. For a NULL-cooldown season (Back to School) that is a
  3-day tail (Sep 15–17) where the engines are in peak and the ledger says OFF.
- `V_SEASON_CONTEXT` excludes `category='seasonal'`; the engines (v27.49) include it. Harmless in
  day terms — Halloween nests inside Christmas and contributes zero unique peak days — but the
  header comment in `V_SEASON_CONTEXT.sql` claiming it "matches the engines' `in_peak`" is now
  stale.

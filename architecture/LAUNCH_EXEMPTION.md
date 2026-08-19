# LAUNCH EXEMPTION — the coach may not loss-cut a launch family

**v27.56 · Ori 2026-08-13 · status: DEPLOYED (BigQuery) / dashboard files written, NOT deployed**

> Ori: *"The launch exemption — but make it as a new criteria (above the revivals criteria) in the
> weekly run page."*

---

## 1. The hole this closes

Standing doctrine (`feedback_launch_money_bleeder`, 2026-07-21):

> **launch = FIND THE RIGHT BID, never loss-cut; bleed via search-term negate.**

The coach implements that at **TARGET grain only** — `V_ADS_COACH.launch_phase` /
`launch_decision`, gated on `V_LAUNCH_POPULATION`. Its **BUDGET** rows carry
`launch_phase = NULL`, so the campaign-budget engine (`V_ADS_COACH`'s budget CASE) was free to
stop or shrink a family that is *supposed* to lose money while its bid is found.

On 2026-08-13 the hole was live and expensive. Of the **12** coach budget decisions standing on
the two launch families, **9 were cuts**:

| family | age | campaign | budget engine wanted |
|---|---|---|---|
| Bunny | 2.7mo | BUNNY- BROAD | `CAMPAIGN_STOP` |
| Bunny | 2.7mo | BUNNY-SP/AUTO (Birthday) | `CAMPAIGN_STOP` |
| Bunny | 2.7mo | BUNNY-SP/AUTO (Brave) | `CAMPAIGN_STOP` |
| Bunny | 2.7mo | BUNNY-SP/AUTO (Proud) | `CAMPAIGN_STOP` |
| Bunny | 2.7mo | BUNNY-SP/BROAD (Hunter…) | `GUARDIAN_BUDGET_DECREASE` $16 → $4 |
| LolliBall | 1.6mo | BALL-SP/AUTO (Blue) | `CAMPAIGN_STOP` |
| LolliBall | 1.6mo | BALL-SP/AUTO (Mint) | `GUARDIAN_BUDGET_DECREASE` $23 → $11 |
| LolliBall | 1.6mo | BALL-SP/AUTO (Pink) | `GUARDIAN_BUDGET_DECREASE` $10 → $3 |
| LolliBall | 1.6mo | BALLS- BROAD | `GUARDIAN_BUDGET_DECREASE` $57 → $26 |

Two more (BALL Purple $12→$8, BALL White $19→$9) were only masked by the 3-day
no-re-suggest cooldown and would have fired within days.

---

## 2. Membership is computed, not listed

`V_LAUNCH_EXEMPTION` derives launch phase from each family's **own first sale** —
`MIN(date)` over `T_UNIFIED_DAILY` where `units > 0`, the same definition
`V_PRODUCT_LAUNCH_MODEL` and `V_LAUNCH_RAMP` already use. Nothing is hardcoded; a family enters
and leaves launch phase on its own record.

Ages at build time (2026-08-13):

| family | first sale | age |
|---|---|---|
| LolliBall | 2026-06-26 | 1.6 mo |
| Bunny | 2026-05-24 | 2.7 mo |
| LolliME | 2025-07-01 | 13.4 mo |
| Bottle | 2025-06-23 | 13.7 mo |
| Fresh | 2024-08-14 | 23.9 mo |
| Lollibox | 2024-03-27 | 28.5 mo |

### The boundary: 183 days (6 months) — and why

**The data cannot pick it.** There is a ten-month hole between 2.7 and 13.4 months: *every* cut
anywhere in (3 mo, 13 mo) selects exactly the same two families. So the boundary is a doctrine
choice and has to be defended as one, not fitted to six rows.

1. **183d is the tightest boundary the warehouse already agrees with.**
   `V_PRODUCT_LAUNCH_MODEL` requires ≥ 180 days of history before a product's own record is
   allowed to be a pattern — the system already treats the first ~6 months as too young to judge.
2. **12 months was rejected** (the forecast's first-year run-rate guard). A family a year old that
   still loses money is a business problem, not a launch; a 12-month exemption would have covered
   LolliME and Bottle for most of their lives.
3. **It is a backstop, not the driver.** Where Ori has recorded a sanction, its dated stop gate
   binds first — and today it does for both families.

```
exempt_until = LEAST(first_sale + 183d, DE_LAUNCH_INVESTMENT.stop_date)
```

| family | age boundary | sanctioned stop | exempt_until | source |
|---|---|---|---|---|
| Bunny | 2026-11-23 | 2026-10-31 | **2026-10-31** | `SANCTIONED_STOP_DATE` |
| LolliBall | 2026-12-26 | 2026-11-30 | **2026-11-30** | `SANCTIONED_STOP_DATE` |

Past `exempt_until` the row disappears from the view and normal coaching resumes — **no code
change, no cleanup**.

---

## 3. An exemption is not a blank cheque

Three bounds, all published as data on every row.

**1 · The end date** — above.

**2 · The envelope.** `DE_LAUNCH_INVESTMENT` records the sanctioned **$/day for the whole family**
and the view compares it with the family's real trailing-7d daily spend:

| family | sanctioned | actually spending | state |
|---|---|---|---|
| Bunny | $30/day (≈$913/mo) | **$43.56/day** | `OVER_ENVELOPE` +$13.56/day |
| LolliBall | $55/day (≈$1,674/mo) | **$150.38/day** | `OVER_ENVELOPE` +$95.38/day |

An over-envelope family sets `escalate_to_ori = TRUE`. Taking money out is **Ori's budget
decision**, not a coach ROAS cut — so the view also publishes the order in which it should come
out: `envelope_trim_rank`, worst settled GP-ROAS first, biggest spender as the tiebreak,
`protected_winner` rows (≥10 settled clicks at ≥1.0× GP-ROAS) always last. *Today no campaign in
either family is a protected winner* — the best settled record is BALLS- BROAD at 0.79× on 1,763
settled clicks.

> **Open decision for Ori:** the exemption currently stays ACTIVE while over-envelope (doctrine:
> the coach must not loss-cut a launch). The alternative — over-envelope voids the exemption — is
> a one-line change in `V_LAUNCH_EXEMPTION` (`camp` filter). It was not taken because a blind
> ROAS cut takes money out of the *wrong* campaigns for the *wrong* reason.

**3 · A narrow blast radius.** The exemption blocks exactly one class of decision.

---

## 4. What is blocked, what is not

### `blocks_enforced` — wired in `V_ADS_COACH.scored_exempt`

`CAMPAIGN_STOP` · `GUARDIAN_BUDGET_DECREASE` · `BLITZ_BUDGET_DECREASE` ·
`COOLDOWN_BUDGET_REDUCE` · `RESTORE_BUDGET_PRE_PEAK` · `GUARDIAN_BUDGET_CONTAIN` **post-grace only**

### `allows` — still fully live

* Search-term negation (`NEGATE_TERM` / `STOP_TERM`) — **the sanctioned bleed control**
* Obvious-waste bid trims — `DARK_BRAKE` / `TRIM_BID` / `FIT_CPC`
* The wake step-down (`V_KEYWORD_GUARD.wake_step_bid`)
* `LAUNCH_TAPER` at optimizer EXIT/POST
* All budget **increases**, `DEFENSE_BUDGET_FLOOR`
* `STOP_SEASONAL` — calendar-driven, not a profit verdict
* **Broken-launch containment inside the first 14 days** (>$25 spent, ZERO orders → $10/day)
* Bringing the family back inside its sanctioned envelope

### The grace subtlety

`GUARDIAN_BUDGET_CONTAIN` is emitted by **two** arms of the budget CASE with the *same string*:

* the **14-day grace arm** — a broken launch, >$25 spent with ZERO orders, contained at $10/day.
  This is a zero-order waste trim that exists **for** launches. It must survive.
* the **ROAS arm** — two bad weeks in a row (w1<0.5, prev<0.7). This is a loss-cut. It is blocked.

Since the action string cannot distinguish them, the view does it on campaign age:
`in_grace_window` (first FACT activity < 14 days ago) → `blocks_contain = FALSE`.

### `blocks_pending` — named in the doctrine, deliberately NOT wired

* the coach's target-grain ROAS park `STOP_TARGET` — **4 rows / $78 spend_4w** on these families
* the engine parks in `V_OOB_KEYWORD` / `V_KEYWORD_LIFT`

Left alone on purpose: the OOB **seat model**'s `PARK_WAIT` is *capacity*-driven and is the
sanctioned launch mechanism ("winner-as-main is emergent" — others park/trim, freed budget flows
to the winner). Blanket-blocking parks would break the engine the exemption exists to protect.
Both are one `WHEN` each if Ori wants them.

---

## 5. Wiring

```
DE_LAUNCH_INVESTMENT ─┐
T_UNIFIED_DAILY ──────┼─► V_LAUNCH_EXEMPTION ─┬─► V_ADS_COACH.scored_lx → scored_exempt
V_CAMPAIGN_FAMILY_MAP ┤   (1 row / campaign)  │      └─► V_COACH_CAMPAIGN_BUDGET (passthrough)
V_DIM_CAMPAIGN_CURRENT┤                       │      └─► SP_REFRESH_ADS_COACH_ACTIONS → FACT
FACT_AMAZON_ADS ──────┘                       └─► cube/schema/LaunchExemption.js → Weekly Run panel
```

### `V_ADS_COACH` (the gate)

Two new CTEs sit between `scored` and the output; the final `SELECT` reads
`FROM scored_exempt AS scored`, so **every existing reference in the file is untouched**.

* placed **after** the cooldown/deadband `REPLACE` on purpose — `budget_action_suppressed` then
  records what *would* have been emitted today, not something the cooldown had already masked;
* `budget_action` → `LAUNCH_EXEMPT_HOLD`;
* **`recommended_budget` → NULL on held rows.** Load-bearing: `V_COACH_CAMPAIGN_BUDGET.is_change`
  and the bulksheet queue key on `recommended_budget`, so leaving it populated would let the very
  cut just blocked be exported anyway;
* **`launch_down_rec_blocked` — the second leak.** The 3-day cooldown `REPLACE` masks the *action*
  to `BUDGET_OK` but leaves the *number*, and `is_change` keys on the number. Two LolliBall
  campaigns (Purple $12.29→$8, White $19.20→$9) were carrying an exportable downward budget behind
  a `BUDGET_OK` label — the gate would have been bypassed entirely. On an exempt campaign **no
  downward budget recommendation is published at all**, whatever the action says. (The underlying
  quirk is pre-existing and account-wide; only the launch-family half is closed here.)
* new output columns: `launch_exempt`, `launch_exempt_family`, `launch_exempt_until`,
  `launch_exempt_reason`, `launch_cut_suppressed`, `launch_down_rec_blocked`,
  `budget_action_suppressed`, `budget_suppressed_to`.

### `SP_REFRESH_ADS_COACH_ACTIONS` (minimal change, Step 5 only)

1. `_base_rows` carries `ca.budget_action_suppressed` + `ca.budget_suppressed_to`;
2. `strategic_task`: `LAUNCH_EXEMPT_HOLD → MAINTAIN`;
3. one `WHEN` in the BUDGET `action_explanation` that **names the suppressed decision**:

> *LAUNCH EXEMPTION: budget held at $23. The coach would have applied GUARDIAN_BUDGET_DECREASE (to
> $11/day) — blocked because this is a launch family, which is SUPPOSED to lose money while the
> right bid is found. Bleed control on a launch is search-term negation and bid trims, never a
> budget loss-cut.*

Nothing else in the procedure was touched. The FACT schema is unchanged.

### Panel

`dashboard-react/src/pages/LaunchExemptionPhase.tsx`, mounted in `WeeklyRunPage.tsx` step 4
**above** `RevivalsPhase` (Ori's ordering: Low stock → Launch → Revivals). Display-only:
membership, the end date, the envelope verdict, the trim order and every sentence come from the
view. Uses `cubeLoadWithMeta` and checks `res.error`, so a cube outage renders "unavailable"
instead of falsely claiming no family is in launch phase.

---

## 6. Verification (2026-08-13)

* `V_LAUNCH_EXEMPTION`: 15 rows / 15 distinct campaigns (campaign grain, no fan-out).
  Deterministic — pulled twice byte-identical, md5 `1d471b6eb33b1d7e0bb61f096a30825c`.
* Gate effect, account-wide: **9** campaigns became `LAUNCH_EXEMPT_HOLD`; **26**
  `GUARDIAN_BUDGET_DECREASE`, **8** `CAMPAIGN_STOP` and **1** `GUARDIAN_BUDGET_CONTAIN` still
  stand elsewhere — **no non-exempt campaign moved**.
* `SP_REFRESH_ADS_COACH_ACTIONS` re-run end-to-end: 9 `LAUNCH_EXEMPT_HOLD` BUDGET rows, all with
  `recommended_budget = NULL`, all carrying the naming explanation.
* `V_COACH_CAMPAIGN_BUDGET`: **0** `is_change` rows on exempt campaigns (52 elsewhere, untouched).
  All 12 launch-family budget rows carry `recommended_budget = NULL`.
* `T_COACH_CAMPAIGN_BUDGET` rebuilt by hand (`CREATE OR REPLACE TABLE … AS SELECT * FROM
  V_COACH_CAMPAIGN_BUDGET`, the exact statement `SP_REFRESH_CUBE_TABLES:47` runs) — otherwise the
  Weekly Run campaign rows, which read the **T_ snapshot** and not the view, would have kept
  offering the blocked cuts until the next orchestrator pass.
* Dashboard: `tsc --noEmit` clean, 726 vitest pass.

---

## 7. Known gaps / follow-ups

1. **`V_WEEKLY_RUN_CAMPAIGN.strategy_type` still buckets exempt campaigns as `CUT`** (they fall
   through to the `effective_roas < 0.9` arm). Cosmetic but wrong-signalling — it tells Ori to
   "trim or stop the spend here" on a protected campaign. Fix is one `WHEN`, deliberately not
   taken in this pass because the output vocabulary (`SCALE`/`CUT`/`MARGIN`) has no honest slot
   for "protected launch" and adding one touches the frontend help text.
2. **`blocks_pending`** (§4) — target-grain and engine parks.
3. **The over-envelope decision** (§3).
4. `config.yaml` has a pre-existing duplicate-key defect at the `DE_HALO_WEIGHTS` entry
   (`type`/`source_files` written twice, ~line 833) that makes a strict YAML parse fail. Not
   introduced here, not fixed here.

---

## 8. The launch bid ladder (v27.59, Ori 2026-08-13)

The exemption blocks every *budget* loss-cut. It always allowed bid trims, but nothing actually
emitted one on a launch schedule. This is that lever — and it is the **only** downward thing the
exemption now carries.

> **Ori, verbatim:** "launch_bid ok between 0.5 and 0.7 trim keyword bid 5% and use launch_bid /
> improving between 0.7 and 0.9 do not do / profitable launch_bid ok <0.5 trim keyword bid 10%"

and, correcting the first build: **the ladder judges on the SHORT window**, not the settled one.

**View:** `scripts/bigquery/views/V_LAUNCH_BID_LADDER.sql` (target grain — one row per
campaign × keyword/target)
**Cube:** `cube/schema/LaunchBidLadder.js` (live read, 15-min TTL)
**Panel:** the `bid ladder` toggle inside `LaunchExemptionPhase.tsx`, one per family

### 8.1 The ladder

| GP-ROAS on the short window | action | step |
|---|---|---|
| `< 0.50` | `LAUNCH_BID_TRIM_10` | −10% |
| `0.50 – 0.70` | `LAUNCH_BID_TRIM_5` | −5% |
| `0.70 – 0.90` | `LAUNCH_BID_HOLD_IMPROVING` | none — "improving, leave it alone" |
| `>= 0.90` | `LAUNCH_BID_HOLD_PROFITABLE` | none — "profitable, launch_bid ok" |
| no spend on the window | `LAUNCH_BID_HOLD_NO_EVIDENCE` | none |
| trim band, but the bid is already at its floor | `LAUNCH_BID_HOLD_AT_FLOOR` | none |

Bands are half-open `[lo, hi)`. GP-ROAS = gross profit ÷ ad spend with tier COGS charged, so `1.00`
is breakeven **after** product cost — which is why `0.9` ("profitable") sits just under it.

**The steepest thing this view can say is −10%.** It emits no budget column, no park verb and no
stop verb. Everything §4 blocks stays blocked.

### 8.2 The judged window — short, and deliberately unsettled

`w_days` comes from **`V_PEAK_WINDOW_RULE`** — the one place the house decides how long "recent" is
(7 days off peak, 3 in peak unless 7 has been *proven* better for that occurrence). Today: in peak,
`BTS`, `w_days = 3`, verdict `PEAK_DEFAULT_NOT_PROVEN`. The window is the last `w_days` **complete**
days ending at the **ads watermark** (`MAX(date)` in `FACT_AMAZON_ADS`, today `2026-08-12`) — not
`today − 1`, so a late 07:40 load slides the whole ladder back a day instead of judging a
half-loaded one.

> ⚠ **Settle caveat, stated once.** A 3-day window is unsettled: SP sales accrue to D+7 and SB to
> D+14, so GP-ROAS is understated and the band is biased **toward trimming**. Accepted, not
> accidental. Ori asked for the short window, and the cost of being wrong is 5–10% of one bid for
> one day, re-judged tomorrow. Contrast §4, where settled 28-day evidence gates a *campaign stop* —
> a decision you cannot undo by re-running it. Different blast radius, different window. Both
> numbers ride on every row (`w_gp_roas` next to `campaign_settled_gp_roas`) so the disagreement is
> visible rather than argued about.

**Last day is published, not judged.** Ori's table format is "last day + 7 days window", so `d1_*`
is on every row; the band is taken on the w-window alone. The "must fail **both** windows" test
belongs to the low-stock −50% rule (`V_LOW_STOCK_ADS`) — a far more aggressive lever. Importing its
conjunction here would silently disable the ladder on any target that had one good day.

**Evidence gate = `w_spend > 0`, and nothing more.** No minimum-click threshold was invented; Ori
set none, and a 5–10% nudge does not need one. Instead the evidence is *published* —
`w_clicks / w_orders / w_spend` on every row plus `evidence_grade = 'THIN'` under 3 window clicks,
which changes no action but makes a one-click verdict legible as a one-click verdict.

### 8.3 How `launch_bid` anchors the trim — destination, not one-step ceiling

`launch_bid` is **read, never recomputed**: `FACT_ADS_COACH_ACTIONS.launch_bid` /
`launch_bid_source`, computed in `V_ADS_COACH` as anchor CPC (research 30d/12m → the target's own 8w
CPC → strategy template max → flat cold bid) × `LAUNCH_BID_MULT`, capped at `LAUNCH_BID_CEILING`.

Three readings of "use launch_bid" were tested against today's 105 exempt target rows:

1. **As the TARGET** (`proposed = launch_bid × 0.95`) — would **raise** the bid on 92 of 105 rows.
   Current bids sit at $0.24–$0.25 against launch_bids up to $1.40. It answers "trim" with a 4–5×
   increase. **Rejected.**
2. **As a FLOOR** ("launch_bid is ok, don't go below it") — blocks the trim outright on those same
   92 rows, *and on both rows in the 0.5–0.7 band*, since every trimmed bid is already far under
   launch_bid. The ladder would emit nothing in the very band the instruction was written for.
   **Rejected.**
3. **As a CEILING on the anchor** (`anchor = LEAST(current_bid, launch_bid)`) — the only reading
   that both trims and uses the number. But in **one step** it stops being gentle: *"best friends
   personalized gifts girls"* (bid $1.36, launch_bid $0.65) would be cut to $0.59 — **−56.6% on one
   click of unsettled evidence.** A −57% move is a loss-cut wearing a trim's name.

**Resolution: the ceiling is kept as a DESTINATION and the band keeps the STEP.** Ori's sentence
carries two constraints — *"trim keyword bid 5%"* (how far) and *"use launch_bid"* (where to) — and
a bid **search** honours both by walking:

```
step_bid     = CEIL(current_bid × factor × 100) / 100     -- the band sets the step
proposed_bid = GREATEST(step_bid, bid_floor), capped at the anchor
launch_bid   = the destination, published on every row
```

Each run takes the band's step; the next run re-reads the lowered bid, so a bid above `launch_bid`
converges on it at 5–10% per run for as long as the short window keeps saying the target loses
money — and stops the moment GP-ROAS crosses 0.7. The $1.36 row reaches $0.65 in **8 runs** instead
of one. Nothing is given up but speed, and speed is what one click of unsettled evidence does not
buy. Published so the harder reading is one `CASE` away and never hidden: `above_launch_bid`,
`runs_to_launch_bid`, `ceiling_step_bid`.

Where there is **no** current bid, `launch_bid` is the base — `COALESCE(current_bid, launch_bid)`,
`V_ADS_COACH`'s own idiom for "use launch_bid" three lines away in `launch_recommended_bid`. Dormant
today (0 of 105 rows have a null bid, and such rows are excluded anyway — a trim needs a bid to
trim), written down so the phrase is not re-litigated.

**`CEIL` to the cent, never `ROUND`.** Rounding a $0.36 bid down to $0.32 is an 11.1% cut on a 10%
band. Ceiling to the cent guarantees the realised trim is never *deeper* than the band says —
measured today: `TRIM_10` spans −10.0%…−6.9%, `TRIM_5` spans −4.8%…−4.7%.

**Never a raise.** `proposed_bid` is capped at the anchor, so the arrow only ever points down or
nowhere.

### 8.4 Floors — no trim may land below the row's minimum

| row | floor | source |
|---|---|---|
| SP | **$0.20** | house floor (Amazon's own SP minimum is $0.02, but a bid that low buys no placement worth having) |
| SB, video creative | **$0.25** | Amazon SB `minBid` |
| SB, `PRODUCT_COLLECTION` / `STORE_SPOTLIGHT` | **$0.10** | Amazon `minBid` for those creatives |

The same floors `V_OOB_KEYWORD` / `V_KEYWORD_LIFT` already use — one floor governs the system.
Creative type comes from `DIM_AD_GROUP.creative_type` (`is_current`). When the floor binds,
`floor_binding = TRUE` and the reason string says the realised trim is smaller than the band rather
than quietly reporting "−10%". If the floor leaves no room at all the row reads
`LAUNCH_BID_HOLD_AT_FLOOR` and proposes nothing.

### 8.5 Population, grain and dedup

* **IN:** every `action_type = 'TARGET'` coach row whose campaign is in `V_LAUNCH_EXEMPTION`,
  `campaign_state = 'ENABLED'`, `keyword_id NOT NULL`, `current_bid NOT NULL`.
* **OUT — brand DEFENSE** (`V_CAMPAIGN_ROLE.role` / `strategy_category LIKE '%DEFENSE%'`). Defense is
  never profit-judged: it is a moat, not a ROAS bet. No exempt campaign is defense today, so this
  excludes nothing — it is there so the rule is right the day a launch family gets one.
* **OUT — `TARGET_PAUSED`** rows: no live bid to trim.

`V_ADS_COACH` is search-term/ASIN grain, so one keyword arrives as several TARGET rows with
**different** `launch_bid` values (today 105 rows over 74 keywords; *"gift for girls"* alone carries
1.40 / 1.38 / 1.00). A bulksheet takes one bid per keyword. The view dedupes to
`(campaign_id, keyword_id)` with a single `ARRAY_AGG(STRUCT(...) ORDER BY priority_score DESC,
launch_bid DESC, asin, action_id LIMIT 1)` — **one struct**, so `current_bid` / `launch_bid` /
`launch_bid_source` / the coach's own action are read from one row and cannot be cross-paired.
Never two `ANY_VALUE()`s out of one `GROUP BY`. The order is total, so the pick is deterministic.

### 8.6 Relation to the coach's own bid actions, and why `V_LAUNCH_EXEMPTION` did not change

The coach still emits its own `REDUCE_BID` / `INCREASE_BID` on these campaigns — the exemption never
blocked bid moves. This view does **not** override or suppress them: it publishes
`coach_target_action` / `coach_recommended_bid` beside its own proposal and raises
`conflicts_with_coach`, so the two are reconciled by Ori looking at them rather than one silently
winning. Changing `V_ADS_COACH`'s bid arm was outside what Ori asked for.

`V_LAUNCH_EXEMPTION` is **deliberately unchanged in grain and dependencies** — only its header and
its published `allows` string now name the ladder. It is read by `V_ADS_COACH`; the ladder reads
`FACT_ADS_COACH_ACTIONS`, which `V_ADS_COACH` materialises. Pulling ladder columns into the
exemption would close a stale-data loop around the coach engine and add cost to a view already near
BigQuery's planner limit ("too many subqueries"). **The ladder reads the exemption, never the
reverse.**

### 8.7 Verification (2026-08-13, ads watermark 2026-08-12)

* Window resolved: `in_peak = true`, `BTS`, `w_days = 3`, `2026-08-10 .. 2026-08-12`.
* `V_LAUNCH_BID_LADDER`: **73 rows / 73 distinct (campaign, keyword)** — no fan-out; 12 campaigns,
  2 families. Deterministic — pulled twice byte-identical, md5 `b7fc40b5cfbfed1e2351d5bd8de472e8`.
* Bands: **33** `TRIM_10` · **2** `TRIM_5` · **0** `HOLD_IMPROVING` · **6** `HOLD_PROFITABLE` ·
  **32** `HOLD_NO_EVIDENCE` · **0** `HOLD_AT_FLOOR`. **35 proposals**, **$1.83** of bid removed in
  total. 41 of 73 rows carry `THIN` evidence — the honest cost of a 3-day window at keyword grain.
* Floors: **0** proposals below their floor; the smallest proposed bid is **$0.22** against a $0.20
  SP floor. **0** proposals above the current bid (no raises). All 73 rows are SP today, so the SB
  floors are exercised by construction, not by data.
* Band fidelity: **0** proposals cut deeper than their band's nominal percent, checked directly
  (`proposed_bid < current_bid × trim_factor`). Realised: `TRIM_10` −10.0%…−6.9%,
  `TRIM_5` −4.8%…−4.7%.
* **A float bug was found and fixed during verification.** `CEIL(0.40 × 0.90 × 100)/100` in FLOAT64
  is `0.37`, not `0.36` — binary `0.40 × 0.90 × 100` evaluates to `36.000000000000007`, so the
  ceiling lands a cent high and a "−10%" trim silently becomes −7.5%. Verified live: FLOAT64 gives
  0.37 on a $0.40 bid and 0.73 on $0.80; NUMERIC gives 0.36 and 0.72. The rounding step now runs in
  `NUMERIC` and is cast back to `FLOAT64` (schema unchanged) — the same lesson `V_KEYWORD_GUARD`
  already recorded. It moved 5 of the 35 live proposals onto their exact band.
* `above_launch_bid` on **1** of 73 rows; it proposes −10.3% (8 runs to `launch_bid`) instead of the
  one-step −56.6%.
* Blocks unchanged on exempt campaigns (`FACT_ADS_COACH_ACTIONS`, 6 446 rows): **0** `CAMPAIGN_STOP`,
  **0** budget decreases of any kind, **0** downward budget numbers, **9** `LAUNCH_EXEMPT_HOLD`.
* `V_LAUNCH_EXEMPTION` still **15 rows / 15 campaigns** (campaign grain intact); `allows` now names
  the ladder on all 15.
* Dashboard: `tsc --noEmit` clean.

### 8.8 Known gaps

1. **`STOP_TARGET` (3 rows) still stands on exempt campaigns.** These are the target-grain ROAS
   parks §4 lists under `blocks_pending` — declared doctrine, never wired, and *not* wired here
   either. One of them (`BALL-SP/AUTO (Blue)` ▸ complements) now has the coach proposing a park and
   the ladder proposing a −10% trim on the same target; `conflicts_with_coach` surfaces it. Ori's
   call, one `WHEN` each.
2. **The ladder is advisory and not queued.** It writes nothing to the DO queue and produces no
   bulksheet rows — deliberately, since `V_COACH_APPLY` dedupes bid rows off `V_ADS_COACH` and
   admitting a second bid source needs a precedence rule Ori has not set.
3. **32 of 73 rows have no spend on a 3-day window.** In peak the window is short enough that
   nearly half the population is unjudgeable on any given day. That is the honest consequence of
   Ori's own window rule, not a defect — but if the ladder feels slow, the lever is
   `DE_PEAK_WINDOW_OVERRIDE`, not a threshold in this view.

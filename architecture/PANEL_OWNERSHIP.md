# Panel ownership — one campaign, one criteria (v27.62, 2026-08-13)

> Object: `V_PANEL_OWNERSHIP` → `FACT_PANEL_OWNERSHIP` (snapshot) → cube `PanelOwnership`.
> Builder: `SP_SNAPSHOT_PANEL_OWNERSHIP`. Advisory. Nothing auto-applies to Amazon.

## Why it exists

Ori, 2026-08-13:

> "same campaign with different measures shows in 2 criterias (this is not good)."

The example he found: **VIDEO- BALL** was live in both *Portfolio 80/20* and *Low stock* at the same
time, with two different numbers.

| panel | action | now | → | per day |
|---|---|---|---|---|
| Low stock | `STOCK_BUDGET_CUT` | $55.06 | $48.85 | **−$6.21** |
| Portfolio 80/20 | `RAISE_WEAK` | $55.06 | $68.83 | **+$13.77** |

Same campaign, same day, **$19.98/day apart, pointing in opposite directions** — on a family with
23 days of cover that goes dry 2026-09-05 with the next boat landing 2026-09-09.

This is not a rendering bug. Both numbers are computed, both are correct inside their own engine,
and neither engine knows the other exists.

## The rule

Ori's priority order: **LOW STOCK > LAUNCH > REVIVALS > everything else.**

A campaign belongs to exactly one criteria. The losing panels either drop the row or show it as an
explicit deferral carrying **no instruction** — never a second, contradictory number.

### The ladder

| rank | owner | scope | evicts? |
|---|---|---|---|
| 1 | `LOW_STOCK` | `FULL` — both levers (bid **and** budget) | **yes**, every lower panel |
| 2 | `LAUNCH` | `PARTIAL_NO_CUT` — blocks ROAS money cuts only | no (see below) |
| 3 | `REVIVAL` | keyword-grain, already single-homed | no (see below) |
| 4 | `OOB` / `LIFT` | the engines | — |

Rank 4's OOB-vs-LIFT split is **not decided here**. It stays exactly where it has always been:
`V_CAMPAIGN_CAP_STATE.is_oob_owned`. This view only reports it so one row shows the whole chain.

### The LOW_STOCK claim predicate — two arms, and both are needed

```
claimed = NOT is_defense AND (
    A. STRUCTURAL : the family's risk_state = 'CRITICAL'
 OR B. INSTRUCTED : low stock carries a live instruction for THIS campaign —
                    a campaign-row suggested budget, or ≥ 1 proposal target row )
```

**Arm A exists because of VIDEO- COMP/BALL.** Low stock says nothing about it (`STOCK_NONE`,
0 proposals) while Portfolio 80/20 proposes `RAISE_WEAK` $12.00 → $18.00. Without the structural
arm that raise stands: **+$6.00/day of fresh demand poured into a family with 23 days of cover.**
"Low stock proposed nothing" does not mean "do what you like" — it means *hold until the boat
lands*. Silence from the owner is still the owner's answer.

**Arm B exists because of BUNNY-SP/AUTO (Brave).** Bunny grades WATCH, not CRITICAL, so arm A does
not fire — but low stock **is** cutting it (`STOCK_BUDGET_CUT` $10.00 → $9.63, the paired cut on a
capped campaign) while Portfolio 80/20 proposes `RAISE_WEAK` $10.00 → $15.00. A contradiction does
not need a CRITICAL grade to be a contradiction.

Together the two arms mean exactly *"low stock has an opinion here"* — one structural, one explicit.
A WATCH-family campaign low stock is silent about (BUNNY - COMPETITORS: 0 proposals, no engine row
either) is claimed by neither arm and stays where it was. Nothing is claimed for tidiness.

**Defense carve-out.** Brand defense is never profit-judged and never throttled by low stock — it
emits `STOCK_PROTECT` and proposes nothing at any risk state. So low stock must not claim it either:
a claim with no instruction behind it would silence the budget ladder, which is defense's *only*
remedy. Defense campaigns fall straight through to rank 4. Same doctrine `V_CAMPAIGN_CAP_STATE`
states for bids, applied one level up to criteria ownership.

### What a claim means

`defer_action IS NOT NULL` ⇒ the owning criteria is the **only** source of bid and budget
instructions for that campaign. Lower panels show `defer_action` + `defer_reason` and **no**
suggested value — the `DEFER_OOB` shape — or drop the row. If the owner proposes nothing, nothing
happens; that is the intended reading of "hold while the family is dry", not a gap for whichever
engine still has a row to fill.

## Precedent followed exactly: `V_CAMPAIGN_CAP_STATE`

The account already solved this once, one level down. `V_CAMPAIGN_CAP_STATE` (v27.45) is THE single
membership function deciding OOB-vs-LIFT ownership of a capped campaign's **bids**;
`V_KEYWORD_LIFT` reads it and emits action `DEFER_OOB`, no `suggested_bid`, reason
*"capped Nd of 7 — out-of-budget engine owns the bids"* — three ladders in the consumer
(action / value / reason), one predicate each, all reading the same boolean.

`V_PANEL_OWNERSHIP` is the same shape one level up: it decides which **criteria** owns a campaign,
and consumers emit `DEFER_LOW_STOCK` the same way.

## Why LAUNCH (rank 2) evicts nothing — a finding, not an omission

The launch controller has had **no panel of its own** on the Weekly Run page since 2026-08-01:

> "Launch-controller cards DISSOLVED (Ori 2026-08-01): low-budget campaigns live in the Portfolio
> 80/20 (seat mechanism) or Out-of-budget while dark; the launch BUDGET engine feeds the Portfolio
> campaign rows. NewCampaignCards is retired from this page." — `WeeklyRunPage.tsx`

The Portfolio 80/20 **LOW tier is** the launch campaigns' home: `is_low_tier` is literally
`budget <= low_budget_cap`, the same predicate as `V_LAUNCH_POPULATION`. Evicting launch campaigns
on rank-2 grounds would empty their only home — **28 of 108 campaigns** would vanish from the page.

What the launch claim *does* enforce is already live and stays where it is: `V_LAUNCH_EXEMPTION`
blocks ROAS-driven money cuts inside `V_ADS_COACH` and (since v27.57) inside `V_OOB_BUDGET_PHASE`'s
CUT branches. That is a partial claim on one lever in one direction — the launch doctrine
("launch = FIND THE RIGHT BID, never loss-cut") — and it is not the same thing as owning the panel.
Hence `claim_scope = 'PARTIAL_NO_CUT'`, `defer_action = NULL`.

## Why REVIVALS (rank 3) evicts nothing either

A revival is a **keyword** verdict, not a campaign one. Claiming a whole campaign for revivals would
silence both engines over every keyword in it because one parked keyword's settled record turned.

The keyword-grain single-home already exists and already works: `FACT_PARK_REVERDICT` carries
`engine_immune` (post-revival settle veto) and `CONFIRM_PARK` (must-not-resurface), and both engines
honour them. Nothing to rebuild.

What this view adds is the one thing that was missing: **a revival must now defer to a stock claim**
(`owner_rank < 3`). Reviving a keyword inside a family that is going dry is the same contradiction
in miniature.

Measured 2026-08-13: **0 of 25 REVIVE-ready rows sit in the CRITICAL family**, so this arm changes
nothing today — it is the guard for the next CRITICAL family, not a live correction.

### ⚠️ OPEN — needs Ori's call

**12 of the 25 REVIVE rows sit in LAUNCH-population campaigns.** Under a literal reading of
"LAUNCH > REVIVALS" those 12 would be deferred and the Revivals panel would lose half its content.
They are **not** deferred here, deliberately:

- a revival is a settled-90d record (≥ 10 clicks at ≥ 1.0× GP-ROAS);
- the launch claim only blocks **cuts**; a revival is not a cut.

Flipping this is one predicate — `defer_revival_panel` would read `claim_rank < 3` over an
`owner_rank`-based claim instead of the FULL-claim rank — and it is Ori's call, not an engine's.
Recorded so the decision is visible, not silently made.

---

## Claimed today (2026-08-13 anchor)

108 ENABLED campaigns · **11 claimed by LOW_STOCK** · 69 LAUNCH (partial) · 7 OOB · 21 LIFT.

| family | grade | campaign | arm | leaves |
|---|---|---|---|---|
| LolliBall | CRITICAL | VIDEO- BALL | A+B | Portfolio 80/20 (`RAISE_WEAK` +$13.77/d), OOB keyword (3 bid rows) |
| LolliBall | CRITICAL | VIDEO- COMP/BALL | A | Portfolio 80/20 (`RAISE_WEAK` +$6.00/d), OOB keyword (`ACTIVATE`, `PARK_WAIT`) |
| LolliBall | CRITICAL | BALL-SP/AUTO (Blue) | A+B | Portfolio 80/20 (`HOLD`), OOB keyword (2 `DARK_BRAKE`) |
| LolliBall | CRITICAL | BALL-SP/AUTO (Mint) | A+B | Portfolio 80/20 (`HOLD`), OOB keyword (2 `DARK_BRAKE`) |
| LolliBall | CRITICAL | BALL-SP/AUTO (Purple) | A+B | Portfolio 80/20 (`HOLD`), OOB keyword (2 `DARK_BRAKE`) |
| LolliBall | CRITICAL | BALL-SP/AUTO (Pink) | A+B | keyword-lift tier |
| LolliBall | CRITICAL | BALL-SP/AUTO (White) | A+B | keyword-lift tier |
| LolliBall | CRITICAL | BALLS- BROAD | A+B | keyword-lift tier |
| Bunny | WATCH | BUNNY- BROAD | B | Portfolio 80/20 (`HOLD`), OOB keyword (`WAKE_STEP`, `DARK_BRAKE`) |
| Bunny | WATCH | BUNNY-SP/AUTO (Brave) | B | Portfolio 80/20 (`RAISE_WEAK` +$5.00/d) |
| Bunny | WATCH | BUNNY-SP/BROAD (Hunter…) | B | keyword-lift tier |

### The money the claim stops

Budget raises removed from Portfolio 80/20, all of them into a family with a stock problem:

| campaign | raise removed |
|---|---|
| VIDEO- BALL | +$13.77/day |
| VIDEO- COMP/BALL | +$6.00/day |
| BUNNY-SP/AUTO (Brave) | +$5.00/day |
| **total** | **+$24.77/day ≈ $753/month** |

Plus four `HOLD` rows removed — no dollars, pure duplicate noise — and the bid-grain instructions
listed above, of which the sharpest is `ACTIVATE` on VIDEO- COMP/BALL: the out-of-budget engine
switching **on** a parked target inside the CRITICAL family while low stock is throttling it.

Direct opposite-direction contradictions eliminated:

| campaign | low stock | engine | gap |
|---|---|---|---|
| VIDEO- BALL | −$6.21/day | +$13.77/day | **$19.98/day** |
| BUNNY-SP/AUTO (Brave) | −$0.37/day | +$5.00/day | **$5.37/day** |
| VIDEO- COMP/BALL | silent (hold) | +$6.00/day | **$6.00/day** |

### It is worse than two panels — `V_KEYWORD_LIFT` publishes a budget too

`V_KEYWORD_LIFT` carries `suggested_budget` on every one of a campaign's keyword rows, mirroring the
budget engine. So **VIDEO- BALL today carries three budget numbers**, not two:

| source | budget |
|---|---|
| Low stock | $48.85 |
| Portfolio 80/20 (`V_OOB_BUDGET_PHASE`) | $68.83 |
| Keyword lift (`V_KEYWORD_LIFT`, on 5 rows) | $68.83 |

Same for VIDEO- COMP/BALL ($12 → $18 repeated on **29** keyword rows) and BUNNY-SP/AUTO (Brave)
($10 → $15 on 4 rows). BALL-SP/AUTO (White) gets a *fourth* opinion: lift proposes $19 → $15.36
while low stock says `STOCK_BUDGET_HOLD`. All of these fall to the same `defer_engine_panel` hook.

### Target-grain collisions — the same keyword, two different bids, same day

Under the claim these are the rows that stop contradicting. `BALLS- BROAD` (LolliBall CRITICAL, not
capped, so `V_KEYWORD_LIFT` owns its bids) is the clearest: **all three** of its live lift bids land
on a target low stock has already ruled on.

| target | low stock | keyword lift |
|---|---|---|
| tween girls trendy stuff | `STOCK_BID_HALVE` $0.64 → **$0.32** | `PARK` $0.64 → **$0.25** |
| mystery box for teen girls | `STOCK_WATCH` $0.76, no move | `NUDGE_UP` $0.76 → **$0.80** |
| gift for tweens girls | `STOCK_WATCH` $0.34, no move | `PARK` $0.34 → **$0.25** |

The first row is the one to read twice. Both engines want the bid down, so a glance says "no
conflict" — but they name different numbers *and different intents*. `STOCK_BID_HALVE` is a
temporary throttle that is lifted the moment the boat lands; `PARK` is a retirement. Agreeing on
direction is not agreeing.

And on BALL-SP/AUTO (Pink): low stock marks `substitutes` `STOCK_PROTECT` — it converted, leave it
alone — while lift proposes `AUTO_DAY_RAISE` $0.36 → $0.38. A raise on a row the owner deliberately
declined to move, inside a family with 23 days of cover.

---

## Consumers and their panel rank

| rank | view | boolean to read |
|---|---|---|
| 1 | `V_LOW_STOCK_ADS` | — never defers |
| 2 | `V_LAUNCH_PHASE1`, `V_SB_LAUNCH_TARGET` | `defer_launch_panel` |
| 3 | `V_PARK_REVERDICT` (Revivals) | `defer_revival_panel` |
| 4 | `V_OOB_BUDGET_PHASE`, `V_OOB_KEYWORD`, `V_KEYWORD_LIFT`, `V_RUN_TARGET`, `V_KEYWORD_GUARD`, `V_CHANGE_SCORECARD` | `defer_engine_panel` |

All three booleans coincide today, because `LOW_STOCK` is the only FULL claim in the ladder. They
are kept separate so that changing which rank evicts which panel stays a one-line edit **in
`V_PANEL_OWNERSHIP`** and never spreads back into the engines.

`SP_ENGINE_PREFLIGHT` reads all three at once, one per engine, and is the only consumer that acts
on a claim at **upload** time rather than at render time — next section.

## The claim is not the collision — the upload gate (`SP_ENGINE_PREFLIGHT`, v27.81, 2026-08-18)

`SP_ENGINE_PREFLIGHT` is the standing contradiction gate: it judges the day's
`FACT_ENGINE_PROPOSALS` partition and stamps every instruction `GO` / `REVIEW` / `EXCLUDE`, and
`DoPage.exportBulksheet` refuses `EXCLUDE` rows at export time. As deployed it now carries **two
independent sources of exclusion**, and the difference between them is a statement about what a
claim *is*.

1. **Collision-based** (the original). Two engines instructed the **same**
   `(campaign_id, key_id, lever)` today, so the lower-ranked one is dropped. It cannot fire
   without a collision — the predicate is literally `n_instr > 1 AND own_rank > 1`. Its
   precedence, `LOW_STOCK > LAUNCH > OOB > REVERDICT > LIFT > COACH`, is the campaign-level cousin
   of this document's ladder, not the ladder itself.
2. **Claim-based** (new). `FACT_PANEL_OWNERSHIP` says a higher panel **owns this campaign
   outright**, and the lower-ranked engine's money instruction is dropped *whether or not the
   owner said anything today*.

### Why the second arm had to exist

A `FULL` claim "evicts every lower panel on BOTH levers" — that is the rule at the top of this
document, and until v27.81 nothing enforced it at upload time. The gate only ever saw collisions,
and a collision needs the owner to speak.

v27.73's **redirect mode** is exactly the case where the owner deliberately does not speak: when a
family is re-aiming its ad doorways at an in-stock sibling, `V_LOW_STOCK_ADS` prices the bid and
budget cuts but stops *proposing* them (`is_proposal = FALSE`; only waste-parks stay proposals). No
proposal, no collision, and a collision-only gate reads the empty doorway as permission. The
procedure's own header records what came through it: 41 `GO` rows from non-owner engines inside
`LOW_STOCK`-owned, CRITICAL, redirect-mode campaigns — LAUNCH 28 (all bid cuts), OOB 5, LIFT 5
(one of them a bid **raise** into a family with 20 days of cover and nothing booked), COACH 3
negates.

This is the same coupling that blinded the claim predicate's arm B and was repaired in v27.78
(`ls_redirect_mode`). Same root cause, one layer further out: **silence from the owner is still the
owner's answer** — the gate simply never read the claim.

### What the deployed procedure reads

One CTE over this table, then one boolean per engine — no ladder arithmetic in the consumer:

```sql
own AS (                                    -- GROUP BY is defensive only: verified 1:1,
  SELECT CAST(campaign_id AS STRING) AS cid,-- 93 rows over 93 distinct campaigns
         LOGICAL_OR(COALESCE(defer_launch_panel,  FALSE)) AS defer_launch_panel,
         LOGICAL_OR(COALESCE(defer_revival_panel, FALSE)) AS defer_revival_panel,
         LOGICAL_OR(COALESCE(defer_engine_panel,  FALSE)) AS defer_engine_panel,
         MAX(owner) AS owner_panel
  FROM `onyga-482313.OI.FACT_PANEL_OWNERSHIP` GROUP BY 1
)
...
CASE p.engine
  WHEN 'LAUNCH'    THEN COALESCE(o.defer_launch_panel,  FALSE)
  WHEN 'REVERDICT' THEN COALESCE(o.defer_revival_panel, FALSE)
  WHEN 'OOB'       THEN COALESCE(o.defer_engine_panel,  FALSE)
  WHEN 'LIFT'      THEN COALESCE(o.defer_engine_panel,  FALSE)
  ELSE FALSE
END AS claim_deferred
```

and in the verdict ladder, the collision arm first and the claim arm immediately under it:

```sql
WHEN r.n_instr > 1 AND r.own_rank > 1                       THEN 'EXCLUDE'  -- collision
WHEN r.lever IN ('BID', 'BUDGET') AND r.claim_deferred      THEN 'EXCLUDE'  -- claim
```

The reason the reader gets is written in plain words and names the owner:
`skipped — low stock owns this campaign today and chose not to brake its bid (nothing else may)`.

### The boundaries, every one deliberate

- **Money levers only.** `BID` and `BUDGET`. A claim is about money, so `NEGATE` is untouched — a
  wasteful search term stays blockable inside a low-stock family.
- **One boolean per consumer rank**, read straight off this table. Which rank evicts which panel
  stays a one-line edit in `V_PANEL_OWNERSHIP`, exactly as the consumers table above promises; the
  gate is a fifth consumer, not a second ladder.
- **The owner never defers to itself.** `LOW_STOCK` falls to the `ELSE`, and so does `COACH` —
  this arm does not defer the coach at all.
- **Fails open.** `COALESCE(defer_*, FALSE)`: a missing or stale ownership row can only ever fail
  to add an exclusion, never silence legitimate work. (5 of the 63 proposal campaigns had no
  ownership row on the day it shipped; they were untouched.) This is the one direction in which a
  stale snapshot now costs more than a skipped raise, which is why the freshness note below
  matters more than it used to.
- **Ordered after the collision arm**, so a genuine collision keeps its more specific reason.

### Measured on the deployed run

`T_ENGINE_PREFLIGHT`, judging the latest proposal partition (2026-08-17, 193 instructions). Every
claim on the board is `LOW_STOCK`:

| engine | lever | excluded **by the claim** | already excluded by a collision | left alone |
|---|---|---|---|---|
| LAUNCH | BID | 30 | 2 | 0 |
| OOB | BID | 3 | 6 | 0 |
| LIFT | BID | 1 | 2 | 0 |
| LIFT | BUDGET | 2 | 0 | 0 |
| LIFT + OOB | NEGATE | 0 | 0 | 4 (`GO`) |

36 money instructions excluded on the claim alone — instructions that had no counterpart from the
owner and would have passed a collision-only gate. The 4 negates are the money-lever boundary
working: they sit in claimed campaigns, carry `claim_deferred = TRUE`, and still ship.

## The hook (one line per ladder, three ladders — the `DEFER_OOB` shape)

⚠️ **Not yet applied.** The eight engine views are owned by the GROSS_PROFIT fix (Job A) in this
same batch. These hooks land after it, so the two changes never touch the same lines at once.

**1 — join** (next to the existing `V_CAMPAIGN_CAP_STATE` join in each view):

```sql
LEFT JOIN `onyga-482313.OI.FACT_PANEL_OWNERSHIP` po
       ON CAST(po.campaign_id AS STRING) = CAST(o.campaign_id AS STRING)
```

**2 — action ladder** (at the very TOP; structural ownership outranks every verdict, exactly as
`DEFER_OOB` does):

```sql
WHEN COALESCE(po.defer_engine_panel, FALSE) THEN po.defer_action
```

**3 — value ladder** (`suggested_bid` / `suggested_budget`), same predicate:

```sql
WHEN COALESCE(po.defer_engine_panel, FALSE) THEN NULL
```

**4 — reason ladder**, same predicate:

```sql
WHEN COALESCE(po.defer_engine_panel, FALSE) THEN po.defer_reason
```

Swap `defer_engine_panel` for `defer_revival_panel` in `V_PARK_REVERDICT` and for
`defer_launch_panel` in `V_LAUNCH_PHASE1` / `V_SB_LAUNCH_TARGET`.

Add `DEFER_LOW_STOCK` to each view's list of non-instructing actions wherever `DEFER_OOB` already
appears (the no-op guards in `V_KEYWORD_LIFT` enumerate them by name).

### Panel side

Read the `PanelOwnership` cube and render — decide nothing:

```ts
const own = await cubeLoadWithMeta({ dimensions: ['PanelOwnership.campaignId',
  'PanelOwnership.deferEnginePanel', 'PanelOwnership.deferAction', 'PanelOwnership.deferReason'] });
if (own.error) { /* degrade: show the panel without deferral marks */ }
```

Rows where `deferEnginePanel` is true render `deferAction` in the action column, an em dash in the
`→ $` column, and `deferReason` in the why column. No threshold, no arithmetic, no verdict and no
prose in TypeScript (`feedback_all_logic_in_backend`).

## Proof that no campaign can emit two contradictory instructions

1. **One row per campaign.** `V_PANEL_OWNERSHIP` is keyed on `campaign_id` over
   `V_DIM_CAMPAIGN_CURRENT` ENABLED — 108 rows, 108 distinct campaigns. `owner_rank` is a single
   `CASE` with mutually exclusive, ordered arms, so a campaign cannot carry two owners.
2. **One authority, one copy.** Every consumer reads the same `FACT_PANEL_OWNERSHIP` row. There is
   no second definition of the claim anywhere — not in another view, not in a cube, not in React.
   (This is the failure mode that produced the bug: `V_LOW_STOCK_ADS` and `V_OOB_BUDGET_PHASE` each
   knew their own membership and neither knew the other's.)
3. **The claim suppresses the value, not just the label.** The hook nulls `suggested_bid` /
   `suggested_budget` in the same predicate that sets the action. A deferred row has no number to
   contradict with — the same guarantee `DEFER_OOB` gives today.
4. **Deterministic.** `V_PANEL_OWNERSHIP` is byte-identical over two consecutive runs
   (109 lines incl. header, md5 `ac80b48c050332fb51f61e028e0f9f4f`, 2026-08-13). No `ANY_VALUE`
   pairing: every aggregate is a per-column `MIN`/`MAX` over values that are family-constant by
   construction, and no two aggregates are ever divided into one derived number
   (`fact_oi_any_value_pairing_nondeterminism`).
5. **Coverage is total.** Every ENABLED campaign gets a row and a rank; there is no "unowned"
   state that a panel could interpret for itself. `claim_rank = 99` means *no FULL claim* — an
   explicit answer, not a NULL.

## Planner doctrine — nothing hot reads the view

`V_PANEL_OWNERSHIP` reads `V_LOW_STOCK_ADS`, which drags the whole inventory chain
(`fam_state` → `fam_agg` → `asin_shares` → `V_SUPPLY_CHAIN_SUMMARY` → `V_PLAN_FORECAST`) plus a full
`FACT_AMAZON_ADS` target scan, and whose own header records that it sits **at** BigQuery's
query-planning ceiling. The engines are at that ceiling too
(`fact_oi_cube_table_planner_blowup`).

So: the **view is the definition**, `SP_SNAPSHOT_PANEL_OWNERSHIP` materialises it into
`FACT_PANEL_OWNERSHIP`, and every engine, cube and panel reads the **table** — the same doctrine as
`FACT_PARK_REVERDICT` and `FACT_KEYWORD_GUARD`.

**This is load-bearing, not tidiness.** The first cut of the view read the low-stock engine at two
grains (`row_kind='FAMILY'` for the verdict, `row_kind='CAMPAIGN'` for the lever). BigQuery inlines
CTEs, so that was two full expansions of a view already at the ceiling, and it failed outright:
*"Not enough resources for query planning — too many subqueries or query is too complex."* The
CAMPAIGN branch already carries the family verdict on every row, so the FAMILY read bought nothing
but a second expansion. **One read. Do not add a second.**

The cost of that choice: `stockout_date` / `next_arrival_date` are NULL on the CAMPAIGN branch, so
the reason strings quote cover days and not the dry date. The dry date stays one glance away on the
low-stock panel itself, which is where the full diagnosis belongs.

### Freshness

The claim's inputs all move once a day — `FACT_INVENTORY_SNAPSHOT` (daily load) and the ads anchor
(daily). A daily snapshot is therefore exactly as fresh as the evidence a claim could be taken on.

Stale-snapshot direction is safe, and worth stating precisely because a claim is a *silencer*:

- a stale **claim** (family recovered, snapshot still says CRITICAL) leaves a campaign deferred for
  up to one refresh cycle. Cost: the engines skip a raise for a day. Harmless.
- a stale **non-claim** (family just turned CRITICAL, snapshot not rebuilt) is the direction that
  matters, and it cannot outrun its own evidence — the snapshot is rebuilt in the same daily pass
  that loads the inventory and ads it depends on.

### Orchestration slot

`SP_SNAPSHOT_PANEL_OWNERSHIP` runs **after** `FACT_INVENTORY_SNAPSHOT` and the ads FACT load
(`V_LOW_STOCK_ADS` reads both) and **before** the engine `T_` builds in `SP_REFRESH_CUBE_TABLES`, so
the engines compile against the ownership of the run they are part of.

# HOLDOUT — the randomized trial that answers "is the engine worth anything?"

**Born:** 2026-08-19, v27.83. **Trial ids:** `HOLDOUT-2026Q4-CAMPAIGN` (trial 1, archived from
2026-10-05) and **`HOLDOUT-2026Q4-CAMPAIGN-T2` (trial 2, the live trial from 2026-10-05)**.
**Ori:** *"the main goal of ads is to make more total of dollars that we would do without the changes."*
**Ori, 2026-08-18:** *"start the holdout."* **Ori, 2026-10-04, on trial 2's list:** *"ok seed 5, deploy it."*

> **Status, from 2026-10-05: the live trial is trial 2, `HOLDOUT-2026Q4-CAMPAIGN-T2`** (§9).
> - **Size:** 59 campaigns, 12 of them controls.
> - **Dates:** the export gate binds from 2026-10-05. The window runs 2026-10-06 .. 2027-01-26. The
>   interim look is 2026-12-15 and the first readout 2027-02-09.
> - **Approval and deploy:** Ori approved the list on 2026-10-04, and the deploy is on 2026-10-05 by
>   `scripts/bigquery/migrations/2026-10-05_holdout_t2_deploy.sh`.
> - **Trial 1** (`HOLDOUT-2026Q4-CAMPAIGN`) is contaminated and archived from 2026-10-05. §0–§8 describe
>   trial 1 wherever a passage does not say trial 2. Its 69 rows are kept unchanged (§6 "Rulings
>   2026-10-03").
> - **How the engine is kept off a control:** every reader that does so reads `V_HOLDOUT_ARM` (the arm
>   that binds today, any trial). The readout and the board read the live trial from `V_HOLDOUT_TRIAL`.
> - **Plan:** `docs/superpowers/plans/2026-10-03-holdout-restart.md`.

---

## 0. The one-paragraph version

We randomly picked 14 of the 69 eligible campaigns and forbade the engine from touching them —
no bid, no budget, no negative — for 16 weeks. The other 55 run exactly as they do today. On
2027-01-05 we compare the two groups on net dollars. That comparison is the first honest answer
this account has ever had to "does the engine make money?". **It is also a blunt instrument: it
can only detect an effect bigger than about $2,261 per 14 days, which is larger than the entire
14-day net profit of the campaigns under test.** Read §7 before you read any number it produces.

**Trial 2, the live trial from 2026-10-05:** 12 of 59 campaigns are held out from 2026-10-06 for 16
weeks, and the two groups are compared on 2027-02-09. The MDE is about $2,089 per 14 days, the same
blunt instrument (§8 "Trial 2's readout", §9).

---

## 1. The estimand — what number are we actually after

> Over the trial window, how many more (or fewer) **total dollars of net profit**
> (`GROSS_PROFIT − Ads_cost`) did the **69 eligible campaigns** produce **because** the engine
> managed them, compared to what they would have produced if it had not?

Three things are load-bearing in that sentence:

- **Total dollars, not per-keyword dollars.** A sum of keyword-grain effects is *not* an
  account-level counterfactual even when the controls are good — it cannot see budget
  reallocation between keywords, cannibalization, or organic halo, which is most of what "total
  dollars" means to Ori.
- **The 69 eligible campaigns**, which is 76% of account ad spend and $26,377 per 28 days. Brand
  defense, Bunny and LolliBall are outside the estimand *in both arms*. Anything the readout says
  is silent about them.
- **Net profit, not ROAS.** `GROSS_PROFIT` is read from `FACT_AMAZON_ADS`, never recomputed
  (THE GP RULE, see `V_CHANGE_SCORECARD`).

---

## 2. Why difference-in-differences failed here — the numbers, not the theory

Before building this, we tried to answer the question observationally with matched DiD on the
existing data. It does not work on this account, and the failure is not marginal.

| Test | Result |
|---|---|
| **Selection placebo** — emulate the engine's own selection (rank keywords by trailing-14d dollars), then change **nothing** | **+$1,505 .. +$2,445** on the losers arm (**+3.9 .. +7.1 sd**), **−$1,094 .. −$1,829** on the winners arm, over four independent no-upload dates |
| The account's true 14-day net over the same period | about **−$2,500 .. −$2,730** |
| So the artifact is | **~90% of the entire quantity being measured** |
| Share of active keywords touched by the engine | **73.5%** |
| Share of ad dollars touched | **85.1%** |
| Clean untouched pool clearing 10 clicks in *both* windows | **7 keywords / $819** — against **379 treated / $29,326** |
| Matching success for treated keywords | fails for **98.1%** |
| Untouched keywords not even present in `FACT_KEYWORD_STATE` | **120 of 161** |
| Why the untouched arm is untouched | **because it is dying** — −83% clicks over the window |

The last row is the whole problem. There is no natural control group to find, because "untouched"
is not a random condition on this account — it is a symptom. **So we create one by randomization.**

For contrast, the placebo bias under this design's stratified random assignment is
**−$72 to +$35 per 14 days**. That is the difference between an instrument and a mirror.

---

## 3. The randomization unit — the campaign, and why not the keyword

**This is the decisive design constraint, and Ori's own doctrine already contains it.** The
low-stock engine states: *"in a CAPPED campaign the budget is spent regardless, so removing a
target does not return money — it RE-ROUTES it to the neighbours."*

Therefore **keyword-level randomization is invalid inside a budget-capped campaign.** Holding out
keyword A hands A's forgone impressions and budget to its **treated** neighbours in the same
campaign. The arms interfere, the treated arm is flattered, and the trial measures reallocation
as if it were skill. That is a SUTVA violation — interference between units.

| unit | n | $/28d | interference | MDE /14d | verdict |
|---|---|---|---|---|---|
| keyword, uncapped campaigns only | 182 | $13,382 | **MEDIUM-HIGH and understated.** Only 37 campaigns are *truly* never-capped (126 keywords / $7,338), and none of the top-3 spenders are among them — the arm measures the money the engine cares least about. Even inside a genuinely uncapped campaign the arms still share an ad group, an auction, a portfolio pot and an organic halo. And it cannot see reallocation between keywords at all. | $1,325 | **rejected — invalid** |
| **campaign cluster** | **69** | **$26,377** | **LOW-MEDIUM.** Zero within-campaign spillover by construction. What remains is cross-campaign: the BASE/GROWTH portfolio pot, organic halo between variations of one family, and our own campaigns bidding the same term. Strata balance the arms on these; they do not make them independent. | **$2,261** | **CHOSEN** |
| family cluster | 5 | $26,377 | LOWEST — absorbs portfolio reallocation and organic halo inside the unit. | $4,211 | rejected — statistically dead: 5 clusters, 3 df, a 4.82× multiplier, and a 20% share means holding out exactly **one** family (Lollibox alone is 28% of account dollars). MDE = 32% of the spend under test. |
| hybrid (cluster the capped, randomize keywords in the uncapped) | 203 | $26,377 | MEDIUM | $2,328 | rejected — the variances **add**, landing *worse* than pure clustering while inheriting the keyword arm's residual interference and doubling the analysis surface. It buys nothing. |

Campaign clustering also matches the question: a whole-campaign arm **captures** reallocation
between its keywords instead of being fooled by it.

---

## 4. The objects

| object | role |
|---|---|
| `V_HOLDOUT_ELIGIBLE` | Who may enter, and the frozen facts the randomization blocks on. **One consumer only** (`SP_ASSIGN_HOLDOUT`) — it reads `V_CAMPAIGN_CAP_STATE` and `V_LAUNCH_POPULATION`, so nothing hot may touch it. From 2026-10-05 its stock literal is trial 2's (below). |
| `DE_HOLDOUT_ASSIGNMENT` | **The arms.** One row per unit, written once, never updated. Carries `trial_id`: trial 1's 69 rows and trial 2's founding 59, plus trial 2's late arrivals. |
| `DE_HOLDOUT_TRIAL` | (trial 2) **Which trial is live.** It is append-only, with one row per event, `OPENED` or `ARCHIVED`. A trial is archived by appending a row, never by editing its assignment rows. Trial 1 has a back-filled `OPENED` row (its v27.83 constants) and an `ARCHIVED` row effective 2026-10-05 that states its contamination. Trial 2's `OPENED` row carries its seed, dates, `t_mult`, MDE and Ori's words. |
| `V_HOLDOUT_TRIAL` | (trial 2) One row per trial: `gate_from`, `gate_to` = `LEAST(win_end, archived_from − 1)`, `win_start`, `win_end`, `interim_look`, `first_readout`, `is_live`, `status_today`. Exactly one trial is live. The readout, the board and `SP_ASSIGN_HOLDOUT` read that row. |
| `V_HOLDOUT_ARM` | (trial 2) **The gate: the arm that binds today, any trial.** One row per control campaign whose arm binds today or later: `campaign_id`, `gate_from`, `gate_to`, `trial_id`. Every reader that keeps the engine off a control reads it. A hold ends on its trial's last day, and a trial-1 control that trial 2 drew as TREATED is released on 2026-10-05. **A trial with no `OPENED` row is invisible to it**, so an empty registry empties the gate, and the board then reads RED ("no HOLDOUT unit"). |
| `DE_HOLDOUT_BASELINE` | (trial 2, amendment 2026-10-04) Append-only. Each founding control's value, at the assignment, of the settings no source can date: placement and shopper-cohort bid adjustments, and SB product targets' bid and state (§6 "What the alarm sees"). Written once by the founding script, for the founding controls only. A late arrival gets no row and is unwatched on these settings (§6, kind 4). The script records only **present** settings: a row counts only when its source table's latest sync re-stamped it and it is not flagged deleted (§6, kind 4). A later row carries Ori's ruling on a difference. Its value is NULL when he rules that a setting is gone. Read by `holdout_unit_changed`. |
| `SP_ASSIGN_HOLDOUT` | Assigns unassigned eligible units. Append-only, idempotent. Orchestrator **Task 20.55**, before the proposal snapshot. From 2026-10-05 it writes into **the live trial only, and late arrivals only**. A founding cohort is written once from the approved list, never by this procedure, and it writes nothing into a trial that has no founding rows. |
| `SP_ENGINE_PREFLIGHT` | The gate. A **third** exclusion source beside collision and claim: `HOLDOUT`, covering **all** levers. Verdict `EXCLUDE`. Reads `V_HOLDOUT_ARM` (the arm that binds today, any trial), between `gate_from` and `gate_to`. |
| the other gate readers | `V_PLAN_WINDOW_JUDGMENT`, `V_FAMILY_SEAT_REGISTER` and the three bulksheet generators and the weekly book's mend (`build_weekly_book.py` `MEND_SQL`, added 2026-10-04) (`build_reprice_bulksheet.py`, `build_seasonal_unpause_bulksheet.py`, `build_seat_moves_bulksheet.py`) read `V_HOLDOUT_ARM` (the arm that binds today, any trial). Their `eligible_from` is the arm's `gate_from`. Their snapshots `T_FAMILY_SEAT_REGISTER` and `FACT_PLAN_NEXT_WEEK` follow on the next rebuild. |
| `V_HOLDOUT_READOUT` | The answer, for **the live trial** (read from `V_HOLDOUT_TRIAL`). It is silent until that trial's `first_readout`: 2027-01-05 for trial 1, **2027-02-09 for trial 2**. From v27.162 it also publishes one `CENSORED` row per censored unit and one `PRE_WINDOW_CHANGE` row per HOLDOUT unit changed between its assignment and its window start (dates and the reason, never a dollar) — §6 "Contamination". Trial 1's record is reproduced with `HOLDOUT_INTEGRITY_acceptance.sql`'s `led` and `pre` statements and trial 1's constants. |
| `V_ENGINE_HEALTH` `holdout_unit_changed` | v27.162: RED when a HOLDOUT campaign changed inside its window and the readout does not censor it and its stratum-mates from that day, or changed before its window and the readout does not publish it; AMBER while a change before the window stands unruled — §6 "Contamination". **From 2026-10-05** it reads the live trial and adds two terms. The **touch alarm** is RED for 7 Los Angeles days after any touch on a control, then AMBER. **Feed liveness** is RED when a feed is more than 36 hours old. §6 "What the alarm sees". |
| `V_ENGINE_HEALTH` `seat_holdout_row_on_sheet` | A seat-book row naming a control built while its arm binds (between `gate_from` and `gate_to` of `V_HOLDOUT_ARM`). |

### The eligible population — 69 campaigns, $26,377 / 28d

| exclusion | n | status |
|---|---|---|
| not ENABLED / not serving | — | applied |
| zero ad spend in 28 days (enabled but dormant — a budget line and no outcome) | 3 | applied |
| brand defense ($764/28d — doctrine already forbids the engine moving their bids, so they are untreated in **both** arms and add only noise) | 7 | applied |
| CRITICAL-stock families **Bunny** (21.7d cover) and **LolliBall** (33.7d) — $5,496/28d. Holding these out costs **inventory**, not dollars: a holdout campaign cannot be throttled when the family runs dry. | 14 | applied |
| forecast-THROTTLE families (Fresh, LolliME, Lollibox) | 63 | **considered and rejected** — excluding them removes $25,192 of the $32,637 base and leaves 6 campaigns. There is no trial left. See the censoring rule in §6. |
| launch-phase campaigns (`V_LAUNCH_POPULATION`) | 52 | **considered and rejected** — 52 of 69 and 33.1% of eligible dollars; excluding them leaves 17 clusters and kills cluster randomization. Mitigation: launch status is a **stratum**, frozen at assignment (intention-to-treat), so a campaign the launch controller promotes out mid-trial stays in its original stratum and arm. |

The Bunny/LolliBall list is a **frozen literal** in the view, on purpose. Reading a live
`risk_state` would (a) drag `V_LOW_STOCK_ADS` — at BigQuery's planning ceiling — into the plan,
and (b) let the trial's *population* drift with performance, which is a selection artifact of
exactly the kind this design exists to kill.

**Trial 2's literal is `('LolliBall')`.** The same four rules were re-applied on trial 2's design date,
2026-10-03, and the stock rule was re-graded that day:
- LolliBall is CRITICAL (21.6 days of binding cover) and stays out.
- Bunny is OK (159.4 days, with 6,000 units arriving 10-07), so it is in.

That gives 59 campaigns, $30,114 per 28 days, in five families (Bottle, Bunny, Fresh, LolliME, Lollibox).
The literal stays frozen for the same reason as before.

---

## 5. The randomization, reproducible from the stored columns alone

```
stratum        = channel | CAP/UNC | LNC/GRD            (frozen at assignment; 8 cells)
seq_in_stratum = 0-based rank in stratum by spend_28d DESC, campaign_id
                 CONTINUED as later units arrive — never recomputed
offset         = MOD(ABS(FARM_FINGERPRINT(seed || '|' || stratum)), 5)
arm            = HOLDOUT iff MOD(seq_in_stratum + offset, 5) = 0, else TREATED
seed           = 'OI-HOLDOUT-v1|14'
```

Systematic **1-in-5 inside a size-ordered block**. Size — the dominant variance driver, since the
top-1 campaign is 11.2% and the top-10 are 54.5% of eligible dollars — is blocked *implicitly*,
because every consecutive run of five is a run of neighbours in spend. A full five-way cross of
the design's named strata on 69 units would have been almost all singletons, and a singleton
stratum is not a block, it is a coin flip with extra steps.

**The seed was chosen by pre-declared rerandomization** (Morgan & Rubin). The rule was written
down before the draws were inspected: search `seed_index = 0, 1, 2, …` and take the **first** that
satisfies all three criteria, each taken from the design document:

- **A1** exactly **14** holdout campaigns (the design's 20% of 69);
- **A2** holdout share of eligible 28-day ad dollars inside **[0.18, 0.22]**;
- **A3** **all five** eligible families present in the holdout arm (family is a stratum precisely
  to control organic halo).

`seed_index = 14` is the first pass. 6 and 8 give 15 holdouts; 10 covers only 4 families; the rest
miss the dollar band. **The acceptance region is part of the design** — the permutation inference
in §8 must permute only over assignments that would also have been accepted.

### Realized balance, 2026-08-19

| | HOLDOUT | TREATED |
|---|---|---|
| campaigns | **14** | **55** |
| ad spend, 28d | **$5,135** (19.5%) | **$21,242** |
| gross profit, 28d | $4,865 | $18,936 |
| **net, 28d** | **−$270** | **−$2,306** |
| SB | 4 (29%) | 20 (36%) |
| capped (`is_oob_owned`) | 4 (29%) | 17 (31%) |
| launch population | 11 (79%) | 41 (75%) |
| families represented | 5 of 5 | 5 of 5 |

The pre-trial net difference is real and is **chance**: the holdout arm ran at −$0.053 of net per
ad dollar and the treated arm at −$0.110, worth about **$146 per 14 days**, ~6% of the MDE.
`V_HOLDOUT_READOUT` publishes the pre-period for both arms and reports a **change-score** estimate
alongside the raw one for exactly this reason.

### Trial 2's draw (computed 2026-10-03, approved by Ori 2026-10-04)

The same method, declared before it ran. Only the seed prefix changes, along with the two criteria that
scale with the population:

```
stratum        = channel | CAP/UNC | LNC/GRD                     (frozen at the draw)
seq_in_stratum = 0-based rank in stratum by spend_28d DESC, campaign_id   (fresh for trial 2;
                 CONTINUED by late arrivals, never recomputed)
offset         = MOD(ABS(FARM_FINGERPRINT(seed || '|' || stratum)), 5)
arm            = HOLDOUT iff MOD(seq_in_stratum + offset, 5) = 0, else TREATED
seed           = 'OI-HOLDOUT-v2|' || seed_index, the FIRST seed_index = 0, 1, 2, … passing:
  A1  exactly ROUND(N / 5) controls          (trial 2: 12 = ROUND(59 / 5))
  A2  control share of eligible 28-day ad dollars in [0.18, 0.22]
  A3  every eligible family present among the controls (five)
```

- **The result is `seed_index = 5`** (`OI-HOLDOUT-v2|5`), the first pass. Indices 0–4 fail:
  - 0 gives 14 controls;
  - 1 gives 12 controls at 16.1%;
  - 2 gives 11 controls;
  - 3 gives 11 controls at 24.4%;
  - 4 gives 14 controls covering 4 families.
- **The acceptance region** is 18,190 of the 390,625 offset vectors (4.66%). The permutation inference
  of §8 permutes inside it.
- **The founding cohort is written once, from the literal list Ori approved, and never re-drawn live.**
  - The population reads live views, which cannot be pinned to the design date.
  - Its fingerprint is `4171456845817687166`, over `unit_id|arm|stratum|seq` ordered by `unit_id`.
  - Each row's `assignment_rule` starts `FOUNDING (approved list)`.
- **Late arrivals.** `SP_ASSIGN_HOLDOUT` assigns campaigns that become eligible after 2026-10-03, on
  first sight, by the same seed, with `seq_in_stratum` continuing the stratum's count. Their
  `assignment_rule` starts `LATE ARRIVAL (first sight)`.
- **Realized balance**, controls against treated:
  - 12 against 47 campaigns;
  - 21.01% against 78.99% of the 28-day ad dollars;
  - net per ad dollar −0.141 against −0.120, a gap worth about $68 per 14 days;
  - five families each.

  The full table and the 59-row draw are in the plan, §3.

---

## 6. The frozen-arm rule, and what invalidates the trial

**ASSIGNMENT IS FROZEN FOREVER.** A row in `DE_HOLDOUT_ASSIGNMENT` is written once and is never
updated and never deleted. `SP_ASSIGN_HOLDOUT` contains no `UPDATE`, no `DELETE`, no
`MERGE … WHEN MATCHED` and no `CREATE OR REPLACE TABLE` — its only write is one append-only
`INSERT` anti-joined by equality against the rows already there. New eligible campaigns are
assigned on **first sight**; their `seq_in_stratum` *continues* the stratum's sequence rather than
recomputing it, because a daily recompute would re-rank every unit the moment one campaign's spend
moved and swap arms wholesale.

### These invalidate the trial

1. **`UPDATE` or `DELETE` on `DE_HOLDOUT_ASSIGNMENT`.** Re-randomizing after outcomes exist is not
   a fix for an unlucky draw; it is the manufacture of the result you wanted.
2. **Hand-uploading a bid, budget or negative to a HOLDOUT campaign.** The holdout arm's entire
   contract is that no instruction reaches it — from the engine *or* from a person. One upload and
   that unit is contaminated permanently.
3. **Deliberately moving budget between the arms.** That makes the arms trade with each other and
   the difference stops being an effect.
4. **Pulling a holdout unit out mid-trial** for a reason correlated with its performance or its
   stock. That is a treatment-correlated dropout and it reintroduces the exact selection artifact
   of §2. Use the censoring rule below instead.
5. **Pinning a holdout campaign's bids to a fixed value.** "Holdout" means the engine emits no row
   for that campaign — *not* that its values are frozen. Pinning is itself an intervention and
   would measure "engine vs frozen", not "engine vs status quo". Amazon's own placement adjustments
   and auto-bidding keep running in both arms; that is a shared confounder and is fine.

### The censoring rule — PRE-COMMITTED NOW, IN WRITING

Bunny and LolliBall are CRITICAL today and are already out. Fresh, LolliME and Lollibox are all
forecast-THROTTLE and could grade to CRITICAL during Q4.

> **If a family enters ACTUAL CRITICAL during the trial, it is censored from BOTH arms from that
> date forward, symmetrically across strata, and the readout reports the truncated window.**

Never pull only the holdout campaign. Never pull only the treated one.

### Contamination — the rule as built (R9, ruled 2026-10-02, built v27.162 on 2026-10-03)

**Ori, 2026-10-02 (R9, option (a); spec P-23):** he paused BOX-SP/PHRASE (teen-girl-birthday-gift,
White) `75834491759416` and BOX-VIDEO/COMPETE (Copycat, Blue) `76054744633802` himself on
2026-09-27 — both HOLDOUT, both Lollibox, in the same console batch as three campaigns outside the
trial's HOLDOUT arm. Neither pause has a change-log row; the observed-change ledger
(`FACT_PPC_CHANGE_LOG` source `OBSERVED`, from the DIM SCD2 trail) records both. Rule #2 above makes
both units contaminated permanently, and the ruling is to censor them **and their stratum-mates, in
both arms, from the day of the contamination**, so the comparison inside each stratum stays fair.

**The rule `V_HOLDOUT_READOUT` applies (and publishes):**

- `contaminated_on` (per HOLDOUT unit) = the Los Angeles day of the first change on it inside
  `[eligible_from, trial_end]` that the change log records as applied (`V_PPC_CHANGE_LOG_APPLIED`) or
  the observed-change ledger records as seen on Amazon. A logged change and its observed landing are
  both read; the earlier day counts. An SB keyword's observed instant is the sync that first saw it,
  up to a day late, so an SB keyword contamination can be dated one day late.
- `censored_from` (per unit, both arms) = the earliest `contaminated_on` in the unit's stratum. From
  that day the unit's dollars and proposals leave the estimate; it is rated on its own days before
  it.
- One `CENSORED` row per censored unit names the unit, its arm and stratum, both dates and the change
  that triggered the stratum. The ALL row's sentence (from the trial's first readout) says how many
  units were cut.
- **Changes before the window are not censored** (the window, and R9, start on `eligible_from`).
  One `PRE_WINDOW_CHANGE` row per HOLDOUT unit changed from its assignment day (Los Angeles) to the
  day before its `eligible_from` names the changes day by day (logged and observed rows counted
  apart), the days the estimate scores it as untouched, and no number; the ALL row's sentence says
  how many there are. Whether such a change contaminates the unit is **a ruling for Ori** (below).
- `V_ENGINE_HEALTH` `holdout_unit_changed` reads those rows (never re-derives them) and is RED when a
  change on a HOLDOUT unit, or on a stratum-mate's HOLDOUT unit, is not censored from its day, or
  when a HOLDOUT unit changed before its window and the readout does not publish it from that day;
  RED as well when no HOLDOUT unit or no observed-change row is read; AMBER while any change before
  the window stands, until Ori rules. `SP_RECORD_OBSERVED_CHANGES` (Refresh Task 2.2a) records a
  console change the night it reaches the DIM tables, and the readout censors it on that read; the
  check holds the readout to it. Acceptance with negative controls:
  `scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql` (H1 the censoring and the pre-window
  rows, H2 the check, H3 the readout's gate).

**What the ledger shows inside the window — more than the two pauses (measured 2026-10-03; the
query is the acceptance's `led` statement).** The ledger holds 25 changes on **8 of the 14 HOLDOUT
units inside the window** (from 2026-09-01), every one an observed change with no log row behind it.
This is not every change since the arms were frozen: 7 HOLDOUT units also changed between the
assignment and the window start (next table), so **10 of the 14 HOLDOUT units changed since the
assignment**.

| HOLDOUT campaign | stratum | first change (LA day) | changes |
|---|---|---|---|
| BOX-SP/BROAD (Hunter, Gift for Girl) `200171414843593` | SP\|CAP\|GRD | 2026-09-10 | 3 bid |
| BOX-SP/AUTO (White) `488973733209950` | SP\|UNC\|GRD | 2026-09-10 | 3 bid, 1 keyword pause, 2 budget (30 → 80 → 50 on 09-16) |
| ME-SP/BROAD (Mint, journaling kit for g) `190387447939462` | SP\|CAP\|LNC | 2026-09-11 | 1 bid |
| BOX-SP/BROAD- gifts for girls 10-12 `350259814389755` | SP\|CAP\|LNC | 2026-09-11 | 2 bid |
| BOTTLE-SP/AUTO `279837860088128` | SP\|UNC\|LNC | 2026-09-11 | 3 bid |
| FRESH-VIDEO/ BROAD `446868628489343` | SB\|UNC\|GRD | 2026-09-27 | 8 bid (one SB sync) |
| BOX-SP/PHRASE (teen-girl-birthday-gift, White) `75834491759416` | SP\|UNC\|LNC | 2026-09-27 | campaign pause (Ori, confirmed) |
| BOX-VIDEO/COMPETE (Copycat, Blue) `76054744633802` | SB\|UNC\|LNC | 2026-09-27 | campaign pause (Ori, confirmed) |

So the rule, as ruled (changes inside the window), censors 6 of the 7 strata that hold a HOLDOUT
unit: **61 of 69 units — 13 of 14 HOLDOUT, 48 of 55 TREATED** — each keeping 9 observed days
(censored from 09-10) to 26 (from 09-27). Only SB|CAP|LNC (1 HOLDOUT, 5 TREATED) and SB|CAP|GRD (no
HOLDOUT, 2 TREATED) are untouched. **Ori has confirmed the two pauses only; the other six units'
changes are unconfirmed, and what the trial is worth with this censoring is a decision for Ori, not
for the readout.** No dollar of the estimate was read to measure this: the estimate path was run for
unit counts and observed days only.

**Changes between the assignment and the window start — NOT censored, a ruling for Ori (measured
2026-10-03, review of commit a2e7e1e; the query is the acceptance's `pre` statement, which is the
`led` statement with its lower bound at the assignment day, 2026-08-19).** The arms were frozen on
2026-08-19 (`assigned_at`); the window, R9's censoring and `SP_ENGINE_PREFLIGHT`'s HOLDOUT arm all
start on 2026-09-01. The ledger holds 25 rows on **7 HOLDOUT units** in between (counts are ledger
rows; a logged change and the observed row confirming it are two rows):

| HOLDOUT campaign | stratum | changes before 2026-09-01 (LA day) | change inside the window? |
|---|---|---|---|
| FRESH-SP/PT (Competitors, Blue, A1) `135553284530895` | SP\|UNC\|LNC | 08-21 CAMPAIGN_PAUSE: 1 logged (`stop-20260821-135553284530895`, MANUAL), 1 observed confirming it | no |
| PILOT-WHITE-PHRASE-birthday-gifts `39989090923480` | SP\|UNC\|LNC | 08-21 CAMPAIGN_PAUSE: 1 logged (`stop-20260821-39989090923480`, MANUAL), 1 observed confirming it | no |
| BOTTLE-SP/AUTO `279837860088128` | SP\|UNC\|LNC | 08-23 REDUCE_BID ×2, reprice book `reprice_book_20260823_1527`, logged and observed | yes, from 09-11 |
| FRESH-VIDEO/ BROAD `446868628489343` | SB\|UNC\|GRD | 08-23 INCREASE_BID ×3, the same reprice book, logged and observed | yes, from 09-27 |
| BOX-SP/PHRASE (teen-girl-birthday-gift, White) `75834491759416` | SP\|UNC\|LNC | 08-23 INCREASE_BID ×1, the same reprice book, logged and observed | yes, from 09-27 |
| BOX-SP/BROAD (Hunter, Gift for Girl) `200171414843593` | SP\|CAP\|GRD | 08-25 REDUCE_BID ×1, observed, not logged | yes, from 09-10 |
| BOX-SP/AUTO (White) `488973733209950` | SP\|UNC\|GRD | 08-26 bid ×5, 08-31 bid ×2 and budget ×1, observed, not logged | yes, from 09-10 |

The two 08-21 pauses are still in force: `V_DIM_CAMPAIGN_CURRENT` reads both campaigns PAUSED
(serving status CAMPAIGN_PAUSED), `effective_from` 2026-08-21T11:21:01 (read 2026-10-03; the full
name of the second is PILOT-WHITE-PHRASE-birthday-gifts-for-g (tween-girl-birthday-gift, White)).
Neither campaign has a change inside the
window, so neither is a contaminated unit under R9; their stratum SP|UNC|LNC is censored from 09-11
for another unit, and the estimate scores both as untouched HOLDOUT units for 09-01..09-10.

§6 #2 says one upload contaminates a unit permanently; the plan's R9 rule reads "after
`eligible_from`". The two disagree on these seven units, so the readout publishes them as
`PRE_WINDOW_CHANGE` rows and the board reads AMBER until Ori rules. **The two answers, measured on the
strata (the same ledger, no dollar read):**

- **(a) as built — count changes inside the window only.** 61 of 69 units censored, as above; the
  seven units' days from 09-01 to their stratum's censoring are scored as untouched.
- **(b) count changes from the assignment day** (`censored_from = GREATEST(first change since
  assignment, eligible_from)`): SP|UNC|LNC, SP|UNC|GRD, SP|CAP|GRD and SB|UNC|GRD are censored from
  09-01 and drop out of the estimate — **43 units, 9 HOLDOUT and 34 TREATED** — leaving **26 units,
  5 HOLDOUT and 21 TREATED**: SP|CAP|LNC censored from 09-11, SB|UNC|LNC from 09-27, SB|CAP|LNC and
  SB|CAP|GRD untouched.

Either ruling changes `V_HOLDOUT_READOUT` and `holdout_unit_changed` (for (a), the AMBER becomes a
recorded ruling; for (b), the PRE_WINDOW_CHANGE days censor), and the acceptance with them.

### If the BASE/GROWTH reorg has not landed by Sep 1

Doctrine puts the reorg at **Sep 15–30** with a **+$70.64/day** shift, and the $20.01–31.99 budget
band is FORBIDDEN. A structural migration landing mid-trial is a **differential** shock if it
touches one arm more than the other. Either move `eligible_from`, `trial_end` (in
`SP_ASSIGN_HOLDOUT`) and the matching constants in `V_HOLDOUT_READOUT` **together**, or exclude
any campaign the reorg relocates from **both** arms.

### The engine is a moving target

`v27.48` is flagged DEPLOYED UNVERIFIED, the season-context ledger has 2 decisions pending, and
the intent campaign grid has a legacy double-bid outstanding. Every coacher change during the trial
changes what "treatment" *means*. Either freeze coacher logic for the 16 weeks, or state plainly in
the readout that **the treatment is a moving policy** and the result is "the engine as it evolved
over 16 weeks", not a fixed policy. This is a decision Ori must make; the trial does not make it.

### Rulings 2026-10-03 — the trial restarts (Ori; answers to the piece-1 follow-up questions)

1. **The holdout trial restarts (option (c)).**
   - The window restarts on **2026-10-06** with a **fresh draw by the same method** (§5).
   - Trial 1 stays on record, archived, with its contamination stated below. Its 69 rows in
     `DE_HOLDOUT_ASSIGNMENT` are never updated or deleted (#1 above). A trial is archived by appending a
     row to a registry, never by editing its rows.
   - The safeguard for trial 2 is `V_ENGINE_HEALTH` `holdout_unit_changed`, which must turn the brief RED
     the night a control campaign is touched. **As built (v27.162) it does not.** Read on 2026-10-03, it
     was **AMBER, measured 0**, while its own detail listed 8 of 14 controls changed inside the window,
     among them Ori's two 09-27 pauses.
   - The reason: it turns RED only when `V_HOLDOUT_READOUT` *fails* to censor a change, and the readout
     censors from the same ledger on the same read. The restart adds a touch term: RED for 7 days after
     any change on a control, then AMBER. It also adds a feed-liveness term. Plan §2.7.
   - **Widened before the deploy** (pre-deploy review of 2026-10-03, amendment of 2026-10-04):
     - the touch term also reads changes the ledger does not record, wherever a source carries them;
     - feed liveness watches every path and source table on its own;
     - what no source can see is stated below, under "What the alarm sees".
2. **A seated keyword that later becomes a probe keeps the question it was seated with.**
   - This is a money-plan ruling, recorded here because it came in the same reply.
   - It confirms piece-1 follow-up G1 (builder v27.168): the incumbent is costed by its kept
     `request_basis`, and tonight's `is_probe` still decides the move.
   - Spec P-30, beside P-16 and P-25 in `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md`.
3. **Ori believes he made no change on Amazon since 2026-09-27, and the observed-change feed shows none.**
   The record and Ori agree, and the feed is alive, not stalled. Read on 2026-10-03 at about 16:00 UTC
   (queries in the plan, Appendix A):
   - the ledger's latest `OBSERVED` row is 2026-09-28 04:11 UTC, the 09-27 Los Angeles evening batch
     with the two pauses and the FRESH-VIDEO/ BROAD SB sync;
   - the latest change-log row is 2026-08-25 21:44 UTC. It belongs to batch `weekly_book_20260825_214435`,
     which is still `PENDING_UPLOAD` and was never uploaded. The latest logged change that was *applied*
     is 2026-08-24 17:28 UTC (`seasonal_unpause_20260824_1728`; wording corrected 2026-10-04);
   - the keyword mirror `V_SRC_AmazonAds_keyword` synced at 2026-10-03 11:09 UTC, and all 34,037
     keywords in it carry the bid and state of their current `DIM_KEYWORD` version;
   - since 09-27, `SP_LOAD_DIM_KEYWORD` and `SP_LOAD_DIM_CAMPAIGN` each logged 21 OK runs, and
     `SP_RECORD_OBSERVED_CHANGES` ran OK on every pass from 10-02;
   - `DIM_KEYWORD`'s newest version stays at 09-28 only because SCD2 writes a version on a change.

**Trial 1, archived: the record.** These numbers are measured above in this section ("Contamination"),
and no estimate was ever read.
- The arms were frozen on 2026-08-19 and bound from 2026-09-01. They are archived from 2026-10-05.
- **10 of the 14 HOLDOUT campaigns changed on Amazon after the assignment**: 7 before the window
  (25 ledger rows) and 8 inside it (25 observed rows, none logged), 5 of them in both.
- Under R9 as built, the readout censors **61 of 69 units** (13 of 14 HOLDOUT, 48 of 55 TREATED).
- 4 of the 14 controls are paused today: the 08-21 pauses of 135553284530895 and 39989090923480, and
  Ori's 09-27 pauses of 75834491759416 and 76054744633802.
- The 69 rows' fingerprint on 2026-10-03 was `7298956708089075507`, over every column ordered by
  `unit_id`. Restart check K2 holds it. The pre-window ruling question (a)/(b) above is moot for trial 1.

**What the restart fixes beyond the alarm (found 2026-10-03):**
- Every reader that keeps the engine off a control reads `DE_HOLDOUT_ASSIGNMENT` directly and takes the
  **union of all trials' HOLDOUT rows**: `SP_ENGINE_PREFLIGHT`, `V_PLAN_WINDOW_JUDGMENT`,
  `V_FAMILY_SEAT_REGISTER`, `V_ENGINE_HEALTH` c18 and the three bulksheet generators. All but the
  preflight apply **no end date** at all.
- Appended as-is, trial 2's rows would leave all 14 trial-1 controls frozen beside trial 2's 12.
- They all switch to one view of the arm that binds today (plan §1, §2.1).

### What the alarm sees, and what it cannot see (trial 2, from 2026-10-05)

**R9 is unchanged.** The readout censors only what `FACT_PPC_CHANGE_LOG` records (an applied logged
change, or an observed one), inside the window (Ori, 2026-10-02). **The alarm sees more than R9 censors.** `holdout_unit_changed` reads the live
trial's controls from their assignment day. It is RED for 7 Los Angeles days after any of the following,
then AMBER for as long as any control was ever touched, and it names each one:

1. **A ledger change** (`FACT_PPC_CHANGE_LOG`, logged or observed):
   - a keyword or product-target bid or state;
   - a campaign budget or state;
   - an ad-group default bid or state.

   R9 censors one inside the window. One on 2026-10-05 is published as `PRE_WINDOW_CHANGE`.
2. **A new keyword, product target or ad group on a control.** The source is the entity's first version
   in `DIM_KEYWORD` or `DIM_AD_GROUP`. The ledger never counts a creation.
3. **A portfolio move, a bidding-strategy change, or a campaign end date.**
   - SP: `DIM_CAMPAIGN` versions on `portfolio_id` and `bidding_strategy`.
   - SB: the `bid_optimization` settings in Fivetran's `sb_campaign_history`.
   - SP and SB: an **end date** set, moved or cleared by hand: `end_date` on version pairs of Fivetran's
     `campaign_history` (SP) and `sb_campaign_history` (SB). An end date stops a control serving, and the
     ledger records only budget and state, so before 2026-10-04 the board stayed GREEN on it. Measured
     2026-01-01 .. 2026-10-04: 2 such edits account-wide (SP, August), one of them on T2 control
     `51727823265377` MINT-SP/BROAD (Back to School), end 2026-09-28 -> none on 08-09; 0 on SB.
   - **Not watched, on purpose:** `start_date` (Amazon rewrote it on 16 SP and several SB campaigns in
     May 2026, 05-12 -> 05-09, with no human touch: a false RED) and SB
     `rule_based_budget_applicable_rule_id` (it flips monthly by itself).
4. **A placement or shopper-cohort bid adjustment, or an SB product target's bid or state, that differs
   from its value at the assignment.**
   - These sources have no history and no date, so a change is visible only against
     `DE_HOLDOUT_BASELINE`.
   - **A row in these tables is not necessarily a live setting.** A Fivetran sync re-stamps only the
     rows Amazon still returns. A removed adjustment keeps its old row and its old stamp, and the
     three adjustment tables have no `_fivetran_deleted` flag to mark it. The SP table holds no 0%
     row, so an SP adjustment set to 0% most likely disappears the same way.
   - Measured 2026-10-04: 14 of the 195 SP placement rows were last stamped between 2026-03-17 and
     08-14, on 13 campaigns that have no re-stamped row. Two of them are control ME-COMPETE
     `365568042533669`'s top-of-search 30% and product-page 15%, stamped 2026-06-23. These are almost
     certainly adjustments removed months ago.
   - **So a setting counts only when its row was re-stamped by its table's latest sync** (within one
     hour of that table's newest stamp) and is not flagged deleted. The baseline, the board and the
     restart check K12 all use this one rule. A removed adjustment then shows as a difference. A stale
     row that Fivetran later drops changes nothing, because it was already absent.
   - By that rule, 7 of the 12 controls carry placement rows, 6 of them with a non-zero adjustment.
     1 carries a shopper-cohort row and 1 an SB product target: 15 settings on 8 controls. ME-COMPETE
     carries none.
   - **Which controls it watches.** The live trial's founding controls (`assignment_rule` starting
     `FOUNDING`), whether or not they have a baseline row. Four of the 12 carry no setting today,
     ME-COMPETE among them. An adjustment put on one of them later is present on one side only, and
     it reads RED.
   - **A late-arrival control is not watched on these settings.** That is a control whose
     `assignment_rule` starts `LATE ARRIVAL`. No baseline is taken for it and its settings are never
     compared. The board names it as unwatched, by its `assignment_rule`. Comparing it would read RED
     with nothing touched, because it has no baseline and most SB campaigns carry 0% placement rows.
     Kinds 1–3 still watch it.
   - Such a difference is RED while it stands, because there is no date to age it.
   - Ori's ruling on it is recorded as a new baseline row, after which it reads AMBER. When he rules
     that a setting is gone, that row's value is NULL, meaning absent. If the setting comes back
     later, it reads RED again.
   - **This matters for BOX-VIDEO/PT (Competitors, Purple, A1) `27660342907703`**, the largest control.
     Its one target is an SB product target, which no ledger row, and so no R9 censoring, can ever see.

**Kinds 2–4 are seen by the alarm and not censored by R9.** The board's detail says "seen by the alarm,
not censored by R9 — Ori to rule". Each one is a ruling for Ori, and nothing is decided automatically.

**What no source can see** (measured 2026-10-04; also in the tail of the board's detail on every read):
- **Negatives added or removed by hand.** Fivetran's five negative tables have not been written since
  2025-12-29 .. 2026-01-03. `DE_NEGATIVE_KEYWORDS` holds only the negatives OI uploads itself.
- **Ads and creatives.** Fivetran's product-ad, SB-ad and SB-creative tables are frozen the same way
  (last written 2025-12-28 .. 2026-01-03).
- **A change undone before the next sync,** and two changes between two loads, which read as one
  change carrying the later value.
- **A kind-4 setting put back to its baseline value** before the board reads it.
- **A late-arrival control's kind-4 settings.** It has no baseline, so they are never compared. The
  board names each such control as unwatched.
- **Not a touch at all:** Amazon's own automation, such as dynamic bidding and any budget rule already
  in place, which runs in both arms. That is a shared confounder and is fine (§6 #5 above).

Ori was told on 2026-10-04: **"the safest rule is not to open these 12 campaigns at all."** The rule of
§6 #2 stands for every kind of change, seen or not.

**Feed liveness.** "No change seen" and "the feed stalled" must not read the same. The board is RED when
any of the following is more than 36 hours old:
- the last OK run of `SP_RECORD_OBSERVED_CHANGES`, `SP_LOAD_DIM_KEYWORD`, `SP_LOAD_DIM_CAMPAIGN` or
  `SP_LOAD_DIM_AD_GROUP`;
- the last sync of any one of the eleven Fivetran tables that the ledger and the alarm read.

Measured 2026-10-04: the procedures' largest gap between OK runs over 30 days is 13 hours, and each
table's largest gap between syncs is at most 21 hours. Each sync re-stamps every row Amazon still
returns (not every row in the table), so a table's newest stamp moves with each sync and not only on a
change. The queries are in the plan, Appendix C.

---

## 7. THE HONEST LIMITS — read these before any number

**THE HEADLINE, PLAINLY: no cell in the power grid can detect an effect smaller than about 16% of
the ad spend under test.**

- The chosen cell (20% share, 16 weeks) has an **MDE of $2,261 per 14 days**.
- The eligible population's **entire 14-day net profit is −$1,288**.
- **The MDE is 1.76× the whole quantity being measured.**
- A genuinely good engine adding 7% of ad spend (**$900 per 14 days**) is **completely invisible** —
  detecting it at this share would need **106 weeks**. Detecting $1,300 needs 50 weeks. Detecting
  $1,800 needs 26 weeks.

**Ori should know this BEFORE he freezes 14 campaigns for four months.**

**The trial cannot answer "is the engine adding value."** It can only answer "is the engine adding
or destroying **more than roughly $2,300** per 14 days." If the answer comes back "no", that is
**not** a verdict of worthlessness — it is a verdict of *"the instrument cannot see it"*, and it
must be reported that way or it will be misread as proof the engine is useless.

**The precision ceiling is scale-invariant.** Making the slice bigger or smaller does not rescue
it: drop the top-1 campaign → MDE is 18% of covered spend; top-3 → 18%; top-5 → 19%; full
population → 17%. The skew is *not* the binding constraint. The noise-to-signal ratio of 14-day net
profit at this account size is.

**The noise floor and where it came from.** Measured on May–August data: campaign residual sd **$83
per 14 days** after removing campaign and window fixed effects, lag-1 autocorrelation 0.149,
implied single-window account noise **$686** — which independently reproduces the $767 per-anchor sd
measured on 2026-08-18. The 16-week window runs 1 Sep to 22 Dec and spans BFCM and the whole gift
season. Window fixed effects absorb the shock that hits both arms, but the **idiosyncratic**
variance will be larger in peak. **Expect the real MDE to be 20–40% worse than the table.**

**Cost.** At 20% the holdout arm carries **$5,504 per month** of ad spend under management. What is
FORGONE is only the engine's value on that fifth: if the engine is worth its own MDE ($4,845/month
across the eligible population), the holdout costs **$969/month** — about $3,900 over 16 weeks. If
the engine is worth a modest $1,000/month, it costs $200/month. **If the engine is net-negative, the
holdout arm MAKES money.** The real price is four months of not knowing.

**Coverage.** The estimand is 69 campaigns and $26,377 per 28 days — **76% of account ad spend, not
all of it.** Brand defense, Bunny and LolliBall are outside it in both arms.

**Cross-campaign interference is reduced, not eliminated, and its size is unmeasured.** Dollars the
engine frees in a treated campaign can be re-spent on another treated campaign through the
BASE/GROWTH portfolio pot, which **flatters the treated arm**; organic halo runs between variations
of one family. Family strata balance the arms on this; they do not make the arms independent. **If
the readout comes back positive, this is the first alternative explanation to rule out** — and
there is currently no measurement of its magnitude.

**Small-arm fragility.** 14 holdout clusters means one campaign's bad quarter moves the estimate
materially — the largest eligible campaign is 11.2% of the money on its own.

---

## 8. Reading it out

- **First readout: 2027-01-05** (trial 1; trial 2's is 2027-02-09, below). `V_HOLDOUT_READOUT` returns exactly one estimate row before that
  date — state `NOT_YET`, all numerics `NULL`, verdict `not enough data yet — first readout
  2027-01-05` — and, from v27.162, one `CENSORED` row per censored unit and one `PRE_WINDOW_CHANGE`
  row per HOLDOUT unit changed before its window, which carry dates and a reason and no number (§6
  "Contamination"; acceptance H3 holds the gate).
- **READOUT LAG IS NOT OPTIONAL.** Ads spend settles ~D+3 and sales accrue to D+7/D+14. Reading the
  final window before 2027-01-05 systematically **understates the treated arm's sales**, because
  the treated arm has more recent changes by construction. The readout date already contains the
  14-day settle. **Do not let anyone pull it forward.**
- **Interim safety look: 2026-11-10** (trial 1; trial 2's is 2026-12-15) (8 weeks observed). It can only detect harm above **$3,133 per
  14 days**. It is a **circuit breaker, not a verdict**, and it is a deliberate one-time hand query,
  not something the standing view leaks every morning — a daily-readable estimate on an underpowered
  trial *will* be read early and the first plausible-looking number *will* become the answer.
- **Inference:** with 14 clusters use a **permutation p-value** against the exact assignment
  distribution, permuted **inside the rerandomization acceptance region** of §5 — not a t-test. The
  band the view prints (`t_mult` = 3.27, the design's small-sample cluster multiplier; a naive
  t(0.975, 13) would be 2.16) is an orientation device. Run the pre-registered **leave-one-out**
  sensitivity check as well.
- **Subgroups:** the `ALL` row **is** the trial. The per-action-class rows are **exploratory** —
  the trial is powered for the total and nothing else, and every split multiplies the MDE.
- **The action-class split only exists because the gate records what it blocks.**
  `SP_ENGINE_PREFLIGHT` marks a holdout campaign's proposal `EXCLUDE` but the row stays in
  `FACT_ENGINE_PROPOSALS` with its intended action and verbatim reason. That record is the
  counterfactual: it is what lets the readout compare *"the engine wanted to cut AND we cut"*
  against *"the engine wanted to cut AND the coin said don't"*. **Block the export, never the
  judgement.**

### What the trial will let you say, verbatim

> *"Over 16 weeks from 1 Sep to 22 Dec, the 55 campaigns the engine managed produced $X per 14 days
> more net profit than the 14 randomly-matched campaigns it was forbidden to touch, with a 95%
> interval of plus or minus $2,261. We can rule out the engine adding or destroying more than about
> $2,300 per 14 days across the $13.2k per 14 days it manages. A real effect of a thousand dollars
> either way would be indistinguishable from zero."*

**If that sentence is not worth $5,504 a month and four months of waiting, do not start.**

### And why it is probably still worth it

The account's 14-day net has moved from **+$3,439 to −$2,470** over the last four months while the
engine ran, and Ori's own scorecard measured account **raises at −$752** against **cuts at +$3,051**.
*"The engine is doing large harm"* is a live and plausible hypothesis — and it is the one hypothesis
this trial can actually settle within a quarter.

### Trial 2's readout (`HOLDOUT-2026Q4-CAMPAIGN-T2`)

Trial 1's horizon rule is re-applied: 16 weeks, then the 14-day settle, and the interim look at 8 weeks
plus the settle. **Everything above applies unchanged**, with these dates and numbers:

| | trial 2 |
|---|---|
| assignment, and the export gate opens (`gate_from`) | 2026-10-05 |
| window start (`eligible_from`; the estimate and R9 start here) | 2026-10-06 |
| last day enforced (`trial_end`) | 2027-01-26 |
| **interim safety look** (one-time hand query, a circuit breaker, not a verdict) | **2026-12-15** |
| **first readout** (never pulled forward) | **2027-02-09** |

- **Before 2027-02-09 the readout returns one estimate row.** Its state is `NOT_YET`, every numeric is
  `NULL`, and its verdict names 2027-02-09. Beside it come the `CENSORED` and `PRE_WINDOW_CHANGE` rows,
  which carry dates and reasons and never a number.
- **The band and the MDE.** `t_mult` 3.27 is carried from trial 1's design and was not re-derived for 12
  clusters. The ex-ante MDE is **$2,089 per 14 days**: trial 1's $2,261 rescaled to 12 / 47 on trial 1's
  noise floor. A larger multiplier for 12 clusters would raise it, so read it as a floor.
- **The MDE is about the size of the whole quantity being measured.** `FACT_AMAZON_ADS` summed over the
  59 campaigns reads −$2,052.52 for 2026-09-19 .. 10-02 (read 2026-10-04). §7's warning applies
  unchanged.
- **Inference:** a permutation p-value inside trial 2's acceptance region (§5, "Trial 2's draw"), with
  12 clusters.
- **Pre-registered sensitivity checks.** Both are exploratory, like the action-class rows, and the `ALL`
  row is the trial:
  - **leave-one-out**, as in trial 1;
  - **without the 10 former trial-1 controls** (pre-registered 2026-10-03). Trial 2 drew all 10 of trial
    1's still-eligible controls as TREATED. Those campaigns had no engine instruction from 2026-09-01
    (hand changes aside), and the engine resumes on them from 2026-10-05, so the treated arm opens with
    a catch-up burst. That burst is part of the treatment, and the estimate stays unbiased. This row
    shows how much of the estimate it carries. The 10 campaigns:
    - `66467422009617` BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, D1);
    - `279837860088128` BOTTLE-SP/AUTO;
    - `446868628489343` FRESH-VIDEO/ BROAD;
    - `227290137740434` FRESH-SP/PT (Competitors, Pink, A1);
    - `190387447939462` ME-SP/BROAD (Mint, journaling kit for g);
    - `130253181662559` ME-SP/PHRASE (tween-girl-birthday-gift, Purple);
    - `47108762429478` BOX-VIDEO Competitor;
    - `200171414843593` BOX-SP/BROAD (Hunter, Gift for Girl);
    - `488973733209950` BOX-SP/AUTO (White);
    - `350259814389755` BOX-SP/BROAD- gifts for girls 10-12.
- **Known exposure:** LolliME carries 74% of the control dollars. If LolliME enters ACTUAL CRITICAL, §6's
  censoring rule leaves 5 controls ($59.47 a day) and 29 treated campaigns.
- **The verbatim sentence** of "What the trial will let you say" reads, for trial 2: 16 weeks from 6 Oct
  to 26 Jan, the 47 campaigns the engine managed against the 12 it was forbidden to touch, a 95%
  interval of plus or minus $2,089. The treatment is the engine as it evolved over those weeks (§6,
  "The engine is a moving target", still unruled).

---

## 9. Trial 2 — `HOLDOUT-2026Q4-CAMPAIGN-T2` (approved 2026-10-04, deploying 2026-10-05)

**Status: approved 2026-10-04, deploying 2026-10-05.**
- **Ori's words** (2026-10-04, after asking "explain seed 5"): **"ok seed 5, deploy it"**. The list below
  is approved unchanged.
- **No date moves**, because the OK came before 2026-10-05 22:00 Los Angeles.
- **The deploy** runs on 2026-10-05 by `scripts/bigquery/migrations/2026-10-05_holdout_t2_deploy.sh`,
  in the window the plan's Task 8 sets. That window opens after the second orchestrator pass of 10-05
  ends and stops by 15:40 UTC. The fallback is after the third pass ends, finishing by 04:40 UTC on
  10-06.
- **The window opens on 2026-10-06.** The plan's Task 9 replaces this status with "running from
  2026-10-06" and the measured results.
- **The record:** the trial-2 `OPENED` row's `ruling` reads `Ori 2026-10-03: restart from 2026-10-06
  with a fresh draw by the same method. List approved by Ori on 2026-10-04: "ok seed 5, deploy it".`
- **The plan** is `docs/superpowers/plans/2026-10-03-holdout-restart.md`. It holds the design, the
  tasks, checks K1–K12, the deploy timing and the full 59-row draw.

**Dates** (trial 1's horizon rule: 16 weeks, then the 14-day settle; interim look 8 weeks + settle):

| | date |
|---|---|
| assignment, and the export gate opens | 2026-10-05 |
| window start (`eligible_from`) | 2026-10-06 |
| last day (`trial_end`) | 2027-01-26 |
| interim safety look | 2026-12-15 |
| first readout | 2027-02-09 |

The gate opens a day before the window because of how the passes fall:
- The orchestrator's first pass of a New York day starts at 05:00 UTC, and its preflight runs at about
  05:30 UTC (measured over 7 days to 2026-10-03). That is the previous day in
  Los Angeles. Every gate reader compares a Los Angeles date.
- So the pass that builds the book uploaded on 10-06 judges under LA 10-05.
- A change on a control on 10-05 itself is published as `PRE_WINDOW_CHANGE` and not censored. This is
  pre-declared, consistent with R9 (a).

**Population.** These are §4's rules re-applied on 2026-10-03, giving 59 campaigns, $30,114 per 28 days
and five families.
- The stock literal was re-graded on the design date. LolliBall is CRITICAL (21.6 days) and stays out.
- Bunny is OK (159.4 days, 6,000 units arriving 10-07), so it is in.
- Keeping trial 1's literal would give 54 campaigns.

**Draw.** §5's method:
- seed `OI-HOLDOUT-v2|<index>`;
- A1 exactly ROUND(N/5) = 12 controls, A2 control dollar share in [0.18, 0.22], A3 all five families;
- the first passing index is **5**;
- the acceptance region is 18,190 of 390,625 offset vectors.

The founding cohort is written once from the literal list Ori approves (fingerprint
`4171456845817687166`), not re-drawn live. `SP_ASSIGN_HOLDOUT` then assigns late arrivals only.

**The 12 controls** (28-day spend to 2026-10-02 ÷ 28):

| family | campaign | campaign_id | $/day |
|---|---|---|---|
| Bottle | BOTTLE-VIDEO/EXACT (social-game, Truth) | 71317833591283 | 0.67 |
| Bottle | BOTTLE-SP/PHRASE (tween-girl-birthday-gift, Truth) | 53343800376430 | 0.02 |
| Bunny | BUNNY-SP/AUTO (Birthday) | 273898143987321 | 5.62 |
| Fresh | FRESH -SP/AUTO (Purple) | 271009556929636 | 3.69 |
| LolliME | ME-SBS/BROAD (Discovery, Journal) | 537046793426450 | 49.32 |
| LolliME | ME-COMPETE (Nollh Mint) | 365568042533669 | 44.76 |
| LolliME | ME-SP/AUTO (Mint) | 527422818407259 | 34.34 |
| LolliME | MINT-SP/BROAD (Back to School) | 51727823265377 | 23.08 |
| LolliME | ME-SP/EXACT (tween-girl-journal-diary, Purple) | 130115986205897 | 12.78 |
| LolliME | ME-SP/PT (Competitors, Mint, D2) | 230219410635024 | 1.64 |
| LolliME | ME-SP/PT (Competitors, Mint, C2) | 222497123677300 | 0.57 |
| Lollibox | BOX-VIDEO/PT (Competitors, Purple, A1) | 27660342907703 | 49.47 |

**Balance**, controls vs treated:

| | controls | treated |
|---|---|---|
| campaigns | 12 | 47 |
| 28-day ad dollars | $6,327 (21.0%) | $23,787 |
| net per ad dollar | −0.141 | −0.120 (about $68 per 14 days) |
| SB | 3 of 12 | 15 of 47 |
| capped | 5 of 12 | 15 of 47 |
| launch | 8 of 12 | 34 of 47 |
| families | 5 of 5 | 5 of 5 |

The ex-ante MDE is $2,089 per 14 days. That is trial 1's $2,261 rescaled to 12/47 on the same noise
floor, and it is a floor.

**Two things to know before saying OK** (plan §3.3):
1. **LolliME carries 74% of the control dollars**, and its stock forecast reads CRITICAL. If LolliME
   enters ACTUAL CRITICAL, §6's censoring rule leaves 5 controls.
2. **None of trial 1's 10 still-eligible controls was drawn as a control again.** All 10 are TREATED, so
   the engine resumes on them from 10-05. A sensitivity row without them is pre-registered.

The plan keeps the first passing seed, because the rule was declared before the draw ran.

**Ori's OK:** 2026-10-04, *"ok seed 5, deploy it"* (after asking "explain seed 5"). The list is
approved unchanged and the dates stand.

**The alarm for trial 2** is §6, "What the alarm sees, and what it cannot see". **The readout** is §8,
"Trial 2's readout". **Hand changes:** none to these 12 campaigns from the assignment on 2026-10-05 to
2027-01-26 (§6 #2). Some kinds of change, such as negatives, ads and creatives, reach no surface at all.

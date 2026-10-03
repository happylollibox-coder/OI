# HOLDOUT — the randomized trial that answers "is the engine worth anything?"

**Born:** 2026-08-19, v27.83. **Trial id:** `HOLDOUT-2026Q4-CAMPAIGN`.
**Ori:** *"the main goal of ads is to make more total of dollars that we would do without the changes."*
**Ori, 2026-08-18:** *"start the holdout."*

> **Status, 2026-10-03:** trial 1 (`HOLDOUT-2026Q4-CAMPAIGN`, §0–§8 as written below) is
> **contaminated and restarts** (Ori, 2026-10-03, option (c)). Its rows are kept unchanged and are
> archived from 2026-10-05. Trial 2 (`HOLDOUT-2026Q4-CAMPAIGN-T2`) starts its window on 2026-10-06 once
> Ori approves its list of control campaigns. See §6 "Rulings 2026-10-03" and §9. The plan is
> `docs/superpowers/plans/2026-10-03-holdout-restart.md`.

---

## 0. The one-paragraph version

We randomly picked 14 of the 69 eligible campaigns and forbade the engine from touching them —
no bid, no budget, no negative — for 16 weeks. The other 55 run exactly as they do today. On
2027-01-05 we compare the two groups on net dollars. That comparison is the first honest answer
this account has ever had to "does the engine make money?". **It is also a blunt instrument: it
can only detect an effect bigger than about $2,261 per 14 days, which is larger than the entire
14-day net profit of the campaigns under test.** Read §7 before you read any number it produces.

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
| `V_HOLDOUT_ELIGIBLE` | Who may enter, and the frozen facts the randomization blocks on. **One consumer only** (`SP_ASSIGN_HOLDOUT`) — it reads `V_CAMPAIGN_CAP_STATE` and `V_LAUNCH_POPULATION`, so nothing hot may touch it. |
| `DE_HOLDOUT_ASSIGNMENT` | **The arms.** One row per unit, written once, never updated. |
| `SP_ASSIGN_HOLDOUT` | Assigns unassigned eligible units. Append-only, idempotent. Orchestrator **Task 20.55**, before the proposal snapshot. |
| `SP_ENGINE_PREFLIGHT` | The gate. A **third** exclusion source beside collision and claim: `HOLDOUT`, covering **all** levers. Verdict `EXCLUDE`. |
| `V_HOLDOUT_READOUT` | The answer. Silent until 2027-01-05. From v27.162 it also publishes one `CENSORED` row per censored unit and one `PRE_WINDOW_CHANGE` row per HOLDOUT unit changed between its assignment and its window start (dates and the reason, never a dollar) — §6 "Contamination". |
| `V_ENGINE_HEALTH` `holdout_unit_changed` | v27.162: RED when a HOLDOUT campaign changed inside its window and the readout does not censor it and its stratum-mates from that day, or changed before its window and the readout does not publish it; AMBER while a change before the window stands unruled — §6 "Contamination". |

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
  that triggered the stratum. The ALL row's sentence (from 2027-01-05) says how many units were cut.
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
   - the latest logged change is 2026-08-25;
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

- **First readout: 2027-01-05.** `V_HOLDOUT_READOUT` returns exactly one estimate row before that
  date — state `NOT_YET`, all numerics `NULL`, verdict `not enough data yet — first readout
  2027-01-05` — and, from v27.162, one `CENSORED` row per censored unit and one `PRE_WINDOW_CHANGE`
  row per HOLDOUT unit changed before its window, which carry dates and a reason and no number (§6
  "Contamination"; acceptance H3 holds the gate).
- **READOUT LAG IS NOT OPTIONAL.** Ads spend settles ~D+3 and sales accrue to D+7/D+14. Reading the
  final window before 2027-01-05 systematically **understates the treated arm's sales**, because
  the treated arm has more recent changes by construction. The readout date already contains the
  14-day settle. **Do not let anyone pull it forward.**
- **Interim safety look: 2026-11-10** (8 weeks observed). It can only detect harm above **$3,133 per
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

---

## 9. Trial 2 — `HOLDOUT-2026Q4-CAMPAIGN-T2` (proposed 2026-10-03, waiting for Ori's OK on the list)

**Nothing below is deployed.** The plan is `docs/superpowers/plans/2026-10-03-holdout-restart.md`: the
design, the tasks, checks K1–K11, the deploy timing and the full 59-row draw.

**Dates** (trial 1's horizon rule: 16 weeks, then the 14-day settle; interim look 8 weeks + settle):

| | date |
|---|---|
| assignment, and the export gate opens | 2026-10-05 |
| window start (`eligible_from`) | 2026-10-06 |
| last day (`trial_end`) | 2027-01-26 |
| interim safety look | 2026-12-15 |
| first readout | 2027-02-09 |

The gate opens a day before the window because of how the passes fall:
- The orchestrator's first pass of a New York day runs at about 05:30 UTC, which is the previous day in
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

**Ori's OK:** _pending_.

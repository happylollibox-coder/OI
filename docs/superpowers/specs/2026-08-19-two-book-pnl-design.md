# Two-Book P&L — judging ads on net profit, including the organic halo

**Date:** 2026-08-19 · **Status:** design approved by Ori, ready for planning
**Supersedes as priority:** the randomized holdout (built 2026-08-19, parked — see §9)

> **⚠ SUPERSEDED IN PART — three points below no longer describe what is built (2026-08-20).**
> Read the implementation plan `docs/superpowers/plans/2026-08-19-two-book-pnl.md` alongside this
> document, and the deployed files in `scripts/bigquery/` ahead of both.
>
> 1. **§5 enforcement: the binding clause is the SANCTIONED DAILY SPEND RATE, not the monthly loss
>    ceiling.** This spec says the exemption becomes conditional on the end date and the
>    month-to-date loss against the ceiling. Measured 2026-08-19, that ceiling never fires: Bunny and
>    LolliBall ran at 1.6x and 1.9x their sanctioned daily spend while losing only $204 and $15
>    against ceilings of $913 and $1,674. Ori's ruling the same day — *"spend rate binds"* — moved
>    the test onto `DE_LAUNCH_INVESTMENT.daily_investment`. The loss ceiling remains as a catastrophe
>    backstop behind it.
> 2. **§4 cadence: the keyword bar is rebuilt DAILY, not monthly.** `SP_SNAPSHOT_FAMILY_BAR` runs as
>    orchestrator task 20.5g-1, every day, before the engine `T_` builds. The 90-day input window is
>    still settled; only the refresh cadence differs.
> 3. **§5 "a declaration requires three fields" is an OPEN QUESTION, not a shipped rule.** Live
>    production has Bunny and LolliBall in the Invest book with `takeover_target_organic_units` NULL,
>    deliberately, until Ori supplies the numbers. Task 9 of the plan states both options and is
>    blocked until he rules. Do not enforce the three-field rule from this document.
>
> The §5 illustration of "a $2,500 ceiling" is an example number only. The ceilings Ori actually
> sanctioned on 2026-08-13 are **$913 for Bunny** and **$1,674 for LolliBall**. Never restore a
> sanctioned value from a number written in a document — read the live row.

## 1. The problem, and how we found it

Ori asked a simple question: *"the main goal of ads is to make more total of dollars that we would
do without the changes."* Three attempts to answer it each overturned the previous framing.

**Attempt 1 — measure the engine against a counterfactual.** Matched difference-in-differences was
built and proved untrustworthy on this account. Emulating the engine's own selection rule (rank
keywords by trailing-14d dollars) and then doing NOTHING produces a measured "effect" of
+$1,505..+$2,445 on the losers arm and −$1,094..−$1,829 on the winners arm, across four independent
no-upload dates — pure mean reversion. The account's true 14-day net is about −$2,500..−$2,730, so
the fabricated effect is ~90% of the entire quantity being measured. There is also no control pool:
73.5% of active keywords and 85.1% of ad dollars are touched, and the clean untouched pool clearing
a 10-click bar is SEVEN keywords / $819 against 379 treated / $29,326. Matching fails for 98.1% of
treated keywords, and the survivors are untouched *because they are dying* (−83% clicks over the
window). **Conclusion: the engine's incremental value is not measurable from observational data here.**

**Attempt 2 — diagnose the apparent collapse.** Ads-attributed P&L fell from +$13,529 (March) to
−$5,612 (July), GP-ROAS 1.45 → 0.84, while spend rose 44%. Decomposing GP-ROAS into its arithmetic
parts (`CVR × order value × margin ÷ CPC`) showed 47% of the fall was **order value** ($43.99 →
$33.98) and 33% conversion rate — only 9% was CPC, the thing the engine controls most directly.
Tracing the order-value collapse found it concentrated in the largest family, whose bucket had
absorbed two new products selling at $16–17 an order against an original product at $47–54.

**Attempt 3 — Ori's correction: include the organic halo.** Measured on TOTAL sales rather than the
ads-attributed slice, July made **+$3,682, not −$5,612**. The "collapse" was an artifact of looking
at a slice that excludes 30–40% of units. The business is profitable; the reporting was not.

### The actual defects, once measured correctly

1. **The engine optimizes the wrong number.** Every bid decision is judged on ads-attributed
   GP-ROAS, which structurally undervalues any keyword that drives organic sales. Live example:
   **Bottle** reads 0.60 on ads net ROAS — a disaster the engine would cut hard — but 0.95 on total
   net ROAS, because it has the **strongest halo in the account (1.59)**. Cutting Bottle's keywords
   on the ads number would destroy the organic demand carrying it.
2. **Deliberate launch investment is invisible and unbounded.** ~$5,400/month flows to Bunny and
   LolliBall at 0.39–0.49 ads net ROAS. Ori confirms this is intentional — buying rank until organic
   demand takes over. But no budget, end date or success test was ever declared, so the spend
   accumulated without a decision and its losses were blended into the engine's scorecard.
3. **One established family leaks, hidden by the blend.** **Fresh** — 24 months old, $6,269/month of
   spend, **halo factor 1.07** (the weakest in the account), net profit −$1,497 over May–July. It
   rents traffic and builds nothing, and nobody could see it because its loss sat inside a blended
   number that also contained deliberate launch spending.

## 2. The two books

Every product family sits in exactly one book. **Harvest is the default**; Invest requires an
explicit declaration, because unbounded investment is the defect being fixed.

| book | membership | judged on |
|---|---|---|
| **Harvest** | default — all established families | **net profit**, with total net ROAS vs 1.0 as the efficiency read |
| **Invest** | explicit declaration only | **budget adherence + organic take-over**, never on profit |

Today: Harvest = LolliME, Lollibox, Fresh, Bottle. Invest = Bunny, LolliBall.

## 3. Measurement basis

**Net profit leads; the ratio explains it.** Ori's framing is total dollars, so the dollar figure is
the headline and the ratio is the diagnostic.

- **Net profit** = `total sales − COGS − ad spend`. Verified 2026-08-19: `V_UNIFIED_DAILY.cogs` is
  all-in (product $54,155 + inbound shipping $14,337 + FBA pick/pack $45,044 + Amazon referral
  $38,498 over May–Jul), so this is a true net profit after Amazon fees, not a gross margin.
- **Total net ROAS** = `(total sales − COGS) ÷ ad spend`. Breakeven 1.0. No parameters.
- **Halo factor** = `total net ROAS ÷ ads net ROAS`. **Measured, never assumed** — read straight
  from dollars rather than inferred from unit ratios and an equal-margin assumption.
- **Ads net ROAS** stays published beside them — not as the verdict, but because the gap between it
  and total net ROAS *is* the halo, and watching that gap is how a product converting paid traffic
  into organic demand becomes visible.

Cut at the **orders watermark**, not the ads watermark: blended measures need the sales side
complete (`fact_oi_orders_vs_ads_watermark`). Windows follow the complete-days convention
(`feedback_window_convention_complete_days`).

### Baseline, May–July 2026

| family | net profit | total net ROAS | halo factor | ads net ROAS |
|---|---|---|---|---|
| LolliME | +$15,406 | 1.49 | 1.26 | 1.18 |
| Lollibox | +$13,537 | 1.59 | 1.37 | 1.16 |
| Bottle | −$203 | 0.95 | **1.59** | 0.60 |
| Fresh | −$1,497 | 0.88 | **1.07** | 0.83 |
| Bunny | −$1,687 | 0.58 | 1.50 | 0.39 |
| LolliBall | −$1,717 | 0.43 | **0.87** ⚠ | 0.49 |
| **total** | **+$23,839** | | | |

Why both metrics: Bottle (0.95) and Fresh (0.88) look like the same problem by ratio, but cost $203
and $1,497 respectively. Ranked by ratio you fix Bottle; ranked by dollars you fix Fresh, which is
the right answer.

## 4. The engine bridge — how the halo reaches a bid decision

**Organic sales are measurable at family grain and NOT attributable to a keyword.** The books
therefore work at family grain while the engine decides at keyword grain. The bridge:

> **Adjust the bar, never the measurement.** The engine keeps measuring ads-attributed GP-ROAS at
> keyword grain — the only honest measure available there. What changes is the *bar* it is judged
> against, set once per family from that family's measured halo.

    keyword_bar = 1 ÷ (1 + credit × (halo_factor − 1)),  credit = 0.5

- **Credit is 0.5, and it is a declared tunable.** Crediting all organic to ads is wrong (brand
  search and repeat buyers would happen anyway); crediting none is today's behaviour and is why the
  engine undervalues rank-building. Half is the conservative middle.
- **Where halo_factor < 1.0, no credit is given** and the bar stays at 1.0.
- The credit can only ever **lower** a bar, never raise one — it cannot be used to justify a cut.
- The bar is **floored at 0.60**; no halo excuses a catastrophic keyword.
- Halo factor is computed on a **settled 90-day window** at family grain and refreshed **monthly**,
  not daily — bids must not chase organic noise.
- **Invest families are exempt** from the bar entirely; they are governed by §5.

**Validation property:** the bar reproduces the total-net-ROAS verdicts at family level (LolliME and
Lollibox clear; Fresh and Bottle fall below). This must be re-checked monthly — if a family passes
its keyword bars while failing total net ROAS, the bridge is miscalibrated.

## 5. The Invest book — bounded investment and the take-over test

**A declaration requires three fields or it is not a declaration:** monthly loss ceiling, end date,
take-over target. Missing any one and the family is Harvest.

The **ceiling is denominated in NET PROFIT** — the same metric the Harvest book uses (`total sales −
COGS − ad spend`), not ad spend and not ads-attributed profit. A $2,500 ceiling means the family may
lose $2,500 of net profit in a calendar month, whatever it spends to do so.

**Enforcement.** The launch exemption — today open-ended, which is how $7.2k/month accumulated
without a decision — becomes conditional on BOTH `today ≤ end_date` AND
`month-to-date loss < ceiling`. When either fails the family reverts to Harvest rules and its
halo-adjusted bar applies. **The engine stops, not the human.**

**The take-over test has two phases, because the question changes with age** (Ori 2026-08-19:
*"the question of launch products is are they improving — not are they profitable — in the first 3
months"*).

**Months 0–3, the RAMP. Judged on TRAJECTORY only. Nothing is required to be positive; everything
is required to be improving.** Three trends, measured month over month:
- **organic units** — rising (the primary signal)
- **total net ROAS** — rising (e.g. 0.43 → 0.55 → 0.68)
- **net profit** — loss shrinking

The decision rule is *"no improvement across two consecutive months"*, never *"still unprofitable"*.
A profitable-at-month-2 test would kill every launch that was working.

**Months 3+, the PROOF.** Level starts to matter: the family must be closing on its declared
take-over target by its end date, and the ceiling and clock enforce themselves per above.

**Why absolute organic units, not share.** Share is a trap: it rises when ads units collapse, which
looks like success and is not. Bunny and LolliBall already sit at ~31% organic — comparable to
Lollibox's 29.7% — so by share alone they would read "finished" while still losing $2,892/month.

**A useful consequence: trajectory is robust to a level bias.** Measuring change rather than level
means a constant COGS misallocation cancels out of the trend — which materially de-risks open item
§9.1 (LolliBall's implausible 0.87 halo). The bias still corrupts the *level*, so it must be fixed
before LolliBall is judged in its months-3+ PROOF phase, but it does not block the ramp test.

## 6. The daily brief

Harvest figures below are REAL (May–Jul 2026). Invest figures are ILLUSTRATIVE — no declaration
exists yet, so the ceilings, day counts and organic trajectories are shape, not measurement.

    HARVEST — judged on net profit
      LolliME    +$15,406   ROAS 1.49  halo 1.26   bar 0.88 / running 1.18   ok
      Lollibox   +$13,537   ROAS 1.59  halo 1.37   bar 0.84 / running 1.16   ok
      Fresh       −$1,497   ROAS 0.88  halo 1.07   bar 0.97 / running 0.83   3rd month below
      Bottle        −$203   ROAS 0.95  halo 1.59   bar 0.77 / running 0.60   below
                                                              Harvest: +$27,243

    INVEST — declared launches
      Bunny       $2,366 of $2,500 ceiling · 42 days left
                  organic units 220 → 268 (+22%)              taking over
      LolliBall   $2,825 of $2,500 ceiling — OVER, exemption lifted
                  organic units 310 → 305 (−2%)               flat, 3rd month
                                                              Invest: −$3,404

Two lines, never blended. July becomes *"Harvest earned X; Invest spent Y of its declared budget"*
instead of *"the account lost $5,612"* — same money, and the second sentence was never true.

## 7. Objects to build

| object | role |
|---|---|
| `V_FAMILY_PNL` | family × period: net profit, total net ROAS, ads net ROAS, halo factor, organic units/share. The measurement spine. |
| `DE_LAUNCH_INVESTMENT` | the declaration: family, monthly ceiling, start/end date, take-over target, declared_by/at. |
| `V_BOOK_ASSIGNMENT` | family → HARVEST/INVEST, derived from the declaration + dates. Default HARVEST. |
| `V_FAMILY_BAR` | family → halo factor and keyword bar (settled 90d, monthly refresh, floor 0.60, no credit below 1.0). |
| `V_INVEST_STATUS` | budget consumed, days remaining, organic-unit trajectory, exemption live/lifted. |
| `V_DAILY_BRIEF` (extend) | the two-book brief of §6. |
| `V_LAUNCH_EXEMPTION` (modify) | exemption conditional on ceiling + end date. |
| engine consumers (modify) | read `V_FAMILY_BAR` instead of a flat 1.0 breakeven. |

## 8. Non-goals

- **No automatic cutting of Harvest families.** Fresh is surfaced with its evidence; the decision
  stays Ori's. Today established that the engine's outcome measurements are weaker than they look.
- **No per-keyword organic attribution.** It does not exist; inventing it would be fiction.
- **No change to the settle discipline, window convention, ownership ladder or preflight gates.**

## 9. Open items and honest limits

1. **LolliBall's halo factor is 0.87** — total gross profit *below* ads-attributed, which is not
   physically sensible. Almost certainly the COGS tier imputation on new products
   (`project_ads_cogs_price_imputation`). **Downgraded from blocking to scheduled** by the §5 ramp
   test: a constant COGS bias cancels out of a month-over-month trend, so it does not corrupt the
   only judgement LolliBall faces for now. It MUST be fixed before LolliBall reaches its months-3+
   PROOF phase, where the level is judged.
2. **Causality is assumed, not proven.** We cannot prove the halo is caused by ads. The 0.5 credit
   is the hedge, and the feedback loop is the test: if lowering a family's bar does not improve its
   net profit over the following quarter, the credit was too generous and gets cut.
3. **The randomized holdout is parked, not deleted.** It answers a narrower question ("does the
   engine beat no engine") at ±$2,261 and not until January 2027. It was built 2026-08-19 and its
   verifier found it not yet valid: baseline imbalance reading −$1,100 on null windows, the export
   gate protecting only 7 of 38 keywords in holdout campaigns, and five Python bulksheet builders
   bypassing preflight entirely. All documented in `architecture/HOLDOUT.md`. The trial window opens
   2026-09-01; if it is not fixed before then it should be formally abandoned rather than left to
   run invalid.
4. **Fresh needs a decision, not just a metric.** 24 months old, halo 1.07, −$1,497. This design
   makes it visible; it does not fix it.

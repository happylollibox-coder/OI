# Two-Book P&L — judging ads on net profit, including the organic halo

**Date:** 2026-08-19 · **Status:** design approved by Ori, ready for planning
**Supersedes as priority:** the randomized holdout (built 2026-08-19, parked — see §9)

> **STANDING RULE 0 — describe the MECHANISM, publish the QUERY, never pin a MEASUREMENT**
> (Ori's ruling, 2026-08-20, fourth repair round. It REPLACES the round-3 version, which allowed a
> measured number to stay if it carried an as-of date. Stamping was tried for a whole round and
> shipped a wrong number under the right date — which looks verified, and is worse than an undated
> one.)
>
> **A DECLARED CONSTANT** — a sanctioned $/day, a stop date, `credit = 0.5`, the 0.60 floor, a
> 28-day window, a 5% band — is true because a person decided it. It may be written down, it may
> gate an assertion, and you should say where it is declared.
> **A MEASUREMENT** — a rate, a ratio, a ROAS, a halo, a net profit, a count, a percentage of a
> ceiling, a byte count — is true only because something was computed from data on a day. It does
> not go in prose, and it may never gate anything. Publish the QUERY instead; run it first and check
> its output, and its column names, against the sentence beside it.
>
> **This document is a DESIGN RECORD dated 2026-08-19.** §1 keeps the one-off analysis findings that
> caused the design to be built, because they are the reasoning trail and no live object restates
> them — they are quarantined in a box that says so. Everything that describes the SYSTEM AS IT
> STANDS has had its measurements removed and replaced with the query that produces them. **Never
> copy a figure out of this document into an operational one.**

> **⚠ SUPERSEDED IN PART — three points below no longer describe what is built (2026-08-20).**
> Read the implementation plan `docs/superpowers/plans/2026-08-19-two-book-pnl.md` alongside this
> document, and the deployed files in `scripts/bigquery/` ahead of both.
>
> 1. **§5 enforcement: the binding clause is the SANCTIONED DAILY SPEND RATE, not the monthly loss
>    ceiling.** This spec says the exemption becomes conditional on the end date and the
>    month-to-date loss against the ceiling. That ceiling structurally never fires: it was backfilled
>    as the sanctioned SPEND rate monthised, and a launch family with real sales loses far less than
>    it spends, so it is a loose bound by construction and a family can sit deep inside it while
>    running well over its rate. Ori's ruling on 2026-08-19 — *"spend rate binds"* — moved the test
>    onto `DE_LAUNCH_INVESTMENT.daily_investment`. The loss ceiling remains as a catastrophe backstop
>    behind it. See both at once:
>    `SELECT family, daily_investment, spend_per_day, spend_rate_ratio, ceiling_used_pct FROM
>    onyga-482313.OI.V_INVEST_STATUS`.
> 2. **§4 cadence: the keyword bar is rebuilt DAILY, not monthly.** `SP_SNAPSHOT_FAMILY_BAR` runs as
>    orchestrator task 20.5g-1, every day, before the engine `T_` builds. The 90-day input window is
>    still settled; only the refresh cadence differs. **Why daily is right, and why §4's stated fear
>    does not apply (added 2026-08-20):** the fear behind "monthly, not daily" was bids chasing
>    organic noise. The input is a *settled* 90-day window, so one rebuild moves it by roughly one
>    day in ninety and a bar built on it cannot be jumpy IN THE ORDINARY CASE — a restatement or a
>    COGS change that rewrites the whole window at once still moves the bar as far as it likes, and
>    the only guarantee is directional (the credit can never raise a bar above 1.0). Daily also
>    removes a second scheduler and keeps the bars in the same daily pass as the engines that will
>    read them. Note this is the MATERIALISATION cadence only. **The §4 clause calling the
>    bar-vs-total-net-ROAS calibration a standing *monthly* check does NOT stand either** (corrected
>    2026-08-20 — this paragraph used to say it did): no monthly job exists anywhere in the
>    warehouse, and the calibration query is run by hand. See the corrected note under §4.
> 3. **§5 "a declaration requires three fields" is an OPEN QUESTION, not a shipped rule.** Live
>    production has Bunny and LolliBall in the Invest book with `takeover_target_organic_units` NULL,
>    deliberately, until Ori supplies the numbers. Task 9 of the plan states both options and is
>    blocked until he rules. Do not enforce the three-field rule from this document.
>
> The §5 illustration of "a $2,500 ceiling" is an example number only. The ceilings Ori actually
> sanctioned on 2026-08-13 are **$913 for Bunny** and **$1,674 for LolliBall** — DECLARED CONSTANTS
> on `DE_LAUNCH_INVESTMENT`, which is why they may be written down at all. Never restore a sanctioned
> value from a number written in a document — read the live row.

## 1. The problem, and how we found it

> **QUARANTINED HISTORICAL ANALYSIS (2026-08-20).** The figures in this section are the findings of
> three one-off investigations run on 2026-08-19. **No live object restates them**, which is why they
> are kept rather than replaced with a query: they are the reasoning trail for why two whole
> approaches were abandoned, and deleting them would leave the next reader free to rebuild both.
> Treat every number below as a dated finding, never as the current state of anything, and **never
> copy one into a header, a registry entry, a plan step or an SOP.** The current state lives behind
> the queries published in the sections after this one.

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

*(The three defects below are properties of the SYSTEM, not of 2026-08-19's data, so they are stated
as mechanisms with the query that shows them — Standing Rule 0. They are outside the quarantine box.)*

1. **The engine optimizes the wrong number.** Every bid decision is judged on ads-attributed
   GP-ROAS, which structurally undervalues any keyword that drives organic sales. A family can read
   as a disaster on ads net ROAS and be fine on total net ROAS; the gap between the two IS its halo,
   and cutting that family's keywords on the ads number destroys the organic demand carrying it.
   See the two columns side by side:
   `SELECT family, book, ads_net_roas, total_net_roas, halo_factor, keyword_bar FROM
   onyga-482313.OI.V_FAMILY_BAR ORDER BY keyword_bar`.
2. **Deliberate launch investment is invisible and unbounded.** Real money flows every month to
   families being bought into rank. Ori confirms this is intentional — buying rank until organic
   demand takes over. But no budget, end date or success test was ever declared, so the spend
   accumulated without a decision and its losses were blended into the engine's scorecard. What is
   flowing today: `SELECT family, daily_investment, spend_per_day, sanction_end_date FROM
   onyga-482313.OI.V_TWO_BOOK_BRIEF WHERE book='INVEST' AND row_kind='FAMILY'`.
3. **An established family can leak, hidden by the blend.** A mature Harvest family that rents
   traffic and builds nothing shows a weak halo and a real dollar loss every window — and nobody
   could see it, because its loss sat inside a blended number that also contained deliberate launch
   spending. Rank the Harvest book on dollars and the leak is the bottom row:
   `SELECT family, net_profit, ad_spend, total_net_roas FROM onyga-482313.OI.V_TWO_BOOK_BRIEF
   WHERE book='HARVEST' AND row_kind='FAMILY' ORDER BY net_profit`.

## 2. The two books

Every product family sits in exactly one book. **Harvest is the default**; Invest requires an
explicit declaration, because unbounded investment is the defect being fixed.

| book | membership | judged on |
|---|---|---|
| **Harvest** | default — all established families | **net profit**, with total net ROAS vs 1.0 as the efficiency read |
| **Invest** | explicit declaration only | **budget adherence + organic take-over**, never on profit |

Which family is in which book is a READING of `DE_LAUNCH_INVESTMENT`, not a fact about the design,
and it changes the moment a sanction is signed or expires — so it is not written here.
Read it: `SELECT family, book, declaration_valid, stop_date FROM
onyga-482313.OI.V_BOOK_ASSIGNMENT ORDER BY book, family`.

## 3. Measurement basis

**Net profit leads; the ratio explains it.** Ori's framing is total dollars, so the dollar figure is
the headline and the ratio is the diagnostic.

- **Net profit** = `total sales − COGS − ad spend`. `V_UNIFIED_DAILY.cogs` is all-in — landed
  product cost, inbound shipping, FBA pick/pack AND the Amazon referral fee — so this is a true net
  profit after Amazon fees, not a gross margin. Check the composition against `V_UNIFIED_DAILY`
  rather than against a figure written here.
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

**The baseline WINDOW is a declared constant; the figures on it are a measurement.** The window
2026-05-01 to 2026-07-31 is the one this design was argued on and is frozen as `period_label =
'BASELINE_MAY_JUL'` in `V_FAMILY_PNL`. The table of figures that used to sit here has been removed
under Standing Rule 0 — it was already drifting, because ads money restates and a "frozen" window
does not freeze the numbers on it. **Reproduce it instead of quoting it:**

    SELECT family, net_profit, total_net_roas, halo_factor, ads_net_roas
    FROM `onyga-482313.OI.V_FAMILY_PNL`
    WHERE period_label = 'BASELINE_MAY_JUL'
    ORDER BY net_profit DESC;

The Task 1 acceptance assertion reproduces this same window, which is what makes it the baseline.

Why both metrics: **a ratio has no size in it.** Two families the same distance under 1.0 can be a
rounding error apart in dollars or thousands apart, because the ratio says nothing about how much was
spent to get there. Ranked by ratio you may fix the cheap one; ranked by dollars you fix the
expensive one, and dollars is the right answer.

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
- **Where halo_factor is at or below 1.0, no credit is given** and the bar stays at 1.0. (The
  deployed test is `halo_factor > 1.0` for credit, i.e. `<= 1.0` gets none; behaviourally identical
  at exactly 1.0, wording aligned 2026-08-20 with `V_FAMILY_BAR.sql`.)
- The credit can only ever **lower** a bar, never raise one — it cannot be used to justify a cut.
- The bar is **floored at 0.60**; no halo excuses a catastrophic keyword.
- Halo factor is computed on a **settled 90-day window** at family grain and refreshed ~~**monthly**,
  not daily~~ — bids must not chase organic noise.
  > **CORRECTION 2026-08-20 — the cadence is DAILY, and this line's rejection of daily by name is
  > superseded.** `SP_SNAPSHOT_FAMILY_BAR` runs as orchestrator task 20.5g-1 in
  > `SP_ORCHESTRATE_DAILY_REFRESH`, every day, and has since it was deployed; the deployed
  > `V_FAMILY_BAR.sql` header was corrected on 2026-08-19 and `config.yaml` on 2026-08-20. The
  > reasoning above is preserved because the *fear* was legitimate and worth keeping on record — it
  > is the conclusion that was wrong. A settled 90-day window moves by roughly one day in ninety per
  > rebuild, so a daily refresh cannot make the bar chase noise IN THE ORDINARY CASE. That bounds
  > ordinary drift and is not an absolute: a restatement or a COGS change that rewrites 90 days at
  > once moves the halo, and with it the bar, as far as it likes. The only guarantee is directional —
  > the credit can never raise a bar above 1.0. The window itself is unchanged: still settled, still
  > 90 days.
- **Invest families are exempt** from the bar entirely; they are governed by §5.

**Validation property:** the bar reproduces the total-net-ROAS verdicts at family level — if a family
passes its keyword bar while failing total net ROAS, the bridge is miscalibrated.

> **CORRECTED 2026-08-20, twice over.** (a) **It is not monthly.** This line said "re-checked
> monthly"; no monthly job exists anywhere in the warehouse — the bar is rebuilt daily and this check
> is run by hand. (b) **It is ONE-DIRECTIONAL, and the named families were a snapshot.** Clearing the
> bar must imply clearing total net ROAS 1.0; the reverse is not required, and a family failing its
> bar while clearing 1.0 is the bar being STRICTER than the truth, which is the direction the design
> wants — it must never be alarmed on. Alarm on PERMISSIVE breaks only (clears the bar, fails 1.0),
> which the algebra in `V_FAMILY_BAR.sql`'s header shows are reachable only where halo < 1. Which
> families sit on which side moves with the data and is deliberately not written here; the query is
> published in that header. Run it before quoting any count.


## 5. The Invest book — bounded investment and the take-over test

**A declaration requires three fields or it is not a declaration:** monthly loss ceiling, end date,
take-over target. Missing any one and the family is Harvest.

The **ceiling is denominated in NET PROFIT** — the same metric the Harvest book uses (`total sales −
COGS − ad spend`), not ad spend and not ads-attributed profit. A $2,500 ceiling means the family may
lose $2,500 of net profit in a calendar month, whatever it spends to do so.

**Enforcement.** The launch exemption — today open-ended, which is how real money accumulated month
after month without a decision — becomes conditional on BOTH `today ≤ end_date` AND
`month-to-date loss < ceiling`. When either fails the family reverts to Harvest rules and its
halo-adjusted bar applies. **The engine stops, not the human.**

> **CORRECTION 2026-08-20 — THE SPEND RATE BINDS, NOT THE CEILING. The paragraph above is superseded
> and is kept only so the reasoning trail survives.** Ori's ruling on 2026-08-19 was *"spend rate
> binds"*, and the reason is STRUCTURAL rather than a reading of any particular day: the ceiling is
> denominated in NET PROFIT but was backfilled from the sanctioned SPEND rate monthised, and a launch
> family with real sales loses far less than it spends. So the ceiling is a loose bound **by
> construction**, a family can sit deep inside it while running well over its sanctioned rate, and a
> ceiling-only condition would leave such a family **fully exempt on the very day it is furthest over
> rate** — enforcement in name only. The live rule is therefore `today ≤ end_date` **AND**
> `spend rate ≤ daily_investment`, with the monthly loss ceiling demoted to a catastrophe backstop
> sitting behind the rate.
>
> **NO RATE, RATIO OR CEILING PERCENTAGE APPEARS ON THIS LINE, AND NONE MAY BE ADDED**
> (Standing Rule 0). The figures that used to sit here went stale twice — once on their own, and once
> when the window under them was redefined from month-to-date to a trailing span of complete days,
> which re-scored both families. This sentence used to state four of them and then claim, in the same
> paragraph, that they had been removed; both halves cannot be true. Read them off the object:
> `SELECT family, daily_investment, spend_per_day, spend_rate_ratio, ceiling_used_pct,
> rate_window_basis, protection_qualified FROM onyga-482313.OI.V_INVEST_STATUS`.
>
> **AND "the engine stops, not the human" IS NOT TRUE TODAY — it is the goal, not the state.** Under
> Ori's 2026-08-20 ruling *"Tell the truth now, release nothing"*, Task 8b is on hold and
> `V_LAUNCH_EXEMPTION` is not to be edited, so nothing in the engine reads the sanction. Both
> conditions are **measured and reported** by `V_INVEST_STATUS.protection_qualified` and shown in
> `V_TWO_BOOK_BRIEF` alongside the dollars of budget cuts the coach is holding — and the only thing
> that stops a launch today is a person reading that row. The brief says so in plain words.

**The take-over test has two phases, because the question changes with age** (Ori 2026-08-19:
*"the question of launch products is are they improving — not are they profitable — in the first 3
months"*).

**Months 0–3, the RAMP. Judged on TRAJECTORY only. Nothing is required to be positive; everything
is required to be improving.** Three trends, measured month over month:
- **organic units** — rising (the primary signal)
- **total net ROAS** — rising
- **net profit** — loss shrinking

The decision rule is *"no improvement across two consecutive months"*, never *"still unprofitable"*.
A profitable-at-month-2 test would kill every launch that was working.

**Months 3+, the PROOF.** Level starts to matter: the family must be closing on its declared
take-over target by its end date, and the ceiling and clock enforce themselves per above.

**Why absolute organic units, not share.** Share is a trap: it rises when ads units collapse, which
looks like success and is not. A launch can reach an established family's organic SHARE while still
losing money every month, and by share alone it would read "finished". Compare the shares yourself —
`SELECT family, organic_pct, net_profit FROM onyga-482313.OI.V_FAMILY_PNL WHERE period_label='M3'
ORDER BY organic_pct DESC` — and note that the ramp test reads the ABSOLUTE counts, not this column.

**A useful consequence: trajectory is robust to a level bias.** Measuring change rather than level
means a constant COGS misallocation cancels out of the trend — which materially de-risks open item
§9.1 (a launch family's implausible sub-1.0 halo on its early windows). The bias still corrupts the
*level*, so it must be fixed before that family is judged in its months-3+ PROOF phase, but it does
not block the ramp test.

## 6. The daily brief

**This is the SHAPE of the brief, with every number removed** (Standing Rule 0 — the version of this
block that carried real Harvest figures beside illustrative Invest ones invited a reader to quote
either as current, and both were stale within a day). The built object is `V_TWO_BOOK_BRIEF`; read
the live shape with `SELECT * FROM onyga-482313.OI.V_TWO_BOOK_BRIEF ORDER BY sort_order`.

    HARVEST — judged on net profit
      <family>   <net profit>   ROAS <total net>  halo <factor>   bar <bar> / running <ads net>   <verdict>
      ... one row per Harvest family, RANKED BY DOLLARS, not by ratio ...
                                                              Harvest: <sum of the rows above>

    INVEST — declared launches
      <family>   <spend rate> against the sanctioned <$/day> · sanction runs to <end date>
                 organic units <whole month> → <whole month>            <trajectory verdict>
                                                              Invest: <sum of the rows above>

Two lines, never blended, and NO grand total. The month becomes *"Harvest earned X; Invest spent Y of
its declared budget"* instead of *"the account lost Z"* — same money, and only the first sentence was
ever true. An Invest row carries no profit verdict; it reports the spend rate against what was
sanctioned, the date that sanction runs to, whether protection still holds, and the organic
trajectory in absolute units.

## 7. Objects to build

| object | role |
|---|---|
| `V_FAMILY_PNL` | family × period: net profit, total net ROAS, ads net ROAS, halo factor, organic units/share. The measurement spine. |
| `DE_LAUNCH_INVESTMENT` | the declaration: family, monthly ceiling, start/end date, take-over target, declared_by/at. |
| `V_BOOK_ASSIGNMENT` | family → HARVEST/INVEST, derived from the declaration + dates. Default HARVEST. |
| `V_FAMILY_BAR` | family → halo factor and keyword bar (settled 90d, ~~monthly refresh~~ **DAILY refresh — correction 2026-08-20, see §4**, floor 0.60, no credit at or below 1.0). |
| `V_INVEST_STATUS` | sanctioned spend rate vs measured rate, ceiling consumed, sanction end date, organic-unit trajectory, and whether protection still qualifies. |
| `V_DAILY_BRIEF` (extend) | the two-book brief of §6. |
| `V_LAUNCH_EXEMPTION` (modify) | ~~exemption conditional on ceiling + end date~~ **exemption conditional on SPEND RATE + end date — correction 2026-08-20, see §5. NOT BUILT: on hold, this view is not to be edited.** |
| engine consumers (modify) | read `V_FAMILY_BAR` instead of a flat 1.0 breakeven. **NOT BUILT: on hold — correction 2026-08-20.** |

> **CORRECTION 2026-08-20 — WHAT THIS TABLE ACTUALLY DESCRIBES.** It is a build list, not a status
> report, and read as a status report it overstates what exists. Two rows above are the same
> superseded ceiling-only rule §5 corrects; both are struck through rather than rewritten so the
> reasoning trail survives. Current state: rows 1–5 are shipped (`V_FAMILY_PNL`,
> `DE_LAUNCH_INVESTMENT`, `V_BOOK_ASSIGNMENT`, `V_FAMILY_BAR`, `V_INVEST_STATUS`). The
> `V_DAILY_BRIEF` (extend) row was deliberately not taken — a separate `V_TWO_BOOK_BRIEF` was built
> instead, so the daily brief keeps one responsibility; that deviation is recorded in the plan. The
> last two rows are **unbuilt and on hold** under *"Tell the truth now, release nothing"*
> (Ori, 2026-08-20): the launch exemption and the two bid engines are not to be edited, and
> `T_FAMILY_BAR` is materialised daily but no engine reads it. So the bars change no bid, and the
> sanction stops nothing, until that hold is lifted.

## 8. Non-goals

- **No automatic cutting of Harvest families.** Fresh is surfaced with its evidence; the decision
  stays Ori's. Today established that the engine's outcome measurements are weaker than they look.
- **No per-keyword organic attribution.** It does not exist; inventing it would be fiction.
- **No change to the settle discipline, window convention, ownership ladder or preflight gates.**

## 9. Open items and honest limits

1. **A launch family's halo factor sits BELOW 1.0 on its early windows** — total gross profit *below*
   ads-attributed, which is not physically sensible. Almost certainly the COGS tier imputation on new
   products (`project_ads_cogs_price_imputation`). **Downgraded from blocking to scheduled** by the
   §5 ramp test: a constant COGS bias cancels out of a month-over-month trend, so it does not corrupt
   the only judgement that family faces for now. It MUST be fixed before it reaches its months-3+
   PROOF phase, where the level is judged. **ALWAYS NAME THE WINDOW when you quote a halo** — the
   same family reads on opposite sides of 1.0 on `BASELINE_MAY_JUL` and on the settled `M3` window
   the bar actually uses, and quoting the wrong one led a reviewer to conclude the no-credit guard
   was broken when it was not:
   `SELECT family, period_label, halo_factor FROM onyga-482313.OI.V_FAMILY_PNL
   WHERE period_label IN ('M3','BASELINE_MAY_JUL') ORDER BY family, period_label`.
2. **Causality is assumed, not proven.** We cannot prove the halo is caused by ads. The 0.5 credit
   is the hedge, and the feedback loop is the test: if lowering a family's bar does not improve its
   net profit over the following quarter, the credit was too generous and gets cut.
3. **The randomized holdout is parked, not deleted.** It answers a narrower question ("does the
   engine beat no engine"), at a confidence band wide enough that it would not resolve until 2027. It
   was built 2026-08-19 and its verifier found it not yet valid on three counts: a baseline imbalance
   visible on null windows, an export gate protecting only a minority of the keywords in holdout
   campaigns, and Python bulksheet builders bypassing preflight entirely. The measured sizes of all
   three are in `architecture/HOLDOUT.md` and are deliberately not restated here. Its DECLARED trial
   window opens 2026-09-01; if it is not fixed before then it should be formally abandoned rather
   than left to run invalid.
4. **A long-lived Harvest family that leaks needs a DECISION, not just a metric.** A mature family
   with a weak halo and a real dollar loss every window is a business call, not an engine call. This
   design makes it visible; it does not fix it. Size it on the day you act — see the Harvest ranking
   query in §1.

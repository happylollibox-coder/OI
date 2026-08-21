# The last-day veto: testing its premise

**Status:** measured 2026-08-21. Objects deployed: `V_LASTDAY_VETO_PREMISE`,
`V_LASTDAY_VETO_PREMISE_READOUT`, `V_LASTDAY_VETO_LAG_OBSERVED`.
**Related:** `architecture/DAILY_BRIEF.md` (how a held row is recorded), `architecture/HOLDOUT.md`
(why this is not an experiment), `scripts/bigquery/queries/REPEAT_VETO_RUNS.sql` (the
standing-block question), `V_ADS_SETTLE_CURVE` (the accrual the instrument stands on).

---

## 1. What was tested, and what was not

The last-day veto is a symmetric one-day hold. Above its click bar, a filling day reading under
the raise bar holds a raise; a filling day reading at or above the cut bar holds a cut. It has no
state — the next day's re-run is the recheck.

**Not tested: the veto's effect.** A control group for a one-day delay on a few dozen keyword-days
is invisible next to the whole-engine holdout's own minimum detectable effect, which is already
larger than the entire net of the population it measures. Running it would forgo real value to buy
noise.

**Tested: the veto's premise.** The raise arm rests on one claim and nothing else — *a poor filling
day predicts a poor settled day*. That claim is falsifiable on data already held, at zero cost and
with nothing forgone. If a filling `0.00x` usually resolves to a healthy number once attribution
accrues, the arm is firing on attribution lag rather than on performance.

## 2. The obstacle, and why there is no direct reconstruction

`FACT_AMAZON_ADS` is **restated in place**. Nothing in the warehouse snapshots ads data at keyword
grain by load date:

| candidate | why it cannot answer |
|---|---|
| `FACT_ADS_RESTATEMENT` | grain is `(report_date, snapshot_at, channel)` — account level, no keyword |
| `FACT_KEYWORD_STATE`, `FACT_KEYWORD_GUARD` | daily snapshots, but of **settled 90-day** aggregates |
| `FACT_ENGINE_PROPOSALS` | quotes the filling reading verbatim inside a vetoed row's reason — but until v27.98 the veto *erased* those rows, so the snapshots that exist carry essentially none of them |
| Fivetran sync metadata | `_fivetran_synced` says *when* a row was last restated, never what it previously said |

**Ruling: a direct reconstruction of "what keyword K's day D read at age 1" is not possible.** Any
answer must be reconstructed, and must say so.

## 3. The instrument

`V_LASTDAY_VETO_PREMISE` reconstructs the filling reading from the settled row plus the **measured**
account accrual in `V_ADS_SETTLE_CURVE` — the same as-seen technique the 3-vs-7 peak-window study
used. For a fully settled keyword-day at the engine's own last-day grain
`(campaign_id, targeting, date)`:

```
spend_1d  ≈ spend_settled × spend_fill                     spend_fill = age-1 spend share, measured
orders_1d ~ Binomial(orders_settled, sales_fill)           sales_fill = age-1 sales share, measured
roas_1d   ≈ gp_roas_settled × (orders_1d / orders_settled) / spend_fill
```

Orders are treated as exchangeable within the day, which makes every quantity a closed form rather
than a simulation:

```
P(filling day reads exactly 0.00x)       = (1 − sales_fill) ^ orders_settled
P(filling day reads under the raise bar) = BinomCDF(j* − 1; orders_settled, sales_fill)
P(filling day reads at/above the cut bar)= 1 − BinomCDF(j*cut − 1; orders_settled, sales_fill)
```

where `j*` is how many of the day's settled orders must already be attributed for the reading to
clear that bar. Both CDFs are computed inline from log-factorials — no UDF, no simulation, and the
arithmetic on any single row is checkable by hand.

Each keyword-day contributes its **probability** of tripping an arm, not a 0/1, because the filling
reading is a random thinning of the settled day.

### Limits, and the sign of each

* `spend_fill` / `sales_fill` are **account medians** applied to every keyword-day; the model
  describes the average keyword-day and understates both tails.
* Exchangeable orders ignores that a day's last click has less time to convert than its first, so
  real filling days are worse than modelled — **bias in the veto's favour**.
* Gross profit per order is taken as flat within the day — **bias in the veto's favour**.
* The population is every at-volume SP/SB keyword-day, **not** the subset the engine proposed a
  move on that morning. Read every probability as conditional on a published move existing.
* Settled means older than the SB attribution window plus slack. There is no "nearly settled" row.

### The independent check on the model's one real assumption

`V_LASTDAY_VETO_LAG_OBSERVED` is the only **observed** reading of lag at keyword grain:
`SRC_ACC_AmazonAds_purchased_product` splits a keyword-day's conversions by attribution window
(1 / 7 / 14 / 30 days). It answers the question the model cannot ask itself — *is lag a property of
the keyword?* If some search terms bought same-session and others slept on it, the veto would be
wrong on an identifiable subset and the repair would be an exemption, not a retirement.

Its four limits are load-bearing and are stated in full in the view header: the 1-day bucket is
attribution lag only and not age-1 visibility (it is the more optimistic of the two, so findings
drawn from it stay conservative in the veto's favour); the feed does not reconcile to
`FACT_AMAZON_ADS`, so `capture_ratio` is published per row rather than asserted; SP only, because
brand keyword ids in that feed do not join; and a row exists only where a purchase eventually
happened.

**Two model validations, both reproducible from the queries in §4:** the modelled share of
at-volume keyword-days reading exactly `0.00x` while filling reproduces the independently observed
share that motivated the v27.76 gate; and the observed zero-at-one-day rate by settled order count
tracks the uniform-thinning prediction, with only modest excess dispersion across keywords.

## 4. The queries

Both arms, as distributions:

```sql
SELECT * FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE_READOUT`
WHERE row_kind = 'SUMMARY' ORDER BY arm, channel;

SELECT * FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE_READOUT`
WHERE row_kind = 'BAND' ORDER BY arm, channel, settled_band;
```

Does a higher click bar help? (`veto_clk1`)

```sql
SELECT channel,
  CASE WHEN clicks_1d_model <= 15 THEN 'a. 11-15 clicks'
       WHEN clicks_1d_model <= 25 THEN 'b. 16-25'
       WHEN clicks_1d_model <= 40 THEN 'c. 26-40'
       ELSE 'd. 41+' END AS clk_band,
  ROUND(SUM(p_veto_raise_v76), 1) AS mass,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(settled_clears_raise_bar, p_veto_raise_v76, 0)),
                          SUM(p_veto_raise_v76)), 1) AS pct_fine_at_raise_bar
FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE`
WHERE at_volume GROUP BY 1, 2 ORDER BY 1, 2;
```

Does a stricter expected-orders gate help? (`veto_min_expected_orders`)

```sql
WITH g AS (SELECT * FROM UNNEST([2.0, 3.0, 4.0, 5.0, 6.0]) AS gate)
SELECT g.gate,
  ROUND(SUM(GREATEST(p_under_raise_bar
       - IF(expected_orders_1d >= g.gate, 0, p_reads_zero), 0)), 1) AS mass,
  ROUND(100 * SAFE_DIVIDE(
    SUM(IF(settled_clears_raise_bar,
           GREATEST(p_under_raise_bar - IF(expected_orders_1d >= g.gate, 0, p_reads_zero), 0), 0)),
    SUM(GREATEST(p_under_raise_bar - IF(expected_orders_1d >= g.gate, 0, p_reads_zero), 0))), 1)
    AS pct_fine_at_raise_bar
FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE` v CROSS JOIN g
WHERE v.at_volume GROUP BY 1 ORDER BY 1;
```

Is lag a property of the keyword, or of the account? (excess dispersion vs binomial)

```sql
WITH k AS (
  SELECT campaign_id, keyword_id, SUM(orders_final) AS ordF, SUM(orders_1d) AS ord1
  FROM `onyga-482313.OI.V_LASTDAY_VETO_LAG_OBSERVED`
  WHERE orders_final > 0 GROUP BY 1, 2 HAVING SUM(orders_final) >= 8),
s AS (SELECT ordF, SAFE_DIVIDE(ord1, ordF) AS sh FROM k),
m AS (SELECT AVG(sh) AS mu FROM s)
SELECT COUNT(*) AS keywords, ROUND(MIN(m.mu), 3) AS mean_kw_share,
       ROUND(STDDEV(s.sh), 3) AS sd_observed,
       ROUND(SQRT(AVG(m.mu * (1 - m.mu) / s.ordF)), 3) AS sd_if_uniform
FROM s, m;
```

Is a held keyword held again tomorrow? (the standing-block risk)

```sql
WITH k AS (
  SELECT campaign_id, targeting, COUNT(*) AS days, AVG(p_veto_raise_v76) AS p_mean
  FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE`
  WHERE at_volume GROUP BY 1, 2 HAVING COUNT(*) >= 10)
SELECT COUNT(*) AS keywords, ROUND(APPROX_QUANTILES(p_mean, 10)[OFFSET(5)], 3) AS p50,
       ROUND(APPROX_QUANTILES(p_mean, 10)[OFFSET(9)], 3) AS p90,
       COUNTIF(p_mean >= 0.5) AS kw_held_over_half_the_time,
       ROUND(AVG(SAFE_DIVIDE(1, 1 - LEAST(p_mean, 0.99))), 2) AS mean_expected_run_days
FROM k;
```

Run `scripts/bigquery/queries/REPEAT_VETO_RUNS.sql` for the same question on rows actually held,
now that v27.98 records them.

## 5. The rulings

### The cut arm is sound, and the reason is arithmetic rather than statistical

A filling reading can only **overstate** a day in one way: through spend that has not landed yet.
Sales accrue more slowly than spend does, so the reading is
`settled_gp_roas × (attributed share) / spend_fill`, and the attributed share cannot exceed one.
A day whose filling reading reaches the cut bar therefore cannot settle below
`cut_bar × spend_fill`, published on every row as `cut_arm_settled_floor`. At the measured age-1
spend fill that floor sits **above breakeven for both channels**, and the readout confirms the
empirical consequence: the cut arm holds no cut on a day that settled as a loser. The residue it
does hold sits between breakeven and the cut bar — profitable days, where holding the cut was right
anyway.

**The one honest caveat** is published beside it as `cut_arm_settled_floor_worst_fill`: on a day
whose spend fills unusually late, the guarantee weakens because the denominator is further from
final. The floor is a function of the accrual curve, so it must be re-read — not re-derived — if
the feed's timing ever changes.

### The raise arm is firing partly on lag, and cannot be tuned out of it

The held mass does concentrate on days that settled poorly, so the arm is not noise. But a material
minority of the raises it holds land on days that settled **at or above the very bar the veto used
to call them poor** — and the way that share responds to the arm's own dials is the finding:

* **Raising the click bar makes it worse.** The share of holds placed on days that turned out fine
  rises monotonically with the filling day's clicks. More clicks means more orders, and a zero at
  high volume is far more likely to be attribution lag than an absence of demand.
* **Raising the expected-orders gate makes it worse.** The gate keeps only the surprising zeros —
  which is to say the zeros on keywords with the strongest 90-day record, exactly the keywords
  whose sales were most likely still in flight.

Every dial that is supposed to make the arm more confident moves its error rate the wrong way.
That is the signature of an arm reading lag rather than performance, and it is why the answer is
not a tuning.

### Lag is not a property of the keyword

Per-keyword one-day attribution shares are dispersed only modestly more than binomial sampling
alone would produce, and no useful population of chronically-late keywords exists. **The raise arm
cannot be repaired by exempting a slow subset**, because there is no slow subset to exempt.

### The standing-block risk is real in principle and small in practice

Under the v27.76 gate a keyword's per-day probability of tripping the raise arm is low, and the
expected consecutive run is barely longer than a single day. The stateless veto is not, today,
a permanent block wearing a one-day costume — but that is a property of the gate's rarity, not a
property of the design, so it must be re-read from the query in §4 whenever the gate moves.

## 6. Recommended change

**Keep the cut arm exactly as it is. Retire the raise arm.**

The cut arm buys a guarantee that is arithmetic — under-attribution can only make a day look worse,
so a filling day already converting is conservative proof that a cut is premature. Nothing about
the premise test weakens it.

The raise arm buys a hold whose error rate rises with every dial meant to sharpen it, on evidence
that cannot be told apart from attribution lag, in exchange for delaying a move the complete-day
windows had already justified. The complete-day windows end at the watermark minus one and decide
moves on settled data; retiring the raise arm is precisely "wait for a settled day" — it hands the
decision back to the only windows that have one.

If the arm is kept for now, it should be kept **narrow and honest**: the click bar and the
expected-orders gate should not be raised, because both make it worse, and the labelling shipped in
v27.98 means every hold it places is now recorded with its reason and can be audited against this
document rather than argued about.

# The Catalog's forecast chain — design

**Status:** design, 2026-08-25. Derives from `architecture/THREE_LAYERS.md` §2.0, §2.0.1, §1.5, which
win on conflict. Nothing here is built.

**Purpose (§2.0, Ori):** *"The main purpose of the Catalog is not to say what happened in the last 90
days. It is to predict what the result will be for the window the Brain asks him… and strive for at
least 85%."*

---

## 1. The contract

```
ask(subject, window) -> {
    best_cpc,                       -- the price that MAXIMISES contribution; the Catalog finds it
    ceiling_cpc,                    -- the price where contribution reaches ZERO
    expected_clicks,
    expected_orders,
    expected_cost,
    expected_ads_net_roas,
    expected_net_roas,
    expected_family_net_profit,     -- THE OBJECTIVE
    basis,                          -- how each link was estimated
    confidence
}
```

**The Catalog chooses the price (§2.0.1, corrected by Ori).** The Brain never sends a CPC. Finding the
price at which a subject is worth the most *is* establishing worth.

**`best_cpc` and `ceiling_cpc` are different prices and both are published.** The ceiling is the edge of
the cliff; the optimum is where to stand. Today's engine computes only the ceiling (`affordable_bid =
gp_per_click / bar`), which is why it has been bidding at the price where a keyword earns nothing extra.

---

## 2. The chain, link by link

| # | link | how it is estimated | already exists? |
|---|---|---|---|
| 1 | **CPC → clicks** | the response curve, §3 | **no — this is the build** |
| 2 | **clicks → orders** | CVR, shrunk toward the family rate by evidence (§4) | partly |
| 3 | **orders → gross profit** | GP per order, `gpo_f` in the snapshot | yes |
| 4 | **→ ads net ROAS** | `gp / cost` | arithmetic |
| 5 | **→ net ROAS** | ads net ROAS × the family halo factor | yes (`T_FAMILY_BAR.halo_factor`) |
| 6 | **→ family net profit contribution** | `gp × halo − cost` | arithmetic |

**Only links 1 and 2 are modelling.** Everything after is arithmetic on numbers the account already
holds. That is the whole reason the chain is worth building as a chain: **when contribution is wrong,
the error decomposes onto a link**, and four of the six links cannot be the culprit.

---

## 3. The response curve — and the finding that shapes it

**Measured 2026-08-25 over 180 days, 718 keywords with clicks:**

| | |
|---|---|
| keywords with ≥30 days of clicks AND ≥$0.20 CPC spread (fittable) | **253 (35.2 %)** |
| of those, correlation between realised CPC and clicks, averaged | **0.19** |
| **clearly positive** (r > 0.2) | **120 (47.4 %)** |
| **flat — no observable response** (−0.2 ≤ r ≤ 0.2) | **112 (44.3 %)** |
| negative (r < −0.2) | 21 (8.3 %) |

**So the premise holds for about half of the fittable keywords and NOT for the other half.** The curve
cannot be assumed. It must be fit, tested, and abstained from where absent.

**A flat keyword is not a failure — it is an answer, and an important one.** If paying more buys no
more clicks, then the best CPC is the **lowest price that holds current volume**, and every cent above
it is waste. That is a real recommendation the account has never had, and it applies to 44 % of the
keywords we can actually measure.

**Three tiers of evidence, and the third one abstains:**

| tier | population | what the Catalog does |
|---|---|---|
| **FITTED** | ≥30 days of clicks and ≥$0.20 CPC spread — 253 keywords | fit the subject's own curve |
| **POOLED** | has clicks but not enough spread or history | use the family × match-type curve, shrunk toward it by evidence |
| **UNKNOWN** | no usable history | **abstain — publish no forecast** (§2.7: `NO_EVIDENCE` is not `LOW`) |

**Functional form: piecewise-linear over a CPC grid, not a fitted equation.** Evaluate observed
clicks-per-day in CPC buckets, interpolate, and extrapolate flat beyond the observed range. Reasons:
it needs no distributional assumption; it cannot invent a response outside the prices actually paid
(a fitted power law will happily promise clicks at a CPC never tried); and it is legible — a reader can
see the buckets. **Never extrapolate a rising curve past the highest CPC ever paid.**

---

## 4. Conversion — shrinkage, not averaging

CVR at keyword grain is desperately thin: the median subject has **4.2 orders per 7-day window**
(measured §2.0.1). A raw `orders / clicks` on 4 orders is noise.

`cvr_used = (k · cvr_family + n · cvr_subject) / (k + n)` where `n` is the subject's clicks and `k` is a
declared prior weight. A subject with no clicks reads exactly the family rate; a subject with thousands
reads its own. **`k` is a declared constant, tested per §6.1, never tuned silently.**

---

## 5. Finding the best CPC

**Grid search, not calculus.** Evaluate the whole chain at each CPC on a declared grid (the floor to
1.5× the highest CPC ever paid, in cent steps) and take the CPC with the highest
`expected_family_net_profit`. Publish the curve alongside the maximum, because the Brain's real question
is often *how much do I lose by bidding less* — and a flat peak and a sharp peak are different risks.

`ceiling_cpc` falls out of the same grid: the highest CPC where contribution is still ≥ 0.

**Why a grid rather than an optimiser:** every point is explainable, the peak is auditable, and there is
no local-minimum failure mode to reason about. The grid is at most a few hundred points per subject.

---

## 6. Scoring — the 85 %

**Per subject, every link is recorded.** Predicted vs actual for clicks, orders, cost, ROAS,
contribution — so the error decomposes and the Catalog can see *which link* broke (§2.0.1: *"maybe more
clicks, maybe less cpc, maybe something else"*).

**The pass mark is measured on the SUM, at family grain.** Measured 2026-08-25: only **13.8 % of
keywords** take ≥7 orders in a 7-day window, so ±1 sale exceeds 15 % and a per-keyword 15 % target
would be measuring dice. At family grain **100 %** clear it (avg 886.9 orders). So:

> **85 % correct = the family's predicted net profit contribution is within 15 % of actual, on the
> window the Brain asked about.**

Per-subject error is still recorded — it is what says which link to fix — it is simply not the pass mark.

`V_SEAT_REQUEST_OUTCOME` already scores a Catalog claim against actuals (§6.0, shipped 2026-08-25). It
needs pointing at a chain instead of a backward average, plus a family-level roll-up.

---

## 7. What it must refuse to do

- **No forecast without evidence.** UNKNOWN publishes nothing; it does not publish a family average
  wearing a subject's name.
- **No extrapolation above the highest CPC ever paid** on that subject or its pool.
- **No verdict.** The chain is a prediction. Whether the money is spent is the Brain's (§1.1).
- **No demand data moving a verdict on its own** (§2.3) — market volume caps `expected_clicks`, it does
  not create them.

---

## 8. Acceptance

1. Every FITTED subject's curve is monotone non-decreasing in CPC, or is reclassified flat.
2. No subject publishes `expected_clicks` above its own observed maximum × a declared headroom factor.
3. `best_cpc ≤ ceiling_cpc` on every row, always.
4. UNKNOWN subjects publish nulls, never numbers.
5. The chain reconciles: `contribution = gp × halo − cost` to the cent.
6. Backtest against the same five as-of dates used in §2.0, reporting family-level 15 % accuracy
   **against the 55.9 % / constant-guess baseline already measured.** A version that does not beat the
   constant is not shipped.

---

## 9. Build order

| step | what | size |
|---|---|---|
| 1 | `V_CPC_RESPONSE` — the bucketed curve per subject and per pool, plus its tier | 2–3 days |
| 2 | `V_CATALOG_FORECAST` — the chain and the grid search over it | 2–3 days |
| 3 | point `V_SEAT_REQUEST_OUTCOME` at the chain; add the family roll-up and the 85 % | 1–2 days |
| 4 | backtest against §2.0's five dates; ship only if it beats the constant | 1 day |

**Naming stays Amazon's (§1.5).** `campaign_id`, `keyword_id`, `cpc`. Domain assumptions — the settle
lag, the prior weight `k`, the grid bounds, the headroom factor — are **declared constants**, so porting
sets values rather than hunting literals.

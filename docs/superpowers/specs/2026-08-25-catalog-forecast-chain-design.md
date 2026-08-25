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

**The window is 365 days (Ori, 2026-08-25).** Measured both ways before settling it: at 180 days
718 keywords carry clicks and 382 are fittable; **at 365 days, 1,810 carry clicks and 933 are
fittable — 2.4× the base at the same 51.5 % rate.** A year also spans a full seasonal cycle, so the
curve is not fit entirely inside one demand regime. The cost is that a year-old price may no longer
buy what it did, which §4.1 handles by weighting recent buckets more heavily rather than by shortening
the window.

**Measured over the last 180 days of that year, on the subjects fittable there:**

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
| **FLOW** | has clicks but not enough spread or history | use a matching **customer purchase flow** (§4), shrunk toward it by evidence, and **name the flow in the answer** |
| **UNKNOWN** | no usable history | **abstain — publish no forecast** (§2.7: `NO_EVIDENCE` is not `LOW`) |

**Functional form: piecewise-linear over a CPC grid, not a fitted equation.** Evaluate observed
clicks-per-day in CPC buckets, interpolate, and extrapolate flat beyond the observed range. Reasons:
it needs no distributional assumption; it cannot invent a response outside the prices actually paid
(a fitted power law will happily promise clicks at a CPC never tried); and it is legible — a reader can
see the buckets. **Never extrapolate a rising curve past the highest CPC ever paid.**


---

## 3.1 MEASURED 2026-08-25 — the window, not the grouping, is what breaks the forecast

The flow tree was built and then used to predict: every subject at its node's profile, summed to the
family, compared to what the family actually did over the last 28 days. **The result was a decisive
failure, and the failure names its own cause.**

| family | subjects | actual net profit | error, **365-day** profile | error, **28-day** profile |
|---|---|---|---|---|
| Lollibox | 50 | −$1,514 | 394 % | **73 %** |
| LolliME | 142 | +$1,146 | 202 % | 175 % |
| Bunny | 46 | −$723 | 158 % | **82 %** |
| Fresh | 54 | −$667 | 407 % | **10 %** ✅ |
| LolliBall | 35 | −$647 | 425 % | **19 %** |
| UNMAPPED | 42 | −$537 | 145 % | **50 %** |
| Bottle | 13 | +$37 | 506 % | 389 % |

**Same tree, same nodes, same members — only the window changed.** A profile learned over 365 days
predicted **positive** net profit for every family while most were losing money; the same nodes learned
over the prior 28 days got the sign right everywhere and put Fresh inside the 15 % target.

**So the 365-day window is right for one link and wrong for the others.** A year is needed for the
RESPONSE CURVE — its shape needs price variation, and 365 days gives 933 fittable subjects against 382
at 180 (§3). But a year is badly stale for the LEVELS: CVR, gross profit per order, and CPC drift, and a
year-old average of them is not a forecast of next week. **The links need different windows, and only a
chain that is split by link could have shown that.**

**Two corrections this forces, both of things stated earlier in this document.**

1. **"Errors cancel in the aggregate" is only true of UNBIASED errors.** §6 argued the 85 % could be
   met on the sum because per-subject noise averages out. It does — but the 365-day error is not noise,
   it is **bias in one direction**, and bias does not cancel no matter how many subjects are added. The
   aggregate was *worse* than the typical subject, not better.
2. **Percentage error on a near-zero base is meaningless.** Bottle's actual net profit is $37 on 13
   subjects, so a $145 miss reads as 389 %. The 85 % target needs an **absolute floor** — a family whose
   net profit is smaller than the floor is scored on dollars, not on percent — or small families will
   fail the target forever for arithmetic reasons rather than modelling ones.

**What this does not say.** It does not say the tree is wrong: the grouping held its shape while the
window changed underneath it. And it does not say 28 days is the answer — LolliME is 175 % even there,
with the sign inverted, which is a family that genuinely improved recently and a half-life would handle
better than either fixed window.

---

## 4. CUSTOMER PURCHASE FLOWS — what the Catalog uses when it has no data

**Ruled by Ori, 2026-08-25:** *"The Catalog should create assumptions based on other changes it created
— call it customer purchase flows. So when there is no data you can use a customer purchase flow you
know is working in order to estimate it. When you answer the Brain you should write to him if the
estimation was based on data, or mention the customer purchase flow you used."*

This replaces the "shrink toward family × match-type" pooling the first draft proposed, and it is
better for a reason worth stating: **family × match-type is an arbitrary grouping; a flow is a
behavioural one, and it has a NAME.** A named thing can be cited, argued with, and — most importantly —
**scored**.

**A flow is a pattern of how a customer arrives and buys**, learned from subjects that have data and
applied to subjects that do not. Each one carries:

| field | what it holds |
|---|---|
| `flow_name` | e.g. `COMPETITOR_CONQUEST_VIDEO`, `GIFT_OCCASION_EXACT`, `AUTO_DISCOVERY_CLOSE_MATCH` |
| membership rule | **declared**, from fields that already exist: `match_type`, `is_pt`, `channel`, the supervised intent (`DE_SEARCH_TERM_INTENT`, 92.3 % coverage), and Research's `occasion` / `age_group` / `product_type` |
| the learned profile | the response curve shape, CVR, GP per order, from members that ARE fittable |
| its own evidence | how many members, how much data, over what period |
| **its own track record** | how well subjects estimated through it have actually performed |

**The loop that makes this more than a prior: A FLOW IS SCORED TOO.** When a subject estimated through
`GIFT_OCCASION_EXACT` misses, that is evidence about the flow, not only about the subject. Flows
therefore get better with use, and a flow that keeps missing is retired rather than quietly relied on.
This is §6's improvement obligation applied to the assumptions themselves — the part of the Catalog
that *"strives"*.

**A flow is never invented for one subject.** It must have enough fittable members to have been learned
from something, or it does not exist. A flow with one member is that member wearing a general name.

### 4.1 Conversion inside a flow

CVR at keyword grain is desperately thin: the median subject has **4.2 orders per 7-day window**
(§2.0.1). Raw `orders / clicks` on 4 orders is noise.

`cvr_used = (k · cvr_flow + n · cvr_subject) / (k + n)` — the subject's own rate, pulled toward **its
flow's** rate by a declared prior weight `k`. A subject with no clicks reads exactly its flow; a subject
with thousands reads itself. **`k` is a declared constant, tested per §6.1, never tuned silently.**

Recent buckets are weighted more heavily than year-old ones by a declared half-life, which is how a
365-day window is used without pretending a price paid last August still buys what it did.

## 4.2 Disclosure — every answer says where it came from

**The Brain is always told which it got.** `basis` is not optional and is never blank:

| basis | meaning |
|---|---|
| `DATA` | the subject's own fitted curve — with its day count and CPC spread |
| `FLOW: <name>` | estimated through a named flow — **with the flow's own track record attached** |
| `UNKNOWN` | no data and no matching flow. **Publishes nulls, not numbers.** |

A forecast that does not say where it came from is worse than no forecast, because the Brain cannot
weigh it. And a `FLOW:` answer that cannot state the flow's accuracy is a guess with a label on it.

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
6. Every row states its `basis`, and no `FLOW:` row omits the flow's own track record.
7. No flow is used that has fewer than a declared minimum of fittable members.
8. Backtest against the same five as-of dates used in §2.0, reporting family-level 15 % accuracy
   **against the 55.9 % / constant-guess baseline already measured.** A version that does not beat the
   constant is not shipped.

---

## 9. Build order

| step | what | size |
|---|---|---|
| 0 | `DE_CUSTOMER_PURCHASE_FLOW` — the declared flows and their membership rules; learn each profile from its fittable members | 2–3 days |
| 1 | `V_CPC_RESPONSE` — the bucketed curve per subject and per flow, over 365 days, plus its tier and basis | 2–3 days |
| 2 | `V_CATALOG_FORECAST` — the chain and the grid search over it | 2–3 days |
| 3 | point `V_SEAT_REQUEST_OUTCOME` at the chain; add the family roll-up and the 85 % | 1–2 days |
| 4 | backtest against §2.0's five dates; ship only if it beats the constant | 1 day |

**Naming stays Amazon's (§1.5).** `campaign_id`, `keyword_id`, `cpc`. Domain assumptions — the settle
lag, the prior weight `k`, the grid bounds, the headroom factor — are **declared constants**, so porting
sets values rather than hunting literals.

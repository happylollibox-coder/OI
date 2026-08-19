# SOP — V_TARGET_BID_SHADOW / FN_TARGET_BID_SHADOW

**Status: SHADOW. Nothing reads it. Do not wire it into any engine.**
Built 2026-08-11. Supersedes nothing; replaces nothing; competes with nothing yet.

---

## 0. Why this exists, and why it is not switched on

Ori asked: *"Should I change my bids per campaign type or keyword type (general, product) based on
sales — or should I always strive to the bid target no matter sales?"*

The agreed shape of the answer was: **the bid always sits at a TARGET; SALES update the TARGET, not
the bid directly; and how far a keyword's own sales move its target depends on how much evidence it
has.** This object is that design, built, deployed as a shadow and backtested against what the
engine actually did.

v27.40 shipped the previous attempt straight into the live engine and was reverted the same day —
267 rows, $2,457/week of measured harm. Two root causes, both closed here:

| v27.40 root cause | what it was | how this closes it |
|---|---|---|
| **(a) Units** | `target_cpc` was calibrated in CPC units and written into a bid field. Realized CPC ran ~1.26× the stated bid, so every bid overpaid. | `target_cpc` and `target_bid` are separate columns. `target_bid = (target_cpc / k_transfer)^(1/0.686)` — the inverse of the **measured** transfer `realized_CPC = k × bid^0.686`. The 1.425 v27.40 inherited was re-measured and rejected: it is an artifact of `V_TARGET_DAILY.keyword_bid`, which is restamped on every partition refresh (M5). |
| **(b) Estimator** | A last-year-window rule; measured as the worst performer, cutting 44.6% of SP spend at GP-ROAS 1.149. | No LY term anywhere. There *cannot* be one: keyword-grain data starts 2025-10-28, so every keyword's LY window is either missing or its launch ramp. |

And it adds a third failure mode that neither v27.40 nor this brief anticipated — see §4.

---

## 1. The model

```
cvr_hat        account CVR → family → campaign → keyword, empirical-Bayes,
               k = [300, 2500, 1000] clicks, stored as a RATIO to the account
               level, multiplied by the freshest settled 28-day level
gp_per_order   MEASURED family constant, SUM(GROSS_PROFIT)/SUM(Ads_orders), 90 settled days
breakeven_cpc  gp_per_order × cvr_hat
target_cpc     breakeven_cpc / 1.4021
target_bid     (target_cpc / k_transfer)^(1/0.686)
               clamped to [per-format floor, min($2.00, 0.70 × breakeven_cpc)]
               then the season gate
```

### 1.1 The target GP-ROAS is derived, not chosen

This is the one place the model departs from the brief, and it matters.

**Pricing to breakeven is a zero-net-profit objective.** GP-ROAS = 1.0 means gross profit exactly
equals ad spend. A bid model that aims there aims at making nothing.

The profit-maximising bid puts the **marginal** click at breakeven, not the average one. With
`clicks(b) = C·b^η` and `cpc(b) = k·b^γ`:

```
d(GP)/db = d(spend)/db   ⇒   θ·η·GP = (η+γ)·spend
⇒   target GP-ROAS = (η + γ) / (θ · η)
```

where θ is the value of a marginal click relative to the average click. Using the measured
η = 1.706 and γ = 0.686:

| θ | target GP-ROAS | target_cpc as a fraction of breakeven_cpc |
|---|---|---|
| 1.00 (marginal click as good as average) | **1.402** | 0.713 |
| 0.85 | 1.650 | 0.606 |
| 0.70 | 2.003 | 0.499 |

**That 0.499–0.713 range reproduces, from first principles, the independently measured 0.49–0.70×
safe bid band.** Two unrelated calibrations landing on the same interval is the strongest single
piece of corroboration in this work. The view ships θ = 1.0 (T = 1.4021) — the conservative end in
bid terms.

Sensitivity of T to the elasticity CIs at θ = 1: **1.32 – 1.50**. It is not a knife-edge.

### 1.2 What is NOT in the model, and why

Measured, out of sample, and rejected — these are the direct answer to Ori's question:

| candidate | verdict |
|---|---|
| campaign type (SP/SB) | 0.6% of a held-out keyword's CVR variance, CI [−17.2, +14.3]. Not a segment. Also *not comparable*: SP orders are `purchases_30_d`, SB `attributed_conversions_14_d`. |
| target type (keyword vs product/ASIN vs auto) | 3.8%, CI [−25.5, +23.7]. As a standing level it makes the model **worse** (−0.77 pt). Ori's raw 1.62× "product converts better" is Simpson's paradox: 54% of SP PRODUCT clicks are LolliME, 78% of SP KEYWORD clicks are Lollibox. |
| match type | 2.3%, CI [−32.6, +23.8]. Also unidentified — only 3 of 68 SP and 2 of 35 SB campaigns run more than one match type. |
| SB ad_format | 0.00 pt as a level. Also degrades the bid→CPC transfer. |
| intent, season, placement | intent is family re-encoded; season is a level factor, not a keyword attribute; placement is ASIN-targeting seen from the other side — do not count it twice. |
| ASIN / campaign / target's own margin history | none beat a flat family margin constant out of sample. Margin evidence is ~25× scarcer per target than CVR evidence. |

Target type survives in exactly one place: as the **cold-start entry prior** for a campaign with no
history (family × target_kind, +7.97 pt leave-one-campaign-out, P = 0.905). It is an entry prior
only, dropped the moment the campaign has clicks.

### 1.3 Family label

`gp_per_order` and the CVR family pool are keyed on **`V_DIM_CAMPAIGN_FAMILY`**, not
`ASIN_BY_CAMPAIGN_NAME`. The `ASIN_BY_CAMPAIGN_NAME` CASE in
`scripts/bigquery/procedures/SP_FACT_AMAZON_ADS.sql` (lines 118–138) has no Bunny or LolliBall
branch and its terminal `ELSE 'B0C1VLXYBP'` files all 20 of those campaigns as White Lollibox — 16.5%
of current non-defense spend priced at $21.36/order when the truth is $5.36–5.92. This view routes
around the defect. **The defect still needs fixing at source**; everything else keyed off
`ASIN_BY_CAMPAIGN_NAME` still has it.

---

## 2. Objects, and how to change them

| object | file | note |
|---|---|---|
| `FN_TARGET_BID_SHADOW(anchor DATE, apply_season_gate BOOL)` | `scripts/bigquery/functions/FN_TARGET_BID_SHADOW.sql` | **all logic lives here** |
| `V_TARGET_BID_SHADOW` | `scripts/bigquery/views/V_TARGET_BID_SHADOW.sql` | 5-line wrapper; pins anchor and gate, filters `is_live` |

Edit the function, never the view, or the live view and the backtest drift apart. The function is
parameterized precisely so the backtest evaluates **byte-identical arithmetic** at historical
anchors.

`apply_season_gate` exists because `V_KEYWORD_CONTEXT_GATE` is current state with no anchor
parameter. Pass `FALSE` for any historical evaluation or you leak the future.

**Determinism:** deployed and read twice, byte-identical (md5 `b8187b2e6755ffe81854d4105e06e4f7`,
344 live rows at anchor 2026-07-11). No `ANY_VALUE()` anywhere; `MIN()` and
`ARRAY_AGG(... ORDER BY ... LIMIT 1)` are used instead so a tie resolves the same way on every run.
No ratio divides two `ANY_VALUE()`s (M6).

---

## 3. The backtest

**Design.** Four anchors. Each fits on the 90 settled days ending at the anchor and is evaluated on
the 30 days after it. Everything sits inside the settled region (SP `purchases_30_d` ⇒ D−30 cut, so
nothing later than 2026-07-11 is used).

| fold | anchor | test window | targets | actual spend | actual net | actual GP-ROAS |
|---|---|---|---|---|---|---|
| Z (calibration input only) | 2026-03-13 | 03-14 … 04-12 | — | — | — | — |
| A | 2026-04-12 | 04-13 … 05-12 | 130 | $16,906 | $4,098 | 1.242 |
| B | 2026-05-12 | 05-13 … 06-11 | 145 | $22,318 | $3,318 | 1.149 |
| C | 2026-06-11 | 06-12 … 07-11 | 245 | $23,299 | −$2,167 | 0.907 |
| **pooled** | | **90 days** | **520** | **$62,524** | **$5,249** | **1.084** |

Coverage of in-window non-defense clicks: 99.6% / 94.9% / 83.6%. The fold-C shortfall is targets
launched *after* the anchor — unpriceable at decision time, correctly absent.

**Counterfactual.** For every target we know what happened (clicks, spend, gross profit) and what bid
actually ran (reconstructed SCD2 bid, click-weighted — never `V_TARGET_DAILY.keyword_bid`, per M5).
Under a different bid `b₁`, with `r = b₁/b₀`:

```
clicks₁ = clicks₀ · r^1.706        cpc₁ = cpc₀ · r^0.686
spend₁  = spend₀  · r^2.392        gp₁  = gp₀ · (clicks₁/clicks₀)^θ
```

Campaign budgets bind (counterfactual campaign spend capped at `budget × 30`). θ = 1.0 is the
headline and is **generous to raises**; θ is swept at 1.2 / 0.85 / 0.70 with T re-derived each time.

**Every arm uses the same pricing pipeline and the same clamps.** Arms differ only in how they
estimate a target's value per click. That is what makes the segmentation comparison clean.

---

## 4. What the backtest found

### 4.1 Bidding straight to the target loses money

| arm | Δ net, 90 held-out days | 95% CI (campaign-cluster bootstrap, 1000 reps) | P(beat doing nothing) |
|---|---|---|---|
| **model at full strength (λ = 1)** | **−$6,576** | [−8,704, −67] | **0.010** |
| model damped, λ = 0.25 | +$1,380 | [+144, +2,500] | 0.941 |
| do nothing (freeze bids at anchor) | +$29 | [−1,157, +1,783] | — |
| LY rule as v27.40 shipped it | −$481 | | |
| **the v27.40 units bug, on this model's own target_cpc** | **−$12,519** | | |
| ORACLE — knows each target's realised value/click | +$13,987 | [+7,949, +17,242] | 1.000 |

Two things to take from that.

The **units bug alone costs $12,519 per 90 days ≈ $974/week** on $62.5k of settled spend. The sibling
bid→CPC study, on a different book four months later by a completely different method, put the same
defect at $2,247/week price-only. Same sign, same order, two independent routes. **That is the single
most valuable thing in this work and it is a guardrail, not a model.**

And ORACLE says the money is real: +$13,987 is there for a model that knows what a click is worth.
This model does not capture it. Understanding why is the rest of the report.

### 4.2 Why: the transfer function cubes your error

```
bid    ∝ vpc^(1/γ)     = vpc^1.458
clicks ∝ vpc^(η/γ)     = vpc^2.487
spend  ∝ vpc^((η+γ)/γ) = vpc^3.487
```

A **+30% error in estimated value-per-click becomes a +150% error in spend** on that target. Measured
here: click-weighted sd of `log(predicted vpc / realised vpc)` = 0.406, which by Jensen alone inflates
expected spend **2.7×** before any bias.

Gross profit rises with the *square* of the value estimate; spend rises with the *cube*. A value
estimate unbiased in logs **still overspends in expectation**. This is a property of the transfer
function, not of this CVR model — every target-bid model on this account inherits it, and it is a
third failure mode that neither v27.40 nor the brief anticipated.

### 4.3 The cross-section is good. The level is not. And the level cannot be fixed by lagging.

| | corr(log predicted, log realised vpc) | slope of realised on predicted |
|---|---|---|
| account level only | +0.074 | +0.384 |
| family | +0.275 | +0.844 |
| **model (family→campaign→keyword)** | **+0.697** | **+0.979** |

Slope 0.979 means the cross-sectional spread is **correctly scaled** — the hierarchy is not
over-confident about which keyword is better. It works.

The level does not. Realised value per click ÷ predicted, by fold: **Z 1.216 · A 0.751 · B 0.960 ·
C 0.731.** In three of four periods the model is off by 20–27%, and the sign flips.

I tried the obvious operational fix — carry the previous period's ratio forward as a calibration
scalar (legitimate: at anchor A everything ≤ A is settled, so the model fitted at A−30 and the
outcomes over (A−30, A] are both available). **It does not work.** The bias is not persistent enough
one period ahead:

| λ | model raw | model with lagged calibration |
|---|---|---|
| 0.25 | +$1,380 | +$1,484 |
| 1.00 | −$6,576 | **−$10,113** |

At full strength the calibration makes things materially *worse*, because fold Z's +21.6% correction
was applied to fold A, where the truth was −25%. Recorded as a **failed** experiment; the level
problem stays open.

### 4.4 Damping, and the asymmetry that matters

```
bid = bid_now × (target_bid / bid_now)^λ
```

| λ | 0 | 0.15 | 0.25 | 0.35 | 0.50 | 0.75 | 1.00 |
|---|---|---|---|---|---|---|---|
| Δ net, 90d | +$22 | +$1,136 | **+$1,380** | +$1,275 | +$484 | −$2,533 | −$6,576 |

Optimum λ ≈ 0.25, flat over 0.15–0.35. At θ = 0.85 the optimum is ≈ 0.25–0.35; at θ = 0.70 it is
≈ 0.5. λ = 0.25 is conservative across the whole θ range. It means a target whose model bid is double
its current bid moves **+19%, not +100%**.

Split λ by direction and the picture sharpens dramatically:

| λ_up ↓ / λ_down → | 0.00 | 0.25 | 0.50 | 1.00 |
|---|---|---|---|---|
| **0.00** | +$22 | +$2,138 | +$3,286 | **+$4,231** |
| 0.25 | −$735 | +$1,380 | +$2,528 | +$3,473 |
| 0.50 | −$2,780 | −$662 | +$484 | +$1,430 |
| 1.00 | −$10,766 | −$8,641 | −$7,510 | −$6,576 |

**The model's CUT signal is worth acting on. Its RAISE signal is not.** Never raising and cutting all
the way to target scores +$4,252 (this arm, implemented directly) — beating symmetric λ = 0.25 by
+$2,851 [1,721, 4,376], P = 1.000. That is exactly what the convexity predicts: raising amplifies
error into spend at the cube, cutting shrinks exposure to it.

### 4.5 THE NULL TEST — and it is the most important table here

The counterfactual mechanically rewards cutting anything below GP-ROAS 1.402, and the book runs at
1.084. So before crediting the model for its cuts, cutting **blindly** has to be ruled out.

| arm | spend | Δ spend | GP-ROAS | Δ net, 90d | $/wk |
|---|---|---|---|---|---|
| actual | $62,524 | — | 1.084 | 0 | 0 |
| blanket cut every bid ×0.9, no model | $48,687 | −$13,837 | 1.165 | +$2,796 | +$218 |
| blanket cut every bid ×0.8, no model | $36,744 | −$25,780 | 1.263 | +$4,401 | +$342 |
| **blanket cut every bid ×0.7, no model** | $26,877 | −$35,647 | 1.381 | **+$4,986** | **+$388** |
| model cuts only, to target | $43,133 | −$19,391 | 1.220 | +$4,252 | +$331 |
| model cuts only, all at a flat −20% | $47,132 | −$15,392 | 1.184 | +$3,432 | +$267 |
| ACCOUNT-level model cuts only | $38,184 | −$24,339 | 1.249 | +$4,272 | +$332 |
| blanket ×0.856, **sized to the model's exact spend** | $43,150 | −$19,373 | 1.205 | +$3,605 | +$280 |
| ORACLE cuts only | $33,037 | −$29,486 | 1.435 | +$9,122 | +$710 |

Paired bootstrap, 1000 reps:

| comparison | point | 95% CI | P(A > B) |
|---|---|---|---|
| model cuts vs blanket ×0.7 | −$734 | [−2,581, +945] | 0.202 |
| **model cuts vs blanket sized to the same spend** | **+$647** | [−574, +1,944] | 0.859 |
| model cuts vs the same rows cut a flat −20% | +$820 | [+114, +1,585] | **0.988** |
| model cuts vs **ACCOUNT-level** model cuts | −$19 | [−1,650, +1,690] | 0.475 |
| model cuts vs do nothing | +$4,223 | [+2,476, +5,830] | 1.000 |

Read that carefully.

* **Almost all of the gain is a LEVEL move, not a targeting move.** A dumb uniform bid cut captures
  more of it than the model does. The dominant fact about this book is that it bids above the
  profit-maximising point — GP-ROAS 1.084 against a target of 1.402 — and that is one number, not 520.
* **The per-keyword hierarchy is worth nothing in dollars here.** An account-level constant with no
  segmentation at all scores within $19 of the full family→campaign→keyword model (P = 0.475). This
  holds even though the hierarchy demonstrably predicts CVR far better (corr +0.70 vs +0.07). Better
  CVR prediction did not become money, because the cubic amplification eats it.
* **What the model *does* add is magnitude, not selection.** Given the same set of rows to cut, using
  the model's number rather than a flat −20% is worth +$820, P = 0.988. That is the one per-target
  contribution that clears the noise.

Robustness — at θ = 1.2 (marginal click *better* than average, the assumption that most disfavours
cutting) the blanket cut's advantage collapses and the model's does not:

| θ | model cuts-only | blanket ×0.7 | do nothing |
|---|---|---|---|
| 1.20 | **+$1,783** | +$792 | −$541 |
| 1.00 | +$4,252 | +$4,986 | +$29 |
| 0.85 | +$6,998 | +$8,485 | +$541 |

So the model beats the blanket cut precisely when the blanket cut is not almost free. That is
reassuring about the model and damning about the counterfactual's sensitivity to θ.

---

## 5. The verdict, plainly

**Does bidding to this target beat doing nothing?**

* At full strength: **no.** −$6,576 over 90 held-out days, P(better than doing nothing) = 0.01.
  Materially harmful, for the same structural reason v27.40 was.
* Damped to λ = 0.25: **probably yes, by about +$1,380 per 90 days ≈ $107/week**, 95% CI against
  doing nothing [−$227, +$2,411], P = 0.94. Suggestive, not proven.
* Cuts-only (never raise, cut to target): **+$4,252 per 90 days ≈ $331/week**, P = 1.000 vs doing
  nothing — but a blindly uniform −30% bid cut scores +$4,986, so this is not a model result.

**The three competing claims:**

| claim | status |
|---|---|
| "Always strive to the target rather than reacting to sales" | **Supported.** Every target-priced arm beats the LY reactive rule, and the architecture (sales → target → bid) survives. |
| "Segment bids by campaign type or keyword type" | **Rejected.** 0.6% and 3.8% of a held-out keyword's CVR, both CIs spanning zero; as standing levels they make the model worse. In dollars, family × target-type and family × channel both score below plain family. |
| "A keyword's own sales should move its target in proportion to its evidence" | **Half supported.** The empirical-Bayes shrinkage is what makes the cross-section work (corr +0.70, slope +0.98) and its magnitudes are worth +$820 (P = 0.99) once you have decided what to cut. But it is worth $0 against an account-level constant for *choosing* what to cut, and the bid step needs its own damping on top (λ ≈ 0.25) because the transfer cubes whatever error survives. On today's book the average target's bid is only **9.9% its own data** — 30.2% campaign, 58.0% family, 2.0% account. |

**The finding that dominates all of them:** the account bids above the profit-maximising point. Moving
the whole book's target CPC down is worth several times more than any per-keyword targeting, and it is
one decision, not 520. But it is a strategic decision — a −30% blanket bid cut contracts clicks ~42%
in this model — and it belongs to Ori, not to a bid engine.

---

## 6. What must be true before this is wired into anything

Four gates, in order. None is optional.

1. **Ship the units guardrail first, on its own.** Any code path that assigns a CPC-scale quantity to
   a bid field must go through `(target_cpc / k_transfer)^(1/0.686)`. That defect measures at
   $974/week here and $2,247/week in the sibling study. It is worth more than the model and needs
   none of it.
2. **Never ship the raw target.** Whatever consumes this applies λ ≈ 0.25, or λ_up = 0 with a
   damped λ_down. Bidding straight to `target_bid` is a measured loss at P = 0.99.
3. **Fix the level, or accept that this is a level tool.** The model misprices the account by 20–27%
   per period, the sign flips, and the obvious lagged calibration fails. Until that is solved, the
   per-keyword machinery is not earning its keep and the honest use of this view is as a *cut list
   with magnitudes*, not as a bid source.
4. **Fix the family label at source** — `SP_FACT_AMAZON_ADS.sql` lines 118–138: add Bunny and
   LolliBall branches, change the terminal `ELSE 'B0C1VLXYBP'` to `NULL`/`UNMAPPED`. This view routes
   around it; nothing else does.

Cheaper than all four: **audit the placement bid adjustments.** 133 campaigns carry a top-of-search
adjustment averaging +92.7%, 48 carry a product-page adjustment averaging +181%. That is why 20% of
spend clears above the stated bid. The bid model is bidding into a multiplier the account set itself.

---

## 7. Today's book (anchor 2026-07-11, 344 live targets)

| action | targets | 28d spend | median target_bid ÷ bid_now |
|---|---|---|---|
| CUT | 236 | $8,331 | 0.46 |
| RAISE | 48 | $1,319 | 1.27 |
| HOLD | 27 | $648 | 0.96 |
| PARK_UNPRICEABLE | 29 | $160 | 0.29 |
| NO_CURRENT_BID | 4 | — | — |

Binding clamp: NONE 208 · SAFE_CEILING 57 · FLOOR 43 · BELOW_FLOOR 32 · SEASON_BLOCK_CUT 4.
Season gate touches 50 rows; 22 targets are cold-start.

Mean evidence weights: own 0.099 · campaign 0.302 · family 0.580 · account 0.020.

---

## 8. Known limits

1. **The counterfactual is elasticity-based, not causal.** η = 1.706 and γ = 0.686 were measured
   within-target on 384 real bid changes; they are short-run and absorb whatever budget reallocation
   followed. Every estimate is marginal — one target at a time — and ignores cross-target
   interference inside a budget-capped campaign. **The blanket-cut numbers extrapolate hardest and
   should be treated as directional only:** a −30% whole-book bid cut is far outside the support of
   the events the elasticities were fitted on.
2. **θ is assumed, not measured**, and it is the largest unmeasured quantity here. Whether the
   marginal click is worth the average click decides both the target GP-ROAS (1.40 vs 2.00) and
   whether the blanket cut beats the model. Everything is reported across θ ∈ {1.2, 1.0, 0.85, 0.70}
   and the qualitative verdict holds, but θ deserves its own study — it is the obvious next one.
3. **ORACLE is an optimistic ceiling.** It is scored on the same realised gp/click that drives the
   counterfactual, so a target that got lucky looks valuable *and* performs well by construction.
4. **520 target-folds, ~130 campaign-folds, 90 test days.** The bootstrap clusters by campaign, which
   is the right unit, but the intervals are wide and the λ = 0.25 verdict is one bad quarter from
   being overturned.
5. **The lagged-calibration arm is a negative result on n = 3 transitions.** It failed here; that is
   weak evidence that it always fails.
6. **The LY comparison is partial.** It reproduces `V_OOB_KEYWORD`'s `ly_cpc` (same-28-days-last-year
   realised CPC, ≥10 LY clicks, keyword text, auto/product excluded). The band fallback
   (`DE_PRODUCT_STRATEGY_PROFILE`) is current-state with no history and cannot be reconstructed at a
   historical anchor, so the LY arm only reprices the ~13% of rows where the LY term fires.
7. **SB bid history starts 2026-04-01** (`sb_keyword` SCD2), so folds Z and A lean more on SP.
8. **The season gate is off in the backtest** (`apply_season_gate = FALSE`) because
   `V_KEYWORD_CONTEXT_GATE` has no anchor parameter. Its live effect is unmeasured.
9. **Launch campaigns are inside the population.** Under the no-loss-cuts launch doctrine they are
   *expected* to lose money while the right bid is found, so the model's cuts on them are not
   automatically correct. This view does not know which campaigns are launches; a consumer must.

---

## 9. Reproduction

BigQuery scratch (read-only build; the only writes are `TMP_TGT_*` and the two shadow objects):
`TMP_TGT_BT` (model at 4 anchors × actual outcomes), `TMP_TGT_BT_SEG` (competing segmentations fitted
on the same windows). Both rebuild from the SQL below.

Scripts, all under
`/private/tmp/claude-504/-Users-ori-Develop/3cf66eb9-f161-4996-95fa-fd3ad8ee1193/scratchpad/bid/`:
`bt_build.sql` · `seg.sql` (panels) · `bt2.py` (arm comparison) · `bt3.py` (damping, error
amplification, repricing footprint) · `bt4.py` (level vs cross-section) · `bt5.py` (lagged
calibration) · `bt6.py` (asymmetric damping) · `bt7.py` (the null test).

---

# 10. Placement — the correction of 2026-08-11

Ori: *"Bid is different from CPC because some campaigns have placement adjustments."* He is right, and
it invalidates part of §4.2. `k_transfer` was fitted as a per-`(channel × target_kind)` constant. It is
not a constant. It silently blended the **auction** (a thing you must fit) with each campaign's
**placement settings** (a thing you can simply look up). Shadow view: `OI.V_BID_CPC_TRANSFER`.

## 10.1 The corrected form

```
realised_CPC = k_pure(channel × target_kind) · bid^γ · M(campaign)
bid          = ( target_cpc / (k_pure · M) )^(1/γ)

M(campaign)  = Σ_p  click_share_p · I_p · (1 + adj_p/100)^β
```

| parameter | value | 95% CI | how measured |
|---|---|---|---|
| γ | **0.778** | [0.638, 0.872] | within-**target** FE WLS of log cpc on log bid; 2,799 target-days / 270 targets / 93 campaigns / 24,828 clicks; campaign-cluster bootstrap |
| β (contested) | **0.725** | [0.550, 0.908] | within-**campaign** WLS of log(cpc_p/cpc_OTHER) on log(1+adj/100), placement-specific intercepts; 127 campaign-placements, 39 dosed |
| β (brand defense) | **0** | — (n=1 at the click bar) | four campaigns at +500%, both channels, realise 0.85–1.48× where β = 0.725 predicts 4.2× |
| I_TOS / I_DP / I_OTHER / I_OFF | 1.162 / 0.939 / 1.000 / 0.418 | | click-weighted premium vs the campaign's own *Other on-Amazon*, measured on **un-adjusted campaigns only** |
| k_pure SP KEYWORD / AUTO / PRODUCT | 0.9286 / 0.8505 / 0.8415 | | γ pinned at 0.778, level fitted on log(cpc) − log(M) |
| k_pure SB PRODUCT / KEYWORD | 0.7759 / 0.8665 (fallback) | | SB KEYWORD too thin to fit |

**Bids are the exact `old_bid`/`new_bid` pairs OI itself posted** (`V_PPC_CHANGE_LOG_APPLIED`), carried
forward to the next posted change. Never `V_TARGET_DAILY.keyword_bid`; never the Fivetran SCD2 mirrors.

## 10.2 Detail page is intrinsically *cheaper* than rest of search

I_DP = 0.939. A detail-page uplift therefore buys, at a premium, inventory that was available **below**
base rate. This statement needs no pass-through estimate at all and it is the cleanest way to describe
what is wrong with a +300% detail-page setting.

## 10.3 The brand-defense split is load-bearing, not a cosmetic exclusion

On brand terms you own the auction, so a second-price multiplier never binds. Applying a **single** β to
the whole account makes this model **worse than having no placement term at all** — held-out RMSE
+8.2%, and the cross-campaign slope of log(cpc/bid^γ) on log(M) collapses to +0.030. Setting β = 0 on
brand defense restores it: slope **+0.951 [+0.462, +1.380]**, held-out RMSE **−8.5%**. Do not
"simplify" this away. Note the asymmetry in what is established: the *estimate* of 0 rests on one
campaign clearing the ≥10-click-both-arms bar; the *falsification of β = 0.725* on that population is
what is strong, and it is strong (predicted 4.2×, observed 0.85–1.48× on four independent campaigns).

**Product defense is the opposite of brand defense** and must not be lumped with it: the four
`*-SP/PT (Product Defense)` campaigns at +300% detail page show implied β of 0.49 / 0.76 / 0.99 / 1.05.
Competitor detail pages are contested; your own brand terms are not.

## 10.4 Does the correction pay, and can the account tell?

Yes, and yes. Leave-one-**campaign**-out, held-out RMSE of log(cpc):

| population | clicks | pooled | corrected | Δ |
|---|---|---|---|---|
| all | 24,828 | 0.3066 | **0.2805** | **−8.5%** |
| M < 1.05 | 17,992 | 0.2814 | 0.2661 | −5.4% |
| M 1.05–1.15 | 4,857 | 0.2658 | 0.2457 | −7.5% |
| M ≥ 1.15 | 1,979 | 0.4939 | 0.4094 | **−17.1%** |

Monotone in the dose. That monotonicity is the signature of a correctly specified known input rather
than an extra free parameter. M ranges **0.895 → 4.260** across 142 campaigns (click-weighted 1.092);
**25% of window spend sits at M ≥ 1.15**, so this is not a rounding error on a tail.

## 10.5 How much of the 0.686 exponent was really placement

**+0.007 of exponent and 3.9 percentage points of within-R².** Essentially none — and the sign is *up*,
not down.

It could not have been much. The adjustment is a campaign-level constant, and 0.686 came from a
within-target design, so the only route in is **mix shift** — and mix does not move with the bid:
log(M_mix) on log(bid) with target FE has slope **+0.0005**, R² **0.00000**. What the old `k` was wrong
about is the **level**, and only for the campaigns that carry a real uplift.

γ = 0.778 [0.638, 0.872] **contains 0.686**, so there is no contradiction with §4.2. The higher point
estimate is what errors-in-variables predicts once the bid is measured without noise. If it holds, it
also softens §4.2's error amplification: spend ∝ vpc^((η+γ)/γ) falls from **3.487 → 3.03**, and the
inverse exponent 1/γ from **1.458 → 1.286**.

## 10.6 Known defects — read before trusting a level

1. **No adjustment history exists anywhere.** `campaign_placement_bidding` and
   `sb_campaign_bid_adjustments_by_placement` carry one row per campaign+placement and
   `_fivetran_synced` is *"last time the API returned this record"*, not *"when the value was set"*. M is
   a current snapshot applied to a historical window, and that is **provably wrong** for the four
   `*-SP/PT (Product Defense)` campaigns whose +300% switched on in June 2026 (detail-page impression
   share 0.00–0.07 → 0.47–0.91 in one month). **Re-read the view before every run.**
2. **The arithmetic bound still fails.** On dynamic-bids-**down-only** campaigns a second-price auction
   cannot charge more than bid × M. Using the exact bids OI posted, **31–43% of down-only clicks
   violate it** in every target kind (AUTO 32.7%, KEYWORD 43.0%, PRODUCT 31.2%). So either some posted
   bids never took effect, or `DIM_CAMPAIGN.bidding_strategy` is stale, or there is a multiplier nobody
   has found. Until that is closed, `k_pure` is provisional; γ and M are ratio designs and do not depend
   on it.
3. **`targeting_report.keyword_bid` is restamped and must never be used for history.** Worked example:
   target `445052966395752` reads `keyword_bid = 0.41` on every historical date including 2026-08-02,
   when the SCD2 mirror and the realised CPC ($1.157) both say the bid was $1.13. This is the raw
   Fivetran defect behind the known `V_TARGET_DAILY.keyword_bid` warning.
4. **`ad_group_history` keeps no bid history** — 982 of 990 ad groups carry exactly one distinct
   `default_bid`. Any reconstruction that falls back to the ad-group default is unfounded before the
   last change.
5. **SB shopper-cohort multipliers** (up to +150%, on the largest SB campaigns) compound with the
   placement lever and their **exposure share is in no report**, so they cannot enter M.
   `sb_cohort_max_pct` is carried as a flag: where it is set, **M is an under-estimate**.
6. **`SITE_AMAZON_BUSINESS` is a site adjustment, not a placement.** Its clicks sit inside the four
   placement rows and cannot be separated. Carried as a flag, not netted out.
7. **Population.** The γ fit rests on targets the coach actually touched between 2026-06-14 and
   2026-08-09. Untouched targets are unrepresented.
8. **`campaign_id` is STRING** in `campaign_placement_bidding` and both `sb_*` adjustment tables and
   **INT64** in `campaign_placement_report`. Cast, or the join returns zero rows silently — which is
   very likely why this lever stayed invisible.

## 10.7 What to change in `FN_TARGET_BID_SHADOW` (not yet changed)

Replace the `k_transfer` CASE with `k_pure(channel × target_kind) × M(campaign)` read from
`OI.V_BID_CPC_TRANSFER`, and move γ from 0.686 to 0.778. Nothing has been wired; both objects remain
shadow.

## 10.8 Reproduction

Scratch: `OI.TMP_PLA_AUD_PLACE` · `TMP_PLA_AUD_CAMP` · `TMP_PLA_AUD_MAIN` (audit) ·
`TMP_PLA_BIDPANEL` (the target-day bid panel driving γ). Audit output:
`.tmp/placement_adjustment_audit_20260811.csv` (221 campaigns — every campaign carrying any
adjustment, including the 115 with zero clicks).

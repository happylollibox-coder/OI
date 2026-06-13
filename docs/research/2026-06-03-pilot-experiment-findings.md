# Pilot Experiment — Findings for the Automatic Campaign Creator

> Source: Ori's research from a 24-day live pilot (May 11 – June 3, 2026) running two
> parallel experiments (PILOT-* and p1-* prefixes) on the Happy Lolli Amazon Ads account.
> **Status: provisional — single-run, off-season.** Adopt the *principles*, treat the
> *constants* as hypotheses pending the 2-year validation in §12. Implementation phasing:
> see `docs/superpowers/specs/2026-06-13-pilot-findings-implementation-phases.md`.

---
## TL;DR — what to change in the campaign creator
1. **Switch the pilot success metric from absolute ROAS ≥ 3.0 to FAMILY-RELATIVE ROAS.** A pilot is judged against its product family's average ROAS, not a fixed number.
2. **Adopt a two-objective evaluation:** (a) near-term profit, (b) cheap-CPC banking for peak season. "Losing" campaigns are not automatically failures.
3. **Evaluate on a trailing window, not lifetime cumulative.** Cumulative ROAS punishes pilots for early ramp-up cost they've already recovered.
4. **Use recent days asymmetrically:** recent good days may trigger SCALING; recent bad days may NOT trigger cuts (attribution lag biases recent data downward).
5. **CVR is the only reliable ROAS predictor.** CTR, bid, and CPC do not predict ROAS. Gate decisions on CVR + volume.
6. **Match type: Broad discovers, Phrase converts narrowly.** Don't kill Phrase for low volume; kill it for low CVR after enough clicks.
7. **Filter pre-loaded negatives** so they never block the pilot's own keyword.
8. **Never let a product negate its own proven winners** (we found White Lollibox negating "teen girl gifts" as exact, a term that converts for it).
---
## 1. FAMILY-RELATIVE ROAS (replaces absolute 3.0 target)
### What we learned
Off-season, families perform very differently. Measured family ROAS (May 25–Jun 3, fully settled):
| Family | ROAS |
|---|---|
| ME (LolliME) | 3.30 |
| BOX (Lollibox) | 2.30 |
| BRAND-STORE | 1.90 |
| FRESH | 1.45 |
| BOTTLE | 1.29 |
A pilot at ROAS 2.5 is **below average** in the ME family but **above average** in BOX. The same absolute number means opposite things depending on family. A flat 3.0 target would wrongly close viable BOX/FRESH/BOTTLE campaigns that are actually beating their family.
### Rule to implement
```python
relative = pilot_roas / family_roas   # family = all campaigns on the same product family
if   relative >= 1.20:  action = SCALE
elif relative >= 0.80:  action = HOLD
elif relative >= 0.50:  action = KEEP_ALIVE_REDUCE_BID   # cheap CPC bank
else:                   action = CLOSE_CANDIDATE          # only if volume confirms (see §5)
```
`family_roas` is computed from the trailing settled window across all campaigns mapped to that product family (use portfolio name, fall back to campaign-name inference).
---
## 2. TWO-OBJECTIVE FRAMEWORK (off-season vs peak)
### What we learned
The account has a strong seasonal cycle (peak around gifting season). Off-season, the operator deliberately wants to keep some unprofitable-today campaigns alive to:
- bank cheap CPC history on relevant product keywords,
- hold/grow organic relevance and rank,
- be positioned to win cheap, high-volume clicks when peak demand arrives.
So a campaign losing money in June can be a **strategic investment** for Q4, not a failure.
### Rule to implement
Add a campaign objective tag:
```python
objective ∈ { "PROFIT", "CPC_BANK" }
```
- **PROFIT** campaigns: must clear family-relative ≥ 0.8 or get cut.
- **CPC_BANK** campaigns: kept alive at a floor bid as long as:
  - the keyword is product-relevant (descriptive, not just demographic), AND
  - CPC stays cheap (cpc ≤ family_avg_cpc), AND
  - it still gets *some* impressions (relevance signal intact).
  CPC_BANK campaigns are exempt from the close rule until `peak_prep_date - lead_time`.
Config additions:
```python
peak_season_target_date: date      # when cheap-CPC campaigns must be ready
keep_alive_floor_bid: float        # e.g. 0.35 (operator-set; pending confirmation)
cpc_bank_relevance_required: bool = True
```
---
## 3. EVALUATE ON A TRAILING WINDOW, NOT LIFETIME CUMULATIVE
### What we learned
Two pilots (WHITE-BROAD-gift-for-13+yo, WHITE-BROAD-birthday-gifts-10-12) looked like failures on 14-day cumulative ROAS (2.64, 2.73) but their **recent** 6-day ROAS was 4.51 and improving — because the early launch days carried ramp-up cost that was already recovered. Cumulative averaging hid the recovery.
### Rule to implement
At each checkpoint, compute ROAS over the **trailing 7 settled days**, not lifetime:
```python
window_end   = today - attribution_lag_days       # 3
window_start = window_end - 7
roas_recent  = sales(window_start..window_end) / spend(window_start..window_end)
# use roas_recent for graduate/close; keep cumulative only as a secondary sanity check
```
---
## 4. ATTRIBUTION LAG + ASYMMETRIC USE OF RECENT DAYS
### What we learned (measured across 10 days with repeated pulls)
A single day's ad-only ROAS is **understated** when read fresh, because sales attribute late but spend does not. Average uplift from first read to settled: **+19%** (median ~16%). Settles by ~day 3. Does not compound; plateaus at the true value.
Uplift factor by data age:
| Age of day | Multiply observed ROAS by |
|---|---|
| 1 day old | ~1.16 |
| 2 days old | ~1.08 |
| ≥3 days old | 1.00 (settled) |
### Rule to implement (asymmetric — important)
Because the bias is one-directional (recent data can only be too LOW, never too high):
```python
# SCALING decisions: may use recent days. Trigger on RAW (uncorrected) ROAS.
#   If raw already clears the scale threshold, it's genuinely good (raw = worst case).
if action == SCALE and raw_roas >= scale_threshold and clicks >= 10 and orders >= 2:
    do_scale()
# CUTTING decisions (reduce bid / pause / close / negative):
#   FORBIDDEN on data younger than `attribution_lag_days` (3).
#   A low recent reading may simply be unsettled.
if action in {REDUCE_BID, PAUSE, CLOSE, ADD_NEGATIVE}:
    require day_age >= 3   # else defer
```
Net: **recent days can only earn a campaign more budget, never less.** When normalizing for reporting, multiply *sales* (not spend) by the uplift factor, then recompute ROAS.
---
## 5. CVR IS THE DOMINANT (ONLY) ROAS PREDICTOR
### What we learned (correlation across all pilot keyword-weeks)
| Predictor | Correlation with ROAS |
|---|---|
| CVR | **+0.95** |
| Impressions | +0.70 |
| Clicks | +0.56 |
| CPC/Bid ratio | −0.28 |
| Bid | +0.09 (noise) |
| CPC | −0.09 (noise) |
| CTR | **−0.01 (none)** |
Winners and losers had nearly identical bid, CPC, and CTR. They differed almost only on CVR (≈45× gap between winner and loser cohorts). **CTR is a vanity metric here** — high CTR campaigns still lost money.
### Rule to implement
- Use **CVR (after enough clicks)** as the primary signal. Do not optimize toward CTR.
- Minimum clicks before trusting CVR: **≥20** for a go/no-go (at 10 clicks the CVR estimate is too noisy).
- For brand-new keywords with no ad history, seed the CVR prediction from the parent ASIN's **SQP CVR** on that query.
- Volume gate to avoid small-sample luck: require **≥10 clicks AND ≥2 orders** before SCALE. (Several "ROAS 14–84" rows were a single lucky 1-click order — do not scale on those.)
---
## 6. MATCH TYPE: BROAD DISCOVERS, PHRASE CONVERTS NARROWLY
### What we learned
- **Broad** match drove most discovery volume and most of the orders.
- **Phrase** match was low-volume but, when it did get clicks on the right keyword, sometimes converted at very high CVR (e.g. MINT-PHRASE-cute-diary: 8 clicks → 3 orders, ROAS 14.9; MINT-PHRASE-cute-notebooks: ROAS 8.2).
- Do **not** kill Phrase for low volume alone — kill it for low CVR after sufficient clicks. Many Phrase pilots were simply starved at $0.65–0.78 bids and never got a fair test.
### Rule to implement
- Launch each pilot keyword in **both Broad and Phrase**.
- Phrase low-traffic handling: raise bid (up to ceiling) to earn a fair sample before judging. Only close Phrase if it has clicks but no CVR.
- Match-type-aware bid raises: **Auto/Broad expand match scope when bid is raised → cap raise at +5%.** Phrase/Exact stay narrow → +20% raises are fine.
---
## 7. KEYWORD CHARACTER: PRODUCT-DESCRIPTIVE BEATS AUDIENCE-DESCRIPTIVE
### What we learned
- **Product-descriptive** keywords (what the item IS) converted: "journaling kit", "cute notebooks", "cute diary", "journal kit for girls ages 8-12".
- **Audience-descriptive** keywords (who it's FOR) mostly did not: "teen gifts for girls", "gifts for girls age 8-10", "cute things for teen girls" — these attracted browsers, not buyers.
- The single worst pilot, WHITE-BROAD-teen-gifts, burned the most spend with near-zero orders across 130+ clicks.
### Rule to implement
In discovery, **rank product-descriptive candidates above audience-descriptive ones.** Tag each candidate keyword; down-weight or defer pure demographic/gifting phrases unless SQP shows strong CVR for that exact query on that ASIN.
---
## 8. NEGATIVE-KEYWORD SAFETY (two hard rules)
### 8a. Filter pre-loaded negatives so they never block the pilot keyword
When seeding a new pilot with negatives inherited from existing ASIN campaigns, drop any negative whose text is a substring of the pilot keyword. (We caught existing Mint campaigns negating "notebook"/"cute"/"kit" — exactly the pilot terms. Unfiltered, they'd have zeroed out the pilots.)
```python
safe_negs = [n for n in inherited_negs if n.lower() not in pilot_keyword.lower()]
```
### 8b. Never let a product negate its own proven winners
Audit existing negatives against the promote-to-exact list before peak. We found **White Lollibox negating "teen girl gifts" / "gifts for teen girls" as exact negatives**, yet those queries convert for White. Self-blocking. Before each season, reconcile negatives against proven converters and remove conflicts.
### 8c. Relevance check before adding a negative
Do NOT negate a search term just for "≥7 clicks, 0 orders." At ~3% category CVR, 7 clicks → expected ≈0.2 orders, so zero is normal noise. Only negate if the term is **also off-topic/irrelevant** to the product. Relevant-but-not-yet-converting terms stay (they may be CPC-bank value).
---
## 9. CHECKPOINT LOGIC (updated)
Replace the old fixed Day-7/Day-14 absolute-ROAS tables with:
```
DAILY:
  - add negatives only for irrelevant terms (see §8c), only on data ≥3 days old
  - SCALE on recent good days (raw ROAS clears threshold + volume gate)  [§4, §5]
CHECKPOINT (Day 7, Day 14, then weekly):
  metric   = trailing-7-settled-day ROAS                                 [§3]
  relative = metric / family_roas                                        [§1]
  if clicks_total < 10:                 CLOSE (no demand) unless CPC_BANK + relevant
  elif relative >= 1.20:                SCALE (raise budget; +25–100% by confidence)
  elif relative >= 0.80:                HOLD
  elif relative >= 0.50:                KEEP_ALIVE at floor bid (CPC bank)  [§2]
  else (relative < 0.50):
        if clicks >= 25 and orders == 0: CLOSE
        else:                            KEEP_ALIVE at floor bid
  NEVER close on data younger than 3 days.                               [§4]
  Day-7 max action on a loser is bid reduction, never close.
```
Budget-cap handling: if a campaign hits >80% budget utilization with healthy ROAS, **raise budget, not bid** (raising bid changes match scope unpredictably for Auto/Broad).
Halo: true ROAS ≈ reported × 1.10 (next-day organic correlates with today's ad spend at r≈0.64). Optionally accept graduates whose reported ROAS×1.10 clears the family bar.
---
## 10. CONFIG DELTA (add these keys)
```python
# evaluation
roas_mode: str = "family_relative"          # was "absolute"
eval_window_days: int = 7                    # trailing settled window (was cumulative)
attribution_lag_days: int = 3
attribution_uplift = {1: 1.16, 2: 1.08, 3: 1.00}
# recent-day asymmetry
allow_scale_on_recent_days: bool = True      # raw ROAS + volume gate
allow_cut_on_recent_days: bool = False       # cuts require age >= attribution_lag_days
# volume gates
min_clicks_for_cvr_trust: int = 20
scale_min_clicks: int = 10
scale_min_orders: int = 2
# two-objective
objectives_enabled: bool = True
peak_season_target_date: date = None         # OPERATOR TO SET
keep_alive_floor_bid: float = 0.35           # OPERATOR TO CONFIRM (0.25 / 0.35 / 0.40)
# keyword character
prefer_product_descriptive: bool = True
# match-scope safety
broad_auto_max_bid_raise_pct: int = 5
phrase_exact_max_bid_raise_pct: int = 20
```
---
## 11. OPEN ITEMS FOR THE OPERATOR (need answers to finalize automation)
1. **peak_season_target_date** — when must CPC-bank campaigns be ready?
2. **keep_alive_floor_bid** — 0.25 / 0.35 / 0.40?
3. Should **p1** campaigns be folded into the same automated framework, or kept as a separate manual track? (They live in production portfolios, not isolated — attribution is noisier.)
4. Confirm family→portfolio mapping so `family_roas` is computed from the right buckets.
---
## 12. VALIDATION STILL PENDING (2-year DB)
The above thresholds come from one 24-day run. Confirm against 2 years of history before hard-coding:
- CVR↔ROAS correlation stability over time and across families
- The 8% CVR floor vs the family-relative approach (which generalizes better?)
- Attribution uplift factors (1.16 / 1.08) by season and family
- ASIN-level CVR ranking stability (is Mint LolliME reliably the best ME ASIN?)
- Day-of-week ROAS pattern (weekend ≈ −28% observed short-term)

# Out-of-budget phase — Weekly Run

**Date:** 2026-07-30 · **Owner:** Ori · **Status:** v2 — campaign → keyword → search-term hierarchy + apply-all (v1: campaign-level advisory)

## Goal (Ori, verbatim intent)

> "Main goal is that campaigns won't be out of budget but use almost all their budget.
> If campaign is out of budget and performs good — raise budget."

A **technical phase**, deliberately straightforward: one screen listing every enabled campaign
(SP **and** SB, launch **and** working) that Amazon reported `CAMPAIGN_OUT_OF_BUDGET` on the
anchor day, with the dark %, utilization, performance and ONE budget suggestion each.

## Where

Weekly Run page, its own collapsible section directly **below the Coach-logic flowchart** and above
the launch cards. Component: `dashboard-react/src/pages/OobBudgetPhase.tsx` · cube `OobBudget`
(live read) · view `scripts/bigquery/views/V_OOB_BUDGET_PHASE.sql`.

## Rules (same definitions as the launch controller's budget ladder — applied uniformly)

Signals: `pct_dark` = share of the anchor day Amazon reported out-of-budget (from the unified
`V_SRC_AmazonAds_campaign_history` event log — see CAMPAIGN_LAUNCH_RAMP.md §"Status source");
net ROAS = corrected gross profit ÷ spend, 1.0 = breakeven (SP from FACT + price-tier COGS; SB
estimated via the campaign's mapped ASIN cost ratio, same as `V_SB_LAUNCH_CAMPAIGN`).

**Tier split (Ori 2026-07-30 v3):** evidence windows scale with the budget tier — small campaigns
are judged daily, working campaigns on their working cadence. STRONG needs BOTH windows; CUT needs
BOTH windows bad (symmetric evidence, no one-day verdicts).

| tier | condition (first match wins) | action | suggested budget |
|---|---|---|---|
| all | dark ≤ 10% | WATCH | — |
| ≤ low-budget cap ($20 off / $30 peak) | last-day ≥ 1.2× AND prev-2d ≥ 1.5× | RAISE_STRONG | `LEAST(budget ÷ %active, ×3)` |
| | last-day ≥ 1.2× | RAISE_WEAK | `LEAST(budget ÷ %active, ×2)` |
| | last-day < 0.9× AND prev-2d < 0.9× | CUT | −10%/day toward $10 |
| | else | HOLD | — |
| > cap, off-season (7d/28d windows) | 7d ≥ 1.2× AND 28d ≥ 1.5× | RAISE_STRONG | same formulas |
| | 7d ≥ 1.2× | RAISE_WEAK | |
| | 7d < 0.9× | CUT | −10%/day toward $10 |
| | else | HOLD | — |
| > cap, peak (3d/7d windows) | 3d ≥ 1.2× AND 7d ≥ 1.5× | RAISE_STRONG | |
| | 3d ≥ 1.2× | RAISE_WEAK | |
| | 7d < 0.9× | CUT | |
| | else | HOLD | — |

> cap cadence throttle: re-suggest only when the last budget change is ≥ 7 days old (off-season) /
≥ 3 days (peak) — the working-campaign rhythm.

`budget ÷ %active` is the projection of what a full serving day would cost — the raise that makes
the campaign *stop* being dark, which is the phase's goal state: **dark 0%, utilization ~85–100%**.

## v2 — keyword and search-term layers (Ori 2026-07-30)

Hierarchy on the panel: **campaign → keywords → search terms**, with one **apply-all** button that
queues every suggestion (budget updates + bid updates + term negations) into the DO queue /
bulksheet flow. Mechanism note (validated in data 2026-07-30): bid cuts do NOT reduce spend — the
budget caps spend either way; they lower CPC so the same budget serves more of the day. 69% of
dark-campaign spend sat on 6+-click keywords, so the −5% lever touches most of the money.

**Keyword layer** (`V_OOB_KEYWORD` — SP keywords/auto/PT **and SB keywords/product targets**;
v2.1, Ori: "i cant see sb keywords as a hierarchy". SB signals from the SB reports with the
est.-net-ROAS cost-ratio method; SB bids from the live sb_keyword / sb_product_target config
mirrors. **Target CPC column** (Ori: "based on time last year if data exists"): precedence =
(1) same 28 days one year back (364-day offset keeps weekday alignment; needs ≥10 LY clicks),
(2) else the coacher band `cpc_target` (product × season × match, conclusive ALL/ALL cells
averaged), (3) else — . Auto clauses/PT skip LY — the clause text is not product-specific.):
same constants as the launch controller, applied to every OOB campaign regardless of engine —
- CONVERTING (net ROAS ≥ 1.0 on last day OR prior-2d) while CAPPED (Ori 2026-07-30, BOX-VIDEO/PT
  case): **never raise the bid** — with clicks ≥ the 4-click goal and bid above the realized 3-day
  CPC, **FIT the bid down to that CPC** (−15%/day, floored at real CPC): "increase budget to $15
  offers ~5 more clicks, but reducing the bid gets more clicks from the same budget." Both levers
  fire together: budget raise buys volume, cheaper clicks buy more of it. Otherwise hold. The ROAS
  ladder raises (+15%/+30% toward $2) survive only in the launch controller's NOT-capped branch.
- NOT converting → **budget-constrained probing economics** (Ori 2026-07-30: "the under-4-clicks
  is due to low budget not low bid" — 10 keywords × 4 clicks at ~$1 CPC = $40 of probing demand on
  a $10 budget; the purpose is to find a winner who then funds the others). In a dark campaign,
  first match wins:

  **SEAT MODEL (Ori 2026-08-01, "lets do it" — supersedes spreading the budget over every target):**
  a capped campaign can only afford to TEST `slots = max(1, round(budget ÷ $4))` keywords at once
  ($10 → 3 seats, $20 → 5, $30 → 8; ~$4/day buys one keyword its 4-click trial). Seats are ranked:
  **(1) converting keywords by recent net ROAS** (winner is always main), **(2) mid-test keywords by
  clicks-so-far** (finish what you started), **(3) untested candidates** by target-CPC-anchored /
  LY-volume rank. Tested losers (≥15 clk/90d, 0 orders) are never seated. Everything beyond the
  seats **PARK_WAITs at $0.25 in a queue** — its test pauses, not dies. When a seat frees (a test
  reaches its 15-click verdict) the next candidate **ACTIVATEs** at `min(1.5 × target CPC, $1.50)`
  (fallback: the per-seat affordable CPC). Growth is paced by the 20% rule: at most
  `max(1, floor(0.20 × budget ÷ $4))` activations per day — 80% of any budget raise keeps feeding
  the winners. The per-seat affordable CPC = `budget ÷ (slots × 4)` (≈$0.83 on $10/3 seats)
  replaces the old all-targets affordable as the TRIM target: real trial economics, not a number
  diluted by ten idle bids. Real example (ME-SP/PT Competitors Mint C1, $10, 10 targets): 90d spend
  $115 — $72 went to two tested losers while the two converters took $32; the seat model gives the
  3 seats to the 1.23× winner, the 1.03× marginal and the 7/15 mid-test, queues 5, parks the rest.
  1. **tested ≥ 15 clicks over 90d, no sale → PARK at $0.25** — it had its test; free the budget
     for the untested keywords, even if the parked bid gets no clicks.
  2. **bid above the affordable CPC with REAL evidence (≥ 4 clicks yesterday) → TRIM toward it** —
     the affordable CPC = `budget ÷ (targets × 4-click goal)`, floored $0.20 (Ori: "TRIM floor
     should not stop at $1.00"). Step = `max(15%, 30% × dark)` per day. Evidence gate added
     2026-08-01 (Ori: "cheap gift for girl has only 1 click but action is reduce bid due to bid
     eats the budget") — 1–2 clicks is NOT proof the keyword eats the budget; those rows fall to
     the campaign-wide brake below.
  3. **any keyword that clicked YESTERDAY, above the $0.20 floor → DARK_BRAKE** (Ori 2026-08-01:
     never brake a keyword that did not click — its bid did not eat the budget) (2026-08-01, replaces flat SLOW
     −5%): the bid lever against darkness is CAMPAIGN-WIDE and proportional — step =
     `max(5%, 30% × dark)` per day (68% dark → −20%/day; 82% → −25%/day), re-fires every day the
     campaign stays capped, floor $0.20 — Ori: "bid should be reduced with more than 5% and
     continue reducing until dark is 0%" (single-keyword BOX-VIDEO/PT case) and "no keyword is the
     eater — the campaign bleeds from many small bids" (VIDEO- COMP/BALL case). The brake stops
     when the campaign leaves the dark set (dark ≤ 10%, the phase's WATCH tolerance).
  4. zero clicks in both windows → **HOLD, never probe up** — the constraint is budget, not bid.
     (+5% probing survives only in the launch controller's NOT-capped branch.)
  A found winner automatically becomes **main**: the others park/trim, the freed budget flows to
  him, his ROAS ladder raises him, and campaign profitability triggers the budget promotion.
- 1-day cooldown: a keyword changed < 1 day ago (FACT_PPC_CHANGE_LOG) shows HOLD "changed today".

**Search-term layer** (`V_OOB_SEARCH_TERM`, SP + SB, TWO windows — Ori 2026-07-30: "to negate
general big words need to check 3 month data; small volume words 28 days are enough"):
- **big general word** (≥ 30 clicks over 90 complete days **ACCOUNT-WIDE**, all campaigns SP+SB —
  per-slice volume fragments a big word into "small" pieces; caught by Ori on "teen girl gifts
  trendy stuff": 13 clicks in one slice, 1,326 clicks / 11 orders account-wide) → negate only on
  **0 orders anywhere in the full 90d**, AND (Ori 2026-07-30, the 2-week-old campaign case: "too
  early to negate — only after real 90 days with at least 25 clicks I will consider") only in
  campaigns **≥ 90 days old** with **≥ 25 clicks for this word in this campaign** — a young
  campaign hasn't given a big word its own trial yet;
- **small word** → negate at **≥ 10 clicks · 0 orders over 28d**;
plus the structural rules: the term is not the keyword itself (`term ≠ keyword`, normalized —
applies to MANUAL and SB keywords), AUTO targets skip the term≠keyword test (every auto term
differs by construction; the 0-order gate protects harvesting), PT targets excluded entirely
(the "term" is the targeted ASIN). Winners (orders in 90d) are shown, never negated.

`days_since_budget_change` (from `FACT_PPC_CHANGE_LOG`) is displayed so re-suggestions after a
fresh change are visibly "just changed".

## Lever 2B — 80/20 portfolio + probe rotation (Ori 2026-07-30, `V_KEYWORD_LIFT`)

Working campaigns only (budget > low-budget cap), SP **and SB** (v2 2026-07-30), dark or not.
Window W = 7d off-season / 3d peak. Classes over W (corrected net ROAS): WINNER ≥ 1.1 with ≥ 1
order · MARGINAL 0.7–1.1 with orders · LOSER < 0.7 or clicks with 0 orders · IDLE (candidate pool).

**80% of spend to winners:** losers ranked best-first (ROAS desc) keep spending inside a 20%
exploration allowance; everything beyond it PARKs at $0.25. **1–2 probes at a time**: next
candidate (anchored first, then LY volume) lifts to `min(1.5 × target CPC, $2)` (fallback:
winners' avg CPC); the probe episode is STATELESS — measured as FACT activity after the last
INCREASE_BID upload (change log); bid moves daily during the test (6+ clicks/day no sale → −5%);
**verdict at 20 episode clicks**: ≥ 1.0× → WINNER_FOUND (joins the 80% pool), else PARK and the
next 1–2 candidates promote. Goal: every un-parked keyword profitable over W — the best keyword
per intent at the best bid. Probing keywords are exempt from PARK/TRIM and (by design) from the
coacher's pullback; this engine's verdicts take precedence for keywords it touched within W.
Panel: `KeywordLiftPhase.tsx` ("Portfolio 80/20") below the Out-of-budget section; rows route to
the SP/SB bulksheet tab by the view's `channel` column.

**SB arm (v2, 2026-07-30).** Coverage audit 2026-07-30: 9 enabled SB working campaigns
(~$2,525/wk — e.g. ME-VIDEO/EXACT $200, FRESH-VIDEO/BROAD $100, ME-VIDEO/BROAD Hunter $53) had
NO keyword engine — not dark (outside the OOB phase), budget > cap (off the launch controller),
and V_KEYWORD_LIFT was SP-only. Same classes / 20% allowance / probe machinery on SB-native
sources, the way `V_SB_LAUNCH_TARGET` mirrors `V_LAUNCH_PHASE1`:

- **Population:** `V_DIM_CAMPAIGN_CURRENT` `campaign_type='SB'`, ENABLED + serving
  (ENABLED / OUT_OF_BUDGET), budget > cap — same predicate as the SP arm.
- **Targets + live bids:** the minutes-fresh config mirrors `sb_keyword` ∪ `sb_product_target`
  (enabled, not deleted; SB has no auto clauses); ad-group `default_bid` fallback as SP.
- **Performance:** `sb_search_term_report` (keyword_id grain) ∪ `sb_target_report` (target
  grain) — **NOT `sb_keyword_report`** (died 2025-12-29; `sb_product_target_report` does not
  exist). Anchor day = sb_search_term_report watermark (per-channel anchors, same as this phase).
- **Net ROAS:** the SB ESTIMATE `sales × (1 − mapped-ASIN cost_ratio) ÷ spend` — SB reports have
  no per-unit COGS (same method as all SB views). Orders = `attributed_conversions_14_d`.
- **Target CPC precedence:** LY same-28d (keyword text, account-wide, ≥10 LY clicks) → the FINE
  band cell (`campaign_type='SB'` × ad_format via `DIM_AD_GROUP.creative_type` × match,
  CONCLUSIVE) → the coarse ALL/ALL band. Product targets skip LY (band or nothing).
- **Probe episodes:** stateless, same as SP — last INCREASE_BID in `FACT_PPC_CHANGE_LOG`
  (keyword_id holds the SB target id), 14d lookback, episode evidence = SB report activity after
  the upload date, verdict at 20 episode clicks.
- **Capped guard — both arms (v3 2026-07-30; SB-only in v2):** `PROBE_START` requires the
  campaign NOT capping (dark ≤ 10% on the anchor day, from the channel's own event log — SB
  anchored on its report watermark, SP on FACT's `wm`) — in a capped campaign under-clicking is
  the budget dying, not the bid; probing up is a budget artifact (the no-loss-cuts rule). Idle
  keywords there show IDLE "capped — probes held". Running probes still get verdicts and the
  −5% descent. The SP gap was latent when closed: on 2026-07-30 no SP PROBE_START sat in a dark
  campaign (BOX-SP/AUTO (White), 22% dark, had 0 probe starts).

## Known caveats

- SB campaigns overdeliver up to **2× daily budget** while "out of budget" (Amazon SB rule) —
  utilization > 100% on SB rows is real spend, not a bug.
- For LAUNCH campaigns the suggestion matches `V_LAUNCH_PHASE1`'s dark-gated branch by
  construction (same constants); the not-dark branches (starve / promotion) live only in the
  launch controller — this phase only covers campaigns that actually went dark.
- Anchor day per channel: SP anchors on FACT's watermark, SB on `sb_campaign_report`'s — each
  channel is judged on its own last complete day, mirroring the two launch engines.

## v4 — the Portfolio absorbs the launch controller (Ori 2026-08-01)

"The launch controller cards should also be part of Out of budget or Portfolio 80/20 with the seat
mechanism. Format of Portfolio 80/20 should be the same as Out of budget (actions on the 3
hierarchies — campaign, keyword, search term/negate)."

- **Two sections only.** Out of budget owns every campaign capping (dark > 10%); the **Portfolio
  80/20 owns every healthy enabled campaign — ANY budget, both channels** (V_KEYWORD_LIFT v4
  dropped the budget > cap population filter). The launch-controller card section is retired from
  the Weekly Run page. Partition verified: 19 OOB + 89 Portfolio = 108 servable campaigns.
- **Seat mechanism everywhere:** slots = max(1, round(budget/$4)) in the Portfolio too — seats
  ranked proven (roas90/class, probes protected) → mid-tests by clicks → anchored candidates;
  tested losers (≥15 clk/90d, 0 orders) permanently park; beyond-seat rows PARK_WAIT $0.25;
  PROBE_START requires a free seat AND the 1–2-probe pace AND not capped.
- **Same grammar:** the Portfolio panel renders the OOB columns (item | dark | now $ | last day |
  prev-2d | CPC/target | action | → $ | apply | why) on three levels — campaign rows carry the
  launch controller's BUDGET engine output (V_LAUNCH_PHASE1 / V_SB_LAUNCH_CAMPAIGN suggestions;
  the launch controller lives on as the budget engine, its bid logic superseded by seats),
  keyword rows carry the seat/probe verdicts with last-day and prev-2d windows, term rows carry
  the two-window negates (V_OOB_SEARCH_TERM engine='LIFT').

## v5 — graduation budget rule + Brand defense section (Ori 2026-08-01)

- **Graduation budget fix (ONE-TIME, 2026-08-01):** campaign 7d net ROAS > 1.0 AND budget < $30
  → $31 (past both season caps). Ori: "this suppose to be one time bulksheet" — executed as a
  10-campaign bulksheet (8 SP + 2 SB, .tmp/budget_graduation_onetime_20260801.xlsx), NOT a
  standing rule. The engines' campaign-grain suggested_budget/budget_reason columns remain as
  NULL hooks for future budget logic; ongoing budgets run on the existing ladders.
- **Brand defense is its own section** (campaigns named '%Brand Defense%'): excluded from
  Out-of-budget and Portfolio displays. The moat doctrine enforced in data: defense keywords get
  action DEFENSE (never parked/probed by ROAS — the coacher defense mode owns bids, raising
  toward the $2 hard cap), and defense campaigns are excluded from V_OOB_SEARCH_TERM entirely
  (never negate brand terms in defense). The only lever on the panel is BUDGET (incl. the
  graduation rule). Partition: OOB (dark, non-defense) + Portfolio (healthy, non-defense) +
  Brand defense (all 8) = 108 servable.
- **2×2 layout (Ori 2026-08-01):** the two engine surfaces render split by budget tier —
  "Low budget — out of budget" (dark, ≤ cap) · "Portfolio 80/20 — out of budget" (dark, > cap) ·
  "Low budget" (healthy, ≤ cap) · "Portfolio 80/20" (healthy, > cap) · "Brand defense".
  Presentational only (tier prop on the panel components); engines unchanged. Partition verified
  15 + 4 + 61 + 20 + 8 = 108.

## v6 — Ori's tuning round (2026-08-01)

| knob | value |
|---|---|
| Loser allowance | **20% off-season / 40% peak** |
| Max probes per campaign | **2 off-season / 4 peak** |
| Dark ladder, working tier | STRONG ×1.5 @ prev-2d ≥ 1.5 AND today ≥ 1.2 · WEAK ×1.25 @ today ≥ 1.2 · CUT @ evidence (7d off / 3d peak) < 0.6 AND today < 0.6 → GREATEST(×0.8, floor) |
| Dark ladder, low tier | STRONG ×2 · WEAK ×1.5 (same conditions) · CUT @ prev-2d < 0.6 AND today < 0.6 → GREATEST(×0.8, floor) |
| Budget floor | **$10 off-season / $15 peak** |
| Healthy campaigns (all tiers) | ONE budget rule: W AND today both < 0.6 → −20% to the floor (raises belong to the dark ladder — a healthy campaign is not hitting its cap). Brand Defense EXCLUDED from the auto-cut (moat doctrine); flag to include. |
| Raise formulas | fixed multipliers (the budget ÷ %active projection retired) |

## v7 — negate bars on SQP market data (Ori 2026-08-01)

> "big word is a search term with more than 1000 sells for amazon in last 90 days [per SQP] and
> sqp have 90 days data on it and this campaign is at least 90 days old, and this campaign gave
> it ≥25 clicks of its own trial and this campaign have no sells then negate. if exist in sqp but
> do not has 90 days of data — wait. Small word — everything else: 15 clicks, 0 sales, 28 days."

- **BIG word** = the MARKET buys it: > **1,000 Amazon purchases in 90 days** per SQP
  (`FACT_SEARCH_QUERY.TOTAL_PURCHASES`, deduped per query-week), **and** SQP history on the term
  spans ≥ 90 days. Negate only when: campaign ≥ 90 days old AND ≥ 25 clicks of its own trial AND
  **this campaign** has no sales on the term (the account-wide-orders test is retired — a term
  converting elsewhere may still be negated here).
- **SQP-WAIT**: term exists in SQP with < 90 days of history → no negate of either kind until the
  market data matures (~1,790 term rows protected on day one).
- **SMALL word** (everything else, incl. terms Amazon never surfaces in SQP): **15 clicks**
  (raised from 10) · 0 sales · 28 days at this slice.
- Unchanged guards: term ≠ keyword · AUTO skips the same-word test · PT excluded · never in
  Brand Defense.
- First run: OOB 25 negates (9 big + 16 small) · Portfolio 29 (6 big + 23 small); sample big
  negate: 'gifts for 10 year old girl' — 5,949 market purchases/90d, 37 clicks here, 0 sales.

## v8 — seasonal revival + target-vs-bid reductions (Ori 2026-08-02)

Ori: "1. implement the seasonal revival rule 2. the out of budget methodology should catch dark
campaigns 3. if target < bid and net ROAS is marginal reduce slowly toward the target bid
4. if target < bid and net ROAS is loosing reduce to the target bid."

**Seasonal revival** (`seasonal_now`, both engines — `V_KEYWORD_LIFT` + `V_OOB_KEYWORD`):
- Signal: the keyword TEXT (account-wide) had **≥ 1 ad order in this same 28-day window last
  year** (364-day offset, the same `ly` CTE that anchors the personal target CPC). Auto clauses
  and product targets excluded. The window slides daily, so "christmas gift for girl" flips
  seasonal in late October automatically and flips back after the season.
- Effect: a `seasonal_now` keyword is **never permanent-parked as a tested loser** (the
  ≥15 clk/90d · 0-order park is gated `AND NOT seasonal_now`) and **jumps the candidate queue** —
  seat_rank and cand_rank order it right after the proven/converting keys, so it takes the next
  freed seat and probe slot. ACTIVATE/probe reasons carry a "SEASONAL REVIVAL" prefix.
- The `ly` CTE gate widened: `HAVING clicks >= 10 OR orders >= 1` — the CPC anchor (`ly_cpc`)
  still requires ≥ 10 LY clicks (quality), but a 4-click 2-order LY seller now revives.
- Current-season evidence still wins: a revived keyword that loses NOW can still hit the loser
  allowance PARK — LY signal opens the door, this year's clicks decide.

**Target-vs-bid reductions** (`V_KEYWORD_LIFT`, both arms — bid > target_cpc + $0.05):
- `MARGINAL` (0.7–1.1×): action **EASE_TO_TARGET** — glide `max(bid × 0.95, tcpc)` per day
  (slow reduction toward the target; the −5%/day grammar shared with OOB EASE).
- `LOSER` (inside the allowance): action **CUT_TO_TARGET** — suggested_bid = `tcpc` in one step.
- `WINNER`: untouched — established doctrine, real results own winning bids; the target
  only governs entries and raise ceilings, never pulls a winner down.
- Ordering: the allowance PARK still fires first for losers beyond the 20/40% pool; only the
  kept tail gets CUT_TO_TARGET. Both actions dedupe against the 1-day cooldown as usual.

**Dark campaigns** (directive 2 — no code change): a Portfolio campaign that goes dark > 10%
is already caught by the single-home rule — it moves to the Out-of-budget section next refresh
and the OOB ladder + seat model own its budget and bids until darkness clears.

## v9 — seasonal campaigns get their own home (Ori 2026-08-02)

Ori: "seasonal campaigns should be also separated (seasonal and seasonal out of budget); in
seasonal also show paused seasonal campaigns; other (paused not seasonal campaigns)."

**`is_seasonal` (campaign grain, both engine views — V_KEYWORD_LIFT + V_OOB_BUDGET_PHASE):**
name-based, mirroring `is_defense`:
`REGEXP_CONTAINS(LOWER(campaign_name), 'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday')`.
'prime'/'season' deliberately NOT matched (too ambiguous — archived 'jewelry prime' etc.).
Current live set: 6 enabled '(Back to School)' campaigns + 2 paused '(Boost, Easter 2026)'.

**Weekly Run sections (single home, priority defense > seasonal > tier):**
1–4. The 2×2 (Low budget / Portfolio 80/20 × out-of-budget / healthy) now EXCLUDES seasonal
   campaigns (`NOT is_seasonal`), as it already excludes defense.
5. Brand defense — unchanged; a campaign that is both defense and seasonal stays here (the moat
   outranks the season).
6. **Seasonal — out of budget** — enabled seasonal campaigns dark > 10%, full OOB grammar
   (budget ladder + seat model + negates), any tier.
7. **Seasonal** — enabled healthy seasonal campaigns, full Portfolio grammar (any tier), PLUS
   **paused seasonal campaigns** as display rows (name + PAUSED badge + budget + season note) so
   e.g. the Easter 2026 boosts stay visible for revival when their season nears. Paused rows are
   display-only — no bid/budget actions (nothing serves).
8. **Other — paused** — replaces the legacy SCALE/MARGIN/CUT coacher list, which by v8 contained
   EXACTLY the 44 paused campaigns (engines own every enabled+serving campaign, so only paused
   ones leaked through). Now explicitly: paused AND NOT seasonal, collapsed by default, keeps the
   manage (map/rename/pause) button and trailing 28d/net-per-day stats, sorted by net/day so
   profitable-when-paused revival candidates surface first.

Paused campaigns come from a new live-view cube `CampaignDim` on V_DIM_CAMPAIGN_CURRENT
(campaign_state / is_seasonal / is_defense flags; ARCHIVED excluded everywhere).
Keyword-grain `seasonal_now` (v8) is unchanged and independent — a seasonal KEYWORD can live in
any campaign; a seasonal CAMPAIGN is a homing/display concept.

## v10 — $1 seat-entry floor (Ori 2026-08-02)

Ori: "when starting a seat minimum bid should be 1 dollar (i wont move if not)."

Every seat-entry bid is floored at **$1.00** — below that the keyword simply doesn't move
(no impressions, the test never produces data):
- `V_KEYWORD_LIFT` PROBE_START: `min(max(coalesce(1.5×target, winners-avg-CPC, $1), $1), $2)`.
  The anchor REQUIREMENT is gone — a keyword with no LY target, no band cell and no winner CPC
  now enters at the $1 floor instead of never starting (this unfroze MINT-SP/EXACT,
  MINT-VIDEO/EXACT and FRESH-VIDEO/EXACT, which had $0 spend in-season because no probe could
  ever fire).
- `V_OOB_KEYWORD` ACTIVATE: `min(max(coalesce(1.5×target, per-seat affordable), $1), $1.50)`.
- The floor applies to ENTRIES only. Once clicks flow, the evidence-based reductions
  (probe -5%/day descent, EASE/CUT_TO_TARGET, TRIM, DARK_BRAKE) may go below $1 — real CPC
  data outranks the no-movement heuristic.

## v11 — 4-click trial gate on loser reductions (Ori 2026-08-02)

Trigger case: FRESH-SP/BROAD (Back to School), day 1 of spend ($3.10, 3 clicks). The 20%
loser allowance is spend-share math — on a newborn campaign the allowance is cents, so the
first 1–2 clicks blew through it and both spending keywords were PARKed while the only
0-click keyword got the probe. That contradicts "1 click do not break", the TRIM evidence
bar (>=4 clicks), and finish-what-you-started.

Rule (`V_KEYWORD_LIFT`, both arms): a LOSER can be **allowance-PARKed or CUT_TO_TARGET only
with >= 4 clicks in the window W** — the same evidence bar as TRIM. Under 4 clicks it is
KEEP_TAIL with reason "still in its 4-click trial (N clicks so far) — 1 click does not
break; keep gathering". The permanent park (15 clk/90d) and the probe verdict (20 clicks)
are unchanged — this gate only stops under-evidence in-window reductions.
Effect at deploy: 22 keywords portfolio-wide moved from PARK/CUT to in-trial KEEP_TAIL;
49 allowance parks and 5 cuts (all >= 4 clicks) stand.

## v12 — paused sections in the Seasonal grammar, historic-only (Ori 2026-08-02)

Ori: "other format should be like Seasonal but only with historic measures (last month, last
3 month, last year); also add Seasonal Paused and show only the performance of the relevant
season last year."

New view **`V_PAUSED_CAMPAIGN_HISTORY`** (cube `PausedHistory`, panel `PausedHistoryPhase`):
paused campaigns at (campaign, target) grain from FACT history + campaign rollup rows.
Display-only — nothing spends while paused, no actions, no apply buttons.

- **Seasonal Paused** (after Seasonal): paused seasonal campaigns, ONE column — the relevant
  season's most recent occurrence (name token → DIM_US_HOLIDAYS holiday; window
  pre_season_start → COALESCE(cooldown_end, holiday_date)). E.g. the Easter 2026 boosts show
  their actual Easter-2026 run (BOX-SP 639c · $574 · 0.71× · 17 ord; the keyword rows expose
  the revival candidates — "easter baskets for teens" 1.85×). Replaces the v9 inline ⏸ rows
  in the Seasonal section.
- **Other** (bottom, replaces the legacy SCALE/MARGIN/CUT list entirely): paused non-seasonal
  campaigns with last month · last 3 months · last year columns (clicks · spend · est. net
  ROAS via mapped-ASIN cost ratio). Population is now the FULL paused set from DIM (68), not
  the coacher table's 44 — campaigns with zero rows in T_WEEKLY_RUN_CAMPAIGN appear too.
  The ⋯ manage button of the legacy list is retired with it (mapping lives in Admin).

## v13 — season ramp: RAISE_TO_TARGET (Ori 2026-08-02)

The gap (Ori's "gift for girl" December example): a keyword ticking along at its June bid
($0.50) keeps that bid straight through December even when the LY-anchored target rises to
$1.20 — the target only caps raises and drives reductions. Strong winners get coacher raises
and parked/idle keywords re-enter via probes at 1.5x target, but the in-between keyword
(running, a few clicks, not strong) quietly starves through its own season.

Rule (`V_KEYWORD_LIFT`, both arms): **RAISE_TO_TARGET** when `seasonal_now` (its season is
arriving — LY same-window orders) AND class WINNER or MARGINAL (orders prove the season)
AND bid < 60% of the current target → glide UP `min(max(bid×1.10, bid+$0.05), target)` per
day. Never above target from this rule (beyond-target raises stay earned via the coacher);
losers excluded (they'd lose faster at higher CPCs — the probe path is their way back).
$0.50 → $1.20 takes ~10 days at this pace. Panel: emerald action, apply button queues the
raise. At deploy: 2 live ramps (both under-bid seasonal converters at $0.20–0.30 bids).

## v14 — probes compete for seats + seat status everywhere (Ori 2026-08-02)

Trigger (the "why are there 4 seats" case, ME-SP/PT B2 + VIDEO- BALL): in-flight Portfolio
probes were blanket-exempt from the OOB seat model ("probe in flight — hold"), so a 3-seat
campaign could carry 5 full bids while 70%+ dark, and the visible queue started at #3
because the probes silently occupied #1–#2.

Rule (`V_OOB_KEYWORD`): **a probe only keeps its bid while it holds a seat.**
- Seated probe (seat_rank ≤ slots): HOLD, untouched — "probe in flight — holds a seat until
  its 20-click verdict" (the Portfolio engine still owns the bid; no TRIM/DARK_BRAKE).
- Beyond-seat probe: **PARK_WAIT $0.25** like any mid-test — "probe pauses — beyond the seats
  while the campaign caps"; it resumes via ACTIVATE when a seat frees or darkness clears.
- A mid-probe keyword still never permanent-parks (tested_loser gated `AND NOT is_lift_probe`
  — the 20-click verdict outranks the 15-click bar).

**Seat status on every keyword row** (Ori: "for all tables add keyword seat status"): the
OOB, Portfolio (all tiers incl. Seasonal) and Brand-defense tables now show `seat i/M` (sky)
or `queue #k` (faint) on each keyword — OobKeyword cube gained slots/seatRank dims.
Paused-history tables excluded (no seats while paused).

## v15 — term winners must earn 1.1x (Ori 2026-08-02)

Trigger: asin="B09V45RH3Q" showed "1 winner" for a term with 3 orders at 0.84x net ROAS —
"winner" meant only "an order exists somewhere in 90d".

Rule (`V_OOB_SEARCH_TERM.is_winner`): a winning search term needs **>= 1.1x net ROAS at
this slice over 90d** — the same bar as the keyword WINNER class. SP terms use real
GROSS_PROFIT; SB terms estimate net via the campaign cost ratio (new prod CTE, same method
as the SB launch views). `net_roas_90d` exposed. The account-wide-orders arm is dropped
(an order elsewhere does not make THIS slice a winner). Negation is untouched — the negate
bars still key on 0 orders, so an ordered-but-under-1.1x term is neither winner nor negate:
it just keeps gathering. At deploy: 167 order-but-under-bar terms demoted.

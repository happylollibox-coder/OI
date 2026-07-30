# Intent-Grouped Campaign Model — Design (Sub-projects A + B)

**Status:** SUPERSEDED (campaign portion) by `INTENT_CAMPAIGN_GRID.md` 2026-07-25 · was DESIGN / pending Ori review · 2026-07-16
**Scope of this doc:** A (intent-theme model) + B (Research page determination + cross-family Brand Spotlight). C–E outlined for context only.

## Campaign grain (governing rule — Ori 2026-07-16)

| Role | Grain |
|---|---|
| **AUTO** | **per product** (one auto campaign per product/variation) |
| **BRAND_DEFENSE** | per **family** |
| **PRODUCT_DEFENSE** | **store** — cross-family (one, catalogue-wide) |
| **COMPETITOR / EXACT / BROAD / PHRASE / SB_VIDEO** | **family × match-type × intent** |

**Only Auto is per product. Everything else is family-grain** (Prod Def is store-grain), and each family campaign carries a **product suggestion** — the system nominates which product(s) to run as the Product Ad (e.g. the best-converting variation). Family-grain also aligns naturally with research/intent keywords, which are already family-grain — this **resolves former open question #1**.

Example: `LolliME – Broad – Journal` is a **family** (LolliME) campaign, not a per-variation one.

## Goal & context

Move offense advertising from *1-campaign-per-keyword* (hard to maintain) to **intent-grouped campaigns**: one campaign per **(family × match-type × intent)**, holding **≤10 keywords**. Applies to match types **Exact / Broad / Phrase / Competitor / Video** (Video: Ori edits existing campaigns himself). **Brand Defense / Product Defense are unchanged.** New campaigns are created at **$10/day budget, $1.00 default bid**.

**Migration = alongside, gradual.** The new model runs beside the existing offense strategies (`HUNTER`, `EXACT_BOOST`, `CATEGORY_CONQUEST`, `COMPETITOR_CONQUEST`, `LOW_COST_DISCOVERY`); products migrate one at a time. No existing strategy is deleted in A/B.

### Terminology (avoid collision)
OI already uses **`intent`** for a keyword *class* — `BRAND` / `PRODUCT` / `GENERIC` (`V_KEYWORD_INTENT_CLASS`, `DE_KEYWORD_INTENT_OVERRIDE`). That meaning stays. This project's new concept is a **theme bucket** (journal, birthday, easter…). To keep them distinct we name it **"intent theme"** in code/objects (`DE_INTENT_THEMES`, `intent_key`), and reserve bare "intent" for the existing keyword class.

## Data already in place (reused, not rebuilt)
- **`FACT_RESEARCH_RANKED`** (family × term): `occasion`, `holiday`, `product_type`, `age_group`, `gender`, `brand`, `weekly_market_purchases`, `overall_fit`, **`rank`**. Source of both the intent match-rule columns and the ranking metric.
- **`DIM_US_HOLIDAYS`**: `holiday_name`, `boost_start`, `peak_start`, `cooldown_start`, `cooldown_end`, `ramp_up_days` — supplies **start/pause dates** for time-based intents (recurs yearly). Holidays present: Christmas, Easter, Halloween, Valentines Day, Back to School, Black Friday, Cyber Monday, Prime Day.
- Segment vocab: `occasion` ∈ {Birthday, Sleepover, Graduation, Get Well, Performance, Camp, Back to School, Sweet 16, Encouragement, Wedding}; `product_type` ∈ {Gift Sets, Journal & Diary, Beauty, Toys, Bath & Spa, Social Game, Crafts & DIY, …}. **Christmas/Easter/etc. are in the `holiday` column, not `occasion`.**

**Ranking metric (decided):** top-10 keywords per (product × intent) by `FACT_RESEARCH_RANKED.rank`.

---

## A. Intent-theme model

### A.1 `DE_INTENT_THEMES` (new DE table, editable via Flask/Admin)
One row per intent theme.

| column | type | notes |
|---|---|---|
| `intent_key` | STRING | PK, kebab, e.g. `birthday`, `easter`, `beauty`, `gift`, `tween-gift` |
| `label` | STRING | display, e.g. "Birthday" |
| `intent_type` | STRING | `GENERIC` \| `TIME_BASED` |
| `match_occasion` | STRING | nullable — equals `FACT_RESEARCH_RANKED.occasion` |
| `match_holiday` | STRING | nullable — equals `.holiday`; for `TIME_BASED` |
| `match_product_type` | STRING | nullable — equals `.product_type` |
| `match_age_group` | STRING | nullable — equals `.age_group` |
| `match_keyword_regex` | STRING | nullable — REGEXP over `LOWER(query_text)` (e.g. `gift` → `\bgifts?\b`) |
| `holiday_name` | STRING | nullable FK → `DIM_US_HOLIDAYS.holiday_name` (start/pause dates for `TIME_BASED`) |
| `cross_family` | BOOL | eligible for Brand-Spotlight / brand-store grouping |
| `is_active` | BOOL | |
| `priority` | INT64 | tie-break ordering |
| `created_at`,`updated_at` | TIMESTAMP | |

**Match semantics:** a term matches an intent when **all non-null** `match_*` fields match (AND); `match_keyword_regex` is a REGEXP_CONTAINS on `query_text`. Most intents set exactly one field.

Examples:
- `beauty` — GENERIC, `match_product_type='Beauty'`
- `birthday` — GENERIC, `match_occasion='Birthday'`
- `gift` — GENERIC, `match_keyword_regex=r'\bgifts?\b'`
- `tween-gift` — GENERIC, `match_age_group='10-12 (Tween)'` + `match_keyword_regex=r'\bgifts?\b'`
- `easter` — TIME_BASED, `match_holiday='Easter'`, `holiday_name='Easter'`
- `christmas` — TIME_BASED, `match_holiday='Christmas'`, `holiday_name='Christmas'`
- `back-to-school` — TIME_BASED, `match_holiday='Back to School'`, `holiday_name='Back to School'`

### A.2 Seed (broad, then Ori prunes)
Seed script generates rows from the live vocab:
- **TIME_BASED**: one per `DIM_US_HOLIDAYS.holiday_name` (Christmas, Easter, Halloween, Valentines, Back to School, Black Friday, Cyber Monday, Prime Day).
- **GENERIC occasion**: one per distinct `occasion` (Birthday, Sleepover, Graduation, Camp, Sweet 16, Wedding, …).
- **GENERIC product_type**: one per major `product_type` (Beauty, Journal & Diary, Gift Sets, Crafts & DIY, Bath & Spa, Social Game, Toys, …).
- **GENERIC keyword**: `gift`, `tween-gift`.
Seed writes to `.tmp` for review, then loads on approval (idempotent MERGE on `intent_key`).

### A.2b Relevance gate — `is_relevant` (Ori 2026-07-16) ✅ BUILT

`FACT_RESEARCH_RANKED` scores **every term for every family**, so without a gate all 6 families match all 36 intents (Bottle — a truth-or-dare game — would get a `journal-diary` campaign) ⇒ 36 intents × 5 match types per family.

**Decision order — first rule wins** (`relevance_reason` exposes the trace):

1. **MANUAL OVERRIDE** — `DE_FAMILY_INTENT_OVERRIDE.force_relevant` per (family × intent). `DE_INTENT_THEMES.is_active` is *global* and can't express "school is wrong for LolliME but fine for Lollibox"; this can. Absent row ⇒ let the gates decide.
2. *(No TIME_BASED special case any more.)* Seasonal used to be unconditionally relevant because it **could not be judged**: rank was zeroed off-season and a 90d ads read was noise. Both are now fixed — `effective_rank` makes seasonal rankable and the **season window** makes it measurable — so seasonal runs the **same rules as everything else**. Untested seasonal is *not* penalised for having no history (the profit gate only fires at ≥100 clicks), so it falls through to the fit gate and is judged on fit alone.
3. **PROFIT GATE** → drop when **conclusive AND hopeless**: `ads_clicks ≥ 100` **AND** `ads_net_roas < 0.5`. Rank is a market-**fit** signal, not profit — LolliME/`school` clears rank 63 yet returns **0.27x on $358 over 613 clicks** (77 clicks/sale). Untested intents (<100 clicks) are **not** dropped.
   - **The floor is 0.5, not breakeven 1.0.** A flat <1.0 cut left **Fresh with ZERO intents** — its whole book is marginal (0.66–0.92), which is a bid/price/margin problem to *fix*, not an intent to delete. 0.5 kills only the genuinely dead and matches the GUARDIAN floors, which are already context-dependent (1.1 / SEASONAL 0.7 / NEW_LAUNCH 0.5).
4. **FIT GATE** → `family_best_effective_rank ≥ 60` (ungated rank, so seasonal is judged on real fit+demand). *rank ≥ 75 was too strict (Fresh cleared zero); ≥ 50 left ~22.*

**ADS WINDOW is per intent:** GENERIC = last 90d · TIME_BASED = **that holiday's last started season** (`DIM_US_HOLIDAYS` boost_start → cooldown_end of the most recent occurrence begun). A 90d window is meaningless out of season — LolliME/easter read **−5.21x on $1.21** (Apr–Jul) vs **4.67x on $51.37 / 17 orders** over the real Easter 2026 season. Seasonal is real money the 90d window hid: Lollibox christmas-gift $3,084/149 ord, Lollibox easter $2,977/249 ord/2.07x, Fresh easter 6.01x. Needs `fam_ads` at DAY grain + 2y history.

**Outcome:** Bottle drops christmas-gift (0.0x on 249 clicks across a whole Christmas) · Halloween drops for Bunny/LolliBall (eff_rank 33, fit 10, 474 demand, no pause date) · Bunny/LolliBall keep never-run christmas-gift (eff_rank 80) as genuine untried opportunities.

`ads_*` are measured over **all** the intent's matched terms for the family (not just the top-10), 90d. Thresholds are documented constants in the view — tune there.

**Killed by the profit gate:** LolliME toys/school · Lollibox bath-spa/toys · Bottle toys/tween-gift · Bunny toys/keychain/performance · LolliBall tween-gift/birthday/gift · Fresh none.
⚠️ **LolliBall is left with 1 generic intent** (accessories) — it's a recent launch whose gift/birthday/tween-gift all sit at 0.16–0.44. Correct per the data, but worth an override if you want to keep investing in the launch.

Consumers filter on `is_relevant`; non-relevant rows stay in the view for exploration. Validated output (fit gate only, before the profit gate):

| family | relevant GENERIC intents |
|---|---|
| Bottle | birthday, gift, party-supplies, sleepover, social-game, tween-gift |
| Bunny | birthday, gift, graduation, performance, tween-gift |
| Fresh | bath-spa, birthday, gift, gift-sets, tween-gift |
| LolliBall | accessories, birthday, gift, tween-gift |
| LolliME | birthday, crafts-diy, gift, home-room, journal-diary, school, tween-gift |
| Lollibox | birthday, gift, graduation, journal-diary, performance, tween-gift |

Only 3 of the 8 seasonal intents materialise (christmas, easter, halloween) — the other 5 (black-friday, cyber-monday, prime-day, valentines-day, back-to-school) have no `holiday`-tagged terms with demand.

**Data gap:** Halloween has a NULL `cooldown_end` on every occurrence in the live `DIM_US_HOLIDAYS` ⇒ no pause date (Christmas/Easter are fine). The season pick coalesces to `holiday_date` so NULLs can't select a past occurrence, but D (scheduling) needs a real pause date here.

### A.2c Specificity routing + ranking fixes (Ori 2026-07-16) ✅ BUILT

**Specificity routing — one term, one intent.** Compounds are subsets by construction, so `gift`
(a bare `\bgifts?\b` regex) swallowed everything: it shared **1,201** terms with `tween-gift`,
**738** with `birthday`, **680** with `gift-sets`. The same keyword would seed several campaigns
bidding against each other.
- `specificity` = count of non-null `match_*` conditions. `gift`(1) < `birthday-gift`(2) < `tween-birthday-gift`(3).
- Each (family × term) keeps only its **most specific** matching intent; ties → `priority` ASC, then `intent_key`.
- **Compound intents added (6):** `birthday-gift`, `christmas-gift`, `easter-gift`, `tween-birthday-gift`, `tween-christmas-gift`, `tween-easter-gift` (`tween-gift` already existed). 47 themes total.
- Result: **0 terms with >1 intent**. `gift` for LolliME went $1,901 → $546 and its ROAS *improved* 1.57 → 1.83 — the old number was an average masking two different intents.

**Age-birthday intents route on age + occasion only — no "gift" word required (Ori 2026-07-22).**
The four age-specific birthday themes (`kid-birthday-gift`, `tween-birthday-gift`, `teen-birthday-gift`,
`age-8-14-birthday-gift`) had `match_keyword_regex=r'\bgifts?\b'`, so an age + Birthday term *without*
"gift" (e.g. "12 year old girl birthday", "14 year old girl birthday") failed the AND and fell through to
generic `birthday` (occasion-only). Fix: **`match_keyword_regex` set to NULL** on those four themes so
**"N year old … birthday" routes by age** — 12→`tween-birthday-gift`, 14→`teen-birthday-gift`,
8→`kid-birthday-gift`. Their specificity drops 3→2 (occasion + age), but they still beat generic `birthday`
(spec 1) on specificity and beat the no-age `birthday-gift` catch-all (spec 2) on `priority` (5 < 15).
The generic `birthday-gift` theme keeps its regex — it is the no-age gift catch-all. This is a live edit to the
`DE_INTENT_THEMES` data-entry table (the rows have no repo seed file — the DDL at
`scripts/bigquery/tables/DE_INTENT_THEMES.sql` is CREATE-only; the table is the source of truth).
Blast radius (Lollibox): generic `birthday` 265→6; the age buckets absorbed them
(kid 118→163, teen 185→248, tween 232→324).

**`effective_rank` — seasonal terms are rankable again.** `V_RESEARCH_RANKED` sets
`rank = 0 when (holiday IS NOT NULL AND NOT is_holiday_active)`, else `ROUND(AVG(overall_fit, purchase_rank))`.
Out of season every holiday term is rank 0, so ordering by rank silently fell through to the demand
tie-break — LolliME/easter surfaced **"easter candy"** (143K demand, fit 0) at #1 while
*"easter gifts for girls"* sat 10th. Ordering by `overall_fit` alone over-corrected (fit-100 terms with
1 weekly purchase). `effective_rank` rebuilds the **same formula minus the holiday gate**, so a seasonal
term gets the rank it would have in season — blending fit AND demand. GENERIC terms are unaffected.

**Term fit floor — `overall_fit > 0`.** `effective_rank` averages fit with `purchase_rank`, so a fit-0
term rides in on pure volume (easter candy: fit 0 + purchase_rank 100 → effective_rank 50, still #5).
A fit-0 term is by definition irrelevant to the family and must never enter a campaign. Removes
**136/792 (17%)** of keyword slots; starves **no** GENERIC intent (3 TIME_BASED go empty — correct:
no relevant terms ⇒ no campaign). LolliME/easter now leads with *"easter for teen girls"* (fit 30, 837 demand).

**Brand exclusion — own-brand terms never enter an intent (Ori 2026-07-21).** An intent *is* its
SP campaign (Exact/Broad/Phrase/Competitor); bidding on your own brand name there just pays for
traffic that converts organically and fights **Brand Defense**, which owns brand. Own-brand terms
were leaking into generic themes (e.g. cross-family **Gift Sets** carried *"purple lollibox"*,
*"white lollibox"*, *"happy lolli care package 12 year old girl"*), inflating theme ranks and
polluting the Brand-Spotlight suggestion feed. Fix: anti-join the `matched` CTE against
**`DIM_BRAND_PHRASES`** (`STRPOS(term, phrase) > 0`) — the maintained own-brand phrase table, where
every phrase contains a brand root (`lolli`/`lollime`/`lollibox`/`happy lolli`, per
`SP_ACCUMULATE_BRAND_PHRASES`), so a substring match is unambiguously brand and can't swallow a
generic term. Same match pattern as `V_SEARCH_TERM_SEGMENT`. This governs both the Intents panel and
Brand Spotlight, since both read `V_INTENT_KEYWORDS`. Competitor-brand exclusion (e.g. "pretty me")
is **not** covered here — no competitor list feeds this pipeline yet (open item).

### A.2d The PEAK principle (Ori 2026-07-16) ✅ BUILT

> *"back to school is an occasion (not a holiday) but it acts like a holiday. there is a peak — basically all holidays are the way the peak is behaving before the occasion or the holiday."*

**`intent_type = TIME_BASED` ⟺ it has a PEAK** (a `holiday_name` FK resolving to a `DIM_US_HOLIDAYS`
window). Whether the term data sits in the research `holiday` column or the `occasion` column is an
**accident of storage**, not a property of the thing. The `match_*` rule and `intent_type` are therefore
independent. Auditing the taxonomy against this found four bugs:

| fix | why |
|---|---|
| **`valentines-day` matched NOTHING** | research says `"Valentines"`, `DIM_US_HOLIDAYS` says `"Valentines Day"`. The seed used the holiday-table name. **This hid a live, profitable business: $1,392 spend / 2,313 clicks / 1.52x blended** (Lollibox tween-valentines-gift **3.01x**, teen **1.95x**). One word. |
| **`back-to-school`** | matched on `holiday`; the data is in `occasion`. Now `match_occasion` + keeps its `holiday_name` window — occasion data, holiday behaviour. |
| **`graduation`** | was GENERIC, but it plainly peaks (May/June) → promoted to TIME_BASED; peak window added. |
| **Mothers Day (423K demand!)** | had **no intent and no peak window** — invisible to the model. |

**`DIM_US_HOLIDAYS` rows added** (INSERT only — it is hand-curated, never DELETE+INSERT): Mothers Day
(2nd Sun May), Fathers Day (3rd Sun Jun), Graduation × 2025-27. 24 → 33 rows. Graduation is a
**modelling compromise** — it is a ~6-week season, not a date: anchored 31 May with a wide
Apr 20 → Jun 20 window.

**Mothers Day / Graduation are correctly GATED OUT** (eff_rank 40 / 18 vs the 60 bar) — Ori: *"today
there is no effect I found for happy lolli"*, confirmed by data. The point was to make the peak
**measurable**; if fit ever improves the intent activates on its own.

**✅ Seasonal proliferation — resolved, not a problem.** Seasonal intents are a **calendar, not a
concurrent load**. Lollibox has 13 seasonal intents but is only ever running a few at once:
today **0** (all out of season) · Christmas **6** · Valentines **4** · Easter **3**. Peak concurrency 6.

**Intents matching nothing (10, all benign):** the 4 `*-mothers-day-gift` age compounds (Mothers Day
has 5 fit>0 terms, none age-tagged) · `black-friday`/`cyber-monday`/`prime-day` (research has no such
holiday values — shopping events, not gift-occasion terms; Ori: leave them) · `easter-basket` (loses
its terms to `easter` on the priority tie — correct) · `encouragement`/`mental-wellness` (no terms
survive the fit floor).

### A.3 `V_INTENT_KEYWORDS` (new view) ✅ BUILT
Grain: **(parent_name × intent_key × query_text)** — research is family-grain.
```
FACT_RESEARCH_RANKED r  ⨝  DE_INTENT_THEMES t  ON  (t.match rule matches r)
→ rank terms within (parent_name, intent_key) by r.rank DESC
→ is_top10 = ROW_NUMBER() ≤ 10
```
Columns: `parent_name, intent_key, label, intent_type, query_text, rank, overall_fit, weekly_market_purchases, rn, is_top10, holiday_name`. Registered in `config.yaml`. Consumed by sub-project C (campaign build); surfaced now by B.

---

## B. Research page

### B.1 Per-family "Intents" grouping
On the existing per-family Research view, add an **Intents** panel: each active intent that has ≥1 matching term for the family, showing its **top-10 keywords by rank** (from `V_INTENT_KEYWORDS`), intent_type badge, and (for TIME_BASED) the season window from `DIM_US_HOLIDAYS`. New endpoint `GET /api/research/intents?parent=<family>`.

### B.2 Cross-family "Brand Spotlight" view (new)
A cross-family view (new tab/section — Research is per-family today). Per intent, **aggregated across all families**:
- families that rank for it (count + names), combined top terms, aggregate rank/demand.
- ranked list → the suggestion feed for **brand-store / cross-family campaigns** (sub-project C's brand-store strategy).
New endpoint `GET /api/research/brand-spotlight` → intents with `families[]`, `top_terms[]`, `agg_rank`, `cross_family` flag, season window. New React view mounted on the Research page.

---

## Placement (lane + lever, not a campaign axis)

Two placement families exist: **product placement** (inside the search product grid, top line → bottom, + product-detail pages) and **brand placement** (banner above the grid / mid-page). We deliberately do **not** make placement a campaign axis — that would multiply (product × match-type × intent) by 3–4 and fight the ≤10-kw maintainability goal. Placement is addressed two ways that already fit the model:

**1. Placement type = ad-type lane (already in the model).**
- **Product placement** = **SP** campaigns → the intent match-type campaigns (Exact/Broad/Phrase/Competitor).
- **Brand placement** = **SB** campaigns → the **brand-store + Video** lane (grouped by the same intents; cross-family Brand Spotlight → SB brand campaigns). Brand placement is not extra work — it *is* the brand-store/Video lane.

**2. Within a campaign, placement = bid-adjustment + reporting dimension (coacher-tuned).**
- Control grid position and product-page presence via **placement bid adjustments** (`Top-of-Search %`, `Product-Pages %`) — one campaign, not three. The bulksheet already supports this (`Bidding Adjustment` / `Placement Top`).
- Data on hand: `FACT_AMAZON_ADS.placement_type` (`Search_Results` / `Product_Page`) + `campaign_type` (SP/SB); **top-of-search "top line" granularity is NOT in `placement_type`** — it comes from **TOS-share** (`V_KEYWORD_DAILY`, existing TOS-BRAKE). Signal seen (90d): SB `Product_Page` net ROAS ≈ 2.84 vs SP `Search_Results` ≈ 0.98.

Lands in later sub-projects (does **not** change A/B):
- **C** — SP intent-campaign templates get default placement bid adjustments; SB = brand-store/Video lane.
- **E** — coacher **placement-optimization action**: raise `Top-of-Search %` where TOS is profitable, raise `Product-Pages %` where PP converts, pull back where it loses; surface a per-campaign placement split (SP grid / SP product-page / SB banner) in the Coach/Research decision trace.

## Out of scope here (later sub-projects)
- **C. Campaign structure** — (product × match-type × intent) templates, naming (e.g. `LolliME – Broad – Journal`), ≤10-kw bulksheet at $10/$1, brand-store campaigns for `cross_family` intents. **Placement:** default Top-of-Search / Product-Pages bid adjustments per template; SP = product placement, SB (brand-store/Video) = brand placement.
- **D. Seasonal scheduling** — auto enable at `boost_start`, pause at `cooldown_end`, re-arm yearly (uses `holiday_name` link).
- **E. Coacher integration** — teach `V_ADS_COACH` the new match-type×intent model (currently reads strategy from campaign names). **Placement:** add the placement-optimization action + placement split in the decision trace (see Placement §).

## F. Coverage scan ("ad scan" checklist)

**Goal:** verify all relevant campaigns exist per the strategy model — emphasize **missing** and **redundant**. Checked **at each role's own grain** (see Campaign grain §), NOT as a flat product×role grid.

**Surface (decided):** **one button per family + one Store button** (cross-family). Each is **green when everything for it is defined**, amber/red otherwise. Clicking opens the **mapping list — what's done vs what still needs doing**. This *replaces* the earlier product×role grid.
- **Store button** → `PRODUCT_DEFENSE` (cross-family).
- **Family button** → `BRAND_DEFENSE` (family) + `COMPETITOR/EXACT/BROAD/PHRASE/SB_VIDEO` (family × match-type × intent) + **`AUTO` per product** (the family's products listed individually — the only per-product check).

**Phasing:** intent-grain roles can't be fully verified until the intent model (A) exists.
- **Phase 1 (now):** AUTO per product · BRAND_DEFENSE per family · PRODUCT_DEFENSE at store · family-level *presence* of COMPETITOR/EXACT/BROAD/PHRASE/SB_VIDEO.
- **Phase 2 (after A/B):** expand those to per-intent checks (family × match-type × intent) + the product suggestion for each family campaign.

**Roles checked:** `AUTO`, `BRAND_DEFENSE`, `PRODUCT_DEFENSE`, `EXACT`, `BROAD`, `PHRASE`, `COMPETITOR`, `SB_VIDEO` (brand placement).

**Role classification** (per enabled campaign advertising the product's ASIN; first match wins):
1. `strategy_id = BRAND_DEFENSE` → **BRAND_DEFENSE** (strategy via `DIM_EXPERIMENT_CAMPAIGN.experiment_id` → `DIM_EXPERIMENT.strategy_id`)
2. `strategy_id = PRODUCT_DEFENSE` → **PRODUCT_DEFENSE**
3. `campaign_type = SB` → **SB_VIDEO** (brand placement)
4. `targeting_type = Automatic` (SP) → **AUTO**
5. `strategy_id IN (CATEGORY_CONQUEST, COMPETITOR_CONQUEST)` OR `targeting_type IN (ASIN, ASIN Expanded, Category)` → **COMPETITOR**
6. `targeting_type = EXACT` → **EXACT**; `= BROAD` → **BROAD**; `= PHRASE` → **PHRASE**
   (campaigns are single-match-type by naming convention; use the campaign's dominant `targeting_type`.)

**Per (product × role) cell shows** (decided — so Ori can judge before opting out): status (✓ / **missing** / **redundant**), campaign count, and 60–90d **net ROAS · clicks · impressions · units sold** (from `FACT_AMAZON_ADS`, own-advertised via `advertised_asin`).
- **Missing** = 0 enabled campaigns for the role AND not opted out.
- **Redundant** = >1 enabled campaign for the role, OR two campaigns targeting the same ASIN in the same role (the overlap flagged in the auto-campaign audit).

**`DE_COVERAGE_EXPECTATION`** (new DE table): per (asin, role) `expected` bool — default all-expected; Ori sets `expected=false` to opt a product out of a role ("unless I said no"). Scan reads this to suppress false "missing".

**Surface:** new **Coverage** page — products × roles grid (red = missing, amber = redundant, green = ok), each cell with the metrics above; row = product, expandable to the campaigns filling each role. Endpoint `GET /api/research/coverage` (or `/api/coverage`). Backend = one query reusing the auto-audit data path (`advertised_product` → campaign role → state).

**Note:** placement adjustments already live in `DIM_EXPERIMENT_CAMPAIGN.top_of_search_pct / product_page_pct / rest_of_search_pct` — Phase 2 can add a placement-coverage check per campaign (see Placement §).

## G. Suggested-campaign review → Do page (part of C)

Ori must be able to **edit the keyword set of a suggested campaign, then push it to the Do page** with one button. Flow:

1. **Suggest** — on the Research page (B's intent panel), each **(product × match-type × intent)** that the coverage scan (F) reports as *missing* renders a **suggested campaign**: proposed campaign name, ASIN/SKU, match type, and its **top-10 keywords** from `V_INTENT_KEYWORDS` (each with rank/demand so the choice is informed).
2. **Edit** — add / remove keywords inline. Removing is one click; adding offers the rest of that intent's ranked terms (below top-10) plus free text. **≤10 is a soft cap** — warn past 10, don't block.
3. **Queue** — **"Add to Do page"** button → pushes a `CREATE_CAMPAIGN` item to the existing Do queue (`useDoQueue.addItem`, localStorage-persisted) carrying: `asin`, `sku`, `parent_name`, `match_type`, `intent_key`, `campaign_name`, `keywords[]`, `daily_budget=10`, `default_bid=1.00`, `portfolio_id`, bidding strategy, placement adjustments (see Placement §).
4. **Export** — the Do page lists queued campaign creations alongside existing actions; export emits bulksheet **Create** rows (Campaign → Ad Group → Product Ad → Keyword ×N) at **$10 / $1.00**, reusing DoPage's existing SP column set and the auto-campaign bulksheet row shape already proven in `lollibox_family_auto_campaigns.xlsx`.

**Required change:** `DoQueueItem` is currently keyword/action-shaped (`search_term`, `action`, `campaign`, `targeting`). Add a **`CREATE_CAMPAIGN` variant** with a `keywords[]` payload (and its Do-page renderer + export branch). DoPage already emits Create rows and dedups them — extend, don't fork.

## Open questions / risks
1. **Product vs family grain** — research/intent keywords are family-grain; campaigns are per-product. C will decide whether every product in a family gets the family's intent keywords or a per-ASIN cut.
2. **Overlap** — a term can match several intents (e.g. "easter basket gift" → easter + gift + Gift Sets). Allowed (a term can seed multiple intent campaigns), matching the brand-term rule that a term can run for >1 product; C dedups within a campaign.
3. **Season column source** — TIME_BASED matches on `FACT_RESEARCH_RANKED.holiday`; confirm coverage vs the `is_holiday_active` gate.
4. Naming collision handled by "intent theme" (see Terminology).

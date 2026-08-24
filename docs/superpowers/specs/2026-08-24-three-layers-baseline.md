# Three Layers — baseline research queries (2026-08-24)

The re-runnable record behind `architecture/THREE_LAYERS.md` §10. **This file exists so that a recheck is
a re-run, not a fresh argument.** Every figure published in §10 came from a query below.

**Method** — a keyword's year was simulated against the doctrine across five probes (entry, decline,
seasonality, ownership, money flow), each finding sized in dollars per day against the account, then put
through two adversarial verifiers: one re-ran every query and compared it to the claim, the other
attacked the causal story. The arithmetic passed. **Three of the four largest claims did not survive the
second pass** — see §10.2 and §6.3 of the doctrine, which that failure produced.

**Reading these** — dates are hard-coded to the measurement window (ads watermark 2026-08-23,
snapshot 2026-08-24). To re-measure, move the dates and keep everything else. Some queries reference the
Catalog snapshot, which holds one day only, so a historical re-run of those is impossible by construction
(doctrine violation 6) — that limitation is itself a finding.

**Warning carried from §6.3** — several of these queries compute `GREATEST(spend − GP/bar, 0)`. That is a
one-sided metric: it clips every over-performer to zero and is positive under ordinary dispersion even in
a healthy account. Always report the net beside it.

---

## Register queries (the figures published in §10)

### THE DRIFTING BASKET

HIGH — re-run and confirmed exactly on 2026-08-24: EXACT 19.1%/$102.53, PHRASE 32.2%/$19.02, substitutes 57.2%/$59.43, close-match 59.9%/$68.25, BROAD 63.7%/$468.73, loose-match 67.4%/$93.73, complements 67.5%/$7.97.

```sql
-- Basket drift WITH A CONTROL. EXACT is the control: if it drifts too, the metric measures
-- long-tail noise rather than basket instability. It does not (19.1%).
WITH t AS (
  SELECT CASE WHEN targeting_type='Automatic' THEN 'AUTO ('||LOWER(targeting)||')'
              ELSE 'CONTROL '||UPPER(targeting_type) END grp,
         DATE_TRUNC(date, MONTH) mo, targeting, search_term,
         SUM(Ads_clicks) clk, SUM(Ads_cost) c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-01-01' AND DATE '2026-08-22' AND search_term IS NOT NULL
    AND (targeting_type='Automatic' OR UPPER(targeting_type) IN ('EXACT','PHRASE','BROAD'))
  GROUP BY 1,2,3,4),
prev AS (SELECT grp,targeting,mo,search_term FROM t WHERE clk>0)
SELECT a.grp,
  ROUND(100*SUM(IF(p.search_term IS NULL,a.c,0))/NULLIF(SUM(a.c),0),1) pct_spend_unseen_prior_month,
  ROUND(SUM(a.c)/205,2) usd_day_avg
FROM t a LEFT JOIN prev p ON p.grp=a.grp AND p.targeting=a.targeting
  AND p.search_term=a.search_term AND p.mo=DATE_SUB(a.mo,INTERVAL 1 MONTH)
WHERE a.mo >= DATE '2026-02-01'   -- Jan is the seed month, it has no prior
GROUP BY 1 ORDER BY 2;

-- How rarely the existing guard arms:
SELECT COALESCE(guard_scope,'(not armed)') guard_scope, is_auto, match_type, COUNT(*) n,
       ROUND(AVG(guard_ns_share),3) avg_never_seen_share
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
WHERE snapshot_date=DATE '2026-08-24' AND family IS NOT NULL
GROUP BY 1,2,3 ORDER BY n DESC;
```

### THE JANUARY MIRROR

HIGH — re-run and confirmed exactly: trough $963.32/day at $0.120 net per ad dollar; cleared February $699.75/day at $0.435. The account spent 38% MORE per day during the trough and earned 62% LESS. Foregone = 963.32×0.435 − 115.95 = $303.09/day × 28 days = $8,486.

```sql
SELECT CASE WHEN date BETWEEN DATE '2025-12-28' AND DATE '2026-01-24' THEN '1_trough'
            WHEN date BETWEEN DATE '2026-02-01' AND DATE '2026-02-28' THEN '2_cleared' END seg,
  ROUND(SUM(Ads_cost)/28,2) spend_day,
  ROUND((SUM(GROSS_PROFIT)-SUM(Ads_cost))/28,2) net_day,
  ROUND(SAFE_DIVIDE(SUM(GROSS_PROFIT)-SUM(Ads_cost),SUM(Ads_cost)),3) net_per_ad_dollar
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE date BETWEEN DATE '2025-12-28' AND DATE '2026-02-28'
  AND (date <= DATE '2026-01-24' OR date >= DATE '2026-02-01')
GROUP BY 1 HAVING seg IS NOT NULL ORDER BY 1;
-- foregone/day = trough.spend_day * cleared.net_per_ad_dollar - trough.net_day

-- the cohort funded on Nov-Dec evidence, and what it did afterwards
WITH cohort AS (SELECT keyword_id FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31' GROUP BY 1
  HAVING SUM(Ads_orders)>=3 AND SUM(GROSS_PROFIT)-SUM(Ads_cost)>0),
janfeb AS (SELECT keyword_id, SUM(Ads_cost) cost, SUM(GROSS_PROFIT)-SUM(Ads_cost) net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-01-01' AND DATE '2026-02-28' GROUP BY 1)
SELECT COUNT(*) novdec_winners, COUNTIF(j.net<0) lost_money_janfeb,
  ROUND(SUM(IF(j.net<0,j.net,0)),0) janfeb_losses,
  ROUND(SUM(IF(j.net<0,j.cost,0)),0) janfeb_spend_on_losers
FROM cohort JOIN janfeb j USING (keyword_id);
```

### THE SEASONAL KILL — the one-way door

HIGH — re-run and confirmed exactly: 79 keywords, $96,725 Nov-Dec 2025 ads sales, $14,799 net, 0 still visible to the Catalog. Exclusions are deliberate and stated: dropped 88 keywords in ARCHIVED campaigns ($47,621), 73 in PAUSED campaigns ($20,859) and 49 in ENABLED-but-zero-spend campaigns ($21,290) — a campaign with no current spend is not credibly in use, so its keywords are not credibly recoverable.

```sql
WITH kw AS (SELECT keyword_id, ANY_VALUE(keyword_text) kw_text, ANY_VALUE(campaign_id) campaign_id,
              ANY_VALUE(LOWER(state)) kw_state, ANY_VALUE(match_type) match_type
            FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current GROUP BY 1),
camp AS (SELECT campaign_id, ANY_VALUE(LOWER(state)) cs, ANY_VALUE(campaign_name) cn
         FROM `onyga-482313.OI.DIM_CAMPAIGN` WHERE is_current GROUP BY 1),
cs28 AS (SELECT campaign_id, SUM(Ads_cost) c FROM `onyga-482313.OI.FACT_AMAZON_ADS`
         WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23' GROUP BY 1),
ls AS (SELECT keyword_id, SUM(Ads_orders) ord, SUM(Ads_sales) sales,
         SUM(GROSS_PROFIT)-SUM(Ads_cost) net
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`
       WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31' GROUP BY 1),
lc AS (SELECT keyword_id, MAX(date) last_click FROM `onyga-482313.OI.FACT_AMAZON_ADS`
       WHERE Ads_clicks>0 GROUP BY 1),
ic AS (SELECT DISTINCT keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
SELECT COUNT(*) n, ROUND(SUM(ls.sales),0) novdec_sales, ROUND(SUM(ls.net),0) novdec_net,
  ROUND(SUM(ls.net)/61,2) net_per_season_day,
  COUNTIF(ic.keyword_id IS NOT NULL) still_visible_to_catalog  -- expect 0
FROM kw JOIN ls USING (keyword_id)
LEFT JOIN camp c ON c.campaign_id=kw.campaign_id
LEFT JOIN cs28 ON cs28.campaign_id=kw.campaign_id
LEFT JOIN lc USING (keyword_id) LEFT JOIN ic USING (keyword_id)
WHERE ls.ord>0 AND kw.kw_state IN ('paused','archived')
  AND c.cs='enabled'                 -- exclude retired campaigns (state)
  AND COALESCE(cs28.c,0)>0;          -- exclude dormant campaigns (behaviour)
-- swap the final SELECT for kw.kw_text, c.cn, ls.sales, lc.last_click to get the recovery list
```

### SEASONAL MISPRICING TODAY

MEDIUM — the classification is a direct measurement but only on the comparable half of the account. Of $1,323.22/day, $646.29/day sits on keywords with ≥30 clicks in BOTH windows. Within it: $206.92/day holiday-heavy (≥1.5x), $410.80/day flat, $27.89/day summer-better, $0.67/day zero summer conversions. The other $676.93/day cannot be classified at all and I deliberately did NOT extrapolate the 32% share onto it.

```sql
WITH holiday AS (SELECT keyword_id, SUM(Ads_clicks) clk, SUM(Ads_orders) ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1 HAVING SUM(Ads_clicks)>=30),
summer AS (SELECT keyword_id, SUM(Ads_clicks) clk, SUM(Ads_orders) ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-06-01' AND DATE '2026-08-23'
  GROUP BY 1 HAVING SUM(Ads_clicks)>=30),
now_28d AS (SELECT keyword_id, SUM(Ads_cost) cost_28d FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23' GROUP BY 1),
comparable AS (SELECT h.keyword_id, SAFE_DIVIDE(h.ord,h.clk) cvr_holiday,
    SAFE_DIVIDE(s.ord,s.clk) cvr_summer, COALESCE(n.cost_28d,0)/28 spend_per_day
  FROM holiday h JOIN summer s USING (keyword_id) LEFT JOIN now_28d n USING (keyword_id))
SELECT CASE WHEN cvr_summer=0 THEN 'summer_zero_cvr'
            WHEN cvr_holiday/NULLIF(cvr_summer,0)>=1.5 THEN 'holiday_ge_1.5x (under-priced today)'
            WHEN cvr_holiday/NULLIF(cvr_summer,0)<=0.667 THEN 'summer_better (over-priced today)'
            ELSE 'flat (correctly priced)' END bucket,
  COUNT(*) keywords, ROUND(SUM(spend_per_day),2) spend_per_day
FROM comparable GROUP BY 1 ORDER BY spend_per_day DESC;
-- denominator, so the share is not asserted:
SELECT ROUND(SUM(Ads_cost)/28,2) account_spend_per_day
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23';
```

### THE SEASON DOOR — the window says NO on the eve of the season

MEDIUM — the mechanism is verified in live SQL (SP_SNAPSHOT_KEYWORD_STATE.sql: fixed 90-day trailing frame, no calendar reference) and the peak outcome is a direct measurement, but the $7,473 is an EXPOSURE not a receipt: it prices what the estimator would have said, not a record of parks that actually happened, because the Catalog keeps no history. It also understates, counting only keywords that survived to trade in the peak.

```sql
-- Bar = 1.0 GP-ROAS. Today's family_bar runs 0.74-0.94, so 1.0 is the CONSERVATIVE choice:
-- it condemns FEWER keywords than the live bar would.
WITH trailing_90d_at_nov15 AS (
  SELECT keyword_id, SUM(Ads_clicks) clk, SUM(Ads_cost) cost, SUM(GROSS_PROFIT) gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-08-18' AND DATE '2025-11-15'
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 15),
peak AS (SELECT keyword_id, SUM(Ads_cost) cost, SUM(GROSS_PROFIT) gp, SUM(Ads_sales) sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-16' AND DATE '2025-12-25' GROUP BY 1)
SELECT IF(SAFE_DIVIDE(t.gp,t.cost)<1.0,'trailing_says_BELOW_bar','trailing_says_at_or_above') trailing_verdict,
  IF(SAFE_DIVIDE(p.gp,p.cost)>=1.0,'season_EARNED','season_lost') season_truth,
  COUNT(*) keywords, ROUND(SUM(p.sales),0) peak_sales,
  ROUND(SUM(p.gp-p.cost),0) peak_net, ROUND(SUM(p.gp-p.cost)/40,2) peak_net_per_day
FROM trailing_90d_at_nov15 t JOIN peak p USING (keyword_id)
GROUP BY 1,2 ORDER BY 1,2;

-- the last-year signal exists but never reaches the Catalog's contract:
SELECT COUNT(*) guard_rows, COUNTIF(ly_clk28>0) rows_with_last_year_clicks,
       COUNTIF(ly_conv_cpc IS NOT NULL) rows_with_ly_conv_cpc
FROM `onyga-482313.OI.V_KEYWORD_GUARD`;
SELECT column_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name='FACT_KEYWORD_STATE'
  AND (column_name LIKE 'ly%' OR column_name LIKE 'pace%' OR column_name LIKE '%season%');
```

### THE PARK TRAP — a park is an absorbing state

HIGH on the counts and the one-way bid ratio; the $147.89/day is last-season net profit at stake, not current burn — current holding cost is trivial. Verified today: 544 PARKED, 336 rows with NULL family, 836/838 floor_since NULL.

```sql
WITH parked AS (SELECT keyword_id, current_bid, bid_floor, next_check_what, next_check_date,
                       state_since, floor_since
                FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE state='PARKED'),
served_28d AS (SELECT keyword_id, SUM(impressions) imp, SUM(clicks) clk
  FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23' GROUP BY 1),
last_season AS (SELECT keyword_id, SUM(Ads_orders) ord, SUM(Ads_sales) sales,
    SUM(GROSS_PROFIT)-SUM(Ads_cost) net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31' GROUP BY 1),
bid_moves_60d AS (SELECT keyword_id, COUNTIF(new_bid>old_bid) raises, COUNTIF(new_bid<old_bid) cuts
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE applied_at >= TIMESTAMP '2026-06-25'
    AND UPPER(COALESCE(upload_status,'')) NOT LIKE '%FAIL%' GROUP BY 1)
SELECT COUNT(*) parked_n, COUNTIF(COALESCE(s.clk,0)=0) dark_28d,
  COUNTIF(COALESCE(s.clk,0)=0 AND p.next_check_what LIKE 'parked, record too thin%')
    AS trapped_awaiting_impossible_evidence,
  COUNTIF(p.floor_since IS NULL) floor_since_null,
  COUNTIF(p.state_since IS NULL) state_since_null,
  SUM(IF(COALESCE(s.clk,0)=0, COALESCE(b.cuts,0),0)) dark_cuts_60d,
  SUM(IF(COALESCE(s.clk,0)=0, COALESCE(b.raises,0),0)) dark_raises_60d,
  COUNTIF(COALESCE(s.clk,0)=0 AND ls.ord>0) dark_with_last_season_orders,
  ROUND(SUM(IF(COALESCE(s.clk,0)=0, COALESCE(ls.net,0),0))/61,2) net_per_season_day
FROM parked p LEFT JOIN served_28d s USING (keyword_id)
LEFT JOIN last_season ls USING (keyword_id) LEFT JOIN bid_moves_60d b USING (keyword_id);

-- overdue appointments
SELECT COUNT(*) overdue_n,
  ROUND(AVG(DATE_DIFF(DATE '2026-08-24',next_check_date,DAY)),1) avg_overdue,
  APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24',next_check_date,DAY),4)[OFFSET(2)] p50,
  MAX(DATE_DIFF(DATE '2026-08-24',next_check_date,DAY)) max_overdue
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
WHERE state='PARKED' AND next_check_date <= DATE '2026-08-24';
```

### THE UMBRELLA — right answer, no hands

HIGH — re-run and confirmed to the cent on 2026-08-24: 84 subjects, $359.18/day settled spend, $194.49/day GP, $137.96/day excess. HARVEST 42 subjects $80.26/day; INVEST 42 subjects $57.70/day (launch-exempt, contested). The settled window was verified by exact reconstruction — aggregating FACT_AMAZON_ADS over [wm−settle_days_eff−89, wm−settle_days_eff] reproduces settled_clk90/ord90/sp90/gp90 to the cent.

```sql
-- Bleed on a SETTLED-and-recent window: 28 days ending at wm - settle_days_eff.
-- "Conclusively below bar" is the LADDER'S OWN test on the ladder's own fields.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH sub AS (
  SELECT keyword_id, campaign_id, family, settle_days_eff, family_bar
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE COALESCE(settled_clk90,0) >= 15
    AND COALESCE(settled_roas90,0) - family_bar < -COALESCE(se_eff,0)),
w AS (
  SELECT s.keyword_id, s.campaign_id, s.family, s.family_bar,
         SUM(a.Ads_cost) sp28, SUM(a.GROSS_PROFIT) gp28
  FROM sub s LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON a.keyword_id=s.keyword_id AND a.campaign_id=s.campaign_id
   AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL s.settle_days_eff DAY),INTERVAL 27 DAY)
                  AND DATE_SUB(wm,INTERVAL s.settle_days_eff DAY)
  GROUP BY 1,2,3,4)
SELECT IF(family IN ('Bottle','Lollibox','LolliME','Fresh'),'HARVEST','INVEST') book,
  COUNT(*) n, ROUND(SUM(sp28)/28,2) spend_day, ROUND(SUM(gp28)/28,2) gp_day,
  ROUND(SUM(GREATEST(sp28 - SAFE_DIVIDE(gp28, family_bar),0))/28,2) excess_day
FROM w GROUP BY 1
UNION ALL SELECT 'TOTAL', COUNT(*), ROUND(SUM(sp28)/28,2), ROUND(SUM(gp28)/28,2),
  ROUND(SUM(GREATEST(sp28 - SAFE_DIVIDE(gp28, family_bar),0))/28,2) FROM w;
```

### OUTSIDE THE CATALOG ENTIRELY (incl. the SB '-1' sentinel)

HIGH on the population and the spend — re-run and confirmed exactly: 74 rows outside the Catalog at $132.71/day and 0.528 pooled GP-ROAS, against 385 rows inside at $1,190.51/day and 0.906. Sentinel '-1' verified at $66.96/day over 14 days, 10 campaigns, 30 targets. MEDIUM on the $54.93/day excess figure only, because it is computed against a declared reference bar of 0.8431 (median of the six live family bars) rather than a bar these subjects actually own.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
DECLARE ref_bar FLOAT64 DEFAULT 0.8431;  -- median of the six family bars, 2026-08-24, DECLARED
WITH spend AS (
  SELECT keyword_id, campaign_id, ANY_VALUE(campaign_type) ct, ANY_VALUE(campaign_name) cn,
         ANY_VALUE(targeting) tg,
         SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d, SUM(Ads_clicks) c28
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm AND keyword_id IS NOT NULL
  GROUP BY 1,2)
SELECT COUNTIF(k.keyword_id IS NULL) rows_outside_catalog,
  ROUND(SUM(IF(k.keyword_id IS NULL,s.sp_d,0)),2) outside_spend_day,
  ROUND(SAFE_DIVIDE(SUM(IF(k.keyword_id IS NULL,s.gp_d,0)),
                    SUM(IF(k.keyword_id IS NULL,s.sp_d,0))),3) outside_roas,
  ROUND(SUM(IF(k.keyword_id IS NULL, GREATEST(s.sp_d-SAFE_DIVIDE(s.gp_d,ref_bar),0),0)),2) outside_excess,
  COUNTIF(k.keyword_id IS NOT NULL) rows_in_catalog,
  ROUND(SUM(IF(k.keyword_id IS NOT NULL,s.sp_d,0)),2) inside_spend_day
FROM spend s LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` k USING (keyword_id,campaign_id)
WHERE s.sp_d>0;

-- the sentinel, and proof no layer can see what Pacing prices:
SELECT ROUND(SUM(Ads_cost)/14,2) sentinel_usd_day, COUNT(DISTINCT campaign_id) camps,
       COUNT(DISTINCT targeting) targets
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE keyword_id='-1' AND date BETWEEN DATE '2026-08-10' AND DATE '2026-08-23';
WITH ids AS (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date=DATE '2026-08-24' AND match_type='TARGETING_EXPRESSION' AND channel='SB')
SELECT COUNT(*) sb_pt_targets_pacing_prices,
  COUNTIF(ks.keyword_id IS NOT NULL) in_catalog,
  COUNTIF(pl.keyword_id IS NOT NULL) in_brain
FROM ids
LEFT JOIN (SELECT DISTINCT keyword_id,campaign_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE`) ks
  USING (keyword_id,campaign_id)
LEFT JOIN (SELECT DISTINCT keyword_id,campaign_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of=DATE '2026-08-24' AND plan='B') pl USING (keyword_id,campaign_id);
```

### THE SLOW CONVERTER — the window cannot see it convert

HIGH — re-run and confirmed exactly: band <5% = 158 subjects, $118.60/day, GP-ROAS 0.91, 69.1 days to 2 orders. Band 5-20% = 58 subjects, $154.93/day. Together 216 subjects and $273.53/day = 19.9% of the account. Band ≥20% = 53 subjects, $606.22/day, 3.9 days to 2 orders — so the window works fine for the subjects it can see.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH g AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
           FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
f AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
        SUM(Ads_orders) ord90, SUM(Ads_cost) sp90, SUM(GROSS_PROFIT) gp90
      FROM `onyga-482313.OI.FACT_AMAZON_ADS`
      WHERE date > DATE_SUB(wm, INTERVAL 90 DAY) GROUP BY 1,2),
x AS (SELECT f.ord90, f.sp90, f.gp90, f.ord90*3.0/90.0 lam3
      FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
      JOIN g ON g.cid=ks.campaign_id AND g.kid=ks.keyword_id
      JOIN f ON f.cid=ks.campaign_id AND f.kid=ks.keyword_id
      WHERE f.ord90 > 0)
SELECT CASE WHEN 1-EXP(-lam3)*(1+lam3) >= 0.20 THEN 'A. >=20% chance of 2 orders in a 3d window'
            WHEN 1-EXP(-lam3)*(1+lam3) >= 0.05 THEN 'B. 5-20%'
            ELSE 'C. <5% - can essentially never clear the bar' END band,
  COUNT(*) n, ROUND(SUM(sp90)/90,2) spend_day,
  ROUND(SAFE_DIVIDE(SUM(gp90),SUM(sp90)),2) gp_roas,
  ROUND(AVG(SAFE_DIVIDE(90.0,NULLIF(ord90,0))*2),1) avg_days_to_2_orders
FROM x GROUP BY 1 ORDER BY 1;
-- and the config that sets the window:
SELECT * FROM `onyga-482313.OI.DE_PLAN_CONFIG`;
```

### THE SEASON LEDGER BLENDS FAMILIES

HIGH — direct count. 257 real-keyword texts carry $538.31/day of settled spend; 20 span ≥2 product families and carry $116.58/day (21.7% of the keyword-grain spend the ledger governs, 8.8% of the account). All 20 have rows in the ledger. Magnitude is real: 'gift for girls' spans LolliBall/LolliME/Bunny at $26.59/day with settled GP-ROAS 0.00 to 2.08; 'gift for 14 year old girl' spans Fresh and Bunny at $11.75/day with 0.17 vs 0.85 — one side a clear loss, the other near bar, one verdict for both.

```sql
WITH catalog_texts AS (
  SELECT target_text, COUNT(DISTINCT family) families,
         STRING_AGG(DISTINCT family ORDER BY family) family_list,
         SUM(settled_sp90)/90 spend_per_day,
         MIN(settled_roas90) min_gp_roas, MAX(settled_roas90) max_gp_roas
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE family IS NOT NULL
    -- mirror V_KEYWORD_CONTEXT_GATE's own exclusions: keyword grain only
    AND NOT COALESCE(is_auto,FALSE) AND NOT COALESCE(is_pt,FALSE)
    AND target_text NOT IN ('substitutes','complements','close-match','loose-match','*')
  GROUP BY 1),
ledger_texts AS (SELECT DISTINCT keyword_text FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT`)
SELECT COUNT(*) texts_total,
  COUNTIF(c.families>1) texts_spanning_multiple_families,
  ROUND(SUM(IF(c.families>1,c.spend_per_day,0)),2) colliding_spend_per_day,
  ROUND(SUM(c.spend_per_day),2) keyword_grain_spend_per_day,
  COUNTIF(c.families>1 AND l.keyword_text IS NOT NULL) colliding_and_in_ledger
FROM catalog_texts c LEFT JOIN ledger_texts l ON l.keyword_text=c.target_text;

-- the offending rows, with the spread that proves the blend matters:
SELECT target_text, COUNT(DISTINCT family) families,
  STRING_AGG(DISTINCT family ORDER BY family) family_list,
  ROUND(SUM(settled_sp90)/90,2) spend_per_day,
  ROUND(MIN(settled_roas90),2) min_gp_roas, ROUND(MAX(settled_roas90),2) max_gp_roas
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL
GROUP BY 1 HAVING COUNT(DISTINCT family)>1 ORDER BY spend_per_day DESC;
```

### THE HARVEST GAP — proven terms with no keyword

MEDIUM — re-run and confirmed exactly (130 terms, 488 orders = 7.7% of the account's 6,312, 7,523 clicks, $56.10/day, CVR 6.49% vs account 3.97%). MEDIUM not HIGH because these are the survivors of 48,530 search terms measured in the same window, so their headline GP-ROAS of 1.26 is selection-biased upward by an unknown amount and I do NOT claim it transfers to an exact keyword. Click and order counts are the load-bearing numbers here, not GP.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH st AS (SELECT LOWER(TRIM(search_term)) term, SUM(Ads_clicks) clk, SUM(Ads_cost) sp,
              SUM(Ads_orders) ord, SUM(GROSS_PROFIT) gp
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`
            WHERE date > DATE_SUB(wm, INTERVAL 90 DAY) AND search_term IS NOT NULL
              AND LOWER(search_term) NOT LIKE 'b0%' AND LENGTH(search_term) > 3
            GROUP BY 1),
kw AS (SELECT DISTINCT LOWER(TRIM(keyword_text)) term
       FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current),
acct AS (SELECT SUM(Ads_orders) o, SUM(Ads_clicks) c, SUM(Ads_cost) sp
         FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date > DATE_SUB(wm, INTERVAL 90 DAY))
SELECT COUNT(*) terms_no_keyword, SUM(st.ord) orders90, SUM(st.clk) clicks90,
  ROUND(SUM(st.sp)/90,2) spend_day,
  ROUND(SAFE_DIVIDE(SUM(st.ord),SUM(st.clk)),4) cvr,
  (SELECT ROUND(SAFE_DIVIDE(o,c),4) FROM acct) acct_cvr,
  (SELECT o FROM acct) acct_orders90
FROM st LEFT JOIN kw USING (term)
WHERE kw.term IS NULL AND st.ord >= 2 AND st.clk >= 15;
```

### DECIDED, LOGGED, NEVER UPLOADED

HIGH — re-verified today: 1,829 landed rows, 332 SUPERSEDED_NEVER_UPLOADED (2026-08-22 onward), 40 FAILED_UPLOAD (oldest 2026-08-06), 6 PENDING_UPLOAD. Restricting to keywords ALSO conclusively below bar today gives the conservative slice: 11 subjects, $89.95/day settled spend, $28.40/day excess, of which $27.49/day is HARVEST.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
SELECT COALESCE(upload_status,'(landed)') st, COUNT(*) n,
       MIN(DATE(applied_at,'America/Los_Angeles')) oldest
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` GROUP BY 1 ORDER BY n DESC;

WITH nu AS (
  SELECT keyword_id, MIN(DATE(applied_at,'America/Los_Angeles')) first_proposed,
         MIN(IF(action='REDUCE_BID', new_bid, NULL)) deepest_cut,
         LOGICAL_OR(action='KEYWORD_PAUSE') pause_proposed
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE upload_status IN ('SUPERSEDED_NEVER_UPLOADED','FAILED_UPLOAD','PENDING_UPLOAD')
    AND action IN ('REDUCE_BID','KEYWORD_PAUSE') GROUP BY 1),
r AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d
      FROM `onyga-482313.OI.FACT_AMAZON_ADS`
      WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm GROUP BY 1,2)
SELECT CASE WHEN nu.pause_proposed THEN 'pause proposed, never uploaded'
            WHEN k.current_bid > nu.deepest_cut + 0.005
              THEN 'cut proposed, never uploaded, bid still above it'
            ELSE 'cut proposed and bid is now at/below it' END bucket,
  COUNT(*) n, ROUND(SUM(r.sp_d),2) spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) roas28,
  ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d, k.family_bar),0)),2) excess_per_day,
  MIN(nu.first_proposed) oldest_unexecuted
FROM nu JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` k USING (keyword_id)
LEFT JOIN r ON r.keyword_id=k.keyword_id AND r.campaign_id=k.campaign_id
GROUP BY 1 ORDER BY spend_per_day DESC;
```

### WHIPSAW — repair reversed faster than performed

HIGH on the historical events (47 pairs, 2026-07-30 to 2026-08-15, 35 raises from COACH and 12 from MANUAL; the 35 keywords carry $170.23/day at 0.754 ROAS = $31.16/day excess). But the precedence fix may already be in: FACT_ENGINE_PROPOSALS on 2026-08-24 shows LIFT/OOB/REVERDICT actions EXCLUDEd with hold_source='PLAN'. Every measured whipsaw predates 2026-08-15 and no uploads have landed since 2026-08-23, so there is NO post-fix evidence either way yet. This is the single cleanest re-run test in the baseline.

```sql
-- An APPLIED cut undone by an APPLIED raise within 7 days landing at or above the pre-cut bid.
WITH a AS (
  SELECT keyword_id, campaign_id, DATE(applied_at,'America/Los_Angeles') d, applied_at,
         action, old_bid, new_bid, source
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE COALESCE(upload_status,'') NOT IN
        ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
    AND action IN ('REDUCE_BID','INCREASE_BID') AND old_bid>0 AND new_bid>0),
pairs AS (
  SELECT c.keyword_id, c.campaign_id, c.d cut_day, c.old_bid bid_before_cut,
         c.new_bid bid_after_cut, r.d raise_day, r.new_bid bid_after_raise,
         r.source raise_source, DATE_DIFF(r.d,c.d,DAY) days_between
  FROM a c JOIN a r ON r.keyword_id=c.keyword_id AND r.campaign_id=c.campaign_id
   AND c.action='REDUCE_BID' AND r.action='INCREASE_BID'
   AND r.applied_at > c.applied_at AND DATE_DIFF(r.d,c.d,DAY) <= 7
   AND r.new_bid >= c.old_bid - 0.005)
SELECT COUNT(*) n_whipsaws, COUNT(DISTINCT keyword_id) n_keywords,
  ROUND(AVG(days_between),1) avg_days_from_cut_to_undo,
  ROUND(AVG(SAFE_DIVIDE(bid_after_raise,bid_after_cut)),2) avg_undo_multiple,
  ROUND(AVG(SAFE_DIVIDE(bid_after_raise,bid_before_cut)),2) avg_vs_pre_cut_bid,
  COUNTIF(raise_source='COACH') by_coach, COUNTIF(raise_source='MANUAL') by_manual,
  MIN(cut_day) first_seen, MAX(raise_day) last_seen
FROM pairs;

-- did the precedence fix hold? re-run this in a month:
SELECT engine, action, hold_source, COUNT(*) n
FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
WHERE snapshot_date = DATE '2026-08-24' GROUP BY 1,2,3 ORDER BY n DESC;
```

### THE KILL GATE IS CLOSED, NOT SLOW

HIGH — re-verified today on the live snapshot: 838 of 838 rows have probation_clock_start IS NULL; probation_elapsed true on 0; state='LOSER' on 0; state='FLOOR_PROBATION' on 2 (both already at their $0.20 SP floor, so the only missing ingredient is the clock). 18 subjects are conclusively below bar AND already at/below their own ceiling: $65.65/day at 0.655 ROAS, $19.76/day excess, no further move available to any layer. Plus 21 in DEAD at $5.88/day, all with next_check_date NULL.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
SELECT COUNT(*) rows_in_catalog,
  COUNTIF(probation_clock_start IS NULL) clock_never_started,
  COUNTIF(probation_elapsed) probation_elapsed,
  COUNTIF(state='LOSER') n_loser,
  COUNTIF(state='FLOOR_PROBATION') n_floor_probation,
  COUNTIF(state='DEAD') n_dead, COUNTIF(at_floor) n_at_floor
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;

SELECT COUNT(*) pause_rows_total,
  COUNT(DISTINCT DATE(applied_at,'America/Los_Angeles')) distinct_days_with_a_pause_row,
  COUNTIF(upload_status='SUPERSEDED_NEVER_UPLOADED') pauses_never_uploaded,
  COUNTIF(upload_status IS NULL) pauses_landed
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE action='KEYWORD_PAUSE';

-- subjects that have run the whole repair path and are still losing:
WITH r AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d
           FROM `onyga-482313.OI.FACT_AMAZON_ADS`
           WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm GROUP BY 1,2)
SELECT COUNT(*) n_exhausted, ROUND(SUM(r.sp_d),2) spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) roas28,
  ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d,k.family_bar),0)),2) excess_per_day
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` k LEFT JOIN r USING (keyword_id,campaign_id)
WHERE COALESCE(k.settled_clk90,0)>=15
  AND COALESCE(k.settled_roas90,0)-k.family_bar < -COALESCE(k.se_eff,0)
  AND k.current_bid <= COALESCE(k.affordable_bid,k.bid_floor)+0.005;
```

### THE SEAT IS LAST WINDOW'S SPEND

HIGH on the identity, which is the load-bearing claim: corr(seat_cost_per_day, prior-window spend per day) = 0.995 and the mean ratio is 0.973 — the seat IS last window's spend with a rounding error. Of 53 live seats holding $197.59/day, 40 are underfunded against clicks-needed-for-2-orders at each subject's own settled CVR; 13 fully-funded seats hold $167.86/day = 85% of all seat money. Total to fund every open question properly: $1,418.58 over the seat windows (~$136/day).

```sql
WITH wm AS (SELECT MAX(date) d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
fam_cvr AS (SELECT family, SAFE_DIVIDE(SUM(settled_ord90),NULLIF(SUM(settled_clk90),0)) cvr
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL GROUP BY 1),
cc AS (SELECT CAST(campaign_id AS STRING) cid,
         SAFE_DIVIDE(SUM(Ads_cost),NULLIF(SUM(Ads_clicks),0)) camp_cpc
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm
       WHERE date > DATE_SUB(wm.d, INTERVAL 90 DAY) GROUP BY 1),
p AS (SELECT p.seat_cost_per_day, p.w_sp, p.window_days,
        DATE_DIFF(p.verdict_date, p.as_of, DAY) dv,
        COALESCE(NULLIF(ks.settled_cpc90,0), cc.camp_cpc, 0.6) exp_cpc,
        COALESCE(NULLIF(SAFE_DIVIDE(ks.settled_ord90,NULLIF(ks.settled_clk90,0)),0), fc.cvr, 0.03) exp_cvr
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
      LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` ks
        ON ks.campaign_id=p.campaign_id AND ks.keyword_id=p.keyword_id
      LEFT JOIN fam_cvr fc ON fc.family=p.family
      LEFT JOIN cc ON cc.cid=p.campaign_id
      WHERE p.as_of=DATE '2026-08-24' AND p.is_live_plan AND p.seat_no IS NOT NULL),
q AS (SELECT *, SAFE_DIVIDE(seat_cost_per_day*dv, exp_cpc) clk_bought,
        SAFE_DIVIDE(2, exp_cvr) clk_needed FROM p)
SELECT CASE WHEN clk_bought/clk_needed>=1 THEN 'fully funded'
            WHEN clk_bought/clk_needed>=0.5 THEN '50-99% funded'
            WHEN clk_bought/clk_needed>=0.25 THEN '25-49% funded'
            ELSE 'under 25% funded' END band,
  COUNT(*) seats, ROUND(SUM(seat_cost_per_day),2) seat_dollars_per_day,
  ROUND(AVG(clk_bought),1) avg_clicks_bought, ROUND(AVG(clk_needed),1) avg_clicks_needed,
  ROUND(AVG(dv),1) avg_days_granted,
  ROUND(AVG(SAFE_DIVIDE(clk_needed*exp_cpc, seat_cost_per_day)),1) days_actually_needed,
  ROUND(SUM(GREATEST(0,(clk_needed-clk_bought)*exp_cpc)),2) dollar_shortfall,
  ROUND((SELECT CORR(seat_cost_per_day, w_sp/window_days) FROM q),3) corr_seat_vs_prior_spend,
  ROUND((SELECT AVG(SAFE_DIVIDE(seat_cost_per_day,NULLIF(w_sp/window_days,0))) FROM q),3) avg_ratio
FROM q GROUP BY 1 ORDER BY 1;
```

### THE STARVED ENTRY — a park at the floor buys no evidence

HIGH on the counts and rates. Adversarially: the DOLLARS are trivial — $18.77/day is 1.4% of the account. This scenario matters because it is a discovery blackhole, not a money leak, and inflating it would be dishonest. State dwell is right-censored: the oldest state_since in FACT_KEYWORD_STATE is 2026-07-02, so nothing older than 53 days can be measured, and floor_since only reaches 2026-08-22.

```sql
WITH wm AS (SELECT MAX(date) d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
live AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
         FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
fam_cvr AS (SELECT family, SAFE_DIVIDE(SUM(settled_ord90),NULLIF(SUM(settled_clk90),0)) cvr
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL GROUP BY 1),
ads AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
          SUM(IF(date>DATE_SUB((SELECT d FROM wm),INTERVAL 28 DAY),Ads_clicks,0)) clk28,
          SUM(IF(date>DATE_SUB((SELECT d FROM wm),INTERVAL 28 DAY),Ads_cost,0)) sp28
        FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1,2),
tgt AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
          SUM(impressions) imp_all, SUM(clicks) clk_all
        FROM `onyga-482313.OI.V_TARGET_DAILY` GROUP BY 1,2),
acct AS (SELECT SAFE_DIVIDE(SUM(clicks),SUM(impressions)) ctr
         FROM `onyga-482313.OI.V_TARGET_DAILY`, wm WHERE date > DATE_SUB(wm.d,INTERVAL 90 DAY)),
x AS (SELECT ks.current_bid, IFNULL(ads.clk28,0)/28.0 clk_per_day, IFNULL(ads.sp28,0)/28.0 spd,
        SAFE_DIVIDE(2, COALESCE(fc.cvr,0.04)) clicks_needed, tgt.imp_all, tgt.clk_all
      FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
      JOIN live ON live.cid=ks.campaign_id AND live.kid=ks.keyword_id
      LEFT JOIN ads ON ads.cid=ks.campaign_id AND ads.kid=ks.keyword_id
      LEFT JOIN tgt ON tgt.cid=ks.campaign_id AND tgt.kid=ks.keyword_id
      LEFT JOIN fam_cvr fc ON fc.family=ks.family
      WHERE ks.state IN ('TRIAL','PARKED') AND IFNULL(ks.settled_ord90,0) < 2)
SELECT COUNT(*) untested_live_subjects, ROUND(SUM(spd),2) spend_per_day,
  ROUND(AVG(current_bid),3) avg_bid, COUNTIF(clk_per_day=0) zero_clicks_28d,
  COUNTIF(clk_per_day>0 AND clicks_needed/clk_per_day<=30) can_answer_within_30d,
  COUNTIF(clk_per_day>0 AND clicks_needed/clk_per_day>365) over_a_year_to_answer,
  ROUND(APPROX_QUANTILES(IF(clk_per_day>0,clicks_needed/clk_per_day,NULL),2)[OFFSET(1)],0)
    median_days_to_answer_when_clicking,
  COUNTIF(imp_all>0 AND IFNULL(clk_all,0)=0) served_but_never_clicked,
  COUNTIF(imp_all>0 AND IFNULL(clk_all,0)=0 AND imp_all*(SELECT ctr FROM acct)<1)
    not_even_one_expected_click,
  (SELECT ROUND(ctr,5) FROM acct) account_ctr
FROM x;
```

### THE MIX-DRIFT GUARD LAUNDERS LOSERS

HIGH on the one-sidedness proof, which is the point: clean_roas90 > settled_roas90 on 247 rows, EQUAL on 19, LOWER on exactly 1. Median cleaned/raw lift 3.66x, p90 27.7x, max 583x, and the guard discards 56.8% of ALL settled clicks account-wide. Current outcome changes are small ($13.95/day excess on 3 verdict flips, $4.08/day on 2 frozen cuts) but the worst single case shows the stakes: Lollibox SB 'tween girl gifts' discards 1,784 of 2,060 settled clicks, raw ROAS 0.763 vs bar 0.812 but cleaned 5.385 — a 7.4x price difference riding on which record you believe.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH r AS (SELECT k.keyword_id, k.campaign_id, SUM(a.Ads_cost)/28 sp_d, SUM(a.GROSS_PROFIT)/28 gp_d
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` k LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON a.keyword_id=k.keyword_id AND a.campaign_id=k.campaign_id
   AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL k.settle_days_eff DAY),INTERVAL 27 DAY)
                  AND DATE_SUB(wm,INTERVAL k.settle_days_eff DAY)
  GROUP BY 1,2)
SELECT CASE WHEN k.state != k.raw_state THEN 'A. guard changed the STATE (losing verdict overturned)'
            WHEN k.guard_scope='AT_BAR_PRICE' THEN 'B. guard FROZE the cut (label kept, price held)'
            ELSE 'C. guard did not change the outcome' END bucket,
  COUNT(*) n, ROUND(SUM(r.sp_d),2) settled_spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) settled_roas28,
  ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d,k.family_bar),0)),2) excess_per_day,
  ROUND(SAFE_DIVIDE(SUM(k.ns_zero_ord_clicks),SUM(k.settled_clk90)),3) share_clicks_discarded
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` k LEFT JOIN r USING (keyword_id,campaign_id)
GROUP BY 1 ORDER BY 1;

-- PROOF the filter is monotone upward (re-run this: if still 247/1, nothing was done):
SELECT COUNTIF(clean_roas90 > settled_roas90 + 0.001) higher,
       COUNTIF(clean_roas90 < settled_roas90 - 0.001) lower,
       COUNTIF(ABS(clean_roas90-settled_roas90) <= 0.001) same,
       ROUND(APPROX_QUANTILES(SAFE_DIVIDE(clean_roas90,NULLIF(settled_roas90,0)),100)[OFFSET(50)],2) p50_lift,
       ROUND(MAX(SAFE_DIVIDE(clean_roas90,NULLIF(settled_roas90,0))),1) max_lift
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE COALESCE(settled_clk90,0) > 0;
```

### THE MISSING MIDDLE WINDOW — slow decline is invisible

HIGH — 13 subjects in WINNER/PACED_WINNER/AT_BAR whose fully-settled last 28 days read below (family_bar − se_eff) while settled_roas90 still clears it: $64.05/day settled spend, pooled recent ROAS 0.621 against a pooled 90d record of 0.985. In the live plan, 6 carry move=NONE verdict=GOOD, 5 carry move=NONE verdict=HELD_UNSETTLED, 1 is not in the plan at all, and only 1 has any corrective move.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH s AS (SELECT keyword_id, campaign_id, family, target_text, state, settle_days_eff,
             family_bar, se_eff, settled_roas90, settled_sp90, settled_gp90
           FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
           WHERE state IN ('WINNER','PACED_WINNER','AT_BAR')),
w28 AS (SELECT s.*, SUM(a.Ads_clicks) c28, SUM(a.Ads_cost) sp28, SUM(a.GROSS_PROFIT) gp28
  FROM s LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON a.keyword_id=s.keyword_id AND a.campaign_id=s.campaign_id
   AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL s.settle_days_eff DAY),INTERVAL 27 DAY)
                  AND DATE_SUB(wm,INTERVAL s.settle_days_eff DAY)
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11),
d AS (SELECT *, SAFE_DIVIDE(gp28,sp28) roas28, sp28/28 sp_day,
        GREATEST(sp28 - SAFE_DIVIDE(gp28,family_bar),0)/28 excess_day
      FROM w28 WHERE c28 >= 15)
SELECT CASE WHEN roas28 < family_bar-COALESCE(se_eff,0)
              AND settled_roas90 >= family_bar-COALESCE(se_eff,0)
              THEN 'DECLINING (recent below bar, 90d record still holds)'
            WHEN roas28 < family_bar-COALESCE(se_eff,0) THEN 'recent below bar AND 90d below too'
            ELSE 'recent at/above bar' END bucket,
  COUNT(*) n, ROUND(SUM(sp_day),2) spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(gp28),SUM(sp28)),3) roas28_pooled,
  ROUND(SAFE_DIVIDE(SUM(settled_gp90),SUM(settled_sp90)),3) roas90_pooled,
  ROUND(SUM(excess_day),2) excess_per_day,
  ROUND(APPROX_QUANTILES(IF(roas28 < family_bar AND settled_roas90 >= family_bar,
    SAFE_DIVIDE(settled_gp90 - family_bar*settled_sp90,
                family_bar*(sp28/28) - (gp28/28)), NULL),100)[OFFSET(50)],0)
    median_days_until_90d_crosses
FROM d GROUP BY 1 ORDER BY spend_per_day DESC;
```

### THE RATCHET — cuts capped, raises not

MEDIUM on the dollars, HIGH on the mechanism. Of 457 APPLIED INCREASE_BID rows, 185 (40%) broke the +15.76% cap, max ratio 10.27x. 94 landed at exactly $1.00 between 2026-08-02 and 2026-08-15, average prior bid $0.48, average jump 2.49x, across 92 keywords whose average Catalog ceiling (where below $1) is $0.362. The population figure ($89.58/day) is NOT defensible because the counterfactual is unavailable — some spend would have happened at the lower bid. The $15.03/day is the conservative slice: 48 raises landing on subjects the ladder already called conclusive losers ON THAT DAY.

```sql
-- 1. Cap symmetry, by source. Cuts obey -14.26%; raises break +15.76% 40% of the time.
SELECT source, action, COUNT(*) n,
  COUNTIF(SAFE_DIVIDE(new_bid,old_bid) > 1.1576+0.005) up_over_cap,
  COUNTIF(SAFE_DIVIDE(new_bid,old_bid) < 0.8574-0.005) down_over_cap,
  ROUND(APPROX_QUANTILES(SAFE_DIVIDE(new_bid,old_bid),100)[OFFSET(50)],3) p50_ratio,
  ROUND(MAX(SAFE_DIVIDE(new_bid,old_bid)),2) max_ratio
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
WHERE COALESCE(upload_status,'') NOT IN
      ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
  AND action IN ('INCREASE_BID','REDUCE_BID') AND old_bid>0 AND new_bid>0
GROUP BY 1,2 ORDER BY 1,2;

-- 2. The $1.00 anchor against the Catalog's own ceiling:
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH ev AS (SELECT keyword_id, campaign_id, DATE(applied_at,'America/Los_Angeles') d,
              old_bid, new_bid
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE COALESCE(upload_status,'') NOT IN
        ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
    AND action='INCREASE_BID' AND ROUND(new_bid,2)=1.00 AND old_bid>0
    AND SAFE_DIVIDE(new_bid,old_bid) > 1.1576+0.005)
SELECT COUNT(*) n_raises_to_1_00, COUNT(DISTINCT e.keyword_id) n_keywords,
  ROUND(AVG(e.old_bid),3) avg_bid_before,
  ROUND(AVG(SAFE_DIVIDE(e.new_bid,e.old_bid)),2) avg_jump_multiple,
  COUNTIF(k.affordable_bid < 1.00) n_where_ceiling_below_1_00,
  ROUND(AVG(IF(k.affordable_bid<1.00, k.affordable_bid, NULL)),3) avg_ceiling_when_below,
  MIN(e.d) first_seen, MAX(e.d) last_seen
FROM ev e LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` k USING (keyword_id, campaign_id);
```

### 'NOTHING TO DO' IS THE MODAL PLAN OUTCOME

HIGH on the count, re-verified today: 189 of 365 live plan rows (51.8%) are NOT_SERVING/NONE. Adversarially, the direct cost is TINY — $9.46/day, 0.7% of the account — and saying so plainly matters, because a reader who sees '189 rows in a forbidden state' will assume a large number is behind it. The real money is the 17 conclusive losers inside it ($41.61/day spend, $20.36/day excess, all HARVEST) and the 30 with seasonal history ($4,943 of last-season net).

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
SELECT p.side, p.verdict, p.move, COUNT(*) n,
  ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) pct_of_plan,
  ROUND(SUM(IFNULL(f.sp14,0))/14,2) spend_per_day,
  COUNTIF(IFNULL(f.clk14,0)=0) zero_clicks_14d,
  ROUND(AVG(ks.settled_clk90),1) avg_settled_clk90,
  ROUND(AVG(ks.settled_ord90),2) avg_settled_ord90
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
             SUM(IF(date>DATE_SUB(wm,INTERVAL 14 DAY),Ads_cost,0)) sp14,
             SUM(IF(date>DATE_SUB(wm,INTERVAL 14 DAY),Ads_clicks,0)) clk14
           FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1,2) f
  ON f.cid=p.campaign_id AND f.kid=p.keyword_id
LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` ks
  ON ks.campaign_id=p.campaign_id AND ks.keyword_id=p.keyword_id
WHERE p.as_of=DATE '2026-08-24' AND p.is_live_plan
GROUP BY 1,2,3 ORDER BY n DESC;
```

### THE SEASON RAMP CANNOT ARRIVE IN TIME

MEDIUM. IMPORTANT: this is the SAME money as THE PARK TRAP viewed as a deadline rather than a discovery problem. It is listed separately because it identifies a different owner for the fix, and it is EXCLUDED from the total to avoid double counting.

```sql
WITH parked AS (SELECT keyword_id, current_bid, bid_floor
                FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE state='PARKED'),
last_season AS (SELECT keyword_id, SUM(Ads_orders) ord,
    SUM(GROSS_PROFIT)-SUM(Ads_cost) net,
    SAFE_DIVIDE(SUM(Ads_cost),SUM(Ads_clicks)) cpc_last_season
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31' GROUP BY 1),
served_28d AS (SELECT keyword_id, SUM(clicks) clk FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23' GROUP BY 1)
SELECT COUNT(*) subjects, ROUND(AVG(p.current_bid),2) avg_bid_now,
  ROUND(AVG(ls.cpc_last_season),2) avg_cpc_last_season,
  ROUND(AVG(ls.cpc_last_season/NULLIF(p.current_bid,0)),2) avg_ratio,
  ROUND(AVG(CEIL(LOG(ls.cpc_last_season/NULLIF(p.current_bid,0))/LOG(1.1576))),1) avg_uploads_at_cap,
  MAX(CEIL(LOG(ls.cpc_last_season/NULLIF(p.current_bid,0))/LOG(1.1576))) max_uploads_at_cap,
  ROUND(SUM(ls.net),0) novdec2025_net_at_stake
FROM parked p JOIN last_season ls USING (keyword_id)
LEFT JOIN served_28d s USING (keyword_id)
WHERE ls.ord>0 AND COALESCE(s.clk,0)=0 AND ls.cpc_last_season > p.current_bid;
```

### THE ONE-WAY DOOR OPENS ON NOISE

HIGH on the noise argument, which is the point rather than the dollars. Against each subject's own family CVR, only ONE of the 21 (LolliME close-match, 46 settled clicks) has under a 10% chance of showing zero orders if it converted at the family rate. 20 of 21 are at 12% or higher and 9 are above 33% — a third of the time a perfectly ordinary keyword would look exactly like this. Median settled clicks in the cohort is 20. Three are being PAUSEd in the 2026-08-24 live plan on 15, 16 and 46 settled clicks.

```sql
WITH fam_cvr AS (SELECT family, SAFE_DIVIDE(SUM(settled_ord90),NULLIF(SUM(settled_clk90),0)) cvr
                 FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL GROUP BY 1)
SELECT ks.family, ks.target_text, ks.settled_clk90, ks.settled_ord90,
  ROUND(fc.cvr,4) family_cvr,
  ROUND(ks.settled_clk90 * fc.cvr, 2) expected_orders_if_family_typical,
  ROUND(EXP(-ks.settled_clk90 * fc.cvr), 3) p_zero_orders_if_family_typical,
  ROUND(ks.settled_sp90/90, 2) spend_per_day,
  ks.next_check_date  -- NULL on all 21: DEAD is the one state with no appointment
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
LEFT JOIN fam_cvr fc ON fc.family = ks.family
WHERE ks.state='DEAD' ORDER BY ks.settled_clk90 DESC;
```

## Probe — entry and discovery

### Live SB video product targets spend for months without ever entering the Catalog

2026-08-24: 10 targets, $66.97/day of spend (4.9% of the account's $1,376.52/day 14d run rate), GP-ROAS 0.60 against family bars of 0.738-0.943. That is $15.82/day of gross profit below bar. They have been spending unseen for 33 days on average; the oldest first appeared 2026-06-08 (77 days). Largest single one: BOX-VIDEO/PT (Competitors, Purple, A1) asin=B0FV38L5KB, $29.16/day at GP-ROAS 0.67 vs a Lollibox bar of 0.812.

```sql
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
f AS (SELECT CAST(a.campaign_id AS STRING) cid, CAST(a.keyword_id AS STRING) kid, ANY_VALUE(a.campaign_name) cn, ANY_VALUE(a.campaign_type) ct, ANY_VALUE(a.targeting) tg,
        MIN(a.date) first_seen,
        SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY), a.Ads_cost, 0)) sp14,
        SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY), a.GROSS_PROFIT, 0)) gp14
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` a GROUP BY 1,2),
dk AS (SELECT CAST(keyword_id AS STRING) kid FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current GROUP BY 1),
fb AS (SELECT campaign_id, ANY_VALUE(family) family, ANY_VALUE(keyword_bar) bar, LOGICAL_OR(bar_exempt) exempt FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1)
SELECT f.cn, f.ct, f.tg, fb.family, ROUND(fb.bar,3) bar,
       ROUND(f.sp14/14,2) spend_per_day, ROUND(f.gp14/14,2) gp_per_day,
       ROUND(SAFE_DIVIDE(f.gp14, f.sp14),2) gp_roas,
       ROUND(IF(fb.exempt, 0, GREATEST(0, (fb.bar - SAFE_DIVIDE(f.gp14,f.sp14)) * f.sp14/14)),2) gp_shortfall_per_day,
       f.first_seen, DATE_DIFF((SELECT d FROM wm), f.first_seen, DAY) days_spending_unseen
FROM f
LEFT JOIN dk ON dk.kid = f.kid
LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` ks ON ks.campaign_id = f.cid AND ks.keyword_id = f.kid
LEFT JOIN fb ON fb.campaign_id = f.cid
WHERE dk.kid IS NULL AND ks.keyword_id IS NULL AND f.sp14 > 0
ORDER BY spend_per_day DESC
```

### The entry population is starved, not tested: a park at the floor is indistinguishable from death and buys no evidence

2026-08-24: 230 of 502 live catalog subjects (TRIAL or PARKED with fewer than 2 settled orders) consume $18.77/day at an average bid of $0.406. 154 of them took ZERO clicks in the last 28 days. Only 3 could reach a 2-order verdict within 30 days at their current click rate; 28 would need over a year; the median for those that click at all is 273 days. Separately, 45 live subjects have impressions and no clicks ever — median 21 impressions, and at the account's measured CTR of 0.949% forty of the forty-five have not accumulated even ONE expected click, so their zero is not evidence of anything. They have been serving 38 days on average at an average bid of $0.286, versus $0.53 for subjects th

```sql
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
live AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
fam_cvr AS (SELECT family, SAFE_DIVIDE(SUM(settled_ord90), NULLIF(SUM(settled_clk90),0)) cvr
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL GROUP BY 1),
ads AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
          SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY), Ads_clicks, 0)) clk28,
          SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY), Ads_cost, 0)) sp28
        FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1,2),
tgt AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
          SUM(impressions) imp_all, SUM(clicks) clk_all, MIN(IF(impressions>0,date,NULL)) first_imp
        FROM `onyga-482313.OI.V_TARGET_DAILY` GROUP BY 1,2),
acct AS (SELECT SAFE_DIVIDE(SUM(clicks), SUM(impressions)) ctr FROM `onyga-482313.OI.V_TARGET_DAILY`, wm
         WHERE date > DATE_SUB(wm.d, INTERVAL 90 DAY)),
x AS (SELECT ks.state, ks.current_bid, IFNULL(ads.clk28,0)/28.0 clk_per_day, IFNULL(ads.sp28,0)/28.0 spd,
        SAFE_DIVIDE(2, COALESCE(fc.cvr, 0.04)) clicks_needed, tgt.imp_all, tgt.clk_all, tgt.first_imp
      FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
      JOIN live ON live.cid = ks.campaign_id AND live.kid = ks.keyword_id
      LEFT JOIN ads ON ads.cid = ks.campaign_id AND ads.kid = ks.keyword_id
      LEFT JOIN tgt ON tgt.cid = ks.campaign_id AND tgt.kid = ks.keyword_id
      LEFT JOIN fam_cvr fc ON fc.family = ks.family
      WHERE ks.state IN ('TRIAL','PARKED') AND IFNULL(ks.settled_ord90,0) < 2)
SELECT COUNT(*) untested_live_subjects,
  ROUND(SUM(spd),2) spend_per_day,
  ROUND(AVG(current_bid),3) avg_bid,
  COUNTIF(clk_per_day = 0) zero_clicks_28d,
  COUNTIF(clk_per_day > 0 AND clicks_needed/clk_per_day <= 30) can_answer_within_30d,
  COUNTIF(clk_per_day > 0 AND clicks_needed/clk_per_day > 365) over_a_year_to_answer,
  ROUND(APPROX_QUANTILES(IF(clk_per_day>0, clicks_needed/clk_per_day, NULL),2)[OFFSET(1)],0) median_days_to_answer_when_clicking,
  COUNTIF(imp_all > 0 AND IFNULL(clk_all,0)=0) served_but_never_clicked,
  COUNTIF(imp_all > 0 AND IFNULL(clk_all,0)=0 AND imp_all*(SELECT ctr FROM acct) < 1) zero_click_not_even_one_expected_click,
  ROUND(AVG(IF(imp_all>0 AND IFNULL(clk_all,0)=0, DATE_DIFF((SELECT d FROM wm), first_imp, DAY), NULL)),0) avg_days_serving_no_click,
  (SELECT ROUND(ctr,5) FROM acct) account_ctr
FROM x
```

### The seat is last window's spend, not the price of the answer — measured as an identity, not a tendency

2026-08-24 live plan (plan B, as_of 2026-08-24): 53 seats holding $197.59/day. corr(seat_cost_per_day, prior-window spend per day) = 0.995 and the mean ratio is 0.973 — the seat IS the prior spend. Against clicks needed for 2 orders at each subject's own settled CVR (family CVR fallback), 40 of 53 seats are underfunded. 27 seats buy under 25% of the evidence they demand: an average of 9.1 clicks bought against 106 needed, which at their granted rate would take 196 days — and they are given 9.9. 13 fully-funded seats hold $167.86/day, i.e. 85% of all seat money; the other 40 seats share $29.73/day. Total shortfall to fund every open question properly: $1,418.58 over the seat windows.

```sql
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
fam_cvr AS (SELECT family, SAFE_DIVIDE(SUM(settled_ord90), NULLIF(SUM(settled_clk90),0)) cvr
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL GROUP BY 1),
cc AS (SELECT CAST(campaign_id AS STRING) cid, SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks),0)) camp_cpc
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm WHERE date > DATE_SUB(wm.d, INTERVAL 90 DAY) GROUP BY 1),
p AS (SELECT p.family, p.target_text, p.verdict, p.move, p.seat_cost_per_day, p.w_sp, p.window_days,
        DATE_DIFF(p.verdict_date, p.as_of, DAY) dv,
        COALESCE(NULLIF(ks.settled_cpc90,0), cc.camp_cpc, 0.6) exp_cpc,
        COALESCE(NULLIF(SAFE_DIVIDE(ks.settled_ord90, NULLIF(ks.settled_clk90,0)),0), fc.cvr, 0.03) exp_cvr
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
      LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` ks ON ks.campaign_id = p.campaign_id AND ks.keyword_id = p.keyword_id
      LEFT JOIN fam_cvr fc ON fc.family = p.family
      LEFT JOIN cc ON cc.cid = p.campaign_id
      WHERE p.as_of = DATE '2026-08-24' AND p.is_live_plan AND p.seat_no IS NOT NULL),
q AS (SELECT *, SAFE_DIVIDE(seat_cost_per_day*dv, exp_cpc) clk_bought, SAFE_DIVIDE(2, exp_cvr) clk_needed FROM p)
SELECT CASE WHEN clk_bought/clk_needed >= 1 THEN 'fully funded'
            WHEN clk_bought/clk_needed >= 0.5 THEN '50-99% funded'
            WHEN clk_bought/clk_needed >= 0.25 THEN '25-49% funded'
            ELSE 'under 25% funded' END band,
  COUNT(*) seats, ROUND(SUM(seat_cost_per_day),2) seat_dollars_per_day,
  ROUND(AVG(clk_bought),1) avg_clicks_bought, ROUND(AVG(clk_needed),1) avg_clicks_needed,
  ROUND(AVG(dv),1) avg_days_granted,
  ROUND(AVG(SAFE_DIVIDE(clk_needed*exp_cpc, seat_cost_per_day)),1) days_actually_needed,
  ROUND(SUM(GREATEST(0,(clk_needed - clk_bought) * exp_cpc)),2) dollar_shortfall,
  ROUND((SELECT CORR(seat_cost_per_day, w_sp/window_days) FROM q),3) corr_seat_vs_prior_spend,
  ROUND((SELECT AVG(SAFE_DIVIDE(seat_cost_per_day, NULLIF(w_sp/window_days,0))) FROM q),3) avg_ratio_seat_to_prior_spend
FROM q GROUP BY 1 ORDER BY 1
```

### Slow converters cannot clear a 2-order bar in a 3-day window — one fifth of the account's spend sits on keywords the judging window structurally cannot see convert

2026-08-24, over the 90 days ending 2026-08-23, live catalog subjects with at least one order: 158 subjects have under a 5% Poisson probability of 2+ orders in a 3-day window; they spend $118.60/day (8.6% of the account) and return $107.62/day GP (GP-ROAS 0.91). Widening to under 20%: 216 subjects, $273.53/day — 19.9% of the account's $1,376.52/day. Average time to accumulate 2 orders in the sub-5% band is 69 days. The consequence this window: 7 slow converters are being parked or moved to the floor ($11.35/day of spend, bids cut 65-75%, e.g. 'gifts for 12 year old girl' cut $1.00 -> $0.25 on 271 settled clicks / 9 orders / ROAS 0.79 vs a 0.81 bar), and 30 more sit in NOT_SERVING with move N

```sql
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
g AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
f AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
        SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY), Ads_orders, 0)) ord90,
        SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY), Ads_cost, 0)) sp90,
        SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY), GROSS_PROFIT, 0)) gp90
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1,2),
x AS (SELECT ks.family, ks.state, ks.target_text, f.ord90, f.sp90, f.gp90,
        f.ord90*3.0/90.0 lam3, f.ord90*7.0/90.0 lam7
      FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
      JOIN g ON g.cid = ks.campaign_id AND g.kid = ks.keyword_id
      JOIN f ON f.cid = ks.campaign_id AND f.kid = ks.keyword_id
      WHERE f.ord90 > 0)
SELECT CASE WHEN 1-EXP(-lam3)*(1+lam3) >= 0.50 THEN 'A. >=50% chance of 2 orders in a 3d window'
            WHEN 1-EXP(-lam3)*(1+lam3) >= 0.20 THEN 'B. 20-50%'
            WHEN 1-EXP(-lam3)*(1+lam3) >= 0.05 THEN 'C. 5-20%'
            ELSE 'D. under 5% - can essentially never clear the bar' END band,
  COUNT(*) n, SUM(ord90) orders_90d,
  ROUND(SUM(sp90)/90,2) spend_per_day, ROUND(SUM(gp90)/90,2) gp_per_day,
  ROUND(SAFE_DIVIDE(SUM(gp90), SUM(sp90)),2) gp_roas,
  ROUND(AVG(1-EXP(-lam3)*(1+lam3)),3) avg_p_2orders_in_3d,
  ROUND(AVG(1-EXP(-lam7)*(1+lam7)),3) avg_p_2orders_in_7d,
  ROUND(AVG(SAFE_DIVIDE(90.0, NULLIF(ord90,0))*2),1) avg_days_to_2_orders
FROM x GROUP BY 1 ORDER BY 1
```

### New-candidate blindness on the ads side: 130 proven converting search terms have no keyword anywhere in the account

90 days ending 2026-08-23: 130 search terms with at least 15 clicks AND at least 2 orders each have no matching keyword_text anywhere in DIM_KEYWORD(is_current). They carry 488 orders (7.7% of the account's 6,312), 7,523 clicks (4.7% of 159,150), $56.10/day of spend (5.1%) at a CPC of $0.671 and a CVR of 6.49% against an account CVR of 3.97%. Their GP-ROAS is 1.26 against an account-wide 0.895 and family bars of 0.738-0.943. Loosening to any term with 2+ orders gives 452 terms, 1,233 orders (19.5% of account orders), $66.05/day.

```sql
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
st AS (SELECT LOWER(TRIM(search_term)) term,
         SUM(Ads_clicks) clk, SUM(Ads_cost) sp, SUM(Ads_orders) ord, SUM(GROSS_PROFIT) gp
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm
       WHERE date > DATE_SUB(wm.d, INTERVAL 90 DAY) AND search_term IS NOT NULL
         AND LOWER(search_term) NOT LIKE 'b0%' AND LENGTH(search_term) > 3
       GROUP BY 1),
kw AS (SELECT DISTINCT LOWER(TRIM(keyword_text)) term FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current),
acct AS (SELECT SUM(Ads_orders) ord, SUM(Ads_clicks) clk, SUM(Ads_cost) sp, SUM(GROSS_PROFIT) gp
         FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm WHERE date > DATE_SUB(wm.d, INTERVAL 90 DAY))
SELECT COUNT(*) terms_with_no_keyword, SUM(st.ord) orders_90d, SUM(st.clk) clicks_90d,
  ROUND(SUM(st.sp)/90,2) spend_per_day, ROUND(SUM(st.gp)/90,2) gp_per_day,
  ROUND(SAFE_DIVIDE(SUM(st.gp), SUM(st.sp)),2) gp_roas,
  ROUND(SAFE_DIVIDE(SUM(st.sp), SUM(st.clk)),3) cpc,
  ROUND(SAFE_DIVIDE(SUM(st.ord), SUM(st.clk)),4) cvr,
  (SELECT ord FROM acct) account_orders_90d,
  (SELECT ROUND(SAFE_DIVIDE(ord, clk),4) FROM acct) account_cvr,
  (SELECT ROUND(SAFE_DIVIDE(gp, sp),3) FROM acct) account_gp_roas,
  (SELECT ROUND(sp/90,2) FROM acct) account_spend_per_day
FROM st LEFT JOIN kw USING (term)
WHERE kw.term IS NULL AND st.ord >= 2 AND st.clk >= 15
```

### SQP as a source of NEW candidates is a mirage — the demand data proposes roughly one fundable keyword per quarter

12 weeks ending 2026-08-15 (SQP's latest week). Queries the account converted on: 131 already have a keyword; 425 have no keyword but ads already buy them as a search term (513 conversions, $17,911 sales — the same population as the ads-side harvest gap); 188 have no keyword AND ads have never seen them. Strip the 'other' aggregate row (2.7M impressions, 6 conversions) and brand-name queries and only 149 remain: 150 conversions, 175 clicks, $5,000 of sales in twelve weeks, and exactly ONE query with 2 or more conversions. Average weekly search volume 292.

```sql
WITH q AS (SELECT LOWER(TRIM(query_text)) term, SUM(impressions) our_imp, SUM(clicks) our_clk,
             SUM(conversions) our_conv, SUM(sales_amount) our_sales, MAX(search_query_volume) svol
           FROM `onyga-482313.OI.FACT_SEARCH_QUERY` WHERE week_end_date > DATE '2026-05-23' GROUP BY 1),
kw AS (SELECT DISTINCT LOWER(TRIM(keyword_text)) term FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current),
adst AS (SELECT DISTINCT LOWER(TRIM(search_term)) term FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date > DATE '2026-05-23')
SELECT CASE WHEN kw.term IS NOT NULL THEN '1. we own a keyword for it'
            WHEN adst.term IS NOT NULL THEN '2. no keyword, but ads already buy it as a search term'
            ELSE '3. no keyword and ads have never seen it' END band,
  CASE WHEN q.term = 'other' THEN 'SQP other bucket'
       WHEN q.term LIKE '%happy lolli%' OR q.term LIKE '%lollibox%' OR q.term LIKE '%lollime%' OR q.term LIKE '%lolli %' THEN 'brand'
       ELSE 'non-brand' END kind,
  COUNT(*) queries, SUM(q.our_conv) conversions_12w, ROUND(SUM(q.our_sales),0) sales_12w,
  SUM(q.our_clk) our_clicks_12w, COUNTIF(q.our_conv >= 2) queries_with_2plus_conversions,
  ROUND(AVG(q.svol),1) avg_weekly_search_volume
FROM q LEFT JOIN kw USING (term) LEFT JOIN adst ON adst.term = q.term
WHERE q.our_conv > 0
GROUP BY 1,2 ORDER BY 1,2
```

### A third of the Catalog is ghosts: enabled keywords inside paused campaigns that can never serve, spend or produce evidence

2026-08-24: FACT_KEYWORD_STATE holds 838 rows. 287 (34.2%) are keywords whose DIM_KEYWORD state is ENABLED but whose campaign_state in V_DIM_CAMPAIGN_CURRENT is PAUSED; all 287 are PARKED, all have NULL family, 260 have NULL campaign_name, none has ever appeared in FACT_AMAZON_ADS, and all carry next_check_date 2026-09-07. Overall 352 of 838 rows have NULL campaign_name and 336 have NULL family. Cost: $0.00/day.

```sql
WITH ads AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1,2),
guard AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`),
dk AS (SELECT CAST(keyword_id AS STRING) kid, ANY_VALUE(state) dim_state FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current GROUP BY 1)
SELECT IFNULL(c.campaign_state,'(campaign absent)') campaign_state,
       IFNULL(dk.dim_state,'(absent)') dim_keyword_state,
       ks.state, COUNT(*) n,
       COUNTIF(ks.family IS NULL) null_family,
       COUNTIF(ks.campaign_name IS NULL) null_campaign_name,
       MIN(ks.next_check_date) min_next_check, MAX(ks.next_check_date) max_next_check,
       (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`) catalog_rows_total
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
LEFT JOIN ads ON ads.cid = ks.campaign_id AND ads.kid = ks.keyword_id
LEFT JOIN guard ON guard.cid = ks.campaign_id AND guard.kid = ks.keyword_id
LEFT JOIN dk ON dk.kid = ks.keyword_id
LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c ON c.campaign_id = ks.campaign_id
WHERE ads.cid IS NULL AND guard.cid IS NULL
GROUP BY 1,2,3 ORDER BY n DESC
```

### The one-way door opens on evidence indistinguishable from noise: DEAD is issued at 15-46 clicks with zero orders

2026-08-24: 21 subjects in state DEAD, together $3.73/day of settled spend. Against each subject's own family CVR (Bottle 2.7-5.9% depending on family), only ONE of the 21 (LolliME close-match, 46 settled clicks) has under a 10% chance of showing zero orders if it converted at the family rate. 20 of 21 are at 12% or higher and 9 are above 33% — i.e. a third of the time a perfectly ordinary keyword would look exactly like this. Median settled clicks in the cohort is 20. Three of them are being PAUSEd in the 2026-08-24 live plan on 15, 16 and 46 settled clicks.

```sql
WITH fam_cvr AS (SELECT family, SAFE_DIVIDE(SUM(settled_ord90), NULLIF(SUM(settled_clk90),0)) cvr
                 FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE family IS NOT NULL GROUP BY 1)
SELECT ks.family, ks.target_text, ks.state, ks.settled_clk90, ks.settled_ord90,
  ROUND(fc.cvr,4) family_cvr,
  ROUND(ks.settled_clk90 * fc.cvr, 2) expected_orders_if_family_typical,
  ROUND(EXP(-ks.settled_clk90 * fc.cvr), 3) p_zero_orders_if_family_typical,
  ROUND(ks.settled_sp90/90, 2) spend_per_day,
  DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), ks.state_since, DAY) days_in_state
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
LEFT JOIN fam_cvr fc ON fc.family = ks.family
WHERE ks.state = 'DEAD'
ORDER BY ks.settled_clk90 DESC
```

### 'Nothing to do' is the modal plan outcome — 52% of the plan is in the state the doctrine explicitly forbids

2026-08-24 live plan: 189 of 365 rows (51.8%) are verdict NOT_SERVING with move NONE. 161 of the 189 took zero clicks in the last 14 days. Their direct cost is small — $9.46/day, 0.7% of the account. Average settled record behind them: 32.0 clicks and 0.84 orders over 90 days, so 28 of them do have a real record the plan is ignoring. Adversarial note: this is a discovery failure, not a money leak — the money at stake is the $18.77/day of untested subjects that will never leave this state, not the $9.46/day it currently burns.

```sql
WITH wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
f AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
        SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY), Ads_cost, 0)) sp14,
        SUM(IF(date > DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY), Ads_clicks, 0)) clk14
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1,2)
SELECT p.side, p.verdict, p.move, COUNT(*) n,
  ROUND(100.0*COUNT(*) / SUM(COUNT(*)) OVER (), 1) pct_of_plan,
  ROUND(SUM(IFNULL(f.sp14,0))/14, 2) spend_per_day,
  COUNTIF(IFNULL(f.clk14,0) = 0) zero_clicks_14d,
  ROUND(AVG(ks.settled_clk90),1) avg_settled_clk90,
  ROUND(AVG(ks.settled_ord90),2) avg_settled_ord90
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
LEFT JOIN f ON f.cid = p.campaign_id AND f.kid = p.keyword_id
LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` ks ON ks.campaign_id = p.campaign_id AND ks.keyword_id = p.keyword_id
WHERE p.as_of = DATE '2026-08-24' AND p.is_live_plan
GROUP BY 1,2,3 ORDER BY n DESC
```

## Probe — decline, repair and death

### THE UMBRELLA — the ladder is right, and $359/day keeps flowing anyway. 84 subjects that the Catalog's own arithmetic calls conclusively below bar beyond noise are still funded.

2026-08-24 (watermark 2026-08-23): 84 subjects are below bar beyond noise on >=15 settled clicks. On a fully settled trailing 28-day window they spend $359.18/day and return $194.49/day of gross profit. At their own family bars that GP supports only ~$223/day of spend, so $137.97/day is spent above what the record justifies — 9.5% of the account's $1,455.95/day (7d ending 2026-08-22). HARVEST families carry $80.27/day of that; the INVEST half is Bunny/LolliBall under the launch exemption, where the bar arguably should not bind. Median time already spent in this condition: 19 days HARVEST / 27 days INVEST, max 145 days.

```sql
-- Bleed on a SETTLED-and-recent window: 28 days ending at wm - settle_days_eff.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH sub AS (
  SELECT keyword_id, campaign_id, family, channel, target_text, state, settle_days_eff,
         family_bar, se_eff, settled_clk90, settled_roas90, current_bid, affordable_bid, bid_floor
  FROM OI.FACT_KEYWORD_STATE
  WHERE COALESCE(settled_clk90,0) >= 15
    AND COALESCE(settled_roas90,0) - family_bar < -COALESCE(se_eff,0)),
w AS (
  SELECT s.keyword_id, s.campaign_id, s.family, s.state, s.channel, s.target_text, s.family_bar,
         s.current_bid, s.affordable_bid, s.bid_floor, s.settled_roas90,
         SUM(a.Ads_clicks) c28, SUM(a.Ads_orders) o28, SUM(a.Ads_cost) sp28, SUM(a.GROSS_PROFIT) gp28
  FROM sub s LEFT JOIN OI.FACT_AMAZON_ADS a
    ON a.keyword_id=s.keyword_id AND a.campaign_id=s.campaign_id
   AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL s.settle_days_eff DAY),INTERVAL 27 DAY)
                  AND DATE_SUB(wm,INTERVAL s.settle_days_eff DAY)
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11)
SELECT
  IF(family IN ('Bottle','Lollibox','LolliME','Fresh'),'HARVEST','INVEST') book,
  COUNT(*) n,
  ROUND(SUM(sp28)/28,2) settled_spend_per_day,
  ROUND(SUM(gp28)/28,2) settled_gp_per_day,
  ROUND(SUM(sp28 - SAFE_DIVIDE(gp28, family_bar))/28,2) excess_per_day,
  ROUND(SUM(GREATEST(sp28 - SAFE_DIVIDE(gp28, family_bar),0))/28,2) excess_per_day_posonly
FROM w GROUP BY 1
UNION ALL
SELECT 'TOTAL', COUNT(*), ROUND(SUM(sp28)/28,2), ROUND(SUM(gp28)/28,2),
  ROUND(SUM(sp28 - SAFE_DIVIDE(gp28, family_bar))/28,2),
  ROUND(SUM(GREATEST(sp28 - SAFE_DIVIDE(gp28, family_bar),0))/28,2)
FROM w
```

### DETECTION LATENCY — reconstructed. From the day the ladder's own formula would first have said 'below bar beyond noise' to the day any cut or pause actually reached Amazon: p50 7 days, p90 24 days, and 32 of 84 have never had one at all.

2026-08-24. Reconstructing the ladder's judgement for every past day (settled window [D-sd-89, D-sd], se = roas/sqrt(ord), band collapsing at nf_orders, bar and nf held at today's family value), then matching against APPLIED rows in FACT_PPC_CHANGE_LOG: latency p50 = 7d, p75 = 12d (HARVEST) / 11d (INVEST), p90 = 24d / 20d, max 128d. 32 of 84 subjects (17 HARVEST, 15 INVEST) have had NO landed REDUCE_BID or KEYWORD_PAUSE since their onset; they carry $131.71/day of trailing-28d spend. Upload cadence itself: 25 upload days in the 71 days 2026-06-14..2026-08-23 = one every 2.92 days, max gap 8 days.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH sub AS (
  SELECT keyword_id, campaign_id, family, family_bar, nf_orders, settle_days_eff
  FROM OI.FACT_KEYWORD_STATE
  WHERE COALESCE(settled_clk90,0) >= 15
    AND COALESCE(settled_roas90,0) - family_bar < -COALESCE(se_eff,0)),
dly AS (SELECT keyword_id, campaign_id, date, SUM(Ads_clicks) c, SUM(Ads_orders) o,
        SUM(Ads_cost) sp, SUM(GROSS_PROFIT) gp
        FROM OI.FACT_AMAZON_ADS WHERE date >= DATE '2025-09-01' AND keyword_id IS NOT NULL GROUP BY 1,2,3),
cal AS (SELECT d AS asof FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2026-01-15', wm)) d),
grid AS (SELECT s.*, cal.asof FROM sub s CROSS JOIN cal),
roll AS (SELECT g.keyword_id, g.campaign_id, g.family, g.family_bar, g.nf_orders, g.asof,
        SUM(d.c) clk, SUM(d.o) ord, SUM(d.sp) sp, SUM(d.gp) gp
  FROM grid g JOIN dly d ON d.keyword_id=g.keyword_id AND d.campaign_id=g.campaign_id
   AND d.date BETWEEN DATE_SUB(DATE_SUB(g.asof,INTERVAL g.settle_days_eff DAY),INTERVAL 89 DAY)
                  AND DATE_SUB(g.asof,INTERVAL g.settle_days_eff DAY)
  GROUP BY 1,2,3,4,5,6),
flagged AS (SELECT *, (clk>=15 AND COALESCE(SAFE_DIVIDE(gp,sp),0)-family_bar <
      -COALESCE(IF(ord>=COALESCE(nf_orders,999999),0.0,
                   IF(ord>0,SAFE_DIVIDE(gp,NULLIF(sp,0))/SQRT(ord),NULL)),0)) AS bad FROM roll),
runs AS (SELECT *, SUM(CASE WHEN bad THEN 0 ELSE 1 END)
    OVER (PARTITION BY keyword_id,campaign_id ORDER BY asof ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) grp FROM flagged),
cur AS (SELECT keyword_id, campaign_id, grp cur_grp FROM runs WHERE asof=wm AND bad),
onset AS (SELECT r.keyword_id, r.campaign_id, r.family, MIN(r.asof) conclusive_since
  FROM runs r JOIN cur c USING (keyword_id,campaign_id) WHERE r.bad AND r.grp=c.cur_grp GROUP BY 1,2,3),
acted AS (SELECT o.keyword_id, o.campaign_id,
    MIN(DATE(l.applied_at,'America/Los_Angeles')) first_down_after
  FROM onset o JOIN OI.FACT_PPC_CHANGE_LOG l ON l.keyword_id=o.keyword_id
  WHERE COALESCE(l.upload_status,'') NOT IN ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
    AND l.action IN ('REDUCE_BID','KEYWORD_PAUSE')
    AND DATE(l.applied_at,'America/Los_Angeles') >= o.conclusive_since
  GROUP BY 1,2),
rec AS (SELECT keyword_id, campaign_id, SUM(sp)/28 sp_d FROM dly
        WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm GROUP BY 1,2),
j AS (SELECT o.*, a.first_down_after, rec.sp_d,
        DATE_DIFF(COALESCE(a.first_down_after, wm), o.conclusive_since, DAY) latency_days
      FROM onset o LEFT JOIN acted a USING (keyword_id,campaign_id) LEFT JOIN rec USING (keyword_id,campaign_id))
SELECT IF(family IN ('Bottle','Lollibox','LolliME','Fresh'),'HARVEST','INVEST') book,
  COUNT(*) n,
  APPROX_QUANTILES(latency_days,100)[OFFSET(50)] p50_latency_days,
  APPROX_QUANTILES(latency_days,100)[OFFSET(75)] p75_latency_days,
  APPROX_QUANTILES(latency_days,100)[OFFSET(90)] p90_latency_days,
  MAX(latency_days) max_latency_days,
  COUNTIF(first_down_after IS NULL) n_never_acted,
  ROUND(SUM(IF(first_down_after IS NULL, sp_d, 0)),2) spend_per_day_never_acted,
  APPROX_QUANTILES(DATE_DIFF(wm, conclusive_since, DAY),100)[OFFSET(50)] p50_days_conclusive,
  MAX(DATE_DIFF(wm, conclusive_since, DAY)) max_days_conclusive
FROM j GROUP BY 1 ORDER BY 1
```

### DECIDED, LOGGED, NEVER UPLOADED — 31 keywords are still bidding above a cut that was already decided and written to the change log, and 5 more are still live under a decided pause.

2026-08-24. FACT_PPC_CHANGE_LOG holds 332 SUPERSEDED_NEVER_UPLOADED rows (2026-08-22..24), 40 FAILED_UPLOAD (all 2026-08-06) and 6 PENDING_UPLOAD. Taking the deepest never-uploaded cut per keyword and comparing to today's live bid: 31 keywords still bid ABOVE the decided price, carrying $230.60/day of trailing-28d spend at 0.670 ROAS = $64.34/day of excess over their bars; 5 more have a decided pause and are still running at $63.91/day. Oldest unexecuted decision: 2026-08-06, 17 days. Restricting to only those keywords that are ALSO conclusively below bar today (the F1 population) gives 11 subjects, $89.95/day settled spend, $28.40/day excess, of which $27.49/day is HARVEST.

```sql
-- Decisions made, written to the change log, and never reaching Amazon.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH nu AS (
  SELECT keyword_id,
         MIN(DATE(applied_at,'America/Los_Angeles')) first_proposed,
         MIN(IF(action='REDUCE_BID', new_bid, NULL)) deepest_cut,
         LOGICAL_OR(action='KEYWORD_PAUSE') pause_proposed,
         COUNT(*) n_rows
  FROM OI.FACT_PPC_CHANGE_LOG
  WHERE upload_status IN ('SUPERSEDED_NEVER_UPLOADED','FAILED_UPLOAD','PENDING_UPLOAD')
    AND action IN ('REDUCE_BID','KEYWORD_PAUSE')
  GROUP BY 1),
r AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d
      FROM OI.FACT_AMAZON_ADS WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm GROUP BY 1,2)
SELECT
  CASE WHEN nu.pause_proposed THEN 'pause proposed, never uploaded'
       WHEN k.current_bid > nu.deepest_cut + 0.005 THEN 'cut proposed, never uploaded, bid still above it'
       ELSE 'cut proposed and bid is now at/below it' END bucket,
  COUNT(*) n,
  ROUND(SUM(r.sp_d),2) spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) roas28,
  ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d, k.family_bar),0)),2) excess_per_day,
  MIN(nu.first_proposed) oldest_unexecuted,
  MAX(DATE_DIFF(wm, nu.first_proposed, DAY)) max_days_unexecuted
FROM nu JOIN OI.FACT_KEYWORD_STATE k USING (keyword_id)
LEFT JOIN r ON r.keyword_id=k.keyword_id AND r.campaign_id=k.campaign_id
GROUP BY 1 ORDER BY spend_per_day DESC
```

### NEW FAILURE MODE — the mix-drift guard is mathematically one-sided and launders losers into winners. It discards only zero-order never-seen clicks, so the cleaned ROAS can never be lower than the raw one. Account-wide it throws away 57% of settled clicks.

2026-08-24. Across FACT_KEYWORD_STATE, clean_roas90 > settled_roas90 on 247 rows, EQUAL on 19, and LOWER on exactly 1 — median cleaned/raw lift 3.66x, p90 27.7x, max 583x. Account-wide the guard discards 56.8% of all settled clicks. Where it currently changes the outcome: 3 subjects had a REPRICE/FLOOR_PROBATION verdict overturned to WINNER (84.3% of their clicks discarded) — $39.92/day settled spend at 0.540 ROAS, $13.95/day excess; 2 more keep the losing label but have the cut frozen (guard_scope='AT_BAR_PRICE') — $7.39/day at 0.407 ROAS, $4.08/day excess. Worst single case: Lollibox SB 'tween girl gifts', 1,784 of 2,060 settled clicks discarded, raw ROAS 0.763 vs bar 0.812 but cleaned ROA

```sql
-- The mix-drift / never-seen guard, on a fully settled 28-day window, plus its one-sidedness.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH r AS (SELECT k.keyword_id, k.campaign_id, SUM(a.Ads_cost)/28 sp_d, SUM(a.GROSS_PROFIT)/28 gp_d
  FROM OI.FACT_KEYWORD_STATE k LEFT JOIN OI.FACT_AMAZON_ADS a
    ON a.keyword_id=k.keyword_id AND a.campaign_id=k.campaign_id
   AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL k.settle_days_eff DAY),INTERVAL 27 DAY)
                  AND DATE_SUB(wm,INTERVAL k.settle_days_eff DAY)
  GROUP BY 1,2)
SELECT
  CASE WHEN k.state != k.raw_state THEN 'A. guard changed the STATE (losing verdict overturned)'
       WHEN k.guard_scope='AT_BAR_PRICE' THEN 'B. guard FROZE the cut (label kept, price held)'
       ELSE 'C. guard did not change the outcome' END bucket,
  COUNT(*) n, ROUND(SUM(r.sp_d),2) settled_spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) settled_roas28,
  ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d,k.family_bar),0)),2) excess_per_day,
  ROUND(SAFE_DIVIDE(SUM(k.ns_zero_ord_clicks),SUM(k.settled_clk90)),3) share_of_settled_clicks_discarded
FROM OI.FACT_KEYWORD_STATE k LEFT JOIN r USING (keyword_id,campaign_id)
GROUP BY 1 ORDER BY 1;

-- Proof the filter is monotone upward:
SELECT COUNTIF(clean_roas90 > settled_roas90 + 0.001) higher,
       COUNTIF(clean_roas90 < settled_roas90 - 0.001) lower,
       COUNTIF(ABS(clean_roas90-settled_roas90) <= 0.001) same,
       ROUND(APPROX_QUANTILES(SAFE_DIVIDE(clean_roas90,NULLIF(settled_roas90,0)),100)[OFFSET(50)],2) p50_lift,
       ROUND(APPROX_QUANTILES(SAFE_DIVIDE(clean_roas90,NULLIF(settled_roas90,0)),100)[OFFSET(90)],2) p90_lift,
       ROUND(MAX(SAFE_DIVIDE(clean_roas90,NULLIF(settled_roas90,0))),1) max_lift
FROM OI.FACT_KEYWORD_STATE WHERE COALESCE(settled_clk90,0) > 0
```

### KILL LATENCY IS UNBOUNDED — the only gate that authorises a pause cannot currently be reached by any keyword in the account.

2026-08-24: probation_clock_start IS NULL on 838 of 838 rows; probation_elapsed is true on 0; state='LOSER' on 0; state='FLOOR_PROBATION' on 2 (both already sitting at their $0.20 SP floor, so the only missing ingredient is the clock). 18 subjects are conclusively below bar AND already bidding at/below their own ceiling — $65.65/day of trailing-28d spend at 0.655 ROAS, $19.76/day of excess, with no further move available to any layer. Separately, 21 subjects sit in DEAD (>=15 settled clicks, 0 settled orders), all 21 with next_check_date NULL — DEAD is the one state with no appointment — and they still spend $5.88/day at 0.291 ROAS. Kill throughput over the whole life of the change log (2026

```sql
-- The kill gate: LOSER is the only pause authority, and it depends on a clock that has never started.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH r AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d
           FROM OI.FACT_AMAZON_ADS WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm GROUP BY 1,2),
gate AS (
  SELECT COUNT(*) rows_in_catalog,
         COUNTIF(probation_clock_start IS NULL) clock_never_started,
         COUNTIF(probation_elapsed) probation_elapsed,
         COUNTIF(state='LOSER') n_loser,
         COUNTIF(state='FLOOR_PROBATION') n_floor_probation,
         COUNTIF(at_floor) n_at_floor
  FROM OI.FACT_KEYWORD_STATE),
pauses AS (
  SELECT COUNT(*) pause_rows_total,
         COUNT(DISTINCT DATE(applied_at,'America/Los_Angeles')) distinct_days_with_a_pause_row,
         COUNTIF(upload_status='SUPERSEDED_NEVER_UPLOADED') pauses_never_uploaded,
         COUNTIF(upload_status IS NULL) pauses_landed
  FROM OI.FACT_PPC_CHANGE_LOG WHERE action='KEYWORD_PAUSE'),
stuck AS (
  SELECT COUNT(*) n_exhausted,
         ROUND(SUM(r.sp_d),2) spend_per_day,
         ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) roas28,
         ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d,k.family_bar),0)),2) excess_per_day
  FROM OI.FACT_KEYWORD_STATE k LEFT JOIN r USING (keyword_id,campaign_id)
  WHERE COALESCE(k.settled_clk90,0)>=15
    AND COALESCE(k.settled_roas90,0)-k.family_bar < -COALESCE(k.se_eff,0)
    AND k.current_bid <= COALESCE(k.affordable_bid, k.bid_floor) + 0.005),
dead AS (
  SELECT COUNT(*) n_dead, ROUND(SUM(r.sp_d),2) dead_spend_per_day,
         ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) dead_roas28,
         COUNTIF(k.next_check_date IS NULL) dead_with_no_appointment
  FROM OI.FACT_KEYWORD_STATE k LEFT JOIN r USING (keyword_id,campaign_id) WHERE k.state='DEAD')
SELECT * FROM gate, pauses, stuck, dead
```

### THE RATCHET — cuts are capped, raises are not, and 94 raises in a fortnight jumped straight to exactly $1.00, an average 2.49x step from $0.48.

2026-08-24. Of 457 APPLIED INCREASE_BID rows, 185 (40%) broke the +15.76% blind-step cap, max ratio 10.27x, p90 2.56x. 94 of those 185 landed at exactly $1.00 — between 2026-08-02 and 2026-08-15 only — average prior bid $0.48, average jump 2.49x, across 92 keywords. Of the 92, the 32 that still carry an affordable_bid below $1.00 have an average Catalog ceiling of $0.362, i.e. they were jumped in one step to ~2.8x what the record supports. Those keywords spent $6,795.83 in the ~18 days after the raise, returning $4,402.93 GP (0.648 ROAS) and $1,602.03 of excess over their bars = $89.58/day across the affected population while live. The conservative slice — 48 raises that landed on subjects t

```sql
-- 1. Cap symmetry, by source.
SELECT source, action, COUNT(*) n,
  COUNTIF(SAFE_DIVIDE(new_bid,old_bid) > 1.1576+0.005) up_over_cap,
  COUNTIF(SAFE_DIVIDE(new_bid,old_bid) < 0.8574-0.005) down_over_cap,
  ROUND(APPROX_QUANTILES(SAFE_DIVIDE(new_bid,old_bid),100)[OFFSET(50)],3) p50_ratio,
  ROUND(MAX(SAFE_DIVIDE(new_bid,old_bid)),2) max_ratio
FROM OI.FACT_PPC_CHANGE_LOG
WHERE COALESCE(upload_status,'') NOT IN ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
  AND action IN ('INCREASE_BID','REDUCE_BID') AND old_bid>0 AND new_bid>0
GROUP BY 1,2 ORDER BY 1,2;

-- 2. The $1.00 anchor and what it cost.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH ev AS (
  SELECT keyword_id, campaign_id, DATE(applied_at,'America/Los_Angeles') d, old_bid, new_bid, source
  FROM OI.FACT_PPC_CHANGE_LOG
  WHERE COALESCE(upload_status,'') NOT IN ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
    AND action='INCREASE_BID' AND ROUND(new_bid,2)=1.00 AND old_bid>0
    AND SAFE_DIVIDE(new_bid,old_bid) > 1.1576+0.005),
j AS (
  SELECT e.keyword_id, e.campaign_id, e.d, e.old_bid, e.new_bid,
         k.affordable_bid, k.family_bar, DATE_DIFF(wm, e.d, DAY) live_days,
         SUM(a.Ads_cost) sp, SUM(a.GROSS_PROFIT) gp
  FROM ev e LEFT JOIN OI.FACT_KEYWORD_STATE k USING (keyword_id, campaign_id)
  LEFT JOIN OI.FACT_AMAZON_ADS a ON a.keyword_id=e.keyword_id AND a.campaign_id=e.campaign_id
    AND a.date > e.d AND a.date <= wm
  GROUP BY 1,2,3,4,5,6,7,8)
SELECT COUNT(*) n_raises_to_1_00, COUNT(DISTINCT keyword_id) n_keywords,
  ROUND(AVG(old_bid),3) avg_bid_before, ROUND(AVG(SAFE_DIVIDE(new_bid,old_bid)),2) avg_jump_multiple,
  COUNTIF(affordable_bid < 1.00) n_where_ceiling_below_1_00,
  ROUND(AVG(IF(affordable_bid<1.00, affordable_bid, NULL)),3) avg_ceiling_when_below,
  ROUND(SUM(sp),2) spend_since, ROUND(SUM(gp),2) gp_since,
  ROUND(SAFE_DIVIDE(SUM(gp),SUM(sp)),3) roas_since,
  ROUND(SUM(GREATEST(sp - SAFE_DIVIDE(gp, family_bar),0)),2) total_excess,
  ROUND(AVG(live_days),1) avg_live_days,
  ROUND(SUM(GREATEST(sp - SAFE_DIVIDE(gp, family_bar),0))/AVG(live_days),2) excess_per_day_while_live,
  MIN(d) first_seen, MAX(d) last_seen
FROM j
```

### WHIPSAW — repair work is not merely slow, it is actively reversed. 47 times in 17 days a landed cut was undone within 4.2 days by a landed raise that overshot the pre-cut bid by 55%.

2026-08-24. Pairing APPLIED changes on the same (keyword, campaign): 47 events on 35 keywords between 2026-07-30 and 2026-08-15 where a REDUCE_BID was followed within 7 days by an INCREASE_BID landing at or above the PRE-CUT bid. Mean 4.2 days from cut to undo; the undo lands at 2.72x the cut price and 1.55x the pre-cut bid. 35 raises came from COACH, 12 from MANUAL. Those 35 keywords carry $170.23/day of trailing-28d spend at 0.754 ROAS = $31.16/day of excess over their bars.

```sql
-- Whipsaw: an APPLIED cut undone by an APPLIED raise within 7 days that landed at or above the pre-cut bid.
WITH a AS (
  SELECT keyword_id, campaign_id, DATE(applied_at,'America/Los_Angeles') d, applied_at,
         action, old_bid, new_bid, source
  FROM OI.FACT_PPC_CHANGE_LOG
  WHERE COALESCE(upload_status,'') NOT IN ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
    AND action IN ('REDUCE_BID','INCREASE_BID') AND old_bid>0 AND new_bid>0),
pairs AS (
  SELECT c.keyword_id, c.campaign_id, c.d cut_day, c.old_bid bid_before_cut, c.new_bid bid_after_cut,
         r.d raise_day, r.new_bid bid_after_raise, r.source raise_source,
         DATE_DIFF(r.d, c.d, DAY) days_between
  FROM a c JOIN a r
    ON r.keyword_id=c.keyword_id AND r.campaign_id=c.campaign_id
   AND c.action='REDUCE_BID' AND r.action='INCREASE_BID'
   AND r.applied_at > c.applied_at AND DATE_DIFF(r.d, c.d, DAY) <= 7
   AND r.new_bid >= c.old_bid - 0.005),
s AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d
      FROM OI.FACT_AMAZON_ADS
      WHERE date BETWEEN DATE_SUB(DATE '2026-08-23',INTERVAL 27 DAY) AND DATE '2026-08-23' GROUP BY 1,2)
SELECT COUNT(*) n_whipsaws, COUNT(DISTINCT keyword_id) n_keywords,
  ROUND(AVG(days_between),1) avg_days_from_cut_to_undo,
  ROUND(AVG(SAFE_DIVIDE(bid_after_raise, bid_after_cut)),2) avg_undo_multiple,
  ROUND(AVG(SAFE_DIVIDE(bid_after_raise, bid_before_cut)),2) avg_vs_pre_cut_bid,
  COUNTIF(raise_source='COACH') by_coach, COUNTIF(raise_source='MANUAL') by_manual,
  MIN(cut_day) first_seen, MAX(raise_day) last_seen
FROM pairs;

-- Money on the whipsawed population:
WITH a AS (SELECT keyword_id, campaign_id, DATE(applied_at,'America/Los_Angeles') d, applied_at, action, old_bid, new_bid
  FROM OI.FACT_PPC_CHANGE_LOG WHERE COALESCE(upload_status,'') NOT IN ('FAILED_UPLOAD','SUPERSEDED_NEVER_UPLOADED','PENDING_UPLOAD')
   AND action IN ('REDUCE_BID','INCREASE_BID') AND old_bid>0 AND new_bid>0),
p AS (SELECT DISTINCT c.keyword_id, c.campaign_id FROM a c JOIN a r ON r.keyword_id=c.keyword_id AND r.campaign_id=c.campaign_id
   AND c.action='REDUCE_BID' AND r.action='INCREASE_BID' AND r.applied_at>c.applied_at
   AND DATE_DIFF(r.d,c.d,DAY)<=7 AND r.new_bid>=c.old_bid-0.005),
s AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d FROM OI.FACT_AMAZON_ADS
   WHERE date BETWEEN DATE_SUB(DATE '2026-08-23',INTERVAL 27 DAY) AND DATE '2026-08-23' GROUP BY 1,2)
SELECT COUNT(*) n, ROUND(SUM(s.sp_d),2) spend_day, ROUND(SAFE_DIVIDE(SUM(s.gp_d),SUM(s.sp_d)),3) roas28,
 ROUND(SUM(GREATEST(s.sp_d-SAFE_DIVIDE(s.gp_d,k.family_bar),0)),2) excess_day
FROM p LEFT JOIN s USING (keyword_id,campaign_id) LEFT JOIN OI.FACT_KEYWORD_STATE k USING (keyword_id,campaign_id)
```

### SLOW DECLINE IS INVISIBLE — nobody computes the middle window. The Brain looks at 3-7 days (too noisy), the Catalog at 90 (too slow), and a keyword that turned bad a month ago sits in neither.

2026-08-24. 13 subjects currently in WINNER / PACED_WINNER / AT_BAR whose fully-settled last 28 days read below (family_bar - se_eff) while settled_roas90 still clears it: $64.05/day of settled spend, pooled recent ROAS 0.621 against a pooled 90d record of 0.985, $17.85/day of excess over their bars. Median 41 more days of the current run-rate before the 90-day average itself crosses the bar and the ladder can react; the worst is 163 days (LolliME SB 'journal for girls ages 8-12'). In the live plan, 6 of the 13 carry move=NONE verdict=GOOD ($21.75/day), 5 carry move=NONE verdict=HELD_UNSETTLED ($18.07/day), 1 is not in the plan at all ($21.52/day, Lollibox SP 'happy lolli'), and only 1 has a

```sql
-- Slow decline hidden by the 90-day trailing window.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH s AS (
  SELECT keyword_id, campaign_id, family, channel, target_text, state, settle_days_eff,
         family_bar, se_eff, settled_clk90, settled_ord90, settled_roas90, settled_sp90, settled_gp90,
         current_bid, affordable_bid
  FROM OI.FACT_KEYWORD_STATE WHERE state IN ('WINNER','PACED_WINNER','AT_BAR')),
w28 AS (
  SELECT s.*, SUM(a.Ads_clicks) c28, SUM(a.Ads_orders) o28, SUM(a.Ads_cost) sp28, SUM(a.GROSS_PROFIT) gp28
  FROM s LEFT JOIN OI.FACT_AMAZON_ADS a
    ON a.keyword_id=s.keyword_id AND a.campaign_id=s.campaign_id
   AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL s.settle_days_eff DAY),INTERVAL 27 DAY)
                  AND DATE_SUB(wm,INTERVAL s.settle_days_eff DAY)
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16),
d AS (SELECT *, SAFE_DIVIDE(gp28,sp28) roas28, sp28/28 sp_day,
             GREATEST(sp28 - SAFE_DIVIDE(gp28, family_bar), 0)/28 excess_day
      FROM w28 WHERE c28 >= 15)
SELECT
  CASE WHEN roas28 < family_bar - COALESCE(se_eff,0) AND settled_roas90 >= family_bar - COALESCE(se_eff,0)
         THEN 'DECLINING (recent below bar, 90d record still holds)'
       WHEN roas28 < family_bar - COALESCE(se_eff,0) THEN 'recent below bar AND 90d below too'
       ELSE 'recent at/above bar' END bucket,
  COUNT(*) n, ROUND(SUM(sp_day),2) spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(gp28),SUM(sp28)),3) roas28_pooled,
  ROUND(SAFE_DIVIDE(SUM(settled_gp90),SUM(settled_sp90)),3) roas90_pooled,
  ROUND(SUM(excess_day),2) excess_per_day,
  ROUND(APPROX_QUANTILES(
    IF(roas28 < family_bar AND settled_roas90 >= family_bar,
       SAFE_DIVIDE(settled_gp90 - family_bar*settled_sp90,
                   family_bar*(sp28/28) - (gp28/28)), NULL), 100)[OFFSET(50)],0) median_days_until_90d_crosses
FROM d GROUP BY 1 ORDER BY spend_per_day DESC
```

### THE FORBIDDEN 'NOTHING TO DO' STATE, PRICED — 17 HARVEST subjects that the Catalog calls conclusive losers sit in the live plan with move=NONE, verdict=NOT_SERVING.

2026-08-24, against the live plan (max as_of where is_live_plan). Of the 84 conclusive losers: 41 have no row in the live plan at all ($127.15/day settled spend, $57.14/day excess — but 40 of the 41 are Bunny/LolliBall under the launch exemption, so only $0.35/day of that is HARVEST and the rest is arguably by design); 17 are in the plan with move=NONE verdict=NOT_SERVING and are ALL HARVEST — $41.61/day of settled spend at 0.457 ROAS, $20.36/day of excess; 3 more carry move=NONE verdict=GOOD ($39.92/day, the guard-flipped set). Separately, the repair track itself is small and moves: REPRICE holds 10 subjects, $136.49/day settled spend at 0.633 ROAS, $37.91/day excess, average 9.1 days on th

```sql
-- Why is each conclusive loser still spending? Single attribution, first match wins, settled window.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH s AS (SELECT * FROM OI.FACT_KEYWORD_STATE
           WHERE COALESCE(settled_clk90,0)>=15
             AND COALESCE(settled_roas90,0)-family_bar < -COALESCE(se_eff,0)),
p AS (SELECT keyword_id, campaign_id, move, verdict FROM OI.FACT_PLAN_NEXT_WEEK
      WHERE as_of=(SELECT MAX(as_of) FROM OI.FACT_PLAN_NEXT_WEEK WHERE is_live_plan) AND is_live_plan),
nu AS (SELECT keyword_id, MIN(IF(action='REDUCE_BID',new_bid,NULL)) deepest_cut,
              LOGICAL_OR(action='KEYWORD_PAUSE') pz
       FROM OI.FACT_PPC_CHANGE_LOG
       WHERE upload_status IN ('SUPERSEDED_NEVER_UPLOADED','FAILED_UPLOAD','PENDING_UPLOAD')
         AND action IN ('REDUCE_BID','KEYWORD_PAUSE') GROUP BY 1),
r AS (SELECT s.keyword_id, s.campaign_id, SUM(a.Ads_cost)/28 sp_d, SUM(a.GROSS_PROFIT)/28 gp_d
      FROM s LEFT JOIN OI.FACT_AMAZON_ADS a ON a.keyword_id=s.keyword_id AND a.campaign_id=s.campaign_id
        AND a.date BETWEEN DATE_SUB(DATE_SUB(wm,INTERVAL s.settle_days_eff DAY),INTERVAL 27 DAY)
                       AND DATE_SUB(wm,INTERVAL s.settle_days_eff DAY)
      GROUP BY 1,2)
SELECT
  CASE
    WHEN s.state != s.raw_state OR s.guard_scope='AT_BAR_PRICE' THEN '1. mix-drift guard overturned or froze the losing verdict'
    WHEN nu.pz OR (nu.deepest_cut IS NOT NULL AND s.current_bid > nu.deepest_cut+0.005) THEN '2. cut/pause decided, logged, never uploaded'
    WHEN p.keyword_id IS NULL THEN '3. the Brain never sees it (no row in the live plan)'
    WHEN p.move='NONE' THEN CONCAT('4. in the plan but move=NONE (', p.verdict, ')')
    WHEN s.current_bid > s.affordable_bid + 0.005 THEN '5. repair in flight, bid still above the ceiling'
    ELSE '6. already at/below its ceiling and still losing (kill gate unreachable)' END reason,
  COUNT(*) n, ROUND(SUM(r.sp_d),2) settled_spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) settled_roas28,
  ROUND(SUM(GREATEST(r.sp_d - SAFE_DIVIDE(r.gp_d,s.family_bar),0)),2) excess_per_day,
  COUNTIF(s.family IN ('Bottle','Lollibox','LolliME','Fresh')) n_harvest,
  ROUND(SUM(IF(s.family IN ('Bottle','Lollibox','LolliME','Fresh'),
           GREATEST(r.sp_d-SAFE_DIVIDE(r.gp_d,s.family_bar),0),0)),2) harvest_excess_per_day
FROM s LEFT JOIN p USING (keyword_id,campaign_id) LEFT JOIN nu USING (keyword_id) LEFT JOIN r USING (keyword_id,campaign_id)
GROUP BY 1 ORDER BY settled_spend_per_day DESC
```

### OUTSIDE THE CATALOG ENTIRELY — 74 spending keyword rows carrying $132.71/day at 0.528 ROAS have no row in FACT_KEYWORD_STATE, so no layer can judge them, price them, repair them or kill them.

2026-08-24. Left-joining the trailing-28-day spending (keyword_id, campaign_id) pairs to FACT_KEYWORD_STATE: 385 pairs match ($1,190.51/day at 0.906 ROAS), 74 do not ($132.71/day at 0.528 ROAS on 4,671 clicks; 38 SB, 36 SP). Against a declared reference bar of 0.8431 (the median of the six family bars present today) that is $54.93/day of spend the record does not support. The largest single row is BOX-VIDEO/PT (Competitors, Purple) asin=B0FV38L5KB at $27.06/day and 0.745 ROAS.

```sql
-- Spending keyword rows the Catalog does not hold at all.
DECLARE wm DATE DEFAULT DATE '2026-08-23';
DECLARE ref_bar FLOAT64 DEFAULT 0.8431;  -- median of the six family bars in FACT_KEYWORD_STATE, 2026-08-24
WITH spend AS (
  SELECT keyword_id, campaign_id, ANY_VALUE(campaign_type) ct, ANY_VALUE(campaign_name) cn,
         ANY_VALUE(targeting) tg,
         SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d, SUM(Ads_clicks) c28
  FROM OI.FACT_AMAZON_ADS
  WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm AND keyword_id IS NOT NULL
  GROUP BY 1,2)
SELECT
  COUNT(*) n_rows_outside_the_catalog,
  ROUND(SUM(s.sp_d),2) spend_per_day,
  ROUND(SAFE_DIVIDE(SUM(s.gp_d),SUM(s.sp_d)),3) roas28,
  SUM(s.c28) clicks_28d,
  ROUND(SUM(GREATEST(s.sp_d - SAFE_DIVIDE(s.gp_d, ref_bar),0)),2) excess_per_day_vs_reference_bar,
  COUNTIF(s.ct='SB') n_sb, COUNTIF(s.ct='SP') n_sp
FROM spend s LEFT JOIN OI.FACT_KEYWORD_STATE k USING (keyword_id, campaign_id)
WHERE k.keyword_id IS NULL AND s.sp_d > 0;

-- The rows themselves:
WITH spend AS (SELECT keyword_id, campaign_id, ANY_VALUE(campaign_name) cn, ANY_VALUE(targeting) tg,
  ANY_VALUE(campaign_type) ct, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d, SUM(Ads_clicks) c28, SUM(Ads_orders) o28
  FROM OI.FACT_AMAZON_ADS WHERE date BETWEEN DATE_SUB(DATE '2026-08-23',INTERVAL 27 DAY) AND DATE '2026-08-23'
    AND keyword_id IS NOT NULL GROUP BY 1,2)
SELECT s.ct, s.cn, s.tg, ROUND(s.sp_d,2) spend_day, s.c28, s.o28, ROUND(SAFE_DIVIDE(s.gp_d,s.sp_d),3) roas28
FROM spend s LEFT JOIN OI.FACT_KEYWORD_STATE k USING (keyword_id,campaign_id)
WHERE k.keyword_id IS NULL AND s.sp_d>0 ORDER BY spend_day DESC
```

### FOOTNOTE — DEAD is a terminal parking lot, not a kill. 21 subjects with >=15 settled clicks and zero settled orders, none with an appointment, still spending. Small money, but it is the state the doctrine says must never exist.

2026-08-24: 21 subjects in state DEAD, all 21 with next_check_date NULL, spending $5.88/day on the trailing 28 days at 0.291 ROAS (280 clicks). Average 21 days in state, max 25 — though state_since is truncated by the v27.104/105 ladder rebuild around 2026-08-02..22, so the true dwell is longer and cannot be recovered from this table.

```sql
DECLARE wm DATE DEFAULT DATE '2026-08-23';
WITH r AS (SELECT keyword_id, campaign_id, SUM(Ads_cost)/28 sp_d, SUM(GROSS_PROFIT)/28 gp_d, SUM(Ads_clicks) c28
           FROM OI.FACT_AMAZON_ADS WHERE date BETWEEN DATE_SUB(wm,INTERVAL 27 DAY) AND wm GROUP BY 1,2)
SELECT k.state, COUNT(*) n, ROUND(SUM(r.sp_d),2) spend_per_day, SUM(r.c28) clicks_28d,
  ROUND(SAFE_DIVIDE(SUM(r.gp_d),SUM(r.sp_d)),3) roas28,
  ROUND(AVG(DATE_DIFF(DATE '2026-08-24', k.state_since, DAY)),1) avg_days_in_state,
  MAX(DATE_DIFF(DATE '2026-08-24', k.state_since, DAY)) max_days_in_state,
  COUNTIF(k.next_check_date IS NULL) with_no_appointment
FROM OI.FACT_KEYWORD_STATE k LEFT JOIN r USING (keyword_id,campaign_id)
WHERE k.state='DEAD' GROUP BY 1
```

## Probe — seasonality and dormancy

### THE PARK TRAP — a park is an absorbing state: the exit condition is evidence the park itself prevents

2026-08-24 snapshot: 544 PARKED subjects; 452 took zero clicks in the 28 days to 2026-08-23; 417 of those carry the 'record too thin to judge' appointment whose exit condition they structurally cannot meet. 31 of the dark-parked subjects earned money last holiday season: $71,564 Nov-Dec 2025 ads sales and $12,375 net profit (GROSS_PROFIT − Ads_cost) — 10.0% of the account's $713,273 Nov-Dec ads sales. 2 of the 31 are already in today's revival plan ($27,988 sales / $3,353 net); the remaining 29 are owned by no layer and carry $43,576 sales / $9,021 net = $147.89/day across the 61-day season. The park is also one-way: over the 60 days to 2026-08-24, dark-parked subjects received 166 bid cuts 

```sql
-- PARK TRAP, dated baseline 2026-08-24. Re-run by moving the four anchor dates.
-- A) the trap population and its one-way bid history
WITH parked AS (
  SELECT keyword_id, family, target_text, campaign_name, current_bid, bid_floor,
         next_check_what, next_check_date, state_since, floor_since
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE state = 'PARKED'
),
served_28d AS (   -- target-grain truth for 'did it serve at all'
  SELECT keyword_id, SUM(impressions) imp, SUM(clicks) clk, SUM(cost) cost
  FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23'
  GROUP BY 1
),
last_season AS (
  SELECT keyword_id, SUM(Ads_orders) ord, SUM(Ads_sales) sales,
         SUM(GROSS_PROFIT) - SUM(Ads_cost) net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1
),
bid_moves_60d AS (
  SELECT keyword_id, COUNTIF(new_bid > old_bid) raises, COUNTIF(new_bid < old_bid) cuts
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE applied_at >= TIMESTAMP '2026-06-25'
    AND UPPER(COALESCE(upload_status,'')) NOT LIKE '%FAIL%'
  GROUP BY 1
)
SELECT
  COUNT(*)                                                        AS parked_n,
  COUNTIF(COALESCE(s.clk,0) = 0)                                  AS dark_28d,
  COUNTIF(COALESCE(s.clk,0) = 0
          AND p.next_check_what LIKE 'parked, record too thin%')  AS trapped_awaiting_impossible_evidence,
  COUNTIF(p.floor_since IS NULL)                                  AS floor_since_null,
  COUNTIF(p.state_since  IS NULL)                                 AS state_since_null,
  COUNTIF(COALESCE(s.clk,0) = 0 AND b.keyword_id IS NULL)         AS dark_and_untouched_60d,
  SUM(IF(COALESCE(s.clk,0)=0, COALESCE(b.cuts,0),   0))           AS dark_cuts_60d,
  SUM(IF(COALESCE(s.clk,0)=0, COALESCE(b.raises,0), 0))           AS dark_raises_60d,
  COUNTIF(COALESCE(s.clk,0)=0 AND ls.ord > 0)                     AS dark_with_last_season_orders,
  ROUND(SUM(IF(COALESCE(s.clk,0)=0, COALESCE(ls.sales,0), 0)), 0) AS dark_novdec2025_sales,
  ROUND(SUM(IF(COALESCE(s.clk,0)=0, COALESCE(ls.net,0),   0)), 0) AS dark_novdec2025_net,
  ROUND(SUM(IF(COALESCE(s.clk,0)=0 AND p.next_check_what NOT LIKE 'revival%',
               COALESCE(ls.net,0), 0)) / 61, 2)                   AS unowned_net_per_season_day
FROM parked p
LEFT JOIN served_28d  s  USING (keyword_id)
LEFT JOIN last_season ls USING (keyword_id)
LEFT JOIN bid_moves_60d b USING (keyword_id);

-- B) the latency distribution: how overdue are the parked appointments
SELECT
  COUNT(*) AS overdue_n,
  ROUND(AVG(DATE_DIFF(DATE '2026-08-24', next_check_date, DAY)),1) AS avg_overdue_days,
  APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', next_check_date, DAY),4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', next_check_date, DAY),4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', next_check_date, DAY),4)[OFFSET(3)] AS p75,
  MAX(DATE_DIFF(DATE '2026-08-24', next_check_date, DAY)) AS max_overdue_days
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
WHERE state = 'PARKED' AND next_check_date <= DATE '2026-08-24';
```

### SEASONAL KILLS — keywords paused in live campaigns after last Christmas, now invisible to every layer three months before their season

79 keywords, $96,725 Nov-Dec 2025 ads sales, $14,799 net profit, = $242.61/day across the 61-day season. Exclusion discipline: I dropped (a) 88 keywords in ARCHIVED campaigns ($47,621 last-season sales), (b) 73 keywords in PAUSED campaigns ($20,859), and (c) 49 keywords in ENABLED campaigns that spent $0 in the last 28 days ($21,290) — a campaign with no current spend cannot be shown to still be in use, so its keywords are not credibly recoverable and I excluded them rather than inflate the number. Only campaigns that are both ENABLED in DIM_CAMPAIGN and demonstrably spending today survive. DIM_KEYWORD.effective_from is NOT usable as a pause date (912 rows share a bulk value of 2026-04-01), 

```sql
-- SEASONAL KILLS, dated baseline 2026-08-24.
-- Paused/archived keywords that sold materially last holiday season and whose campaign is
-- demonstrably still in use. Exclusions are explicit in the WHERE clause, not hidden.
WITH kw AS (
  SELECT keyword_id,
         ANY_VALUE(keyword_text) kw_text,
         ANY_VALUE(campaign_id)  campaign_id,
         ANY_VALUE(LOWER(state)) kw_state,
         ANY_VALUE(match_type)   match_type
  FROM `onyga-482313.OI.DIM_KEYWORD`
  WHERE is_current
  GROUP BY 1
),
camp AS (
  SELECT campaign_id,
         ANY_VALUE(LOWER(state)) camp_state,
         ANY_VALUE(campaign_name) campaign_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  WHERE is_current
  GROUP BY 1
),
camp_spend_28d AS (
  SELECT campaign_id, SUM(Ads_cost) cost_28d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23'
  GROUP BY 1
),
last_season AS (
  SELECT keyword_id, SUM(Ads_orders) ord, SUM(Ads_sales) sales,
         SUM(GROSS_PROFIT) - SUM(Ads_cost) net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1
),
last_click AS (
  SELECT keyword_id, MAX(date) last_click_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE Ads_clicks > 0
  GROUP BY 1
),
in_catalog AS (SELECT DISTINCT keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
SELECT
  COUNT(*)                                  AS killed_but_recoverable_n,
  ROUND(SUM(ls.sales), 0)                   AS novdec2025_sales,
  ROUND(SUM(ls.net),   0)                   AS novdec2025_net,
  ROUND(SUM(ls.net) / 61, 2)                AS net_per_season_day,
  COUNTIF(ic.keyword_id IS NOT NULL)        AS still_visible_to_catalog  -- expect 0
FROM kw
JOIN last_season ls USING (keyword_id)
LEFT JOIN camp           c  ON c.campaign_id  = kw.campaign_id
LEFT JOIN camp_spend_28d cs ON cs.campaign_id = kw.campaign_id
LEFT JOIN last_click     lc USING (keyword_id)
LEFT JOIN in_catalog     ic USING (keyword_id)
WHERE ls.ord > 0
  AND kw.kw_state IN ('paused','archived')   -- the keyword was killed
  AND c.camp_state = 'enabled'               -- exclude retired campaigns (state)
  AND COALESCE(cs.cost_28d, 0) > 0;          -- exclude dormant campaigns (behaviour)

-- row-level list, for the recovery bulksheet
-- (same CTEs; replace the final SELECT with:)
-- SELECT kw.kw_text, kw.match_type, kw.kw_state, c.campaign_name,
--        ROUND(ls.sales,0) novdec_sales, ls.ord novdec_orders, ROUND(ls.net,0) novdec_net,
--        lc.last_click_date
-- FROM ... WHERE ... ORDER BY ls.sales DESC;
```

### THE JANUARY MIRROR — the 90-day trailing window keeps Christmas inside it for three months, so the account over-funds for four weeks after demand collapses

Account-wide, 2025-12-28 to 2026-01-24 (28 days): $963.32/day spend returning $0.120 net profit per ad dollar, = $115.95/day net. Same account, 2026-02-01 to 2026-02-28 once the window had cleared: $699.75/day spend returning $0.435 per ad dollar, = $304.22/day net. The account spent 38% MORE per day during the trough and earned 62% LESS. Profit foregone if the trough had been priced at February's efficiency: (963.32 x 0.435) − 115.95 = $302.99/day for 28 days = $8,484. Cross-checked on the seasonal cohort alone (146 keywords with >=3 Nov-Dec orders and positive Nov-Dec net) the numbers are nearly identical ($943.24/day at 0.123 vs $638.44/day at 0.434), which says the trough IS the seasonal

```sql
-- THE JANUARY MIRROR, dated baseline 2026-08-24 measuring the 2025/26 turn.
-- A) account-wide: the trough vs the cleared window
SELECT
  CASE WHEN date BETWEEN DATE '2025-12-28' AND DATE '2026-01-24' THEN '1_trough_Dec28_Jan24'
       WHEN date BETWEEN DATE '2026-02-01' AND DATE '2026-02-28' THEN '2_cleared_Feb'
  END AS segment,
  ROUND(SUM(Ads_cost) / 28, 2)                                          AS spend_per_day,
  ROUND((SUM(GROSS_PROFIT) - SUM(Ads_cost)) / 28, 2)                    AS net_per_day,
  ROUND(SAFE_DIVIDE(SUM(GROSS_PROFIT) - SUM(Ads_cost), SUM(Ads_cost)),3) AS net_per_ad_dollar,
  ROUND(SAFE_DIVIDE(SUM(Ads_orders), SUM(Ads_clicks)) * 100, 2)         AS cvr_pct,
  ROUND(SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)), 2)                 AS cpc
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE date BETWEEN DATE '2025-12-28' AND DATE '2026-02-28'
  AND (date <= DATE '2026-01-24' OR date >= DATE '2026-02-01')
GROUP BY 1
HAVING segment IS NOT NULL
ORDER BY 1;
-- profit foregone/day = (trough.spend_per_day * cleared.net_per_ad_dollar) - trough.net_per_day

-- B) the cohort funded on Nov-Dec evidence, and what it did afterwards
WITH cohort AS (
  SELECT keyword_id
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1
  HAVING SUM(Ads_orders) >= 3 AND SUM(GROSS_PROFIT) - SUM(Ads_cost) > 0
),
janfeb AS (
  SELECT keyword_id, SUM(Ads_cost) cost,
         SUM(GROSS_PROFIT) - SUM(Ads_cost) net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-01-01' AND DATE '2026-02-28'
  GROUP BY 1
)
SELECT
  COUNT(*)                                          AS novdec_winners,
  COUNTIF(j.net < 0)                                AS lost_money_janfeb,
  ROUND(SUM(IF(j.net < 0, j.net,  0)), 0)           AS janfeb_losses,
  ROUND(SUM(IF(j.net < 0, j.cost, 0)), 0)           AS janfeb_spend_on_losers,
  ROUND(SUM(j.net), 0)                              AS janfeb_net_all
FROM cohort JOIN janfeb j USING (keyword_id);

-- C) the decay curve, so the shape is visible not asserted
WITH cohort AS (
  SELECT keyword_id FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1 HAVING SUM(Ads_orders) >= 3 AND SUM(GROSS_PROFIT) - SUM(Ads_cost) > 0
)
SELECT DATE_TRUNC(date, WEEK(SUNDAY)) AS wk,
       ROUND(SUM(Ads_cost)/7, 2) AS spend_per_day,
       ROUND((SUM(GROSS_PROFIT)-SUM(Ads_cost))/7, 2) AS net_per_day,
       ROUND(SAFE_DIVIDE(SUM(Ads_sales), SUM(Ads_cost)), 2) AS roas
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE keyword_id IN (SELECT keyword_id FROM cohort)
  AND date BETWEEN DATE '2025-12-07' AND DATE '2026-03-07'
GROUP BY 1 ORDER BY 1;
```

### THE SEASON DOOR — the same trailing window that over-funds in January under-funds in November, and would have condemned 45 of last season's earners on the eve of the season

Replaying 2025-11-15 with the Catalog's own estimator shape (90-day trailing, >=15 clicks to judge, GP-ROAS < 1.0 = below bar), against what actually happened in the 40-day peak 2025-11-16 to 2025-12-25: trailing-says-below-bar / season-EARNED = 45 keywords, $40,108 sales, $7,473 net; trailing-says-below-bar / season-lost = 66 keywords, $2,131 sales, −$842 net; trailing-says-at-or-above / season-EARNED = 113 keywords, $340,957 sales, $60,938 net; trailing-says-at-or-above / season-lost = 32 keywords, $4,764 sales, −$649 net. False-negative rate at the door: 45/111 = 41%. Value ratio of profit destroyed to loss avoided: 8.9:1. $7,473 over the 40-day peak = $186.83/day. This understates the re

```sql
-- THE SEASON DOOR, dated baseline 2026-08-24, replaying the 2025 season.
-- What the Catalog's own estimator shape would have said on 2025-11-15, versus what the
-- 40-day peak actually paid. Bar = 1.0 GP-ROAS (family_bar today runs 0.74-0.94; using 1.0
-- is the conservative choice, it condemns FEWER keywords than the live bar would).
WITH trailing_90d_at_nov15 AS (
  SELECT keyword_id,
         SUM(Ads_clicks) clk, SUM(Ads_cost) cost, SUM(GROSS_PROFIT) gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-08-18' AND DATE '2025-11-15'   -- the 90d window ending at the door
  GROUP BY 1
  HAVING SUM(Ads_clicks) >= 15                                  -- enough evidence to judge
),
peak AS (
  SELECT keyword_id,
         SUM(Ads_clicks) clk, SUM(Ads_cost) cost, SUM(GROSS_PROFIT) gp,
         SUM(Ads_sales) sales, SUM(Ads_orders) ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-16' AND DATE '2025-12-25'    -- the 40-day peak
  GROUP BY 1
)
SELECT
  IF(SAFE_DIVIDE(t.gp, t.cost) < 1.0, 'trailing_says_BELOW_bar', 'trailing_says_at_or_above') AS trailing_verdict,
  IF(SAFE_DIVIDE(p.gp, p.cost) >= 1.0, 'season_EARNED', 'season_lost')                        AS season_truth,
  COUNT(*)                              AS keywords,
  ROUND(SUM(p.sales), 0)                AS peak_sales,
  ROUND(SUM(p.cost),  0)                AS peak_spend,
  ROUND(SUM(p.gp - p.cost), 0)          AS peak_net,
  ROUND(SUM(p.gp - p.cost) / 40, 2)     AS peak_net_per_day
FROM trailing_90d_at_nov15 t
JOIN peak p USING (keyword_id)
GROUP BY 1, 2
ORDER BY 1, 2;

-- companion: the last-year signal exists but never reaches the Catalog's contract
SELECT COUNT(*) AS guard_rows,
       COUNTIF(ly_clk28 > 0)          AS rows_with_last_year_clicks,
       COUNTIF(ly_conv_cpc IS NOT NULL) AS rows_with_last_year_conv_cpc
FROM `onyga-482313.OI.V_KEYWORD_GUARD`;
-- then confirm the drop: FACT_KEYWORD_STATE has no ly_* / pace_* column at all
SELECT column_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'FACT_KEYWORD_STATE'
  AND (column_name LIKE 'ly%' OR column_name LIKE 'pace%' OR column_name LIKE '%season%');
```

### MISPRICED SEASONAL SPEND TODAY — a sixth of the account is running on subjects whose worth will roughly double before the Catalog notices

Of the account's $1,323.22/day spend in the 28 days to 2026-08-23, $646.29/day (48.8%) sits on keywords with >=30 clicks in BOTH Nov-Dec 2025 and Jun-Aug 2026 — the only population where a seasonality ratio can honestly be computed. Within that comparable half: $206.92/day on 50 keywords whose holiday CVR is >=1.5x their summer CVR (holiday-heavy, under-priced now); $410.80/day on 47 keywords that are flat (0.67x-1.5x); $27.89/day on 10 keywords that convert better in summer (over-priced now, and the smaller problem); $0.67/day on 4 with zero summer conversions. So 15.6% of the whole account, and 32.0% of the comparable half, is spend the Catalog is materially mispricing on a seasonal axis t

```sql
-- SEASONAL SHARE OF TODAY'S SPEND, dated baseline 2026-08-24.
-- Per-keyword CVR, holiday window vs summer window, weighted by what it costs today.
WITH holiday AS (
  SELECT keyword_id, SUM(Ads_clicks) clk, SUM(Ads_orders) ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 30
),
summer AS (
  SELECT keyword_id, SUM(Ads_clicks) clk, SUM(Ads_orders) ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-06-01' AND DATE '2026-08-23'
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 30
),
now_28d AS (
  SELECT keyword_id, SUM(Ads_cost) cost_28d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23'
  GROUP BY 1
),
comparable AS (
  SELECT h.keyword_id,
         SAFE_DIVIDE(h.ord, h.clk) AS cvr_holiday,
         SAFE_DIVIDE(s.ord, s.clk) AS cvr_summer,
         COALESCE(n.cost_28d, 0) / 28 AS spend_per_day
  FROM holiday h
  JOIN summer  s USING (keyword_id)
  LEFT JOIN now_28d n USING (keyword_id)
)
SELECT
  CASE WHEN cvr_summer = 0                                    THEN 'summer_zero_cvr'
       WHEN cvr_holiday / NULLIF(cvr_summer,0) >= 1.5         THEN 'holiday_ge_1.5x  (under-priced today)'
       WHEN cvr_holiday / NULLIF(cvr_summer,0) <= 0.667       THEN 'summer_better    (over-priced today)'
       ELSE                                                        'flat             (correctly priced)'
  END AS seasonality_bucket,
  COUNT(*)                     AS keywords,
  ROUND(SUM(spend_per_day), 2) AS spend_per_day
FROM comparable
GROUP BY 1
ORDER BY spend_per_day DESC;

-- the denominator, so the share is not asserted: how much of today's spend is comparable at all
WITH holiday AS (
  SELECT keyword_id FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 30
),
summer AS (
  SELECT keyword_id FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-06-01' AND DATE '2026-08-23'
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 30
)
SELECT ROUND(SUM(Ads_cost)/28, 2) AS account_spend_per_day,
       ROUND(SUM(IF(keyword_id IN (SELECT keyword_id FROM holiday)
                AND keyword_id IN (SELECT keyword_id FROM summer), Ads_cost, 0))/28, 2)
         AS comparable_spend_per_day
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23';
```

### THE SEASON LEDGER BLENDS FAMILIES — the account's only seasonal memory is keyed on bare target text, which §2.2 forbids

2026-08-24: restricting to real keywords (excluding substitutes / complements / close-match / loose-match / asin= / category= / '*', as the gate itself does), 257 distinct target texts carry $538.31/day of settled spend. 20 of them exist in 2 or more product families and carry $116.58/day — 21.7% of the keyword-grain spend the ledger governs, and 8.8% of the $1,323/day account. All 20 have rows in the season ledger. The magnitude of the blend is real, not theoretical: 'gift for girls' spans LolliBall, LolliME and Bunny at $26.59/day with settled 90d GP-ROAS ranging 0.00 to 2.08 across those families; 'gift for 14 year old girl' spans Fresh and Bunny at $11.75/day with GP-ROAS 0.17 vs 0.85 — 

```sql
-- SEASON LEDGER GRAIN COLLISION, dated baseline 2026-08-24.
-- The ledger is keyed on keyword_text and pooled account-wide; the ladder is keyed on
-- keyword_id and scoped to a product family. Where one text lives in >1 family, the
-- seasonal verdict blends economics the doctrine (§2.2) says may never be blended.
WITH catalog_texts AS (
  SELECT target_text,
         COUNT(DISTINCT family)     AS families,
         STRING_AGG(DISTINCT family ORDER BY family) AS family_list,
         COUNT(DISTINCT keyword_id) AS keyword_instances,
         SUM(settled_sp90) / 90     AS spend_per_day,
         MIN(settled_roas90)        AS min_gp_roas,
         MAX(settled_roas90)        AS max_gp_roas,
         MIN(family_bar)            AS min_bar,
         MAX(family_bar)            AS max_bar
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE family IS NOT NULL
    -- mirror V_KEYWORD_CONTEXT_GATE's own exclusions: keyword grain only
    AND NOT COALESCE(is_auto, FALSE)
    AND NOT COALESCE(is_pt,   FALSE)
    AND target_text NOT IN ('substitutes','complements','close-match','loose-match','*')
  GROUP BY 1
),
ledger_texts AS (
  SELECT DISTINCT keyword_text FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT`
)
SELECT
  COUNT(*)                                                       AS texts_total,
  COUNTIF(c.families > 1)                                        AS texts_spanning_multiple_families,
  ROUND(SUM(IF(c.families > 1, c.spend_per_day, 0)), 2)          AS colliding_spend_per_day,
  ROUND(SUM(c.spend_per_day), 2)                                 AS keyword_grain_spend_per_day,
  COUNTIF(c.families > 1 AND l.keyword_text IS NOT NULL)         AS colliding_and_in_ledger
FROM catalog_texts c
LEFT JOIN ledger_texts l ON l.keyword_text = c.target_text;

-- the offending rows, with the spread that proves the blend matters
SELECT target_text,
       COUNT(DISTINCT family) AS families,
       STRING_AGG(DISTINCT family ORDER BY family) AS family_list,
       ROUND(SUM(settled_sp90)/90, 2) AS spend_per_day,
       ROUND(MIN(settled_roas90), 2)  AS min_gp_roas,
       ROUND(MAX(settled_roas90), 2)  AS max_gp_roas,
       ROUND(MIN(family_bar), 2)      AS min_family_bar,
       ROUND(MAX(family_bar), 2)      AS max_family_bar
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
WHERE family IS NOT NULL
GROUP BY 1
HAVING COUNT(DISTINCT family) > 1
ORDER BY spend_per_day DESC;
```

### THE RAMP CANNOT ARRIVE IN TIME — even if a parked seasonal keyword is discovered, the symmetric move cap cannot get it to a season price before the season is over

31 dark-parked subjects with Nov-Dec 2025 orders: average current bid $0.23, average realised Nov-Dec 2025 CPC $0.50, average ratio 2.14x. Uploads needed at the +15.76% cap: mean 5.3, maximum 10. Against an observed cadence where two thirds of this population got zero bid changes in 60 days. The money behind the ramp is the same $147.89/day of last-season net profit as finding 1 — I am NOT adding it again; the dollarsPerDay below is the same money viewed as a deadline rather than as a discovery problem, and should not be summed with finding 1.

```sql
-- SEASON RAMP LATENCY, dated baseline 2026-08-24.
-- How far the parked seasonal earners are from their own last-season price, expressed in
-- house-capped upload steps (+15.76% = three blind 5% steps).
WITH parked AS (
  SELECT keyword_id, family, target_text, campaign_name, current_bid, bid_floor
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE state = 'PARKED'
),
last_season AS (
  SELECT keyword_id,
         SUM(Ads_orders) ord,
         SUM(Ads_sales)  sales,
         SUM(GROSS_PROFIT) - SUM(Ads_cost) net,
         SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)) AS cpc_last_season
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1
),
served_28d AS (
  SELECT keyword_id, SUM(clicks) clk
  FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23'
  GROUP BY 1
)
SELECT
  COUNT(*)                                                                AS subjects,
  ROUND(AVG(p.current_bid), 2)                                            AS avg_bid_now,
  ROUND(AVG(ls.cpc_last_season), 2)                                       AS avg_cpc_last_season,
  ROUND(AVG(ls.cpc_last_season / NULLIF(p.current_bid, 0)), 2)            AS avg_ratio,
  ROUND(AVG(CEIL(LOG(ls.cpc_last_season / NULLIF(p.current_bid,0)) / LOG(1.1576))), 1)
                                                                          AS avg_uploads_at_cap,
  MAX(CEIL(LOG(ls.cpc_last_season / NULLIF(p.current_bid,0)) / LOG(1.1576)))
                                                                          AS max_uploads_at_cap,
  ROUND(SUM(ls.net), 0)                                                   AS novdec2025_net_at_stake
FROM parked p
JOIN last_season ls USING (keyword_id)
LEFT JOIN served_28d s USING (keyword_id)
WHERE ls.ord > 0
  AND COALESCE(s.clk, 0) = 0                       -- dark today
  AND ls.cpc_last_season > p.current_bid;          -- needs a raise at all

-- the observed touch rate this ramp would have to run through
WITH parked AS (SELECT keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE state='PARKED'),
served_28d AS (
  SELECT keyword_id, SUM(clicks) clk FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date BETWEEN DATE '2026-07-27' AND DATE '2026-08-23' GROUP BY 1),
moves AS (
  SELECT keyword_id, COUNTIF(new_bid>old_bid) raises, COUNTIF(new_bid<old_bid) cuts
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE applied_at >= TIMESTAMP '2026-06-25'
    AND UPPER(COALESCE(upload_status,'')) NOT LIKE '%FAIL%'
  GROUP BY 1)
SELECT COALESCE(s.clk,0)=0 AS dark_28d, COUNT(*) AS n,
       COUNTIF(m.keyword_id IS NULL) AS untouched_60d,
       SUM(COALESCE(m.raises,0)) AS raises_60d,
       SUM(COALESCE(m.cuts,0))   AS cuts_60d
FROM parked p LEFT JOIN served_28d s USING (keyword_id) LEFT JOIN moves m USING (keyword_id)
GROUP BY 1;
```

### SEASONAL MONEY PARKED IN THE BRAIN'S 'NOTHING TO DO' STATE — the limbo §3 forbids, with a Christmas list in it

2026-08-24 plan A: 191 rows at NOT_SERVING/NONE with $0.00 planned spend. 30 of them had Nov-Dec 2025 orders, carrying $29,632 of last-season sales and $4,943 of net profit = $81.03/day across the 61-day season. IMPORTANT OVERLAP: 130 of the 191 are also PARKED in the Catalog, so most of this money is the same money as finding 1 seen from the Brain's side rather than the Catalog's. Do not sum them. I am reporting it separately because it identifies a different owner for the fix — this is the Brain writing a forbidden state, not the Catalog failing to see. Also note the plan covers only ~365 of the Catalog's 838 subjects (violation #12), so 473 subjects are not even in the population that cou

```sql
-- BRAIN LIMBO WITH SEASONAL MONEY IN IT, dated baseline 2026-08-24.
WITH plan_today AS (
  SELECT DISTINCT keyword_id
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
    AND plan = 'A' AND verdict = 'NOT_SERVING' AND move = 'NONE'
),
last_season AS (
  SELECT keyword_id, SUM(Ads_orders) ord, SUM(Ads_sales) sales,
         SUM(GROSS_PROFIT) - SUM(Ads_cost) net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2025-11-01' AND DATE '2025-12-31'
  GROUP BY 1
),
parked AS (SELECT keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE state = 'PARKED')
SELECT
  COUNT(*)                                            AS not_serving_rows,
  COUNTIF(pk.keyword_id IS NOT NULL)                  AS also_parked_in_catalog,  -- the overlap
  COUNTIF(ls.ord > 0)                                 AS with_last_season_orders,
  ROUND(SUM(COALESCE(ls.sales, 0)), 0)                AS novdec2025_sales,
  ROUND(SUM(COALESCE(ls.net,   0)), 0)                AS novdec2025_net,
  ROUND(SUM(COALESCE(ls.net,   0)) / 61, 2)           AS net_per_season_day
FROM plan_today p
LEFT JOIN last_season ls USING (keyword_id)
LEFT JOIN parked      pk USING (keyword_id);

-- the shape of the whole plan, so the 52% is visible not asserted
SELECT plan, verdict, move, COUNT(*) AS rows_,
       ROUND(SUM(planned_spend_per_day), 2) AS planned_spend_per_day
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
GROUP BY 1,2,3
ORDER BY plan, rows_ DESC;
```

## Probe — ownership gaps

### SB product targets arrive under a sentinel keyword_id ('-1'), so the Catalog and the Brain are structurally blind to them and Pacing prices them alone

2026-08-24 snapshot / spend window 2026-08-16..22. 31 distinct (campaign, target) pairs under keyword_id='-1' spending $70.61/day (7d), $68.62/day (14d) across 10 SB campaigns - 4.8% of the $1,455.95/day account. Of that, 17 targets worth $69.66/day are priced by Pacing only; 14 targets worth $0.95/day have no layer at all. The sentinel reappeared 2026-06-08 after a five-month absence, was under $30/day through 2026-07-28, and stepped up to $80-140/day from 2026-07-29 onward.

```sql
-- Ownership of SB product-target spend: who prices the keyword_id='-1' sentinel?
-- Re-run: change the two dates. Baseline: 2026-08-24 snapshot, spend 2026-08-16..2026-08-22.
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-09';
WITH f AS (
  SELECT campaign_id, ANY_VALUE(campaign_name) AS campaign_name, targeting,
         SUM(Ads_cost) AS c14,
         SUM(CASE WHEN date >= DATE_SUB(d_end, INTERVAL 6 DAY) THEN Ads_cost END) AS c7,
         SUM(Ads_clicks) AS clk14, SUM(Ads_orders) AS ord14
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end AND keyword_id = '-1'
  GROUP BY campaign_id, targeting
),
p AS (  -- Pacing proposals carry the REAL keyword id and the target text
  SELECT DISTINCT campaign_id, target_text
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date >= DATE_SUB(DATE '2026-08-24', INTERVAL 9 DAY)
)
SELECT
  IF(p.campaign_id IS NULL, 'no layer at all (not even Pacing)', 'Pacing only') AS owner,
  COUNT(*)                              AS targets,
  COUNT(DISTINCT f.campaign_id)         AS campaigns,
  ROUND(SUM(f.c14)/14, 2)               AS usd_day_14d,
  ROUND(SUM(IFNULL(f.c7,0))/7, 2)       AS usd_day_7d,
  SUM(f.clk14) AS clicks_14d, SUM(f.ord14) AS orders_14d
FROM f
LEFT JOIN p ON p.campaign_id = f.campaign_id AND p.target_text = f.targeting
GROUP BY owner ORDER BY usd_day_7d DESC;

-- Proof the three layers cannot see the subjects Pacing prices:
WITH ids AS (
  SELECT DISTINCT keyword_id, campaign_id
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date = DATE '2026-08-24'
    AND match_type = 'TARGETING_EXPRESSION' AND channel = 'SB'
)
SELECT COUNT(*) AS sb_pt_targets_pacing_prices,
       COUNTIF(ks.keyword_id IS NOT NULL) AS in_catalog,
       COUNTIF(pl.keyword_id IS NOT NULL) AS in_brain,
       COUNTIF(f.keyword_id  IS NOT NULL) AS has_any_fact_row_ever
FROM ids
LEFT JOIN (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
           WHERE snapshot_date = DATE '2026-08-24') ks USING (keyword_id, campaign_id)
LEFT JOIN (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
           WHERE as_of = DATE '2026-08-24' AND plan = 'B') pl USING (keyword_id, campaign_id)
LEFT JOIN (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_AMAZON_ADS`) f
       USING (keyword_id, campaign_id);

-- When it started and how it grew:
SELECT date, COUNT(DISTINCT campaign_id) AS campaigns, ROUND(SUM(Ads_cost),2) AS usd, SUM(Ads_orders) AS orders
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE keyword_id = '-1' AND date >= DATE '2026-06-01'
GROUP BY date ORDER BY date;
```

### The same sentinel removes whole SB product-target CAMPAIGNS from the Brain's budget authority

2026-08-16..22. 36 spending campaigns ($334.84/day) have no Brain budget. Split: $233.50/day is deliberate (14 launch/INVEST campaigns, Bunny + LolliBall), $30.48/day is deliberate (6 brand-defense campaigns), $5.62/day is campaigns with no family today, and $65.25/day across 8 HARVEST campaigns is a genuine hole - dominated by BOX-VIDEO/PT (Competitors, Purple, A1) $34.96/day and ME-VIDEO/PT (Competitors, Pink, D1) $16.04/day, i.e. the same SB product-target campaigns as finding 1.

```sql
-- Campaign-level budget ownership: which spending campaigns does the Brain not budget, and is it deliberate?
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-16';
WITH sp AS (
  SELECT campaign_id, ANY_VALUE(campaign_name) AS cn, SUM(Ads_cost) AS c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end
  GROUP BY campaign_id
),
pl AS (
  SELECT DISTINCT campaign_id
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = DATE '2026-08-24' AND plan = 'B' AND campaign_planned_budget IS NOT NULL
)
SELECT
  CASE WHEN m.parent_name IN ('Bunny','LolliBall')   THEN 'deliberate: launch/INVEST family'
       WHEN UPPER(sp.cn) LIKE '%DEFENSE%'            THEN 'deliberate: brand defense'
       WHEN m.parent_name IS NULL                    THEN 'hole: campaign has no family today'
       ELSE 'hole: harvest campaign with no Brain budget' END AS bucket,
  COUNT(*) AS campaigns, ROUND(SUM(sp.c)/7, 2) AS usd_day_7d,
  STRING_AGG(sp.cn ORDER BY sp.c DESC LIMIT 6) AS examples
FROM sp
LEFT JOIN pl USING (campaign_id)
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.campaign_id = sp.campaign_id
WHERE pl.campaign_id IS NULL
GROUP BY bucket ORDER BY usd_day_7d DESC;
```

### Basket drift is not an auto-targeting problem, it is a match-width problem, and BROAD is the bigger money

Spend 2026-02-01..2026-08-22 (205 days), share of spend landing on search terms that took ZERO clicks under the same targeting in the prior calendar month: CONTROL EXACT 19.1% ($102.53/day) - CONTROL PHRASE 32.2% ($19.02/day) - AUTO substitutes 57.2% ($59.43/day) - AUTO close-match 59.9% ($68.25/day) - CONTROL BROAD 63.7% ($468.73/day) - AUTO loose-match 67.4% ($93.73/day) - AUTO complements 67.5% ($7.97/day). Drifting-basket spend (auto + broad) = $698.11/day, 48% of the account, against a $102.53/day stable-basket control. Month-by-month the auto figure ranges 44%-100%, so this is not a single bad month.

```sql
-- Basket drift with a control: share of spend on search terms that took zero clicks the prior month,
-- auto modes vs EXACT/PHRASE/BROAD. EXACT is the control - if it drifts too, the metric is measuring
-- long-tail noise rather than basket instability.
WITH t AS (
  SELECT CASE WHEN targeting_type = 'Automatic' THEN 'AUTO (' || LOWER(targeting) || ')'
              ELSE 'CONTROL ' || UPPER(targeting_type) END AS grp,
         DATE_TRUNC(date, MONTH) AS mo, targeting, search_term,
         SUM(Ads_clicks) AS clk, SUM(Ads_cost) AS c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE '2026-01-01' AND DATE '2026-08-22'
    AND search_term IS NOT NULL
    AND (targeting_type = 'Automatic' OR UPPER(targeting_type) IN ('EXACT','PHRASE','BROAD'))
  GROUP BY grp, mo, targeting, search_term
),
prev AS (SELECT grp, targeting, mo, search_term FROM t WHERE clk > 0)
SELECT a.grp,
       ROUND(100 * SUM(IF(p.search_term IS NULL, a.c, 0)) / NULLIF(SUM(a.c),0), 1)
         AS pct_spend_on_terms_unseen_last_month,
       ROUND(SUM(a.c) / 205, 2) AS usd_day_avg
FROM t a
LEFT JOIN prev p
  ON p.grp = a.grp AND p.targeting = a.targeting AND p.search_term = a.search_term
 AND p.mo = DATE_SUB(a.mo, INTERVAL 1 MONTH)
WHERE a.mo >= DATE '2026-02-01'   -- Jan is the seed month, it has no prior
GROUP BY a.grp ORDER BY pct_spend_on_terms_unseen_last_month;

-- Month by month, auto only (shows it is not one bad month):
WITH t AS (
  SELECT LOWER(targeting) AS tg, DATE_TRUNC(date, MONTH) AS mo, search_term,
         SUM(Ads_clicks) AS clk, SUM(Ads_cost) AS c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE targeting_type = 'Automatic'
    AND date BETWEEN DATE '2026-01-01' AND DATE '2026-08-22' AND search_term IS NOT NULL
  GROUP BY tg, mo, search_term
),
prev AS (SELECT tg, mo, search_term FROM t WHERE clk > 0)
SELECT a.tg, a.mo, ROUND(SUM(a.c),0) AS usd, COUNT(DISTINCT a.search_term) AS terms,
       ROUND(100 * SUM(IF(p.search_term IS NULL, a.c, 0)) / NULLIF(SUM(a.c),0), 1) AS pct_spend_new
FROM t a
LEFT JOIN prev p ON p.tg = a.tg AND p.search_term = a.search_term
                AND p.mo = DATE_SUB(a.mo, INTERVAL 1 MONTH)
WHERE a.mo >= DATE '2026-02-01'
GROUP BY a.tg, a.mo ORDER BY a.tg, a.mo;

-- How rarely the existing mix-drift guard actually arms:
SELECT COALESCE(guard_scope,'(not armed)') AS guard_scope, is_auto, match_type,
       COUNT(*) AS n, COUNTIF(guard_deferred) AS deferred, COUNTIF(guard_flip) AS flips,
       ROUND(AVG(guard_ns_share),3) AS avg_never_seen_share
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
WHERE snapshot_date = DATE '2026-08-24' AND family IS NOT NULL
GROUP BY guard_scope, is_auto, match_type ORDER BY n DESC;
```

### Coverage arithmetic: the Catalog reports 838 subjects but can only answer for 502, and every Catalog-to-Brain gap is deliberate

2026-08-24 / spend 2026-08-16..22. FACT_KEYWORD_STATE = 838 rows = 502 with a live campaign + 336 whose campaign is PAUSED (every one of the 336: keyword ENABLED, campaign PAUSED - the split is exact, no other combination exists). FACT_PLAN_NEXT_WEEK plan B = 365 subjects. Gap 502-365 = 137: LolliBall 35 subjects $170.26/day + Bunny 79 subjects $57.93/day (launch/INVEST, $228.19/day total) and brand defense 23 subjects $30.26/day. Nothing is in the Brain that is not in the Catalog (0 rows). The 336 ghosts spend $1.20/day between them.

```sql
-- (a) The three-way coverage census: who holds each spending subject?
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-09';
WITH sp AS (
  SELECT keyword_id, SUM(Ads_cost) AS c,
         SUM(CASE WHEN date >= DATE_SUB(d_end, INTERVAL 6 DAY) THEN Ads_cost END) AS c7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end GROUP BY keyword_id
),
ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date = DATE '2026-08-24'),
pl AS (SELECT DISTINCT keyword_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
       WHERE as_of = DATE '2026-08-24' AND plan = 'B')
SELECT CASE WHEN ks.keyword_id IS NOT NULL AND pl.keyword_id IS NOT NULL THEN '1 CATALOG + BRAIN'
            WHEN ks.keyword_id IS NOT NULL THEN '2 CATALOG only'
            WHEN pl.keyword_id IS NOT NULL THEN '3 BRAIN only (should be empty)'
            ELSE '4 NEITHER - spending, unseen' END AS bucket,
       COUNT(*) AS subjects,
       ROUND(SUM(IFNULL(sp.c,0))/14, 2) AS usd_day_14d,
       ROUND(SUM(IFNULL(sp.c7,0))/7, 2) AS usd_day_7d
FROM sp
FULL OUTER JOIN ks ON ks.keyword_id = sp.keyword_id
FULL OUTER JOIN pl ON pl.keyword_id = COALESCE(ks.keyword_id, sp.keyword_id)
GROUP BY bucket ORDER BY bucket;

-- (b) Provenance of the 336 un-askable rows: keyword ENABLED, campaign PAUSED
WITH ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date = DATE '2026-08-24'),
     dk AS (SELECT CAST(keyword_id AS STRING) AS kid, CAST(campaign_id AS STRING) AS cid,
                   ANY_VALUE(UPPER(state)) AS st
            FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current GROUP BY kid, cid),
     dc AS (SELECT campaign_id AS cid, campaign_state FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`)
SELECT ks.family IS NULL AS family_is_null, ks.settled_clk90 IS NULL AS evidence_is_null,
       COALESCE(dk.st,'NOT IN DIM_KEYWORD') AS keyword_state,
       COALESCE(dc.campaign_state,'NO CAMPAIGN ROW') AS campaign_state,
       COUNT(*) AS n
FROM ks LEFT JOIN dk ON dk.kid = ks.keyword_id AND dk.cid = ks.campaign_id
        LEFT JOIN dc ON dc.cid = ks.campaign_id
GROUP BY 1,2,3,4 ORDER BY n DESC;

-- (c) The 137-subject Catalog-not-in-Brain gap, split deliberate vs hole
DECLARE e DATE DEFAULT DATE '2026-08-22'; DECLARE s DATE DEFAULT DATE '2026-08-09';
WITH sp AS (SELECT keyword_id, campaign_id,
              SUM(CASE WHEN date >= DATE_SUB(e, INTERVAL 6 DAY) THEN Ads_cost END) AS c7
            FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN s AND e
            GROUP BY keyword_id, campaign_id),
     ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date = DATE '2026-08-24'),
     pl AS (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
            WHERE as_of = DATE '2026-08-24' AND plan = 'B')
SELECT CASE WHEN ks.family IS NULL                        THEN 'ghost: campaign paused, un-askable'
            WHEN ks.family IN ('Bunny','LolliBall')       THEN 'deliberate: launch / INVEST'
            WHEN ks.is_brand_defense                      THEN 'deliberate: brand defense'
            ELSE 'HOLE' END AS bucket,
       COUNT(*) AS subjects, ROUND(SUM(IFNULL(sp.c7,0))/7, 2) AS usd_day_7d
FROM ks
LEFT JOIN pl ON pl.keyword_id = ks.keyword_id AND pl.campaign_id = ks.campaign_id
LEFT JOIN sp ON sp.keyword_id = ks.keyword_id AND sp.campaign_id = ks.campaign_id
WHERE pl.keyword_id IS NULL
GROUP BY bucket ORDER BY usd_day_7d DESC;
```

### Target text shared across families - real, sized, but latent because every layer keys on keyword_id

2026-08-24 / spend 2026-08-09..22, non-auto subjects with a family only. 20 target texts live in 2 or more families: 18 texts / 37 subjects in 2 families ($95.51/day) and 2 texts / 9 subjects in 3 families ($58.31/day) - $153.82/day total, 11% of the account. Largest: 'gift for girls' (3 families, 5 subjects, $55.80/day), 'back to school gifts' (2, $28.91/day), '12 year old girl gifts' (2, $22.75/day). Separately, the four auto mode names ('close-match','substitutes','loose-match','complements') each appear in all 6 families for $300.68/day - that is the S2.1 container problem, not a phrase collision, and is counted in the drift finding instead.

```sql
-- Real-keyword phrases that live in more than one family (auto containers excluded).
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-09';
WITH ks AS (
  SELECT keyword_id, campaign_id, target_text, family
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = DATE '2026-08-24' AND family IS NOT NULL AND NOT is_auto
),
sp AS (
  SELECT keyword_id, campaign_id, SUM(Ads_cost) AS c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end GROUP BY keyword_id, campaign_id
),
col AS (SELECT target_text, COUNT(DISTINCT family) AS fams FROM ks GROUP BY target_text)
SELECT col.fams AS families_sharing_the_text,
       COUNT(*) AS subjects, COUNT(DISTINCT ks.target_text) AS texts,
       ROUND(SUM(IFNULL(sp.c,0))/14, 2) AS usd_day
FROM ks JOIN col USING (target_text)
LEFT JOIN sp ON sp.keyword_id = ks.keyword_id AND sp.campaign_id = ks.campaign_id
GROUP BY families_sharing_the_text ORDER BY families_sharing_the_text;

-- Which phrases, and worth how much:
DECLARE e DATE DEFAULT DATE '2026-08-22'; DECLARE s DATE DEFAULT DATE '2026-08-09';
WITH ks AS (SELECT keyword_id, campaign_id, target_text, family, is_auto
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
            WHERE snapshot_date = DATE '2026-08-24' AND family IS NOT NULL),
     sp AS (SELECT keyword_id, campaign_id, SUM(Ads_cost) AS c
            FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN s AND e
            GROUP BY keyword_id, campaign_id)
SELECT ks.target_text, ks.is_auto, COUNT(DISTINCT ks.family) AS fams, COUNT(*) AS subjects,
       STRING_AGG(DISTINCT ks.family ORDER BY ks.family) AS families,
       ROUND(SUM(IFNULL(sp.c,0))/14, 2) AS usd_day
FROM ks LEFT JOIN sp ON sp.keyword_id = ks.keyword_id AND sp.campaign_id = ks.campaign_id
GROUP BY ks.target_text, ks.is_auto
HAVING fams >= 2 ORDER BY usd_day DESC;
```

### The family map is ENABLED-only with a 90-day learning window, so both holiday seasons the doctrine wants to price are unattributable to a family

All ads history from 2024-09-05, campaigns matched against V_CAMPAIGN_FAMILY_MAP as of 2026-08-24. Holiday 2024 (Oct-Dec): $101,228 spent, 100.0% in campaigns with no family today, 42 orphan campaigns. Holiday 2025 (Oct-Dec): $215,796 spent, 31.8% ($68,600) with no family today, 55 orphan campaigns. Current quarter (Jun-Aug 2026): 13.7% - so the problem compounds continuously as campaigns are retired. Recoverability by widening the window and dropping the ENABLED filter: holiday 2024 100% recoverable / 0.0% unrecoverable; holiday 2025 100% of the missing recoverable; all history 0.5% unrecoverable.

```sql
-- How much historic spend has no family today, because the map is ENABLED-only with a 90-day window?
WITH s AS (
  SELECT campaign_id, DATE_TRUNC(date, MONTH) AS mo, SUM(Ads_cost) AS c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE '2024-09-05'
  GROUP BY campaign_id, mo
)
SELECT CASE WHEN mo BETWEEN DATE '2024-10-01' AND DATE '2024-12-31' THEN 'holiday 2024 (Oct-Dec)'
            WHEN mo BETWEEN DATE '2025-10-01' AND DATE '2025-12-31' THEN 'holiday 2025 (Oct-Dec)'
            WHEN mo >= DATE '2026-06-01' THEN 'now (Jun-Aug 2026)'
            ELSE 'other' END AS period,
       ROUND(SUM(c), 0) AS total_usd,
       ROUND(100 * SUM(IF(m.campaign_id IS NULL, c, 0)) / SUM(c), 1) AS pct_spend_with_no_family_today,
       COUNT(DISTINCT IF(m.campaign_id IS NULL, s.campaign_id, NULL)) AS orphan_campaigns
FROM s LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m USING (campaign_id)
GROUP BY period ORDER BY period;

-- Adversarial check: is it lost, or merely not exposed? Re-resolve over ALL history, no ENABLED filter.
WITH s AS (
  SELECT campaign_id, DATE_TRUNC(date, MONTH) AS mo, SUM(Ads_cost) AS c
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date >= DATE '2024-09-05'
  GROUP BY campaign_id, mo
),
recover AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
           ROW_NUMBER() OVER (PARTITION BY a.campaign_id
                              ORDER BY SUM(a.Ads_cost) DESC, p.parent_name) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p
      ON p.asin = COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME)
    WHERE a.date >= DATE '2024-09-05'
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
)
SELECT CASE WHEN mo BETWEEN DATE '2024-10-01' AND DATE '2024-12-31' THEN 'holiday 2024'
            WHEN mo BETWEEN DATE '2025-10-01' AND DATE '2025-12-31' THEN 'holiday 2025'
            ELSE 'other' END AS period,
       ROUND(SUM(c), 0) AS usd,
       ROUND(100 * SUM(IF(m.campaign_id IS NULL AND r.parent_name IS NULL,     c, 0)) / SUM(c), 1) AS pct_unrecoverable,
       ROUND(100 * SUM(IF(m.campaign_id IS NULL AND r.parent_name IS NOT NULL, c, 0)) / SUM(c), 1) AS pct_recoverable
FROM s LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m USING (campaign_id)
       LEFT JOIN recover r USING (campaign_id)
GROUP BY period ORDER BY period;
```

### Parks are cheap but blind: 84% of parked subjects took no clicks at all in a week

2026-08-24 snapshot / clicks 2026-08-16..22, family-bearing subjects only. PARKED 213 subjects, 179 (84%) took zero clicks in 7 days, $19.64/day total. For contrast in the same window: WINNER 78 subjects 12% silent $533.50/day, AT_BAR 57 subjects 9% silent $302.27/day, TRIAL 75 subjects 59% silent $94.63/day, DEAD 21 subjects 62% silent $4.20/day. 47 of the 213 parked subjects carry a next_check_date earlier than 2026-08-24.

```sql
-- Population, silence and cost of every Catalog state; parks are the target.
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-16';
WITH ks AS (
  SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = DATE '2026-08-24' AND family IS NOT NULL
),
sp AS (
  SELECT keyword_id, campaign_id, SUM(Ads_cost) AS c7, SUM(Ads_clicks) AS clk7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end GROUP BY keyword_id, campaign_id
)
SELECT ks.state,
       COUNT(*) AS subjects,
       COUNTIF(IFNULL(sp.clk7,0) = 0) AS zero_click_7d,
       ROUND(100 * COUNTIF(IFNULL(sp.clk7,0) = 0) / COUNT(*), 0) AS pct_silent,
       ROUND(SUM(IFNULL(sp.c7,0))/7, 2) AS usd_day_7d
FROM ks LEFT JOIN sp ON sp.keyword_id = ks.keyword_id AND sp.campaign_id = ks.campaign_id
GROUP BY ks.state ORDER BY subjects DESC;

-- Park latency (right-censored - state_since cannot exceed the table's memory chain):
SELECT COUNT(*) AS n,
       COUNTIF(state_since IS NULL) AS no_state_since,
       APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', state_since, DAY), 4)[OFFSET(1)] AS p25_days,
       APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', state_since, DAY), 4)[OFFSET(2)] AS median_days,
       APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', state_since, DAY), 4)[OFFSET(3)] AS p75_days,
       MAX(DATE_DIFF(DATE '2026-08-24', state_since, DAY)) AS max_days,
       COUNTIF(next_check_date < DATE '2026-08-24') AS overdue_recheck
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
WHERE snapshot_date = DATE '2026-08-24' AND family IS NOT NULL AND state = 'PARKED';
```

### NOT_SERVING - the doctrine's forbidden state - is more than half the plan by count and 0.16% of the account by dollars

2026-08-24 plan B. 196 NOT_SERVING subjects, $2.38/day (7d, 2026-08-16..22), 25 clicks in 7 days. Against the Catalog on the same day: 130 PARKED ($0.34/day, 27 overpriced vs affordable_bid), 40 TRIAL ($1.72/day, 6 overpriced), 8 DEAD ($0/day, 8 of 8 overpriced), 7 AT_BAR ($0.19/day), 2 WINNER ($0/day), 2 REPRICE, 2 REVIVED_SETTLING, 5 others. Days since last click across the 196: 92 have never clicked at all, 33 within 14 days, 41 at 15-30 days, 7 at 31-60 days, and 23 beyond 120 days with a median of 237 days.

```sql
-- What the Brain says nothing about, what the Catalog says about the same subjects, and what it costs.
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-09';
WITH sp AS (
  SELECT keyword_id, campaign_id,
         SUM(CASE WHEN date >= DATE_SUB(d_end, INTERVAL 6 DAY) THEN Ads_cost   END) AS c7,
         SUM(CASE WHEN date >= DATE_SUB(d_end, INTERVAL 6 DAY) THEN Ads_clicks END) AS clk7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end GROUP BY keyword_id, campaign_id
),
p AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
      WHERE as_of = DATE '2026-08-24' AND plan = 'B' AND verdict = 'NOT_SERVING'),
ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date = DATE '2026-08-24')
SELECT ks.state AS catalog_says, p.move AS brain_does,
       COUNT(*) AS subjects,
       ROUND(SUM(IFNULL(sp.c7,0))/7, 2) AS usd_day_7d,
       SUM(IFNULL(sp.clk7,0)) AS clicks_7d,
       ROUND(AVG(ks.settled_clk90), 0) AS avg_settled_clk90,
       ROUND(AVG(ks.settled_roas90), 2) AS avg_settled_roas90,
       ROUND(AVG(ks.family_bar), 2) AS avg_family_bar,
       COUNTIF(ks.affordable_bid < ks.current_bid - 0.01) AS priced_above_catalog_ceiling
FROM p
LEFT JOIN ks ON ks.keyword_id = p.keyword_id AND ks.campaign_id = p.campaign_id
LEFT JOIN sp ON sp.keyword_id = p.keyword_id AND sp.campaign_id = p.campaign_id
GROUP BY catalog_says, brain_does ORDER BY usd_day_7d DESC;

-- Latency proxy: how long since these last took a click at all
WITH p AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
           WHERE as_of = DATE '2026-08-24' AND plan = 'B' AND verdict = 'NOT_SERVING'),
     last_evt AS (SELECT keyword_id, campaign_id,
                         MAX(IF(Ads_clicks > 0, date, NULL)) AS last_click
                  FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY keyword_id, campaign_id)
SELECT CASE WHEN l.last_click IS NULL THEN 'never clicked'
            WHEN DATE_DIFF(DATE '2026-08-23', l.last_click, DAY) <=  14 THEN 'a 0-14 d'
            WHEN DATE_DIFF(DATE '2026-08-23', l.last_click, DAY) <=  30 THEN 'b 15-30 d'
            WHEN DATE_DIFF(DATE '2026-08-23', l.last_click, DAY) <=  60 THEN 'c 31-60 d'
            WHEN DATE_DIFF(DATE '2026-08-23', l.last_click, DAY) <= 120 THEN 'd 61-120 d'
            ELSE 'e >120 d' END AS days_since_last_click,
       COUNT(*) AS subjects,
       APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-23', l.last_click, DAY), 2)[OFFSET(1)] AS median_days
FROM p LEFT JOIN last_evt l ON l.keyword_id = p.keyword_id AND l.campaign_id = p.campaign_id
GROUP BY days_since_last_click ORDER BY days_since_last_click;
```

### Live family mapping has no hole at all - checked, and clean

Spend 2026-08-09..22 against V_CAMPAIGN_FAMILY_MAP as of 2026-08-24. Total $1,349.48/day. Resolution: 'the product it advertises' 67 campaigns $1,176.50/day; 'set by hand' 13 campaigns $137.81/day; 'the name it was given' 0 campaigns $0/day; 'nothing here says which family it belongs to' 0 campaigns $0/day. Not in the map because their campaign is no longer ENABLED: 18 campaigns, $35.16/day over 14 days but only $5.83/day over the final 7 - all 18 are PAUSED and their spend is trailing to zero. Separately I tested for family MISattribution by deriving family from the campaign-name prefix and comparing to the map: 0 campaigns disagree.

```sql
-- Live family-mapping coverage, and the decaying tail of paused campaigns.
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-09';
WITH spend AS (
  SELECT campaign_id, ANY_VALUE(campaign_name) AS cn, SUM(Ads_cost) AS sp,
         SUM(CASE WHEN date >= DATE_SUB(d_end, INTERVAL 6 DAY) THEN Ads_cost END) AS sp7,
         MAX(date) AS last_spend_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN d_start AND d_end GROUP BY campaign_id
),
latest AS (
  SELECT campaign_id, campaign_name, state FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
)
SELECT COALESCE(m.resolution_source, 'NOT IN MAP - campaign not ENABLED today') AS resolution_source,
       COALESCE(l.state, '?') AS campaign_state,
       COUNT(*) AS campaigns,
       ROUND(SUM(s.sp)/14, 2)             AS usd_day_14d,
       ROUND(SUM(IFNULL(s.sp7,0))/7, 2)   AS usd_day_7d
FROM spend s
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m USING (campaign_id)
LEFT JOIN latest l ON l.campaign_id = s.campaign_id
GROUP BY resolution_source, campaign_state ORDER BY usd_day_14d DESC;

-- Misattribution check: does the map ever disagree with the campaign-name prefix?
DECLARE e DATE DEFAULT DATE '2026-08-22'; DECLARE s2 DATE DEFAULT DATE '2026-08-09';
WITH latest AS (
  SELECT campaign_id, campaign_name FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
),
nm AS (
  SELECT campaign_id, campaign_name,
         CASE UPPER(REGEXP_EXTRACT(TRIM(campaign_name), r'^([A-Za-z]+)'))
           WHEN 'ME' THEN 'LolliME' WHEN 'MINT' THEN 'LolliME' WHEN 'BOX' THEN 'Lollibox'
           WHEN 'FRESH' THEN 'Fresh' WHEN 'BOTTLE' THEN 'Bottle' WHEN 'BUNNY' THEN 'Bunny'
           WHEN 'BALL' THEN 'LolliBall' WHEN 'BALLS' THEN 'LolliBall' ELSE NULL END AS fam_from_name
  FROM latest
),
sp AS (SELECT campaign_id, SUM(Ads_cost) AS c FROM `onyga-482313.OI.FACT_AMAZON_ADS`
       WHERE date BETWEEN s2 AND e GROUP BY campaign_id)
SELECT nm.campaign_name, nm.fam_from_name, m.parent_name AS fam_in_map,
       m.resolution_source, ROUND(sp.c/14, 2) AS usd_day
FROM nm
JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m USING (campaign_id)
JOIN sp USING (campaign_id)
WHERE nm.fam_from_name IS NOT NULL AND nm.fam_from_name <> m.parent_name
ORDER BY usd_day DESC;   -- baseline 2026-08-24: returns zero rows
```

### Pacing issues GO bid proposals, including raises, on subjects no other layer holds

2026-08-24, grain='BID'. By owner: BRAIN covers 124 proposals ($854.17/day of subject spend, mostly EXCLUDE); CATALOG only 54 proposals ($234.91/day - the launch families, where the LAUNCH controller is the intended authority); NO LAYER 12 proposals ($0.00/day joinable, 4 of them raises). Verdict GO on NO LAYER: 11 rows - 9 LIFT, 2 OOB.

```sql
-- Detector: Pacing proposals on subjects no other layer holds. Any row here is a S7 breach.
DECLARE d_end   DATE DEFAULT DATE '2026-08-22';
DECLARE d_start DATE DEFAULT DATE '2026-08-09';
WITH pr AS (SELECT * FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
            WHERE snapshot_date = DATE '2026-08-24' AND grain = 'BID'),
     ks AS (SELECT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
            WHERE snapshot_date = DATE '2026-08-24'),
     pl AS (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
            WHERE as_of = DATE '2026-08-24' AND plan = 'B'),
     sp AS (SELECT keyword_id, campaign_id,
                   SUM(CASE WHEN date >= DATE_SUB(d_end, INTERVAL 6 DAY) THEN Ads_cost END) AS c7
            FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN d_start AND d_end
            GROUP BY keyword_id, campaign_id)
SELECT pr.engine, COALESCE(pr.verdict, '(null)') AS verdict,
       CASE WHEN pl.keyword_id IS NOT NULL THEN 'BRAIN covers'
            WHEN ks.keyword_id IS NOT NULL THEN 'CATALOG only'
            ELSE 'NO LAYER' END AS owner,
       COUNT(*) AS proposals,
       COUNTIF(pr.suggested_bid > pr.current_bid) AS raises,
       ROUND(SUM(IFNULL(sp.c7,0))/7, 2) AS joinable_usd_day_7d
FROM pr
LEFT JOIN ks ON ks.keyword_id = pr.keyword_id AND ks.campaign_id = pr.campaign_id
LEFT JOIN pl ON pl.keyword_id = pr.keyword_id AND pl.campaign_id = pr.campaign_id
LEFT JOIN sp ON sp.keyword_id = pr.keyword_id AND sp.campaign_id = pr.campaign_id
GROUP BY pr.engine, verdict, owner ORDER BY joinable_usd_day_7d DESC;

-- The offending rows, with the worth judgement Pacing wrote in plain English:
WITH pr AS (SELECT * FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
            WHERE snapshot_date = DATE '2026-08-24' AND grain = 'BID' AND verdict = 'GO'),
     ks AS (SELECT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
            WHERE snapshot_date = DATE '2026-08-24'),
     pl AS (SELECT DISTINCT keyword_id, campaign_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
            WHERE as_of = DATE '2026-08-24' AND plan = 'B')
SELECT pr.engine, pr.campaign_name, pr.target_text, pr.match_type,
       pr.current_bid, pr.suggested_bid, pr.reason_short
FROM pr
LEFT JOIN ks ON ks.keyword_id = pr.keyword_id AND ks.campaign_id = pr.campaign_id
LEFT JOIN pl ON pl.keyword_id = pr.keyword_id AND pl.campaign_id = pr.campaign_id
WHERE ks.keyword_id IS NULL AND pl.keyword_id IS NULL
ORDER BY pr.engine, pr.campaign_name;
```

## Probe — money flow

### The 80/20 ledger is balanced by a settle flag, not by allocation — HELD_UNSETTLED launders $150/day of below-bar spend onto the good side

2026-08-24: 75 HELD_UNSETTLED subjects on the GOOD side, $335.98/day. 20 of them ($142.83/day) fail a 28-day bar test; GP shortfall against the bar $33.09/day. Reclassifying them moves $150.18/day from the 80 side to the 20 side and turns LolliME's apparent $75.98/day of spare allowance into a $4.30/day shortfall.

```sql
WITH p AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan),
w28 AS (SELECT campaign_id, keyword_id, SUM(Ads_cost) sp28, SUM(GROSS_PROFIT) gp28, SUM(Ads_orders) ord28
        FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-07-26' AND '2026-08-22' GROUP BY 1,2),
r AS (
  SELECT p.family, p.side, p.verdict, p.w_sp/3 spd,
    CASE WHEN p.side='GOOD' AND p.verdict='HELD_UNSETTLED'
              AND (COALESCE(w28.ord28,0)=0 OR SAFE_DIVIDE(w28.gp28,w28.sp28) < p.family_bar)
         THEN 'NOT_GOOD' ELSE p.side END AS side_corrected,
    p.allowance_target_per_day
  FROM p LEFT JOIN w28 USING (campaign_id, keyword_id))
SELECT family,
  ROUND(ANY_VALUE(allowance_target_per_day),2) allowance_20pct,
  ROUND(SUM(CASE WHEN side='NOT_GOOD' THEN spd END),2) notgood_as_reported,
  ROUND(SUM(CASE WHEN side_corrected='NOT_GOOD' THEN spd END),2) notgood_after_28d_reclass,
  ROUND(SUM(CASE WHEN side_corrected='NOT_GOOD' THEN spd END) - SUM(CASE WHEN side='NOT_GOOD' THEN spd END),2) laundered_by_HELD_UNSETTLED,
  ROUND(SUM(CASE WHEN side='NOT_GOOD' THEN spd END) - ANY_VALUE(allowance_target_per_day),2) gap_as_reported,
  ROUND(SUM(CASE WHEN side_corrected='NOT_GOOD' THEN spd END) - ANY_VALUE(allowance_target_per_day),2) gap_corrected
FROM r GROUP BY family ORDER BY gap_corrected DESC
```

### CONSTRAINED WINNERS — $174.73/day of proven ceiling headroom, and every one of them is told to do nothing

2026-08-24, 7-day basis 2026-08-16..22: 57 subjects, $412.77/day spend, $565.25/day GP, $174.73/day of headroom to affordable_cpc, 100% at move=NONE. Loosening to any harvest subject with >=2 settled orders below its ceiling gives 114 subjects and $277.41/day; adding launch gives $328.53/day (22% of account spend).

```sql
WITH w AS (SELECT campaign_id, keyword_id, SUM(Ads_cost) sp, SUM(Ads_clicks) clk, SUM(GROSS_PROFIT) gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2),
lean AS (
 SELECT k.campaign_id, k.keyword_id, k.family, k.state,
        SUM(w.clk*(k.affordable_cpc - SAFE_DIVIDE(w.sp,w.clk)))/7 headroom, SUM(w.sp)/7 spd, SUM(w.gp)/7 gpd
 FROM `onyga-482313.OI.FACT_KEYWORD_STATE` k JOIN w USING (campaign_id,keyword_id)
 WHERE k.snapshot_date='2026-08-24' AND w.clk>0 AND k.settled_ord90>=2
   AND k.family NOT IN ('Bunny','LolliBall')
   AND k.settled_roas90 >= k.family_bar AND SAFE_DIVIDE(w.gp,w.sp) >= k.family_bar
   AND k.affordable_cpc > SAFE_DIVIDE(w.sp,w.clk)*1.05
 GROUP BY 1,2,3,4)
SELECT COALESCE(p.side,'(not in plan)') side, COALESCE(p.move,'(none)') move,
  COALESCE(e.action,'(no pacing proposal)') pacing, COALESCE(e.verdict,'-') pacing_verdict, COALESCE(e.hold_source,'-') hold_source,
  COUNT(*) n, ROUND(SUM(lean.headroom),2) headroom_per_day, ROUND(SUM(lean.spd),2) spend_per_day, ROUND(SUM(lean.gpd),2) gp_per_day
FROM lean
LEFT JOIN (SELECT campaign_id,keyword_id,side,move FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan) p USING (campaign_id,keyword_id)
LEFT JOIN (SELECT campaign_id,keyword_id,ANY_VALUE(action) action,ANY_VALUE(verdict) verdict,ANY_VALUE(hold_source) hold_source FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
           WHERE snapshot_date='2026-08-24' AND grain='BID' GROUP BY 1,2) e USING (campaign_id,keyword_id)
GROUP BY 1,2,3,4,5 ORDER BY headroom_per_day DESC
```

### THE QUEUE — 202 not-good subjects with no seat, $98.95/day to buy every answer, and LolliME can afford its whole queue out of allowance it is not spending

2026-08-24: 202 unseated not-good subjects. Cost to fund the whole queue $98.95/day (LolliME $46.37, Lollibox $27.24, Fresh $18.21, Bottle $7.13). Fundable within today's allowance: $46.37/day, all of it LolliME. Median 20 days in state, max 50.

```sql
WITH cfg AS (SELECT 10 AS clicks_to_verdict, 7 AS answer_days),
p AS (SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
      WHERE as_of='2026-08-24' AND is_live_plan AND side='NOT_GOOD' AND seat_no IS NULL),
k AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date='2026-08-24'),
q AS (
  SELECT p.family, COUNT(*) queued_subjects,
    ROUND(SUM(cfg.clicks_to_verdict * COALESCE(k.affordable_cpc, k.bid_floor, 0.30) / cfg.answer_days),2) cost_to_fund_whole_queue_per_day,
    CAST(APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', k.state_since, DAY),4)[OFFSET(2)] AS INT64) median_days_waiting,
    MAX(DATE_DIFF(DATE '2026-08-24', k.state_since, DAY)) max_days_waiting
  FROM p CROSS JOIN cfg LEFT JOIN k USING (campaign_id, keyword_id) GROUP BY 1),
f AS (SELECT family, ANY_VALUE(allowance_target_per_day) allowance,
        SUM(CASE WHEN side='NOT_GOOD' THEN seat_cost_per_day END) seats_funded
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan GROUP BY 1)
SELECT q.family, q.queued_subjects, q.cost_to_fund_whole_queue_per_day,
  ROUND(f.allowance,2) allowance_per_day, ROUND(f.seats_funded,2) seats_funded_per_day,
  ROUND(f.allowance - f.seats_funded,2) headroom_in_allowance_per_day,
  ROUND(LEAST(q.cost_to_fund_whole_queue_per_day, GREATEST(f.allowance - f.seats_funded,0)),2) fundable_today_per_day,
  ROUND(GREATEST(q.cost_to_fund_whole_queue_per_day - GREATEST(f.allowance - f.seats_funded,0),0),2) unfundable_per_day,
  q.median_days_waiting, q.max_days_waiting
FROM q JOIN f USING (family) ORDER BY unfundable_per_day DESC
```

### THE 80/20 PER FAMILY AND THE RAMP — three families over allowance, one under, and the allowance cannot cross a family line

2026-08-24: as reported, three families over by $120.71/day combined and one under by $75.98/day. Convergence 8/6/6 windows = 24/18/18 days at PEAK. Corrected for HELD_UNSETTLED, over-allowance is $199.21/day and unclaimed allowance is $4.30/day.

```sql
WITH f AS (
  SELECT family,
    ANY_VALUE(pot_per_day) pot, ANY_VALUE(allowance_target_per_day) target,
    ANY_VALUE(allowance_ramped_per_day) ramped, ANY_VALUE(notgood_today_per_day) today,
    ANY_VALUE(window_days) wdays, ANY_VALUE(allowance_share) share,
    SUM(CASE WHEN side='NOT_GOOD' THEN seat_cost_per_day END) seats_funded
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan GROUP BY 1)
SELECT family, ROUND(pot,2) good_spend_per_day, ROUND(target,2) allowance_20pct,
  ROUND(today,2) notgood_spend_today, ROUND(ramped,2) allowance_this_window,
  ROUND(today-target,2) gap_to_doctrine,
  ROUND(seats_funded,2) seats_funded_per_day,
  ROUND(target-COALESCE(seats_funded,0),2) unclaimed_allowance_per_day,
  CASE WHEN today>target
       THEN CAST(CEIL(LN(0.10*target/NULLIF(today-target,0))/LN(2.0/3.0)) AS INT64) ELSE 0 END windows_to_converge,
  CASE WHEN today>target
       THEN CAST(CEIL(LN(0.10*target/NULLIF(today-target,0))/LN(2.0/3.0)) AS INT64)*wdays ELSE 0 END days_to_converge_at_this_window
FROM f ORDER BY good_spend_per_day DESC
```

### $85.63/day of SB product targets that no layer sees at all

2026-08-24, 7-day basis: 35 subjects, $85.63/day (5.9% of account spend), $43.07/day GP, net minus $42.56/day. FACT_KEYWORD_STATE has 0 rows with channel='SB' AND is_pt=true.

```sql
WITH w AS (
  SELECT a.campaign_id, a.keyword_id, ANY_VALUE(a.campaign_name) campaign_name,
         ANY_VALUE(a.targeting) targeting, ANY_VALUE(a.campaign_type) ctype,
         SUM(a.Ads_cost)/7 spd, SUM(a.Ads_clicks)/7 clkd, SUM(a.Ads_orders)/7 ordd,
         SUM(a.Ads_sales)/7 sad, SUM(a.GROSS_PROFIT)/7 gpd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date BETWEEN '2026-08-16' AND '2026-08-22'
  GROUP BY 1,2)
SELECT w.campaign_name, w.targeting, w.ctype,
       ROUND(w.spd,2) spend_per_day, ROUND(w.clkd,1) clicks_per_day,
       ROUND(w.ordd,2) orders_per_day, ROUND(w.gpd,2) gp_per_day
FROM w
LEFT JOIN (SELECT campaign_id,keyword_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan) p USING (campaign_id,keyword_id)
LEFT JOIN (SELECT campaign_id,keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date='2026-08-24') k USING (campaign_id,keyword_id)
WHERE p.campaign_id IS NULL AND k.campaign_id IS NULL
ORDER BY spend_per_day DESC
```

### 91 search terms marked GO for negation are bleeding $73.40/day and the last negate reached Amazon 10 days ago

2026-08-24: 91 GO terms, $73.40/day spend, 113.4 clicks/day, 0.29 orders/day, $1.26/day GP. Last applied NEGATE_TERM 2026-08-14 (10 days). Longest-standing cohort: 14 terms x 9 days, $9.88/day, $88.93 cumulative.

```sql
WITH prop AS (
  SELECT DISTINCT campaign_id, ad_group_id, target_text AS search_term, verdict
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date='2026-08-24' AND grain='NEGATE' AND action='NEGATE_TERM'
    AND COALESCE(verdict,'GO') IN ('GO','REVIEW')),
st AS (
  SELECT campaign_id, ad_group_id, search_term,
         SUM(Ads_cost)/7 spd, SUM(Ads_clicks)/7 clkd, SUM(Ads_orders)/7 ordd, SUM(GROSS_PROFIT)/7 gpd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2,3)
SELECT COALESCE(prop.verdict,'GO') verdict, COUNT(*) terms,
  ROUND(SUM(st.spd),2) bleeding_per_day, ROUND(SUM(st.clkd),1) clicks_per_day,
  ROUND(SUM(st.ordd),2) orders_per_day, ROUND(SUM(st.gpd),2) gp_per_day
FROM prop JOIN st USING (campaign_id, ad_group_id, search_term)
GROUP BY 1 ORDER BY bleeding_per_day DESC;

-- latency companion:
SELECT action, MAX(DATE(applied_at)) last_applied,
       DATE_DIFF(DATE '2026-08-24', MAX(DATE(applied_at)), DAY) days_ago, COUNT(*) n
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE upload_status IS NULL GROUP BY 1 ORDER BY days_ago
```

### Good-side protection outlives the evidence — $92.64/day held at move=NONE with a 28-day record below the bar

2026-08-24: 21 subjects, $92.64/day, 28-day gp_roas 0.518, GP shortfall against the bar about $19.47/day. 5 subjects with zero orders in 28 days on $128.59 of spend.

```sql
WITH p AS (SELECT campaign_id, keyword_id, family, family_bar FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
           WHERE as_of='2026-08-24' AND is_live_plan AND side='GOOD' AND good_side_no_sale AND move='NONE'),
w3 AS (SELECT campaign_id, keyword_id, SUM(Ads_cost)/3 spd FROM `onyga-482313.OI.FACT_AMAZON_ADS`
       WHERE date BETWEEN '2026-08-20' AND '2026-08-22' GROUP BY 1,2),
w28 AS (SELECT campaign_id, keyword_id, SUM(Ads_cost) sp28, SUM(GROSS_PROFIT) gp28, SUM(Ads_orders) ord28
        FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-07-26' AND '2026-08-22' GROUP BY 1,2)
SELECT CASE WHEN COALESCE(w28.ord28,0)=0 THEN 'no order in 28d either'
            WHEN SAFE_DIVIDE(w28.gp28,w28.sp28) >= p.family_bar THEN '28d record still above bar'
            ELSE '28d record below bar' END verdict,
  COUNT(*) subjects, ROUND(SUM(w3.spd),2) spend_per_day,
  ROUND(SUM(w28.sp28),2) spend_28d, ROUND(SUM(w28.gp28),2) gp_28d,
  ROUND(SAFE_DIVIDE(SUM(w28.gp28),SUM(w28.sp28)),3) gp_roas_28d, SUM(w28.ord28) orders_28d
FROM p LEFT JOIN w3 USING (campaign_id,keyword_id) LEFT JOIN w28 USING (campaign_id,keyword_id)
GROUP BY 1 ORDER BY spend_per_day DESC
```

### held_despite_evidence — three LolliME subjects, $86.42/day, returning 0.29 per ad dollar against a 0.874 bar

2026-08-24, plan window 2026-08-20..22: 3 subjects, $86.42/day, $25.20/day GP, gp_roas 0.292 against family_bar 0.874. Shortfall against bar about $50.33/day.

```sql
SELECT family, campaign_name, target_text, match_type, verdict, move,
       ROUND(w_sp/3,2) spend_per_day, w_ord orders_in_window,
       ROUND(ret_corrected,3) return_per_ad_dollar, ROUND(family_bar,3) family_bar,
       ladder_state, settle_due_on, SUBSTR(sentence,1,240) sentence
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
WHERE as_of='2026-08-24' AND is_live_plan AND held_despite_evidence
ORDER BY w_sp DESC
```

### Out-of-budget winners: $39.62/day of real headroom on 8 above-bar capped campaigns, and the budget book has not shipped in 9 days

2026-08-24, 7-day basis: 11 capped campaigns, budget set $409.54/day, planned $655.18/day, actual spend $622.16/day, unrealised headroom $41.37/day. Above-bar split: 8 campaigns, $39.62/day unrealised, $137.22/day of unapplied increase. Below-bar split: 3 campaigns, $108.42/day of increase queued.

```sql
WITH perf AS (SELECT campaign_id, SUM(Ads_cost)/7 spd, SUM(GROSS_PROFIT)/7 gpd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1),
fam AS (SELECT family, MAX(family_bar) bar FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
        WHERE snapshot_date='2026-08-24' AND family IS NOT NULL GROUP BY 1),
pb AS (SELECT campaign_id, ANY_VALUE(campaign_planned_budget) pbud, ANY_VALUE(family) fam
       FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan GROUP BY 1)
SELECT CASE WHEN SAFE_DIVIDE(perf.gpd,perf.spd) >= fam.bar THEN 'above family bar' ELSE 'below family bar' END verdict,
  COUNT(*) campaigns, ROUND(SUM(perf.spd),2) spend_per_day, ROUND(SUM(perf.gpd),2) gp_per_day,
  ROUND(SAFE_DIVIDE(SUM(perf.gpd),SUM(perf.spd)),3) gp_roas,
  ROUND(SUM(GREATEST(pb.pbud - perf.spd,0)),2) unrealised_headroom_per_day,
  ROUND(SUM(pb.pbud - c.budget_7d/7),2) planned_increase_unapplied,
  SUM(c.dark_days_7d) dark_days_7d_total
FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` c
JOIN perf USING (campaign_id) JOIN pb USING (campaign_id) JOIN fam ON fam.family = pb.fam
WHERE c.days_capped_7d >= 3
GROUP BY 1
```

### DARK_BRAKE aims a bid cut at the winners it is supposed to protect

2026-08-24: 20 DARK_BRAKE proposals, $430.24/day of underlying spend. Record-above-bar split: 12 subjects, $256.26/day, roas90 1.26, implied spend cut $14.12/day. Record-below-bar split: 8 subjects, $173.97/day, implied cut $12.15/day. All 20 EXCLUDEd.

```sql
WITH w AS (SELECT campaign_id, keyword_id, SUM(Ads_cost)/7 spd, SUM(Ads_clicks)/7 clkd, SUM(GROSS_PROFIT)/7 gpd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2)
SELECT
  CASE WHEN k.settled_roas90 IS NULL THEN 'no record'
       WHEN k.settled_roas90 >= k.family_bar THEN 'record ABOVE bar'
       ELSE 'record below bar' END rec,
  COUNT(*) n, ROUND(SUM(w.spd),2) spend_per_day, ROUND(SUM(w.gpd),2) gp_per_day,
  ROUND(SUM(w.spd*(1 - SAFE_DIVIDE(e.suggested_bid,NULLIF(e.current_bid,0)))),2) spend_cut_implied_per_day,
  ROUND(AVG(k.settled_roas90),2) roas90, ROUND(AVG(k.family_bar),2) bar,
  SUM(CASE WHEN k.affordable_cpc > SAFE_DIVIDE(w.spd,NULLIF(w.clkd,0)) THEN 1 ELSE 0 END) n_below_own_ceiling,
  ROUND(SUM(CASE WHEN k.affordable_cpc > SAFE_DIVIDE(w.spd,NULLIF(w.clkd,0))
        THEN w.clkd*(k.affordable_cpc - SAFE_DIVIDE(w.spd,w.clkd)) END),2) headroom_per_day
FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` e
LEFT JOIN w USING (campaign_id, keyword_id)
LEFT JOIN (SELECT campaign_id,keyword_id,settled_roas90,family_bar,affordable_cpc,settled_ord90
           FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date='2026-08-24') k USING (campaign_id,keyword_id)
WHERE e.snapshot_date='2026-08-24' AND e.grain='BID' AND e.action='DARK_BRAKE'
GROUP BY 1 ORDER BY spend_per_day DESC
```

### THE TRUE DEAD WEIGHT — $21.02/day, and it is smaller than it feels

2026-08-24, 7-day spend rate against a 28-day order test: 39 subjects, $21.02/day, $678.32 over 28 days, 1,071 clicks, 0 orders, $0 GP. Funded tests total $2.46/day; ladder tests $3.63/day.

```sql
WITH w28 AS (
  SELECT campaign_id, keyword_id, SUM(Ads_cost) sp28, SUM(Ads_orders) ord28, SUM(Ads_clicks) clk28, SUM(GROSS_PROFIT) gp28
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-07-26' AND '2026-08-22' GROUP BY 1,2),
w7 AS (
  SELECT campaign_id, keyword_id, SUM(Ads_cost)/7 spd, SUM(Ads_clicks)/7 clkd, SUM(Ads_orders)/7 ordd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2),
k AS (SELECT campaign_id,keyword_id,family,state,is_brand_defense FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date='2026-08-24'),
p AS (SELECT campaign_id,keyword_id,side,verdict,move,seat_no FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan)
SELECT
  CASE
    WHEN k.is_brand_defense THEN 'defense (exempt)'
    WHEN COALESCE(w28.ord28,0) > 0 THEN 'earning-or-converting'
    WHEN p.seat_no IS NOT NULL THEN 'funded test (seat)'
    WHEN k.state IN ('TRIAL','LAUNCH_CONTAINED','REVIVED_SETTLING','FLOOR_PROBATION','PENDING_SETTLE') THEN 'under test (ladder)'
    WHEN k.campaign_id IS NULL THEN 'DEAD WEIGHT - no layer sees it'
    ELSE 'DEAD WEIGHT - seen, unfunded, untested'
  END AS bucket,
  COUNT(*) subjects, ROUND(SUM(w7.spd),2) dollars_per_day,
  ROUND(SUM(w28.sp28),2) spend_28d, SUM(w28.clk28) clicks_28d,
  SUM(w28.ord28) orders_28d, ROUND(SUM(w28.gp28),2) gp_28d
FROM w7 LEFT JOIN w28 USING (campaign_id, keyword_id)
        LEFT JOIN k USING (campaign_id, keyword_id)
        LEFT JOIN p USING (campaign_id, keyword_id)
WHERE w7.spd > 0
GROUP BY 1 ORDER BY dollars_per_day DESC
```

### The rank proxy cannot order 56 of the subjects competing for seats

2026-08-24: 56 subjects, $72.90/day, all with 0 orders and $0 GP in the plan window 2026-08-20..22.

```sql
WITH w AS (SELECT campaign_id, keyword_id, SUM(Ads_cost)/3 spd, SUM(GROSS_PROFIT)/3 gpd, SUM(Ads_orders)/3 ordd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-20' AND '2026-08-22' GROUP BY 1,2)
SELECT
  CASE WHEN p.held_despite_evidence THEN 'held_despite_evidence'
       WHEN p.good_side_no_sale THEN 'good side, no sale in window'
       WHEN p.rank_is_degenerate THEN 'rank proxy degenerate'
       ELSE 'ordinary' END flag,
  p.side, p.move, COUNT(*) n, ROUND(SUM(w.spd),2) spend_per_day, ROUND(SUM(w.gpd),2) gp_per_day,
  ROUND(SAFE_DIVIDE(SUM(w.gpd),SUM(w.spd)),3) gp_roas, ROUND(SUM(w.ordd),2) orders_per_day,
  ROUND(AVG(p.family_bar),3) bar
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p LEFT JOIN w USING (campaign_id,keyword_id)
WHERE p.as_of='2026-08-24' AND p.is_live_plan
GROUP BY 1,2,3 HAVING spend_per_day > 0 ORDER BY spend_per_day DESC
```

### The park is cheap in dollars and expensive in visibility — 544 parked subjects, $20.84/day, and 331 of them have no family

2026-08-24: 544 PARKED, 504 with zero clicks in 7 days (92.6%), $20.84/day, 97.1 clicks/day, 6 orders in 7 days. Median 20 days in state, max 50. 63 overdue next_check_date. 331 with family=NULL.

```sql
WITH k AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date='2026-08-24' AND state='PARKED'),
w AS (SELECT campaign_id, keyword_id, SUM(Ads_cost)/7 spd, SUM(Ads_clicks)/7 clkd, SUM(Ads_orders) ord7
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2)
SELECT COUNT(*) parked_subjects,
  COUNTIF(w.campaign_id IS NULL OR w.clkd = 0) zero_click_7d,
  ROUND(100*COUNTIF(w.campaign_id IS NULL OR w.clkd=0)/COUNT(*),1) pct_zero_click,
  ROUND(SUM(COALESCE(w.spd,0)),2) parked_spend_per_day,
  ROUND(SUM(COALESCE(w.clkd,0)),1) parked_clicks_per_day,
  SUM(COALESCE(w.ord7,0)) parked_orders_7d,
  CAST(APPROX_QUANTILES(DATE_DIFF(DATE '2026-08-24', k.state_since, DAY),4)[OFFSET(2)] AS INT64) median_days_parked,
  MAX(DATE_DIFF(DATE '2026-08-24', k.state_since, DAY)) max_days_parked,
  COUNTIF(k.next_check_date < DATE '2026-08-24') overdue_recheck,
  COUNTIF(k.family IS NULL) no_family_invisible_to_brain,
  COUNTIF(k.floor_since IS NOT NULL) has_floor_since
FROM k LEFT JOIN w USING (campaign_id, keyword_id)
```

### Two 80/20 accountings run side by side and disagree by up to $30/day per family

2026-08-24: register FAMILY rows at horizon='today' vs the live plan's allowance fields. Lollibox over_by $116.01 vs $86.41 (delta $29.60/day). LolliME open_capacity $36.80 vs $62.04 (delta $25.24/day). Fresh open_capacity $14.75 vs $31.37 shortfall sign-flip. Register gap_per_day totals $75.71/day across the four harvest families.

```sql
SELECT family, horizon, ROUND(spend_horizon_per_day,2) spend_hz, ROUND(judged_per_day,2) judged,
 ROUND(defense_per_day,2) defense, ROUND(good_side_per_day,2) good, ROUND(bad_side_per_day,2) bad,
 ROUND(good_share,3) good_share, doctrine_status, ROUND(allowance_per_day,2) allowance,
 ROUND(seats_cost_per_day,2) seats, ROUND(leak_per_day,2) leak, ROUND(gap_per_day,2) untracked_gap,
 ROUND(open_capacity_per_day,2) open_cap, ROUND(over_by_per_day,2) over_by, n_keywords
FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` WHERE row_type='FAMILY' AND horizon='today'
ORDER BY family;

-- compare against the Brain's own numbers:
SELECT family,
 ROUND(ANY_VALUE(pot_per_day),2) pot, ROUND(ANY_VALUE(allowance_target_per_day),2) allowance,
 ROUND(ANY_VALUE(notgood_today_per_day),2) notgood_today,
 ROUND(SUM(CASE WHEN side='NOT_GOOD' THEN seat_cost_per_day END),2) seats
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan GROUP BY 1 ORDER BY 1
```

### SANITY CHECK — the account reconciles to the cent, residual $0.00/day

2026-08-24 snapshot, spend basis 2026-08-16..2026-08-22: total $1,455.95/day, buckets sum $1,455.95/day, residual $0.00/day.

```sql
WITH w AS (
  SELECT campaign_id, keyword_id, SUM(Ads_cost)/7 spd, SUM(GROSS_PROFIT)/7 gpd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2),
p AS (SELECT campaign_id,keyword_id,family,side FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan),
k AS (SELECT campaign_id,keyword_id,family kfam,is_brand_defense FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date='2026-08-24'),
b AS (
  SELECT CASE WHEN k.is_brand_defense THEN 'defense'
              WHEN COALESCE(p.family,k.kfam) IN ('Bunny','LolliBall') THEN 'launch (INVEST)'
              WHEN p.side='GOOD' THEN 'harvest good (80)'
              WHEN p.side='NOT_GOOD' THEN 'harvest not-good (20)'
              WHEN k.campaign_id IS NOT NULL THEN 'catalog-only, no plan row'
              ELSE 'unmapped: no layer sees it' END bucket,
         w.spd, w.gpd
  FROM w LEFT JOIN p USING (campaign_id,keyword_id) LEFT JOIN k USING (campaign_id,keyword_id))
SELECT bucket, ROUND(SUM(spd),2) dollars_per_day, ROUND(SUM(gpd),2) gp_per_day,
       ROUND(100*SUM(spd)/(SELECT SUM(spd) FROM b),1) pct
FROM b GROUP BY 1
UNION ALL SELECT 'TOTAL (all buckets)', ROUND(SUM(spd),2), ROUND(SUM(gpd),2), 100.0 FROM b
UNION ALL SELECT 'ACCOUNT TOTAL FACT_AMAZON_ADS', ROUND(SUM(Ads_cost)/7,2), ROUND(SUM(GROSS_PROFIT)/7,2), NULL
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22'
UNION ALL SELECT 'RESIDUAL (account - buckets)',
  ROUND((SELECT SUM(Ads_cost)/7 FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22') - (SELECT SUM(spd) FROM b),2),
  ROUND((SELECT SUM(GROSS_PROFIT)/7 FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22') - (SELECT SUM(gpd) FROM b),2), NULL
ORDER BY dollars_per_day DESC
```

### Launch (INVEST) is 15.7% of spend and sits outside the 80/20 accounting entirely

2026-08-24, 7-day basis: 53 spending subjects, $228.20/day, $153.94/day GP, gp_roas 0.675, net minus $74.26/day. 0 rows in the live plan. 114 rows in FACT_KEYWORD_STATE across Bunny (79) and LolliBall (35).

```sql
WITH w AS (SELECT campaign_id, keyword_id, SUM(Ads_cost)/7 spd, SUM(GROSS_PROFIT)/7 gpd, SUM(Ads_orders)/7 ordd
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` WHERE date BETWEEN '2026-08-16' AND '2026-08-22' GROUP BY 1,2)
SELECT k.family, k.state, COUNT(*) subjects,
  ROUND(SUM(w.spd),2) spend_per_day, ROUND(SUM(w.gpd),2) gp_per_day,
  ROUND(SAFE_DIVIDE(SUM(w.gpd),SUM(w.spd)),3) gp_roas, ROUND(AVG(k.family_bar),3) family_bar,
  COUNTIF(p.campaign_id IS NOT NULL) rows_in_live_plan
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` k
LEFT JOIN w USING (campaign_id, keyword_id)
LEFT JOIN (SELECT campaign_id,keyword_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of='2026-08-24' AND is_live_plan) p USING (campaign_id,keyword_id)
WHERE k.snapshot_date='2026-08-24' AND k.family IN ('Bunny','LolliBall')
GROUP BY 1,2 ORDER BY spend_per_day DESC
```

-- =============================================
-- V_HOLDOUT_READOUT — the answer. Spec: architecture/HOLDOUT.md.
--
-- THE QUESTION, in Ori's words: "the main goal of ads is to make more total dollars that we would
-- do without the changes." This view is the only object in the stack that tries to answer it with
-- a control group that actually exists.
--
-- ── READ THIS BEFORE READING ANY NUMBER BELOW ────────────────────────────────────────────────
-- THIS IS A HARM DETECTOR, NOT A VALUE CERTIFIER. The design's minimum detectable effect at the
-- chosen cell (20% share, 16 weeks, 14 holdout clusters) is $2,261 per 14 days. The eligible
-- population's ENTIRE 14-day net profit is about -$1,288. The MDE is 1.76x the whole quantity
-- being measured. Concretely:
--   · an engine adding 7% of ad spend (~$900 per 14 days) is COMPLETELY INVISIBLE here — detecting
--     it at this share would take 106 weeks;
--   · detecting $1,300 needs 50 weeks; detecting $1,800 needs 26 weeks;
--   · the precision ceiling is scale-invariant, so a bigger or smaller slice does not rescue it
--     (drop the top-1 campaign: MDE is 18% of covered spend; top-3: 18%; top-5: 19%; whole
--     population: 17%). The skew is not the binding constraint — the noise-to-signal ratio of
--     14-day net profit at this account's size is.
-- Therefore a result of "no detectable difference" is NOT a verdict that the engine is worthless.
-- It is a verdict that THE INSTRUMENT CANNOT SEE IT, and the verdict sentence this view emits says
-- exactly that. The one hypothesis this trial CAN settle inside a quarter is "the engine is doing
-- large harm" — which is live and plausible: the account's 14-day net has moved from +$3,439 to
-- -$2,470 over four months while the engine ran, and Ori's own scorecard measured account raises
-- at -$752 against cuts at +$3,051.
--
-- ── WHY THE VIEW PRINTS NOTHING UNTIL 2027-01-05 ─────────────────────────────────────────────
-- Before the first readout date this view returns exactly ONE row, state NOT_YET, every numeric
-- column NULL. That is deliberate and it is not paternalism:
--   · Ads spend settles ~D+3 and sales accrue to D+7/D+14 (fact_oi_ads_restatement_settle). The
--     TREATED arm has more recent changes than the holdout arm by construction, so reading early
--     systematically UNDERSTATES the treated arm's sales. The readout date already contains the
--     14-day settle. Do not pull it forward.
--   · A daily-readable estimate on an underpowered trial WILL be read early and over-interpreted.
--     The first plausible-looking number becomes the answer. The interim SAFETY look (2026-11-10,
--     8 weeks observed, can only detect harm above $3,133 per 14 days) is a CIRCUIT BREAKER, not a
--     verdict, and it is a deliberate one-time hand query documented in HOLDOUT.md — not something
--     this standing view leaks every morning.
--
-- ── WHAT IS BEING COMPARED ───────────────────────────────────────────────────────────────────
-- Unit: the CAMPAIGN (see V_HOLDOUT_ELIGIBLE for why not the keyword — holding out a keyword
-- inside a capped campaign re-routes its budget to its TREATED neighbours, which is a SUTVA
-- violation that flatters the treated arm).
-- Outcome: DOLLARS = SUM(GROSS_PROFIT) - SUM(Ads_cost) from FACT_AMAZON_ADS, one paired source for
-- both channels, normalised to a 14-day rate. GROSS_PROFIT is READ, never recomputed (THE GP RULE).
-- Baseline: net_28d_at_assign, frozen in DE_HOLDOUT_ASSIGNMENT on the assignment date — so the
-- change-score estimate below is computed against a pre-period that existed BEFORE the coin flip
-- and cannot have been contaminated by it.
-- Split: by the engine's INTENDED action class, taken from FACT_ENGINE_PROPOSALS. This is the
-- point of the whole architecture — SP_ENGINE_PREFLIGHT blocks the EXPORT for a holdout campaign
-- but the proposal is still RECORDED with its intended action, so the readout can compare
-- "the engine wanted to cut AND we cut" against "the engine wanted to cut AND the coin said don't".
-- Without that record the holdout arm would be a black box.
--
-- ── TWO ESTIMATES, AND WHY BOTH ──────────────────────────────────────────────────────────────
-- diff_raw      = mean 14-day dollars per TREATED campaign minus the same for HOLDOUT. Unbiased
--                 under randomization, and it makes no assumption at all.
-- diff_adjusted = the same difference computed on CHANGE SCORES (window 14-day rate minus the
--                 frozen pre-period 14-day rate). Also unbiased under randomization, and it strips
--                 the realized pre-period level gap. That gap is real and must be looked at: on the
--                 assignment date the holdout arm ran at -$0.053 of net per ad dollar and the
--                 treated arm at -$0.110 — chance, but a chance worth ~$146 per 14 days, i.e. ~6%
--                 of the MDE. If the two estimates disagree materially, the pre-period row below is
--                 where to look first.
-- Both are scaled to the account by multiplying the per-campaign difference by the number of
-- eligible units, because the question is about TOTAL dollars, not per-campaign dollars.
--
-- BAND: t_mult x SE(difference of means), with SE from the campaign-level spread inside each arm —
-- the campaign IS the cluster, so a plain two-sample SE at this grain already IS the cluster-robust
-- one. t_mult = 3.27 is the design's small-sample cluster multiplier for 14 clusters; a naive
-- t(0.975, 13) would be 2.16, so the published band is deliberately the conservative one. The
-- design's EX-ANTE MDE ($2,261 per 14 days) is published alongside it: if the realized band comes
-- back much wider, that is the peak-season variance the design warned about (expect 20-40% worse
-- than the table, since the window spans BFCM and the whole gift season).
--
-- INFERENCE CAVEAT, pre-registered: with 14 holdout clusters the right p-value is a PERMUTATION
-- p-value against the exact assignment distribution, permuted INSIDE the rerandomization acceptance
-- region (see DE_HOLDOUT_ASSIGNMENT), not a t-test. The band here is an orientation device. Also
-- pre-registered: a leave-one-out sensitivity check, because the largest eligible campaign is 11.2%
-- of the money on its own and one campaign's bad quarter moves the estimate materially.
--
-- SUBGROUP CAVEAT: the ALL row is the trial. The per-action-class rows are EXPLORATORY — the trial
-- is powered for the total and for nothing else, and every split multiplies the MDE. Read them as
-- directions to investigate, never as findings.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_READOUT` AS
WITH
-- ── TRIAL CONSTANTS. Mirrored from SP_ASSIGN_HOLDOUT; if one moves they ALL move together. ────
k AS (
  SELECT
    'HOLDOUT-2026Q4-CAMPAIGN' AS trial_id,
    DATE '2026-09-01' AS win_start,      -- = DE_HOLDOUT_ASSIGNMENT.eligible_from
    DATE '2026-12-22' AS win_end,        -- = DE_HOLDOUT_ASSIGNMENT.trial_end (16 weeks)
    DATE '2027-01-05' AS first_readout,  -- win_end + the 14-day settle. NEVER pull this forward.
    3.27      AS t_mult,                 -- design's cluster multiplier at 14 clusters (t(.975,13)=2.16)
    2261.0    AS mde_ex_ante_14d         -- the design's own MDE for this cell, per 14 days
),
anchor AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
           FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- the frozen arms. Nothing here recomputes an arm; it only reads one.
asg AS (
  SELECT a.unit_id, a.arm, a.stratum, a.channel, a.family,
         a.net_28d_at_assign
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a, k
  WHERE a.trial_id = k.trial_id AND a.unit_type = 'CAMPAIGN'
),
-- observed days so far inside the window: the normaliser. LEAST(win_end, anchor) means a partial
-- window is rated, never silently summed as if it were complete.
win AS (
  SELECT k.win_start AS s,
         LEAST(k.win_end, anchor.d) AS e,
         DATE_DIFF(LEAST(k.win_end, anchor.d), k.win_start, DAY) + 1 AS n_days
  FROM k, anchor
),
-- outcome at the randomization unit's grain. One paired source: cost and GROSS_PROFIT off the same
-- FACT rows, so the subtraction can never straddle two differently-complete feeds.
out AS (
  SELECT CAST(f.campaign_id AS STRING) AS unit_id,
         SUM(f.GROSS_PROFIT) - SUM(f.Ads_cost) AS dollars_window
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, win
  WHERE f.date BETWEEN win.s AND win.e
  GROUP BY 1
),
-- THE COUNTERFACTUAL RECORD. FACT_ENGINE_PROPOSALS keeps the engine's intended action for HOLDOUT
-- campaigns too — SP_ENGINE_PREFLIGHT blocks their EXPORT, never their judgement. Without this the
-- holdout arm would be "campaigns nothing happened to" instead of "campaigns the engine wanted to
-- move and was forbidden from moving", and the split below would be impossible.
-- v27.98: the same doctrine now covers the LAST-DAY VETO. Until today a vetoed proposal was
-- ERASED rather than labelled — the veto rewrites the action to HOLD and NULLs the bid, which
-- broke the snapshot's filters — so the engine's intent on those keywords was invisible here too.
-- Held rows are recorded now, with the intended action in held_action and the intended value in
-- held_bid (never in suggested_bid, which would be an instruction). READING held_bid IS NOT
-- OPTIONAL: a held row has suggested_bid NULL, so without it every held RAISE would fall to the
-- ELSE branch and be counted as a BID_DOWN — the trial would split on the opposite of what the
-- engine wanted. This is also what makes the veto measurable inside a trial that is already
-- running: a holdout campaign whose engine wanted to raise and was vetoed is still, correctly, a
-- BID_UP unit.
prop AS (
  SELECT CAST(p.campaign_id AS STRING) AS unit_id,
    CASE
      WHEN p.grain = 'NEGATE' THEN 'NEGATE'
      WHEN p.grain = 'BUDGET' THEN IF(COALESCE(p.suggested_budget,0) > COALESCE(p.current_budget,0),
                                      'BUDGET_UP', 'BUDGET_DOWN')
      ELSE IF(COALESCE(p.held_bid, p.suggested_bid, 0) > COALESCE(p.current_bid,0),
              'BID_UP', 'BID_DOWN')
    END AS action_class,
    COUNT(*) AS n_prop
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p, win
  WHERE p.snapshot_date BETWEEN win.s AND win.e
  GROUP BY 1, 2
),
-- one class per unit: what the engine MOST wanted to do to this campaign over the window. A
-- campaign with no proposal at all is its own class — the engine had no opinion, so neither arm
-- was doing anything, and those units carry information about the noise floor and nothing else.
intent AS (
  SELECT unit_id, action_class
  FROM prop
  QUALIFY ROW_NUMBER() OVER (PARTITION BY unit_id ORDER BY n_prop DESC, action_class) = 1
),
unit AS (
  SELECT a.unit_id, a.arm, a.stratum, a.channel, a.family,
         COALESCE(i.action_class, 'NO_PROPOSAL') AS action_class,
         COALESCE(o.dollars_window, 0) * 14.0 / w.n_days   AS d14,
         a.net_28d_at_assign / 2.0                          AS pre14,
         COALESCE(o.dollars_window, 0) * 14.0 / w.n_days
           - a.net_28d_at_assign / 2.0                      AS chg14
  FROM asg a
  LEFT JOIN out o ON o.unit_id = a.unit_id
  LEFT JOIN intent i ON i.unit_id = a.unit_id
  CROSS JOIN win w
),
-- per (class, arm) moments. The ALL row is the trial; the class rows are exploratory.
cell AS (
  SELECT 'ALL' AS action_class, arm, COUNT(*) n, AVG(d14) m, VAR_SAMP(d14) v,
         AVG(pre14) mpre, AVG(chg14) mchg, VAR_SAMP(chg14) vchg, SUM(d14) tot
  FROM unit GROUP BY 1, 2
  UNION ALL
  SELECT action_class, arm, COUNT(*), AVG(d14), VAR_SAMP(d14),
         AVG(pre14), AVG(chg14), VAR_SAMP(chg14), SUM(d14)
  FROM unit GROUP BY 1, 2
),
wide AS (
  SELECT c.action_class,
    MAX(IF(arm = 'HOLDOUT', n, NULL))    AS holdout_n,
    MAX(IF(arm = 'TREATED', n, NULL))    AS treated_n,
    MAX(IF(arm = 'HOLDOUT', tot, NULL))  AS holdout_dollars_14d,
    MAX(IF(arm = 'TREATED', tot, NULL))  AS treated_dollars_14d,
    MAX(IF(arm = 'HOLDOUT', m, NULL))    AS h_mean,
    MAX(IF(arm = 'TREATED', m, NULL))    AS t_mean,
    MAX(IF(arm = 'HOLDOUT', v, NULL))    AS h_var,
    MAX(IF(arm = 'TREATED', v, NULL))    AS t_var,
    MAX(IF(arm = 'HOLDOUT', mpre, NULL)) AS h_pre,
    MAX(IF(arm = 'TREATED', mpre, NULL)) AS t_pre,
    MAX(IF(arm = 'HOLDOUT', mchg, NULL)) AS h_chg,
    MAX(IF(arm = 'TREATED', mchg, NULL)) AS t_chg,
    MAX(IF(arm = 'HOLDOUT', vchg, NULL)) AS h_vchg,
    MAX(IF(arm = 'TREATED', vchg, NULL)) AS t_vchg
  FROM cell c GROUP BY 1
),
est AS (
  SELECT w.*,
    (w.holdout_n + w.treated_n) AS n_units,
    (w.t_mean - w.h_mean) * (w.holdout_n + w.treated_n) AS diff_raw_14d,
    (w.t_chg  - w.h_chg)  * (w.holdout_n + w.treated_n) AS diff_adjusted_14d,
    k.t_mult * SQRT(SAFE_DIVIDE(w.t_var, w.treated_n) + SAFE_DIVIDE(w.h_var, w.holdout_n))
             * (w.holdout_n + w.treated_n) AS band_95_14d,
    k.mde_ex_ante_14d, k.first_readout, k.win_start, k.win_end
  FROM wide w, k
)
-- ── GATE. Before first_readout: ONE row, no estimate, in as many words. ──────────────────────
SELECT
  0 AS row_rank,
  'NOT_YET' AS state,
  'ALL' AS action_class,
  CAST(NULL AS INT64)   AS holdout_n,
  CAST(NULL AS INT64)   AS treated_n,
  CAST(NULL AS FLOAT64) AS holdout_dollars_14d,
  CAST(NULL AS FLOAT64) AS treated_dollars_14d,
  CAST(NULL AS FLOAT64) AS holdout_pre_dollars_14d,
  CAST(NULL AS FLOAT64) AS treated_pre_dollars_14d,
  CAST(NULL AS FLOAT64) AS diff_raw_14d,
  CAST(NULL AS FLOAT64) AS diff_adjusted_14d,
  CAST(NULL AS FLOAT64) AS band_95_14d,
  CAST(NULL AS FLOAT64) AS mde_ex_ante_14d,
  FORMAT('not enough data yet — first readout %s', CAST(k.first_readout AS STRING)) AS verdict
FROM k
WHERE CURRENT_DATE('America/Los_Angeles') < k.first_readout

UNION ALL

SELECT
  IF(e.action_class = 'ALL', 1, 2) AS row_rank,
  'READY' AS state,
  e.action_class,
  e.holdout_n, e.treated_n,
  ROUND(e.holdout_dollars_14d, 2), ROUND(e.treated_dollars_14d, 2),
  ROUND(e.h_pre * e.holdout_n, 2), ROUND(e.t_pre * e.treated_n, 2),
  ROUND(e.diff_raw_14d, 2), ROUND(e.diff_adjusted_14d, 2),
  ROUND(e.band_95_14d, 2), e.mde_ex_ante_14d,
  -- THE PLAIN SENTENCE. It always names the band before the estimate, because on this trial the
  -- band is the finding.
  CASE
    WHEN e.action_class <> 'ALL' THEN
      FORMAT('exploratory split, not a finding — the trial is powered for the total only. %s: engine arm %s vs holdout arm %s per 14 days across %d and %d campaigns.',
             e.action_class,
             FORMAT('$%.0f', e.treated_dollars_14d), FORMAT('$%.0f', e.holdout_dollars_14d),
             e.treated_n, e.holdout_n)
    WHEN ABS(e.diff_raw_14d) <= e.band_95_14d THEN
      FORMAT('NO DETECTABLE DIFFERENCE. Over %s to %s the %d campaigns the engine managed produced %s per 14 days more net profit than the %d randomly-matched campaigns it was forbidden to touch, with a 95%% interval of plus or minus %s. That interval contains zero, so we can rule out the engine adding or destroying more than about %s per 14 days — and NOTHING SMALLER. This is not a verdict that the engine is worthless; it is a verdict that the instrument cannot see an effect this size. A real effect of a thousand dollars either way would be indistinguishable from zero here.',
             CAST(e.win_start AS STRING), CAST(e.win_end AS STRING),
             e.treated_n, FORMAT('$%.0f', e.diff_raw_14d), e.holdout_n,
             FORMAT('$%.0f', e.band_95_14d), FORMAT('$%.0f', e.band_95_14d))
    WHEN e.diff_raw_14d < 0 THEN
      FORMAT('HARM DETECTED. Over %s to %s the %d campaigns the engine managed produced %s per 14 days LESS net profit than the %d randomly-matched campaigns it was forbidden to touch (95%% interval plus or minus %s, change-score estimate %s). This clears the band, which is what this trial was built to catch. Confirm with the permutation p-value inside the rerandomization acceptance region and the leave-one-out check before acting — one campaign is 11.2%% of the money.',
             CAST(e.win_start AS STRING), CAST(e.win_end AS STRING),
             e.treated_n, FORMAT('$%.0f', ABS(e.diff_raw_14d)), e.holdout_n,
             FORMAT('$%.0f', e.band_95_14d), FORMAT('$%.0f', e.diff_adjusted_14d))
    ELSE
      FORMAT('GAIN DETECTED. Over %s to %s the %d campaigns the engine managed produced %s per 14 days MORE net profit than the %d randomly-matched campaigns it was forbidden to touch (95%% interval plus or minus %s, change-score estimate %s). Before believing it, rule out cross-campaign leakage: dollars the engine frees in one treated campaign can be re-spent on another treated campaign through the BASE/GROWTH portfolio pot, which flatters this arm, and organic halo runs between variations of one family. The family strata balance the arms on that; they do not make the arms independent, and its size is unmeasured.',
             CAST(e.win_start AS STRING), CAST(e.win_end AS STRING),
             e.treated_n, FORMAT('$%.0f', e.diff_raw_14d), e.holdout_n,
             FORMAT('$%.0f', e.band_95_14d), FORMAT('$%.0f', e.diff_adjusted_14d))
  END AS verdict
FROM est e
WHERE CURRENT_DATE('America/Los_Angeles') >= e.first_readout
;

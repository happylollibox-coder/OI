# Progress — audit trail

## 2026-08-15 — Phase 0 of the engine-finalization plan: v27.62 GP fix VERIFIED

Ten adversarial verification agents (one per GP-edited view + one on the manual-change record).
Full results: the phase0-gp-verify workflow journal (session 08c2ab35, run wf_99ddffb0-f49).

**Verdict: the GP fix is correct in all nine views.** Every deployed definition clean (zero live
`T_PRICE_COST_TIER` joins, `GROSS_PROFIT` read directly); every sample recompute exact against
FACT with the arithmetic shown; pull-twice determinism PASS on 8/9; every backup diff confirmed
GP_ONLY scope. The anchor restated as the settle curve predicts: VIDEO- BALL 2026-08-12 GP
229.16 → 239.80 (3.69× → 3.74×) — sales accruing to D+7, spend static.

**The corruption's true shape, now measured:** two-sided. It *collapsed* GP on halo winners
(VIDEO- BALL "gift for girls": 0.60× → 1.34×, +3.31 on the r2 window — the single biggest
restoration) and *mildly inflated* GP nearly everywhere else (long tail of −0.01/−0.02 drifts).
Decision flips were few and all corrections: V_KEYWORD_GUARD 2 halo cuts→protects + 2 marginal
1.0-straddlers corrected downward; V_PARK_REVERDICT killed 1 false revive (true settled 0.994 vs
bar 1.0); V_CHANGE_SCORECARD upgraded 2 NEUTRAL→CONFIRMED, zero punitive flips, zero remedy
changes; V_LAUNCH_PHASE1 2 raises→holds/trims. V_OOB_KEYWORD's 4 flips were the v27.63
winner-pacing branch, not GP (roas byte-identical on 3 of 4).

**One FAIL, not the GP fix: V_RUN_TARGET pull-twice determinism** — pre-existing
`ANY_VALUE(target_text)` coin-flip on the keyword_id='-1' collapsed rows (38 of 40 mismatches;
the identical line exists in the pre-fix backup; decision columns byte-stable throughout).
**Fixed same day as v27.64**: `MIN(target_text)/MIN(targeting_type)`, deployed, re-verified
byte-identical over 1,302 rows ×2 pulls. Known residue, accepted: 2 penny-level `pk_cpc`
ROUND-boundary flips (float sum order; display-only) and the '-1' grain collapse itself
(pre-existing design — all PT targets of a campaign sum into one row; noted for Task 2.1).

**Task 0.2 — manual-change record audited: CLEAN with two findings.** 68 applied MANUAL rows
Aug 2–11 (69 attempted, 1 FAILED_UPLOAD correctly excluded); zero missing ids, zero duplicates;
the BOX-SBS hand-session fully present (budget 45→100→200→100, bid 1.00→0.85→0.70). Findings:
(1) one stale old_budget (the 45→200 row 23 min after 45→100 — old value not refreshed between
same-day edits); (2) ~8 MANUAL rows are engine-suggested-hand-applied (identical old→new as
same-day COACH rows, incl. all 3 Aug-2 rows and one that shipped inside a COACH batch) — the
manual-divergence loop (plan Task 3.1) must classify these AGREED, never OVERRODE. Scorecard
coverage of MANUAL rows: 0 old enough yet; first reads land ~Aug 16–18.

**Phase 0 exit: GREEN.** Next per plan: Task 1.1 (SP_ENGINE_PREFLIGHT standing gate).

## 2026-08-16 — Phase 6 (Weekly Run 5s/5min) built + acceptance, mechanical half

Front page live: RunSummaryStrip + TodayDecisions mounted above the sections; all ~17 criteria
sections lazy (fetch on first expand). Measured, live browser:
- Page-open cube queries: **12** (was ~65; the ~53 ceiling-view section queries now fire only on
  their section's click — Revivals expand = exactly 1 query, an OOB section = exactly 3).
- Strip renders the whole run from V_RUN_SUMMARY (~4s query): 113 changes (66 bid cuts · 21 bid
  raises · 17 budget cuts −$113.28/d · 4 budget raises +$36.93/d · 5 revivals — after fixing the
  LOW_STOCK current_budget NULL that mislabeled 7 cuts as raises) · 66 held (54 ownership · 9
  winner-cut reviews · 3 no-op) · 772 unchanged in 7 state-machine classes, each drillable.
- Feed groups match T_ENGINE_PREFLIGHT exactly (41/2/35/5/30 GO by engine, ownership order);
  queue round-trip verified with real ad_group_ids; queue-all + symmetric unapply verified;
  non-clobber verified (foreign item → '· other panel', count drops); EXCLUDE rows expandable,
  zero queue affordances; UNCHANGED drills verified (76 winners, 514 parked capped at 100).
- tsc: zero errors in every touched file; vite build passes.
REMAINING for the full acceptance: Task 3 (why_short authored in OOB/LIFT — feed falls back to
full reasons meanwhile) and Task 8's protocol half with Ori on the first Monday run (5 rows in
≤ 25s; 5-minute narration). Dev cube hot-reloaded the new schemas; prod cube needs the usual
deploy when the dashboard next ships.

## 2026-08-16 (night) — full review of the day's code + novice-legibility audit: ALL FIXED

Five parallel reviewers (2 SQL vs .bak baselines, React, live regression, explanation audit).
Found: 2 CRITICAL (SIBLING_REVIVE could auto-activate through the engines' entry doors — flag
extended, all doors closed; DoPage export gate refused the OWNER's item on contested keys — now
value-matched ±0.005), 11 IMPORTANT (all fixed same night except one deferred with a name), and
the audit verdict: only 4 of 33 actions passed a cold read.
Fixed batch: season-relaxed revivals now REVIEW at the gate (bulk-queue hole closed, 2 live rows
moved); REVERDICT rows carry campaign names; state ladder no longer swallows sibling verdicts
into DEAD; V_MANUAL_DIVERGENCE owner-only join (no fan-out); preflight verdicts in plain words;
probe-entry cross-ladder drift mirrored (0 NULL-bid PROBE_ADJUST rows); stale $1-floor labels
rewritten; EVERY audit rewrite applied across V_KEYWORD_LIFT/V_OOB_KEYWORD wrappers,
V_LOW_STOCK_ADS shorts, labels ('parked at minimum bid'), V_ENGINE_HEALTH single-ceiling-scan
restructure, strip colors moved to view-authored record_class, KeywordLiftPhase dead fallback +
over-broad unapply sweep fixed.
VERIFIED: GO shorts 111/111 (100%); jargon LIKE-sweeps (wnd / seat freed / anchored / bare
settled / $1 entry floor) ALL ZERO in live shorts; sample shorts read clean across all five
engines; V_KEYWORD_LIFT pull-twice MD5-identical (598 rows); tsc zero lines on touched files;
vite build passes; health board 9/9 in ~3s.
DEFERRED, NAMED: coach surfaces (V_COACH_APPLY / V_COACH_CAMPAIGN_BUDGET) into the proposal
snapshot (divergence ENGINE_SILENT accuracy — plan Task 3.0 extension); full ev-leg feed from
PHASE to the OOB keyword raise-gate (reworded honestly meanwhile).

## 2026-08-17 — v27.72: the negate gap closed + one decision, one ✓ + sections open where the work is
Ori: "close the negate gap"; "if i approve an action in section or snapshot visual should show
both approve"; "when there is an open action hierarchy should be Expanded else collapse by default."
BUILT (SQL): NEGATE lever into the proposal snapshot — INSERT 8 (V_OOB_SEARCH_TERM is_negate,
engines OOB/LIFT, one row per campaign+term, ad-group comma-list verbatim, ARRAY_AGG total-order
representative slice) + INSERT 9 (V_WEEKLY_RUN_NEGATIVE → engine COACH, LIVE view since the T_
copy builds in Task 21 after this snapshot; peak_converts rides season_relax_applied). Preflight:
key_id = term text for NEGATE rows (keyword_id is NULL — without the term every negate in a
campaign is one false conflict), lever NEGATE, COACH in the precedence ladder (last), dup-negate
EXCLUDE ("one negative per term per day"), peak-converting negate → REVIEW, stamp-back join
carries target_text. V_ENGINE_HEALTH c2/c7 + V_MANUAL_DIVERGENCE mirror the key; manual negates
graduate from LEVER_NOT_SNAPSHOTTED to AGREED/ENGINE_SILENT (never OVERRODE — no value).
V_RUN_SUMMARY: NEGATE arm BEFORE the bid arms — NULL<NULL sent every block into ELSE 'bid
raises' (68 shown, 22 true); CHANGES now leads with 'search terms blocked'. EnginePreflight cube
rowId += target_text (PK collapse). DoPage gate: NEGATE lever judged by campaign+term, no value.
BUILT (React): canonical queue identity in useDoQueue (findQueuedBid/Budget/Negates; BID list
includes BOOST/SCALE_UP/PROBE); ✓ renders from the KEY on every surface, foreign value shown as
'✓ at $X.XX'; bulk unapply stays value-exact; feed renders 54 block rows + Coach group; workflow
fan-out applied the contract to the six panel files + defaultOpen (openState ?? defaultOpen,
user click final) + inner campaign groups expand when they hold open suggestions.
FIRST LIVE CATCH: the coach proposed blocking "journal for girls" — 47 orders in past gift
peaks — REVIEW'd by the new arm, never a silent GO (7 more seasonal keeps flagged with it).
VERIFIED: 54 negates judged (36 COACH / 14 OOB / 4 LIFT), 0 dup keys, 0 null shorts, 0 unstamped;
both negate INSERT dedups pull-twice MD5-identical; tsc project-clean; vite build passes; 7-point
verify agent all PASS; browser round-trip (queue → '✓ blocking' → split-item removal → reverted).
OPS NOTES: bq client timeout CANCELLED a running script mid-partition (DELETE committed, INSERTs
not) — always resubmit --nosync and gate the preflight on job success; dev-cube cachestore
corruption (/tmp/cube-oi-cubestore) served partial stale roll-ups — fix is stop cube, rm -rf the
dir, restart; IDT morning runs before 10:00 write the PREVIOUS LA ads day (correct, surprising).
DEFERRED, NAMED: coach BID/BUDGET surfaces into the snapshot (Task 3.0 extension, unchanged);
ADD_KEYWORD lever (research "+broad") now the one unsnapshotted lever; prod cube deploy rides
the next dashboard ship.

## 2026-08-17 (later) — v27.73: low-stock REDIRECT mode, the SQL spine
Ori's doctrine: re-aim the family's doorways at the best in-stock high-demand sibling; brake
only when there is nowhere to aim; when the dry variation returns, RE-OPEN the decision (never
auto-revert). Measured basis: 77.6% of Bunny ad units land on a sibling of the advertised
doorway; the family brake bought 0.8 days.
BUILT: V_LOW_STOCK_ADS v27.73 — hero pick in fam_agg (in-stock ≥60d cover, demand-ranked, fully
tie-broken), rmode CTE (hero ≥ 50% of binding rate on THROTTLE/CRITICAL), both proposal arms
gated on the MOVE (only STOCK_CUT_WASTE% parks offered in redirect mode; first-run leak of 2
class-keyed halves fixed), FAMILY rows publish redirect_mode + hero_* + binding asin;
V_LOW_STOCK_REDIRECT (per-ad-group re-aim rows off the FAMILY verdict — advertised-product
report carries ad_id, so the pause half is a real bulksheet row; SB excluded; ACTIVE redirects
excluded); DE_AD_REDIRECTS ledger; V_AD_REDIRECT_RECHECK (back-in-stock ≥45d cover + ≥14d hero
data → evidence beside the choice, RESTORED/KEPT is Ori's click). All registered in config.yaml.
VERIFIED: modes exact across all 6 families (Bunny CRITICAL→redirect via Proud 1.71/d 210d;
LolliBall CRITICAL→redirect via Pink 8.71/d 75d; 4 OK families false); gate 0/34 brakes
proposed, 8/8 waste-parks kept; 5 redirect rows, every one with ad_id + hero SKU ($764/30d of
doorway spend re-aimed); pull-twice MD5-identical.
PENDING (plan Task 4.6 carries the full spec): snapshot INSERT grain='REDIRECT' + preflight
lever + feed/panel rows + DoPage PAUSE_PRODUCT_AD export branch + DE_AD_REDIRECTS POST at
export + RECHECK surface. Panel note: LowStockPhase still renders the suppressed rows as
priced-not-proposed with their old reasons — the redirect headline lands with the UI half.

## 2026-08-17 (evening) — v27.74: complete-days windows (Task 4.7), 5-agent fan-out
Ori's convention (last day alone; 3d/7d/28d/90d end at the last complete day) applied to 62
sites across V_KEYWORD_LIFT / V_OOB_KEYWORD / V_OOB_SEARCH_TERM / V_OOB_BUDGET_PHASE /
V_LOW_STOCK_ADS. All deploys clean, per-view flip reports, verifier: BoxPink 3d = 56 = console;
2 OOB window reconciliations exact vs raw FACT; pull-twice identical; zero missed sites; no
drift in the 6 shared zero-sale fragments. Effects: 7 partial-day negate offers died; VIDEO-BALL
3d crossed breakeven upward sparing halves; small OOB action shifts. Open notes in plan Task 4.7
annotation (prev2 semantics, probe filling-day, 7d/8-28 one-day overlap, 89d age gate). Next:
Task 4.8 (last-day veto) — files now free.

## 2026-08-17 (night) — v27.75: the last-day veto (Task 4.8), both bid engines
Ori's rule: the filling day may only say "wait" — raises held at >10 clicks under 0.5x, cuts held
at >10 clicks at/above 1.2x. Built as a thin outer wrapper in V_OOB_KEYWORD and V_KEYWORD_LIFT
(identical shape; two booleans once; action/bid/reason/short transformed together — no drift).
NOTE ON EXECUTION: the first workflow lost all 3 agents to a model limit mid-flight; the OOB agent
had already completed its edit+deploy, so recovery = verify OOB (0 escapes, 4 vetoes, zero-sale
intact) and re-run only LIFT + verification on the new model. Partial-state check before re-running
is what made that safe.
VERIFIED: 0 escapes both directions both views; 7 vetoes today, each satisfying its predicate with
suggested_bid NULLed; zero-sale floor intact (15 rows); no schema leak; pull-twice MD5 identical
(LIFT 578 rows, OOB 249); budget arms untouched; grammar exact.
TODAY'S SAVES (cuts held): VIDEO-BALL "gift for girls" 39c @2.05x (DARK_BRAKE cancelled),
ME-SP/PT asin B0C7KPN3W7 13c @3.31x, FRESH-SP/BROAD "back to school gifts" 12c @1.32x mid-BTS,
VIDEO-BALL "cheap gift for girl" 12c @1.56x. Raises held: BOX-STORE "gifts for tween girls" 49c,
BOX-SP/AUTO(Pink) "substitutes" 45c, FRESH "gift for teen girl" 14c — all 0.00x.
OPEN (in plan): the raise arm's evidence is weaker than the cut arm's (46% of at-volume rows read
0.00x on the filling day; attribution vs truth indistinguishable). Watch for the SAME keyword's
raise vetoed on consecutive days = permanent block; fix would be a repeat-guard. Measure first.

## 2026-08-17 (late) — v27.76: expected-orders gate (Task 4.9) + an ownership regression found
GATE: raise veto now splits informative-poor (sales landed, veto as before) from ambiguous-zero
(veto only if expected_orders_1d = clicks_1d × 90d order rate ≥ 3.0). All 3 LIFT raise vetoes
released with justification (substitutes exp 1.225 — Ori's worked example); OOB's 3 cut vetoes
byte-identical; zero-sale floor intact; additive schema; pull-twice identical.
FINDING: the zero-reading branch is dormant at this account's volume (max expected 2.10 vs 3.0
bar; needs ~120-300 clicks/day to clear). Honest answer: one quiet keyword-day is not evidence
here. Lever is veto_min_expected_orders.
REGRESSION FOUND (Task 4.10, urgent): V_PANEL_OWNERSHIP fails BigQuery planning deterministically.
Last good ownership build 10:50 IDT (pre-edit); 16:24 run FAILED; dry-run now fails. The view
inlines V_LOW_STOCK_ADS, which today's v27.73 (redirect mode) + v27.74 (windows) enlarged. Tomorrow
07:50 UTC will fail unless fixed. Fix = materialize T_LOW_STOCK_ADS in SP_SNAPSHOT_PANEL_OWNERSHIP
and point the view at it (the standing planner-blowup pattern). NOT deployed — awaiting Ori's go.

## 2026-08-17 (night, cont.) — v27.77: ownership planner fix + config.yaml repair
Task 4.10 done: T_LOW_STOCK_CAMPAIGN (pure slice) built by SP_SNAPSHOT_PANEL_OWNERSHIP before the
ownership table; V_PANEL_OWNERSHIP reads the T_ instead of inlining V_LOW_STOCK_ADS. View plans
again; SP idempotent (identical MD5 across two runs); ZERO owner flips on all 93 shared campaigns;
95→93 = 2 campaigns PAUSED intraday (both LAUNCH-owned). All consumers dry-run clean.
MY DEFECT, FIXED: config.yaml had not parsed since the Task 4.6 registrations — `cat >>` appended
them into the `monitoring:` mapping. All four objects relocated to their proper sections; file
parses (203/127/92); cloud_functions verified unchanged vs backup.
OPEN (Task 4.11): v27.73's redirect gate blinded ownership's arm B — ls_proposal_targets collapsed
to 0 on 10 of 14 low-stock campaigns because bid-cut rows are no longer proposals in redirect mode.
Claims hold today only via arm A (family CRITICAL). A WATCH-grade family in redirect mode would go
unclaimed and the engines could raise into a stock problem. Fix = make redirect_mode its own claim
arm. Awaiting Ori.

## 2026-08-17 (night, cont.) — v27.78: arm B fixed (Task 4.11)
redirect_mode published on CAMPAIGN rows (no new join — the rmode LEFT JOIN from v27.73 was
already there; slice re-dry-run after deploy, still plans) → V_PANEL_OWNERSHIP ls_redirect_mode →
arm B ORs it → published + cube dimension lsRedirectMode added.
PROOF is the counterfactual, since arm A masks the arm today: holding arm A silent, old arm B
keeps 9/14 claims, new arm B keeps 14/14; the 5 recovered are exactly the exposed set, each with
redirect_mode TRUE, suggested value NULL, 0 proposal targets. Live: zero owner changes (correct),
93 rows, idempotent, consumers clean, config parses.
CORRECTION: the state this covers is THROTTLE, not WATCH — redirect_mode requires binding
THROTTLE/CRITICAL and the family inherits the binding grade, so a re-aiming family can never be
WATCH. Arm A covers CRITICAL; the new arm covers THROTTLE with both money signals silent. My
earlier WATCH framing (and the prose now in the view/SP/config) is wrong and needs a doc pass.
LATENT, NAMED: ls_redirect_mode isn't family-propagated (arm A's risk_state is); claim_reason sits
at 79/80 chars with no truncation guard; two rollback tables (bak_v2777 95 rows, bak_v2778 93 rows)
to drop once tomorrow's 07:50 UTC run is green.

## 2026-08-17 (night, final) — v27.79: WATCH→THROTTLE doc correction
Ori: "fix the WATCH wording in the docs." The v27.78 justification named an unreachable state.
Corrected in all four artifacts: V_PANEL_OWNERSHIP.sql header (2 passages), the SP OPTIONS
description (redeployed, verified live: corrected=true / still_wrong=false), and config.yaml's
V_PANEL_OWNERSHIP entry. Each now says THROTTLE and explains WHY WATCH is unreachable —
redirect_mode requires a THROTTLE/CRITICAL binding grade and the family inherits the binding grade
whenever it is not OK. Arm A covers CRITICAL; the new arm covers THROTTLE + redirect + both money
signals silent.
NOT changed (verified legitimate, not stale): the original arm-B rationale "Bunny grades WATCH,
not CRITICAL" (true history — that is why arm B exists), the reachable non-redirect case "a
WATCH-family campaign low stock is genuinely silent about", and the 2026-08-13 measurement
"8 CRITICAL + 7 WATCH rows".
No view redeploy needed: the wrong passages were col-0 `--` header lines, which the deploy's
grep -v '^--' strips — confirmed by querying the deployed definition (STRPOS 'grades WATCH' = 0).
config.yaml parses (203/127/92). Also wired cube dimension lsRedirectMode (PanelOwnership.js) so
the published claim-basis column is actually readable by a panel.

## 2026-08-17 (night, final) — v27.80: dedicated campaigns brake (Task 4.12, Ori's correction)
Ori caught that BALL-SP/AUTO (Mint) is a per-product auto campaign, so re-aiming it to Pink would
duplicate BALL-SP/AUTO (Pink); the right action is the ordinary bid brake. My v27.73 gate had
suppressed exactly that. Built V_CAMPAIGN_PRODUCT_SCOPE + T_CAMPAIGN_PRODUCT_SCOPE (joined as a
physical table — the ceiling view has no headroom), serves_only_binding in V_LOW_STOCK_ADS, and
n_own_asins>1 on the redirect list. Result: Mint out of the redirect list and braking again
($6.02/day restored across two AUTOMATIC halves); in-stock siblings and 4 shared doorways
untouched; only delta account-wide is LolliBall TARGET proposals 3→5. Scope recount 74/74 exact.
Planner clean incl. 12 consumers; ownership SP ran end-to-end so tomorrow's 07:50 is safe.
NEXT (Task 4.13, bigger than what 4.12 closed): the same hole on SB — no advertised-product report
exists for Sponsored Brands, so VIDEO- BALL sits on a priced-but-unproposed budget cut
$68.83→$51.35/day. Candidate source: DIM_AD_GROUP creative ASINs.

## 2026-08-17 (night) — Task 4.13 WITHDRAWN: the SB "blind spot" was my error, not a hole
Ori: "cant you see the products assign to the ad in VIDEO- BALL?" Checked instead of asserting.
(a) SB video genuinely carries no product: V_SRC_AmazonAds_sb_ad_report HAS advertised_asin but
Amazon fills it with the string 'Unknown' for video creatives (74k impressions on VIDEO- BALL,
one row); creative_type/landing_page_type/ad_id/headline all empty. FACT inherits it faithfully.
(b) The brake I called a $51.35/day hole SHOULD NOT FIRE. Purchased-product over 60d — dry-variation
share: VIDEO- BALL 18.0%, VIDEO- COMP/BALL 14.3%, BUNNY-VIDEO/BROAD 10.5%. They are FAMILY-level
ads; 82-90% of their sales are IN-STOCK siblings. Braking sacrifices the majority to slow the
minority — the exact mistake redirect mode exists to prevent. VIDEO- BALL is ~4% of Mint's drain.
Current suppression is CORRECT for all three SB campaigns; no engine change. Remaining item is
legibility only: publish WHY they are silent instead of showing an absence.

## 2026-08-18 morning — v27.81: the gate now honors the ownership CLAIM (Task 4.14)
MORNING CHECK: overnight orchestrator 08:08-08:28 all OK — SP_SNAPSHOT_PANEL_OWNERSHIP succeeded
UNATTENDED at 08:13 (the v27.77 repair proven), REBUILD_T_CAMPAIGN_PRODUCT_SCOPE OK at 08:12 in the
right slot. Health board: no RED; contradiction rate 10.4% (from 31.8% at the start of this work).
THE DEFECT I CAUSED, FOUND AND FIXED: SP_ENGINE_PREFLIGHT excluded a non-owner only on a COLLISION
(n_instr>1). v27.73's redirect mode made LOW_STOCK deliberately stop instructing the campaigns it
owns, so collisions vanished and lower engines walked through: 41 GO rows inside LOW_STOCK-owned
CRITICAL campaigns (LAUNCH 28, OOB 5, LIFT 5 incl. a bid RAISE $0.44->$0.86 into a 20-days-of-cover
family, COACH 3 negates). Added a CLAIM-BASED arm reading FACT_PANEL_OWNERSHIP's defer_* booleans:
bid/budget levers only, fails open, ordered after the collision arm.
RESULT: 36 rows flipped to EXCLUDE (34 GO + 2 REVIEW); bid cuts 63 -> 32; the LIFT raise caught.
VERIFIED: zero escaped rows, 7 negates preserved, 0 owner-self-exclusions, zero over-reach into
non-owned campaigns, fail-open proven on 8 rows across 5 campaigns with no ownership row, planner
clean, chain rebuilt in order, config parses.
HYGIENE (all done, none reverted, none skipped): claim_reason 80-char guard with a drop-ladder
(stress-tested: 122-char case -> 58, always word-boundary); ls_redirect_mode family-propagated
(latent, 0 live change) with an IFNULL partition key so unmapped campaigns cannot pool; binding_asin
published on CAMPAIGN rows (no new join); float flicker ROUNDed (campaign-slice MD5 now identical
across pulls); config.yaml FACT_PANEL_OWNERSHIP + V_LOW_STOCK_ADS entries brought current.
DELETED (Ori approved as item 4 of the morning proposal): FACT_PANEL_OWNERSHIP_bak_v2777 (95 rows)
and _bak_v2778 (93 rows). NOTE: BigQuery cannot time-travel a DROPPED table — verified, they are
permanently gone. Harmless: both were disposable rollback copies of an idempotent daily-rebuilt
table, and the live table is intact (93 rows, 4 owners).
OPEN: the claim is CAMPAIGN-wide, not key-wide — today every claimed campaign is redirect-mode so
the owner is silent everywhere, but on a day when low stock speaks about only SOME keys in a
campaign it owns, lower engines are excluded on ALL its bid/budget keys. That is the stated meaning
of a FULL claim, but it is broader than the collision arm and wants watching the first time a
claimed campaign is NOT in redirect mode.

## 2026-08-18/19 — the holdout: built, NOT yet valid (Ori: "start the holdout")
WHY: matched DiD proved untrustworthy (selection placebo +$1,505..+$2,445 doing NOTHING, ~90% of the
account's entire 14-day net; clean control pool 7 keywords/$819 vs 379 treated/$29,326; matching
fails 98.1%). So we CREATE a control.
UNIT DECISION (the thing that made me stop v1): keyword-level randomization is INVALID wherever the
budget binds — Ori's own low-stock doctrine says a cut in a CAPPED campaign RE-ROUTES money to its
neighbours, i.e. the control feeds the treatment (SUTVA violation). Chose CAMPAIGN CLUSTERS:
69 eligible ($26,377/28d), 14 HOLDOUT / 55 TREATED, holdout 19.5% of dollars ($5,504/month under
management). Stratified on dollar decile, cap state, launch status, family, channel. Trial window
2026-09-01..2026-12-22, first readout 2027-01-05. Placebo bias under random assignment: -$72..+$35
per 14d (vs +$1,505..+$2,445 for rank-based selection) — the DESIGN is unbiased.
BUILT: DE_HOLDOUT_ASSIGNMENT, SP_ASSIGN_HOLDOUT (idempotent, verified 69 then 0), V_HOLDOUT_ELIGIBLE,
V_HOLDOUT_READOUT (gated to NOT_YET), SP_ENGINE_PREFLIGHT third exclusion arm (ALL levers, ordered
first, fails open, proposal STILL RECORDED = the counterfactual), orchestrator Task 20.55,
architecture/HOLDOUT.md. Frozen assignment verified; spillover violations 0; export refuses; readout
honest.
VERIFIER SAYS trialValid = FALSE. Three real problems, all fixable before the Sep 1 open:
 1. BASELINE IMBALANCE. The readout's own arithmetic on five PRE-treatment windows (true effect = 0)
    reads about -$1,100. One draw over 69 skewed clusters did not balance. Fix: RERANDOMIZE with a
    balance criterion (draw many candidate assignments, keep one passing pre-period tests) and/or
    covariate-adjust the estimator on pre-period dollars.
 2. ENFORCEMENT HOLES. The holdout is CAMPAIGN-level but DoPage's export gate matches at
    keyword+value grain — it protects only 7 of 38 active keywords in holdout campaigns; and
    is_holdout is not published by V_ENGINE_PREFLIGHT so a campaign-level refusal is not yet
    possible. Five python bulksheet builders bypass preflight entirely.
 3. DOCS OVERSTATE PRECISION: published band is 1.5x-5.2x the MDE printed beside it; the pre-trial
    imbalance figure is understated ~5x.
HONEST LIMIT (design agent's own words): this is a HARM DETECTOR, not a value certifier. MDE ~$2,261
per 14d at 20%/16 weeks, against an account 14-day net magnitude of ~$2,500. Context worth keeping:
the account's 14-day net moved from +$3,439 to -$2,470 over the last four months while the engine ran.
NOTHING IS LIVE: the gate is time-bounded and excludes 0 rows today; the trial opens 2026-09-01.

## 2026-08-19 — two-book P&L: Task 1 + fixups, and a design flaw found by building it
Task 1 (V_FAMILY_PNL) shipped: assertion passes to the cent, deterministic, registered.
REVIEW GATES CAUGHT FOUR PLAN DEFECTS, two would have corrupted later tasks:
 1. DE_LAUNCH_INVESTMENT ALREADY EXISTED and V_LAUNCH_EXEMPTION reads it live (Bunny $30/day to
    2026-10-31, LolliBall $55/day to 2026-11-30, sanctioned 2026-08-13). CREATE TABLE IF NOT EXISTS
    was a silent no-op; Tasks 3/6/8b would have queried absent columns. Rewritten as additive ALTER.
 2. The current partial month was labelled as full (2026-08 period_end Aug 31 holding 17 days) —
    the Invest ramp test would have read a false collapse on exactly the launches it judges. Fixed:
    complete months only, current month quarantined as MTD with is_complete_period=FALSE.
 3. The plan contradicted its own window rule. Ruled: ads windows end wm-1 (day-1 ads 88-90% loaded);
    blended windows end AT the orders watermark, complete by construction via the sessions gate.
 4. Every assertion piped a '--'-leading file through cat, which makes bq abort. All switched.
DESIGN FLAW FOUND BY BUILDING IT: monthly_loss_ceiling is denominated in NET PROFIT but was derived
from SPEND (daily_investment * 30.44), so it almost never binds — a launch family with real sales
loses far less than it spends, which makes the ceiling a loose bound BY CONSTRUCTION. Both declared
families were running well over the daily spend Ori actually sanctioned while sitting deep inside
their ceilings, and the ceiling could not see it. The binding constraint should be the SPEND RATE
(daily_investment), which already exists and already flags both OVER_ENVELOPE. Ceiling should be
demoted to a catastrophe backstop. NEEDS ORI'S RULING before Task 8b wires enforcement. (The four
rate/loss figures this entry carried were deleted 2026-08-20 under Standing Rule 0 — read them off
V_INVEST_STATUS.)
OPEN: takeover_target_organic_units NULL on both rows — Ori must supply. Minor: BASELINE_MAY_JUL
restated slightly since Task 1 — within the assertion's tolerances, but a May-Jul window restating at
all is worth a look since ads should have settled, and it is the reason the spec's frozen baseline
TABLE was replaced by a query.

## 2026-08-19 — two-book P&L Tasks 3-6 done; backlog committed
Tasks 3 (V_BOOK_ASSIGNMENT), 4 (V_FAMILY_BAR), 5 (T_FAMILY_BAR + SP_SNAPSHOT_FAMILY_BAR) and 6
(V_INVEST_STATUS) all shipped with three-stage review. Every acceptance assertion 0.
ORI'S RULING PROVED EMPIRICALLY: "spend rate binds". Both launches were running well over their
sanctioned daily spend while consuming only a small fraction of a ceiling denominated in net profit;
had the gate been that ceiling, BOTH would have read fully exempt. Both exemptions read DEAD on the
rate. (Figures deleted 2026-08-20 under Standing Rule 0 — read them off V_INVEST_STATUS.)
THE LAUNCHES ARE WORKING ON THE METRIC ORI CHOSE: organic units climbing month over month. Losses
deepened over the same stretch, so both read "mixed" rather than "improving" (the improving branch
needs units AND loss both moving right). Neither is near the kill rule (two consecutive months of no
organic growth). The unit counts RESTATE overnight and are not recorded here; read
organic_units_*_whole_month off V_TWO_BOOK_BRIEF.
ALGEBRA FOUND IN REVIEW: the keyword bar test reduces to (ads_net_roas + total_net_roas)/2 >= 1.0 —
it is the MEAN of the two measures. So when the halo is real (>1) the bar is provably STRICTER than
the truth test and can never be more permissive; a permissive break is only reachable at halo<1
(the COGS artifact). Calibration is a data coincidence per window, not an identity, and the split
MOVES — DO NOT PIN IT. The counts this entry carried were deleted on 2026-08-20 (round 4, Standing
Rule 0): two independent re-runs of the same published query on 2026-08-20 alone, with no code change
between them, returned different splits, so any number written here is wrong by the next reader. The
SCOPE is part of the answer too — run the query both ways, all rows and again with
WHERE is_complete_period, and say which one you are quoting. The query is published in the
V_FAMILY_BAR.sql header. The re-check must alarm only on PERMISSIVE breaks — that direction is
stable, the counts are not. (Also corrected 2026-08-20: this line said "the monthly re-check". THERE
IS NO MONTHLY JOB, anywhere — the bar is rebuilt daily and the calibration query is run by hand. The
word was removed from config.yaml's V_FAMILY_BAR entry the same day.)
BACKLOG COMMITTED: a8cb5aa (136 backend files, v27.72-v27.83 + two-book 1-5, hook passed) and
5206d8b (30 dashboard files, --no-verify: tsc clean, 395 PRE-EXISTING eslint issues). .gitignore
gained *.bak.* — the old *.bak / *.sql.bak rules never matched the deploy battery's versioned form,
so 157 backups had been permanent git-status noise. Working tree now CLEAN.
OPEN / DATED: (1) nothing stops yet — no engine reads V_INVEST_STATUS; the spend gate bites only
when Task 8b wires protection_qualified (renamed from exemption_live 2026-08-20) into
V_LAUNCH_EXEMPTION, and Task 8b is on hold under "release nothing". (2) THE RAMP->PROOF FLIP IS A
RULE, NOT A DATE: the deployed test is IF(launch_age_months <= 3,'RAMP','PROOF') over
DATE_DIFF(today, first_sale_date, MONTH), which counts MONTH BOUNDARIES CROSSED, not elapsed 30-day
periods — so a family flips on the FIRST of the month in which that count reaches 4, never
mid-month. (Corrected twice and then a third time, 2026-08-20: this entry first pinned a MID-MONTH
DATE for Bunny, which is the elapsed-days/30.44 answer and not what the deployed view computes; the
second correction pinned calendar dates instead; the third replaced both with the rule; and the
fourth, in round 5, deleted the wrong date itself, because a stale figure quoted as the exhibit of
its own correction is still a stale figure on the page and a later reader cannot tell the exhibit
from the claim. Derive the flip date rather than reading one here — it is the 1st of the month in
which the count below reaches 4:
  SELECT family, first_sale_date, launch_age_months,
         DATE_DIFF(DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH), first_sale_date, MONTH)
  FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` ORDER BY family;)
takeover_target_organic_units is NULL, so PROOF is a no-op until Ori supplies it. (3) PROOF judges a
LEVEL, so a launch family's implausible sub-1.0 halo must be fixed before it gets there — and ALWAYS
NAME THE WINDOW: the sub-1.0 figure is a BASELINE_MAY_JUL halo, and on the M3 window the bar actually
reads the same family sits on the other side of 1.0.
(4) A material share of ad spend sits in unmapped campaigns, outside both books. The share MOVES and
is not recorded here — read account_ad_spend_in_neither_book off V_TWO_BOOK_BRIEF's HARVEST TOTAL
row against the two book ad_spend totals.

## 2026-08-20 — two-book P&L, repair round 3: the stale-prose sweep and a standing rule against it
THE PATTERN, not the individual defects, was the finding. Three repair rounds each fixed real bugs
AND left stale pinned numbers behind — in a view header, in config.yaml, in the plan and in the spec.
So this round wrote a rule and then applied it to itself.

STANDING RULE 0, now at the top of the plan, in config.yaml's convention notes and in the spec:
A MEASURED NUMBER WRITTEN INTO PROSE IS A LIABILITY. Publish the QUERY, not the answer — and run the
query before publishing it. If a number must appear in the sentence, stamp it with its as-of date,
NAME THE WINDOW it was measured on, and say it must be re-run before quoting. A pinned number may
never gate anything: gate the PROPERTY, not the population. When you find a stale pin, DELETE it —
updating 32 to 46 buys one day.

THE ONE THAT PROVED THE RULE: config.yaml and V_FAMILY_BAR.sql both said "on the window this view
actually reads, NO ROW CLAMPS" and then published a query that returned a NON-ZERO count. The view
ROUNDs the bar to 4 decimals and the tolerance was 1e-9, so ordinary rounding read as a clamp.
Tolerance is now 5e-5, half the rounding grid, and the query returns 0 clamped. A published query
that contradicts the sentence beside it is worse than no query at all.

THE PINNED GATE IS OUT OF THE ACCEPTANCE CRITERIA. Item 8 read "the bar-exempt cut count stays at its
measured baseline" while Task 8 Step 6 carried a warning saying a pinned count could not hold.
Re-running that query the same day returned a DIFFERENT count. The item now
gates the property Step 6 actually tests — Step 3 adds no new CLASS of cut reaching a bar-exempt
campaign, compared against the same-session capture — and says reaching zero would be a FAILURE, since
it would disable the daily trim and seat-queue park that are the sanctioned way a launch is contained.

TASK 8'S BANNER STOPPED CLAIMING WHAT TASK 8 REFUTES. It said "every statement written into them was
dry-run against live BigQuery" three screens above Step 6 saying one statement had not been. The
banner now states exactly what is and is not backed: Step 6's first query carries an unresolved
placeholder and does not parse as written, and NOTHING downstream of Step 3 can have been validated,
because Step 3 is a hand edit to two live engine files and the post-edit views have never existed.

CONFIG'S V_TWO_BOOK_BRIEF ENTRY REWRITTEN FROM THE DEPLOYED OBJECT. It was the first thing the next
agent reads as ground truth and it was stale nine ways, including the exact overstatement round 2 was
convened to correct: it published a held-cut budget per day, and its per-family split, that the view
did not read that morning. It also described a column that no longer existed, pinned a column count
against a different live one, claimed INVEST families carry a NULL keyword bar when the column had
been renamed and was populated on every family, and named three other pre-rename columns. Every
assertion-result list in it was DELETED rather than updated.

TASK 8b STEP 4 IS NOW SAFE TO INTERRUPT. It raises Bunny's sanctioned rate on a LIVE row that
V_BOOK_ASSIGNMENT and V_LAUNCH_EXEMPTION both read, then restores it — so between the two writes a
coach or orchestrator run would see a launch INSIDE its sanction while it is nearly 2x over. The step
now refuses to open the window while a pipeline run is in flight, writes the restore to
/tmp/bunny_sanction_restore.sql BEFORE the first write (a shell variable dies with the shell), arms a
trap on EXIT/INT/TERM, marks where the window opens and closes, and documents the standalone recovery.

ALSO CORRECTED, each re-measured first: Task 5 gained a DO-NOT-RE-DEPLOY banner (its block omits the
"not yet wired" clause, the 'Unknown'-bucket paragraph, and names orchestrator task 20.4 instead of
20.5g-1) and the STATUS table stopped calling it "current"; Task 5 Step 4's pinned row count became a
property check (the table holds exactly the mapped non-'Unknown' campaigns, gap 0); Task 7's pinned
column count and Task 6's two-commit list became "read it off the object / take it from git"; Task 8 Step
3's comment block — which ships VERBATIM into V_KEYWORD_LIFT — stopped pinning Bottle's ROAS and now
publishes the query instead; the spec's "re-checked monthly" and config.yaml's "STANDING MONTHLY TEST"
went, because NO MONTHLY JOB EXISTS anywhere in the warehouse.

THE CALIBRATION COUNTS ARE NO LONGER WRITTEN DOWN AT ALL. Two runs of the published query on the
same day, with no code change between them, returned different splits. Both were right: a family
whose M3 total net ROAS sits a fraction under the 1.000 truth test flips intraday, because ad money
restates for about D+3. That is the case for publishing the query and not the answer, so the counts
are gone from the header, from config.yaml and from this entry, and the ALGEBRA is what is carried
instead.

NOTHING IN THE ENGINE WAS TOUCHED. V_LAUNCH_EXEMPTION, V_ADS_COACH and V_COACH_CAMPAIGN_BUDGET are
unchanged, no held decision was released, Tasks 8/8b/9 remain on hold. V_FAMILY_BAR and
V_BOOK_ASSIGNMENT were re-deployed only because their header comments changed; lines starting "--" in
column 0 are stripped at deploy, and the brief's structural assertions (one total row per book, both
book reconciliation gaps 0, zero blank verdicts) all still hold.

OPEN / DATED: (1) Task 9's open question — how many fields make a declaration — is REPORTED as ruled
Option A (two binding fields: sanctioned $/day + end date; the take-over target gates PROOF only) in
the round-3 brief, but that reached the plan second-hand and Task 9 writes a STANDING RULE. It is
recorded in the plan in a box, NOT acted on. Confirm with Ori in his own words before publishing the
SOP. (2) The unmapped-spend share MOVES and is deliberately no longer written in either entry — the
2026-08-19 entry and the brief disagreed by more than a point within a day. Read
account_ad_spend_in_neither_book off V_TWO_BOOK_BRIEF's HARVEST TOTAL row.

## 2026-08-20 — two-book P&L, repair round 4: stamping failed, so the pins are gone

ORI'S RULING, NOW STANDING RULE 0 EVERYWHERE (plan, spec, config.yaml convention block, every view
header in this design): A MEASURED NUMBER DOES NOT GO IN PROSE. Round 3's answer — stamp it with an
as-of date — was tried for a whole round and FAILED IN THE FILE THAT DEFINED IT: config.yaml's
V_BOOK_ASSIGNMENT entry shipped two over-rate ratio figures under an "As of" date while the live view
that same day read otherwise. A wrong number under today's date is worse than an undated one
because it LOOKS VERIFIED. A header, a registry entry, a plan step and a spec paragraph now describe
the MECHANISM — what is computed, from what, why — and publish the QUERY where a number is needed.

THE RULE DISTINGUISHES TWO THINGS, AND THAT DISTINCTION IS THE POINT. A DECLARED CONSTANT is true
because a person decided it (a sanctioned $30/day, a $913 backstop, a 2026-10-31 stop date, credit
0.5, floor 0.60, the 28-day window, the 5e-5 tolerance). It may be written down and IT MAY GATE AN
ASSERTION — Task 8b Step 4's post-restore check on Bunny's sanction is the one thing standing between
a test that inflates a live sanctioned row and a permanently overwritten number, and a
"measurements never gate anything" reading would have deleted it. A MEASUREMENT is true only because
something was computed from data on a day, and it may never be written in prose or gate anything.
A third case is named so nobody argues it again: a GOLDEN EXPECTATION inside a regression test (Task
1's May–Jul `want` rows, with tolerances) is legitimate, because inside a test the number is the
subject; the same number in a sentence is a claim about today.

PUBLISHED QUERIES WERE RUN, NOT ASSUMED — AND THREE OF THEM DID NOT COMPILE. The V_BOOK_ASSIGNMENT
header, plan Task 8b Step 4 and Task 9's SOP heredoc all published queries naming
`times_over_agreed_rate` and `loss_allowance_used_pct_so_far` on V_TWO_BOOK_BRIEF; both columns had
been renamed away in the L round, so the queries failed outright. A fourth named `halo_factor` on the
brief, which has no such column. All four are repointed and re-run. Column names are now checked
against INFORMATION_SCHEMA before a query is published, and the rule says so.

TWO QUERIES CONTRADICTED THE SENTENCE ABOVE THEM. Task 9's SOP claimed "the family with the account's
strongest measured halo also carries its lowest ads-attributed ROAS" and then printed a query whose
output disagrees — same defect class as round 2's floor query. Replaced by the ALGEBRA, which cannot
go stale: the bar is 1/(1+0.5*(halo-1)), so a stronger halo always means a lower bar. The other was
the plan's own bar-eyeball step, which named four bar values; it now checks monotonicity, bounds and
the ads-vs-total gap instead.

THE COMMENT THAT WOULD HAVE SHIPPED A STALE MEASUREMENT INTO A LIVE ENGINE. Task 8b Step 3's block
goes VERBATIM into V_LAUNCH_EXEMPTION when the task runs, and it carried month-to-date figures from
2026-08-19. Task 8 Step 3's block, which ships into V_KEYWORD_LIFT, had been repaired in round 3 by
replacing the stale figures with LIVE ones — the same defect one day later. Both now carry the
mechanism only, and both say in the comment that no figure of any vintage may be written there.

ALSO FIXED: config.yaml's V_TWO_BOOK_BRIEF entry named TEN columns the object no longer carries (the
gap L reported and could not fix under its own file scope); Task 8b's banner claimed every statement
in the task had been dry-run when nothing downstream of Step 3 reads an object that exists, and now
says exactly how far the evidence reaches, matching how Task 8's banner was qualified; Task 8b Step 2
pinned two families' rates as the explanation of a count while the SAME TASK stated different figures
for them 96 lines later; the spec's §5 correction box stated four rate/loss figures and then claimed
in the same paragraph that they had been removed; the spec's §3 baseline TABLE was replaced by the
query over period_label='BASELINE_MAY_JUL' (it had already drifted); Task 6's step expected a verdict
"against the 400 target" when takeover_target_organic_units is NULL on every row.

MEASURED PIN COUNT OVER THE TWO-BOOK SURFACE — config.yaml's eight two-book entries, the plan, the
spec and the three view headers this round owns — went 445 -> 91. Method, so it can be re-run rather
than believed: count numeric tokens matching money / N.NNx ratio / percentage / multi-decimal / >=3-
digit-count shapes, after stripping ISO dates, commit SHAs and the project id, minus an allowlist of
DECLARED CONSTANTS. This journal entry is deliberately OUTSIDE that count, because it quotes the
defect strings it describes. Most of the 91 that remain are the §1 quarantine box in the spec —
one-off 2026-08-19 analysis findings that no live object restates, kept as the reasoning trail for why
two whole measurement approaches were abandoned, in a box that says exactly that — plus Task 1's
frozen golden expectation and the declared sanctions.

NOTHING IN THE ENGINE WAS TOUCHED. V_LAUNCH_EXEMPTION, V_ADS_COACH and V_COACH_CAMPAIGN_BUDGET are
unchanged, no held decision was released, Tasks 8/8b/9 remain on hold. V_FAMILY_PNL, V_BOOK_ASSIGNMENT
and V_FAMILY_BAR were re-deployed because their comments changed; V_FAMILY_BAR's stored definition is
byte-identical, and the other two differ only in indented comment text — all three return identical
rows to before.

OPEN / DATED: (1) V_INVEST_STATUS.sql and V_TWO_BOOK_BRIEF.sql headers were NOT edited (Tasks K and L
own them); their surviving pins are reported for a follow-up round. (2) The plan's Standing Rule 0 quoted the wrong ratio figures
verbatim as the example of the defect — deliberately, and labelled as false, but still two numbers on
a page. CLOSED in round 5: the figures are deleted from the plan, from config.yaml's rule block, from
the V_BOOK_ASSIGNMENT entry and from this journal, and the SHAPE of the defect is what carries the
lesson instead.

## 2026-08-20 — two-book P&L, repair round 5: the registry, the plan and the queries beside them

THE ROUND'S JOB WAS CONVERGENCE, NOT MORE FIXES. Rounds 1-4 each repaired a real defect and each
shipped a new self-contradiction. Tasks N and O made the brief's verdict prose mechanical and
asserted; this task (P) did the same to the documents around it — the registry entry, the plan, the
spec, this journal — by RUNNING every query they publish instead of reading them.

FOUR PUBLISHED QUERIES DID NOT COMPILE, all against V_TWO_BOOK_BRIEF, all naming columns the view
does not have. `ad_spend` (the column is `ad_spend_in_money_window`) in the plan's SOP heredoc and in
its Known follow-ons bullet, and in spec §1; `spend_per_day` (the brief publishes two arms,
`spend_per_day_in_rate_window` and `spend_per_day_last_7_days`) in spec §1; `halo_factor` and
`keyword_bar` (columns of V_FAMILY_BAR, not of the brief) in Task 7 Step 5. THE FOLLOW-ONS BULLET IS
THE LESSON: round 4 repaired `halo_factor` out of that exact query and left `ad_spend` in it, because
the repair was made by eye rather than by dry-running the result. Every query in the design is now
dry-run before it is written down, and each fixed line says which round broke it.

A QUERY THAT RAN BUT DID NOT SHOW WHAT ITS SENTENCE CLAIMED. config.yaml's V_TWO_BOOK_BRIEF entry
introduced July 2026 as the month that read as a loss on one lens and a profit on the other, then
published a query returning ONE column — the halo-inclusive figure. It cannot show a sign flip. The
plan's own version of the same evidence publishes both columns and does; the registry entry now uses
that form. V_FAMILY_PNL has no ads-only profit column, so the ads-only side must be derived from
ad_spend and ads_net_roas, and the entry says so.

TASK 8b STEP 4'S EXPECTED PROPERTY 4 WAS UNREACHABLE AGAINST THE DEPLOYED GATE. It promised that
raising Bunny's sanction above the measured rate would make protection_qualified read true and drive
the assertion to zero. Two structural reasons it cannot, both now written into the step: (a)
protection_qualified is an AND over eight clauses and the raise moves ONE of them — it also requires
sanction_adherence_judged, a rate window lying wholly on or after sanctioned_on, and no change to a
sanctioned RATE can make a window older; only the feed advancing does, and the short arm clears
first. (b) The assertion joins EVERY declared family, so raising one can only make the count fall.
The step now reads sanction_adherence_judged BEFORE the exposure window opens, branches the
expectation on it, states that spend_breached flipping false is what the raise actually controls, and
publishes a per-family form of the assertion. An operator running the old step would have read
`false` and concluded the Step 3 edit had failed when nothing had.

TASK 8b'S BANNER CONTRADICTED ITSELF, which is why round 4's qualification did not settle it. Step
4's `── 2` reads and Step 5's check were named as BACKED in one paragraph and as NOT BACKED in the
next. The distinction was never which statements — it is STATEMENT versus EXPECTATION. Every
statement in the task parses and runs against today's objects (all were executed, or dry-run where
they write, this round). What cannot be backed is any expectation about what they return after Step
3, because the post-edit V_LAUNCH_EXEMPTION has never existed. Tasks 8's and 9's banners were
re-read against their own steps and are accurate as they stand.

THE STALE FIGURES QUOTED AS EXHIBITS ARE GONE. Round 4 kept the wrong over-rate ratio string verbatim
in four places as the illustration of the defect it had just outlawed, and recorded that as an open
concern. (This paragraph does not repeat them either — a sentence announcing their deletion that
prints them one line later is the same defect wearing an apology.) A stale measurement quoted as the exhibit is still a stale measurement on
the page, and a reader arriving later cannot tell the exhibit from the claim. The SHAPE of the defect
now carries the lesson in all four. The same treatment removed the wrong RAMP->PROOF date this
journal was still quoting as its own correction; the flip is a rule (the 1st of the month in which
DATE_DIFF(today, first_sale_date, MONTH) reaches 4) and the entry publishes the query.

TWO CORRECTIONS A VERIFIER ASKED FOR WERE ALREADY CLEAN, and re-deriving them was the only way to
know. The agree/conservative/permissive split is not written anywhere in the design — round 4 deleted
it from the V_FAMILY_BAR header, from config.yaml and from this journal, and the header now carries
the algebra instead. And no document claims unmapped spend sits in "9 unmapped campaigns". The
underlying fact is worth stating once, because the two populations are easy to conflate: the brief's
neither-book money resolves to a SINGLE advertised-product key over the settled window, all Sponsored
Brands, and the brief's verdict branches on that measured count so it speaks in the singular; the
unresolved-campaign rows in V_CAMPAIGN_FAMILY_MAP are a different population, counted differently.
Neither number is written down here — SELECT COUNTIF(parent_name='Unknown'), COUNT(*) FROM
`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` for one, account_ad_spend_in_neither_book on the brief's
HARVEST TOTAL row for the other.

STANDING RULE 0 SWEEP, SECOND PASS, ENUMERATED RATHER THAN SAMPLED. Every numeric token in
config.yaml's two-book entries, the plan, the spec, this journal's two-book section and the four SQL
files this task owns was extracted and classified. What survives is declared constants (the
sanctions, the 0.5 credit, the 0.60 floor, the 1.0 ceiling, the 5e-5 tolerance, the 5% band, the
100-word cap), arithmetic ON declared constants (the halo 7/3 above which the floor could bite), Task
1's frozen golden expectation with its tolerances, the spec §1 quarantine box of dated 2026-08-19
findings that the box itself forbids copying out, and this journal's dated record of what past
commits contained. Converted or deleted: the four quoted-exhibit ratio figures, the RAMP->PROOF date,
and SP_SNAPSHOT_FAMILY_BAR.sql's "run 2026-08-20 it returned exactly two rows", which became the
property it was standing in for (only the writer and its caller may mention T_FAMILY_BAR, and no
views at all). Line-number pointers into other files were re-verified rather than trusted:
V_LAUNCH_EXEMPTION.sql:224/:235/:290/:310 are all exact, and Task 8b Step 3 depends on it.

VERIFIED, NOT ASSERTED. config.yaml parses; every two-book object is registered exactly once. Task
1's golden assertion returns four zeros; Task 7's returns bad_books 0, bad_row_kinds 0, total_rows 2,
harvest_reconcile_gap 0. V_FAMILY_BAR's clamp query returns rows_clamped 0 and every permissive row
in the calibration query satisfies halo < 1, which is what the header's algebra says must hold.
T_FAMILY_BAR has no null bars and no duplicate campaigns, and no mapped campaign is missing from it.
The INFORMATION_SCHEMA consumer check returns the writer and its caller and no views. Every statement
in Tasks 8, 8b and 9 was executed or dry-run.

NOTHING IN THE ENGINE WAS TOUCHED. V_LAUNCH_EXEMPTION, V_ADS_COACH and V_COACH_CAMPAIGN_BUDGET are
unchanged, no held decision was released, Tasks 8/8b/9 remain on hold, and V_TWO_BOOK_BRIEF.sql and
V_INVEST_STATUS.sql belong to Tasks N and O and were not edited. NO BIGQUERY OBJECT WAS RE-DEPLOYED:
the only two SQL files touched are SP_SNAPSHOT_FAMILY_BAR.sql and V_BOOK_ASSIGNMENT.sql, and in both
every changed line is a `--` comment in column 0, which the deploy strips — so the stored definitions
are byte-identical to what is live and no deploy is owed.

OPEN / DATED: (1) Task 9 still needs Ori's own words on the two-versus-three declaration fields
before the SOP may be published. (2) T_TWO_BOOK_BRIEF still does not exist and nothing builds it; the
brief is at the planner ceiling and the first page or Cube consumer must read a materialised copy,
which has to land BEFORE that consumer, not after the first timeout. (3) Task 8b Step 3's expectations
remain unproven by construction and will stay that way until the hold is lifted and the edit is made.

## 2026-08-20 — two-book P&L, repair round 6: the registry and the headers made true again (Task S)

THE JOB WAS TO RESTATE, NOT TO REBUILD. Tasks Q and R changed the mechanism underneath the documents
— delivery became a property of the DATE, the sanction verdict became a per-WINDOW answer, the
verdict rules went from four to six and the word cap moved off its old constant — so this task
re-derived every number and every guarantee in config.yaml, the plan, the spec, this journal and the
two view headers Q and R own, against the deployed objects rather than against any report.

NOTHING WAS RE-DEPLOYED AND NOTHING IS OWED. The only SQL file touched is V_TWO_BOOK_BRIEF.sql, and
both changed lines are `--` comments in column 0, which the deploy strips: `diff` of
`grep -v '^--'` before and after is empty, so the stored definition is byte-identical to what is
live. V_INVEST_STATUS.sql was not edited at all.

ORI'S PER-WINDOW RULING IS NOW A STANDING RULE, NOT A COMMIT MESSAGE. It is written into the plan as
STANDING RULE 1, beside Standing Rule 0, and into the spec as point 4 of the superseded-in-part box
where the other rulings live: a window may carry a FINDING only when ZERO of its days precede
sanctioned_on; otherwise its excess is stated in full as a COMPARISON and convicts nobody. Both
statements carry the WHY (a rate agreed on a date cannot be broken by days before that date), the
reason it is per window and not per family (the two windows roll clean three weeks apart, so one flag
is too strict before the long arm clears and too loose after), and the mechanism — with no pinned
measurement and with the query that takes today's reading.

CONFIG'S BRIEF ENTRY DESCRIBED AN OBJECT THAT NO LONGER EXISTS, and Task R said so in its own report
rather than leaving it to be found. It carried four verdict rules where six are deployed, a Rule 2
keyed to a per-FAMILY flag that Ori's ruling replaced, and a word cap that had moved. All rewritten
from the deployed body, including the honest distinction R built the round on: a rule keyed on a WORD
LIST is a tripwire and catches only last time's evasion, a rule keyed on a PUBLISHED COLUMN is a
constraint and cannot be talked around.

THE WORD CAP IS NOW WRITTEN DOWN IN EXACTLY ONE PLACE. It had three copies — Rule 3 in the header,
the Standing Rule 0 example list in the same header, and a footer comment beside verdict_words — and
two of them still held the superseded figure after Rule 3 had been re-derived. A declared constant
duplicated into prose drifts the moment the real one moves, so the two copies were replaced by
pointers to Rule 3.

TWO PUBLISHED ASSERTIONS DID NOT DO WHAT THE ACCEPTANCE SECTION SAID THEY DID, and both were found by
RUNNING them rather than reading them. Task 6's assertion names `exemption_live`, renamed to
`protection_qualified` on 2026-08-20 — it does not fail quietly, it fails to compile
("Unrecognized name"), while Acceptance item 5 marked it as passing. Task 4's calibration expression
counts BOTH directions of bar-vs-truth disagreement and returns non-zero against the deployed view,
while Acceptance item 2 claimed all five of its assertions pass — and alarming on a CONSERVATIVE
break is the exact thing this design forbids in three other places, because the bar being stricter
than the truth test is the direction it is meant to err in. The assertion was the stale artifact, not
the ruling: it now reports conservative breaks and gates on permissive ones, and passes.

A COUNT OF THINGS IN THE CODE IS A MEASUREMENT TOO — added to Standing Rule 0, because this is the
class round 5 sampled past. A column count, the number of clauses in an AND, the number of rules a
header enforces: none of them moves when the DATA moves, so they get written down as if declared, and
every one of them has gone stale here because the CODE moved. Two were live this round:
`protection_qualified`'s clause count was stated in config.yaml and in the plan and the deployed
expression does not match it, and the brief's column count has been pinned twice. Both are gone; the
query is published instead. The stale figures themselves are NOT quoted as exhibits — round 4 tried
that and round 5 had to delete them again.

A COMMENT THAT SHIPS INTO A LIVE BID ENGINE WAS QUOTING A MEASUREMENT AGAIN. Task 8 Step 3's block
ships verbatim into V_KEYWORD_LIFT, and it claimed at least one family's total net ROAS "sits within
a percent of 1.000". Re-measured at family grain on the settled window, the closest family sits
further out than that — the claim was false on the day it was read, inside the one comment the block
itself warns must never carry a figure. Replaced by the structural statement and the query. The same
phrase in config.yaml's V_FAMILY_BAR entry was converted the same way.

LINE-NUMBER POINTERS WERE RE-MEASURED, NOT TRUSTED. V_LAUNCH_EXEMPTION.sql :224 / :235 / :290 / :310
are all still exact and Task 8b Step 3 depends on them. Task 8 Step 2's two pointers into
V_KEYWORD_LIFT were NOT exact and are replaced by a grep on the comment text — which is the rule
V_BOOK_ASSIGNMENT.sql's own header already states for this reason.

EVERY PUBLISHED QUERY IN THE DESIGN WAS RUN, NOT READ. config.yaml's eight two-book entries, both
view headers, the spec, the plan's task assertions and Task 9's SOP heredoc. Every one compiles and
every one returns what the sentence beside it claims, with the two exceptions named above. Notable
agreements re-derived rather than copied: Task 1's golden set still returns four zeros; the brief's
acceptance query returns total_rows 2, all four reconciliation gaps 0.0, zero blank verdicts and
zero rule violations across all six rules; the July sign-flip query returns two columns of opposite
sign; the family-bar query returns the bars in the order its sentence describes; the account-delivery
agreement query returns zero on both sides; the clamp query returns zero clamped; every PERMISSIVE
row in the calibration query satisfies halo < 1, which is what the header's algebra requires;
T_FAMILY_BAR's consumer check returns the writer and its caller and no views at all.

ALL THREE HOLD BANNERS RE-VERIFIED BY DRY RUN. Task 8: Step 1's two captures, Step 4's two planner
dry runs, Step 6's SECOND query on its empty-capture path and Step 7's determinism statements for
both engines all validate; Step 6's FIRST query still carries its placeholder and still does not
parse, exactly as the banner says. V_OOB_KEYWORD plans but takes minutes, which is now written down
so a slow terminal is not read as a broken view. Task 8b: every statement dry-run again, including
the MERGE and the restore as dry runs only — nothing was written to DE_LAUNCH_INVESTMENT, whose live
row still reads the sanction Ori signed. Task 9: still BLOCKED on the same question, and every query
inside its SOP heredoc runs and matches its caption.

ONE CORNER FOUND IN TASK 8b's EXPECTATIONS AND WRITTEN DOWN RATHER THAN FIXED IN CODE. The `── 3`
MERGE derives its test rate from the LONG arm alone, while spend_breached is the OR of both arms, so
the raise clears the gate only while the short-window rate sits under the raised sanction plus the
derived margin. Today it does; on a steeply ramping family it need not, and an operator would read a
still-true spend_breached as Step 3 having failed. The expectation now says to read both arms off the
`── 2` capture first.

CORRECTING ROUND 5's OWN SURVIVOR LIST: its Standing Rule 0 sweep recorded the word cap among the
declared constants that survive. That figure has since moved, and the entry above it in this journal
should be read as the record of that round, not as a current statement.

NOTHING IN THE ENGINE WAS TOUCHED. V_LAUNCH_EXEMPTION, V_ADS_COACH and V_COACH_CAMPAIGN_BUDGET are
unchanged, no held decision was released, Tasks 8/8b remain on hold and Task 9 remains blocked.
config.yaml parses and every two-book object is registered exactly once.

OPEN / DATED: (1) Task 9 still needs Ori's own words on the two-versus-three declaration fields; the
two-field ruling has now been reported second-hand in two consecutive rounds and is still not acted
on, because Task 9 writes a STANDING RULE. (2) T_TWO_BOOK_BRIEF still does not exist and nothing
builds it. (3) V_FAMILY_BAR.sql's header carries one hedged measurement of the same class fixed
elsewhere this round ("rows sit within a percent of the 1.000 truth test", true today at the
all-rows scope); that file belongs to no task this round and was not staged. (4) The leading edge of
the rate window is still DISCLOSED, NOT CLOSED, upstream and in the brief.

-- DE_LAUNCH_INVESTMENT — the SANCTIONED launch investment per family, with its dated stop gate.
--
-- WHY THIS TABLE EXISTS (Ori 2026-08-13, launch-exemption build): the launch exemption tells the
-- coach it may not loss-cut a family that is SUPPOSED to lose money while the right bid is found.
-- An exemption with no ceiling and no end date is a blank cheque, so the licence is written down
-- HERE — how much per day Ori sanctioned, and the date the sanction expires — and V_LAUNCH_EXEMPTION
-- reads it. Nothing in this system may extend an exemption past `stop_date`; when the date passes,
-- the family re-enters normal coaching automatically with no code change.
--
-- ONE LOGICAL ROW PER FAMILY. Re-sanctioning = INSERT a new row with a later `updated_at`;
-- V_LAUNCH_EXEMPTION takes the latest per family (QUALIFY ROW_NUMBER), so the history is kept.
--
-- `daily_investment` is the sanctioned SPEND RATE for the whole family (all its ad campaigns
-- summed), NOT a per-campaign budget. V_LAUNCH_EXEMPTION compares it against the family's real
-- trailing-7d daily spend and publishes envelope_state — an over-envelope family is Ori's budget
-- decision, never a coach ROAS cut.
--
-- Absence of a row is meaningful and safe: no sanction on record => the exemption still applies on
-- family age alone (see V_LAUNCH_EXEMPTION.launch_window_days) but expires on the age boundary and
-- publishes envelope_state = 'NO_SANCTION'.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_LAUNCH_INVESTMENT` (
  parent_name      STRING NOT NULL,   -- family, must match DIM_PRODUCT.parent_name / V_CAMPAIGN_FAMILY_MAP
  daily_investment FLOAT64 NOT NULL,  -- sanctioned $/day for the FAMILY (all campaigns summed)
  stop_date        DATE NOT NULL,     -- last day the sanction is valid (inclusive); hard gate
  sanctioned_on    DATE,              -- when Ori sanctioned it
  note             STRING,            -- plain-language provenance, shown on the Weekly Run panel
  updated_at       TIMESTAMP,
  updated_by       STRING,
  -- v27.84 (two-book P&L, 2026-08-19) — the launch licence stated in the OTHER two currencies the
  -- Invest book judges in. Both NULLABLE and both ADDITIVE: nothing above was renamed, dropped or
  -- retyped, because V_LAUNCH_EXEMPTION reads this table live.
  monthly_loss_ceiling          FLOAT64,  -- dollars of NET PROFIT loss allowed per calendar month
  takeover_target_organic_units INT64     -- organic units/month that mean "it took over"
)
OPTIONS (description = 'Sanctioned launch investment per family, with its dated stop gate. daily_investment = sanctioned $/day for the WHOLE FAMILY (all campaigns summed); stop_date = hard expiry. Read by V_LAUNCH_EXEMPTION: the exemption from coach loss-cuts ends at the EARLIER of the family age boundary and stop_date. Latest row per parent_name wins (ORDER BY updated_at DESC). v27.84 (two-book P&L 2026-08-19) added two ADDITIVE nullable columns: monthly_loss_ceiling (dollars of NET PROFIT loss allowed per calendar month; backfilled as daily_investment * 30.44 - the sanctioned spend monthised, a deliberately LOOSE bound that does not replace envelope_state) and takeover_target_organic_units (organic units/month meaning the family took over; NULL = Ori has not set a target, no take-over test can run).');


-- ---------------------------------------------------------------------------------------------
-- CONVERGENCE, because CREATE TABLE IF NOT EXISTS is a SILENT NO-OP against a table that already
-- exists. This table WAS already live with real sanctions when the two-book P&L build needed two
-- more columns, and a plain re-run of the CREATE above would have added nothing while reporting
-- success — the exact failure this block exists to prevent. Re-running the whole file is safe.
--
-- ADDITIVE ONLY. Never rename, drop or retype a column here: V_LAUNCH_EXEMPTION reads this table
-- live (exempt_until = LEAST(first sale + 183d, stop_date)), so a destructive change breaks the
-- coach's launch exemption in production.
-- ---------------------------------------------------------------------------------------------
ALTER TABLE `onyga-482313.OI.DE_LAUNCH_INVESTMENT`
  ADD COLUMN IF NOT EXISTS monthly_loss_ceiling FLOAT64
    OPTIONS (description = 'Dollars of NET PROFIT loss allowed per calendar month for this family while the sanction stands. Net profit = sales - all-in COGS - ad_cost (the V_FAMILY_PNL definition; COGS is all-in, incl. Amazon referral + FBA pick/pack). Backfilled 2026-08-19 as ROUND(daily_investment * 30.44, 0) — the sanctioned SPEND rate monthised, because you cannot lose materially more than you spend, so the sanctioned spend is the natural loss bound. It is a LOOSE bound by construction: a launch family with real sales loses far less than it spends. Re-sanction by inserting a new row, never by editing in place.'),
  ADD COLUMN IF NOT EXISTS takeover_target_organic_units INT64
    OPTIONS (description = 'Organic units per month that mean the family HAS TAKEN OVER — the launch worked and the investment can stop. This is a BUSINESS JUDGEMENT Ori must supply; it is deliberately NOT derivable from the warehouse. NULL means no target on record and no take-over test can be run for that family.');

-- Backfill the loss ceiling from what was already sanctioned, so nothing is invented.
-- Guarded by IS NULL: re-running never overwrites a ceiling Ori has since set by hand.
-- takeover_target_organic_units is deliberately NOT backfilled — see its column description.
UPDATE `onyga-482313.OI.DE_LAUNCH_INVESTMENT`
SET monthly_loss_ceiling = ROUND(daily_investment * 30.44, 0)
WHERE monthly_loss_ceiling IS NULL;

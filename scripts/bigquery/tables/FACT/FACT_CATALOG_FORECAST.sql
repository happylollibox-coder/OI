CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_CATALOG_FORECAST`
(
  -- WHAT THE CATALOG SAID, ON THE DAY IT SAID IT. Forecast chain step 3.
  -- V_CATALOG_FORECAST is a LIVE view over CREATE-OR-REPLACE snapshots: ask it tomorrow and it
  -- answers from tomorrow's data, so a prediction does not survive the query that produced it and
  -- CANNOT BE SCORED. Per-link scoring -- which is the whole reason 2.0.1 made the answer a chain --
  -- requires the forecast to outlive the moment. This ledger is that memory.
  -- APPEND-ONLY. A forecast that turned out wrong is the most valuable row in the table; nothing
  -- here is ever corrected, only superseded by a later forecast_on.
  forecast_on         DATE      OPTIONS (description = "The as-of day the Catalog made this claim. Partition key. NOT the window it describes."),
  captured_at         TIMESTAMP OPTIONS (description = "When this row was written here. Provenance, never a business date -- the append-then-prune dedupe keys on it."),
  source              STRING    OPTIONS (description = "ORCHESTRATOR | MANUAL -- how this row arrived."),
  source_detail       STRING    OPTIONS (description = "Exactly what was read and when, so any row can be re-derived."),

  -- the window this claim is about
  window_start        DATE,
  window_end          DATE,
  window_days         INT64,
  season              STRING    OPTIONS (description = "The season of the window, by majority of days. A window straddling two seasons is claimed for the one holding most of it, and the row says which."),
  settles_on          DATE      OPTIONS (description = "window_end plus the channel's settle lag (SP 7, SB 14). Scoring before this date marks the Catalog down for sales that have not landed."),

  -- the subject
  family              STRING,
  campaign_id         STRING    OPTIONS (description = "STRING end to end: campaign ids exceed 2^53 and lose precision as a number."),
  campaign_name       STRING    OPTIONS (description = "Recorded for reading, NEVER a join key -- ids in this account carry more than one name."),
  keyword_id          STRING,
  target_text         STRING,
  match_type          STRING,
  channel             STRING,

  -- the price the Catalog chose, and the shape around it
  best_cpc            FLOAT64   OPTIONS (description = "The CPC the Catalog says maximises contribution. The Catalog chooses the price; the Brain never sends one."),
  ceiling_cpc         FLOAT64   OPTIONS (description = "Where contribution reaches zero -- the house's own affordable_cpc, reproduced by the chain rather than replaced."),
  best_cpc_closed_form FLOAT64  OPTIONS (description = "ceiling * e/(1+e), the provable optimum the grid is pinned against."),
  best_cpc_at_grid_edge BOOL    OPTIONS (description = "TRUE means the optimum may lie beyond the highest price this keyword was ever paid -- 'as far as the evidence goes', not 'the best price'."),
  optimum_below_floor BOOL      OPTIONS (description = "TRUE means the profit-maximising price is under the platform minimum: the subject is not worth even its floor."),

  -- THE CHAIN, PREDICTED FOR THE WHOLE WINDOW. Each link is stored separately because a wrong
  -- contribution must name its own fault (2.0.1: "maybe more clicks, maybe less cpc, maybe
  -- something else"). A single stored total would say only that the money was wrong.
  predicted_clicks         FLOAT64,
  predicted_orders         FLOAT64,
  predicted_cost           FLOAT64,
  predicted_gross_profit   FLOAT64,
  predicted_ads_net_roas   FLOAT64,
  predicted_net_roas       FLOAT64,
  predicted_contribution   FLOAT64 OPTIONS (description = "Contribution to FAMILY net profit at half halo credit -- the objective, and the same credit the engine's bar uses."),

  -- the inputs, so a wrong link can be traced to the number that produced it
  cvr_used            FLOAT64,
  gp_per_order_used   FLOAT64,
  gp_per_click_modelled FLOAT64,
  elasticity          FLOAT64,
  baseline_cpc        FLOAT64,
  baseline_clicks_per_day FLOAT64,
  halo_factor         FLOAT64,
  keyword_bar         FLOAT64,
  halo_credit         FLOAT64   OPTIONS (description = "Stored so a later change to the shared credit is visible in the record rather than silently re-scoring old claims."),

  -- disclosure, kept with the claim because a forecast without its basis cannot be weighed later
  rate_basis          STRING,
  clicks_basis        STRING,
  elasticity_basis    STRING,
  sentence            STRING
)
PARTITION BY forecast_on
CLUSTER BY family, campaign_id
OPTIONS (description = "THE CATALOG'S MEMORY: every claim it made, on the day it made it, so the claim can be scored later. Forecast chain step 3 (spec docs/superpowers/specs/2026-08-25-catalog-forecast-chain-design.md, THREE_LAYERS.md 2.0.1 and 6). WHY IT MUST EXIST: V_CATALOG_FORECAST is a live view over CREATE-OR-REPLACE snapshots, so asking it tomorrow returns tomorrow's answer and yesterday's prediction is gone -- the actuals survive, the forecast does not, and per-link scoring is impossible without both. APPEND-ONLY AND NEVER CORRECTED: a forecast that turned out wrong is the most valuable row here. Each LINK of the chain is stored separately, which is the point of making the answer a chain at all -- a wrong contribution must name which link broke rather than only reporting that the money was wrong. settles_on carries the channel's settle lag so nothing is scored before the sales have landed. Written by SP_APPEND_CATALOG_FORECAST. Read by V_CATALOG_FORECAST_OUTCOME. Decides nothing and can move no bid.");

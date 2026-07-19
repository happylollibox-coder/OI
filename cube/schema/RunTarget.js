// Cube: RunTarget — one row per (campaign, target) for the merged Weekly Run step-4 card. Keywords AND
// auto groups, NEW campaigns AND mature, from T_RUN_TARGET. Each target carries two measure windows
// (row 2 = recent, row 3 = trend) with CPC · clicks · TOS% · units · net ROAS, plus the unified bid
// suggestion (launch controller for new, coacher for mature keywords). Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md.
cube(`RunTarget`, {
  sql: `SELECT campaign_id, keyword_id, target_text, targeting_type, is_auto_group, is_new, anchor_date,
               match_type, ad_group_id, current_bid, suggested_bid, bid_action, bid_reason,
               r2_spend, r2_cpc, r2_clk, r2_ctr, r2_tos, r2_units, r2_roas, r2_roas_corr, r2_impr, r2_acos,
               r3_spend, r3_cpc, r3_clk, r3_ctr, r3_tos, r3_units, r3_roas, r3_roas_corr, r3_impr, r3_acos,
               pk_spend, pk_cpc, pk_clk, pk_ctr, pk_tos, pk_units, pk_roas, pk_roas_corr, pk_acos
        FROM \`onyga-482313.OI.T_RUN_TARGET\``,

  refreshKey: { every: `30 minutes` },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId:        { sql: `CONCAT(campaign_id, '|', COALESCE(keyword_id,'none'))`, type: `string`, primaryKey: true },
    campaignId:   { sql: `campaign_id`,   type: `string` },
    keywordId:    { sql: `keyword_id`,    type: `string` },
    targetText:   { sql: `target_text`,   type: `string` },
    isAutoGroup:  { sql: `is_auto_group`, type: `boolean` },
    isNew:        { sql: `is_new`,        type: `boolean` },
    anchorDate:   { sql: `CAST(anchor_date AS STRING)`, type: `string` },
    matchType:    { sql: `match_type`,    type: `string` },
    adGroupId:    { sql: `ad_group_id`,   type: `string` },
    currentBid:   { sql: `current_bid`,   type: `number` },
    suggestedBid: { sql: `suggested_bid`, type: `number` },
    bidAction:    { sql: `bid_action`,    type: `string` },
    bidReason:    { sql: `bid_reason`,    type: `string` },
    r2Spend: { sql: `r2_spend`, type: `number` }, r2Cpc: { sql: `r2_cpc`, type: `number` }, r2Clk: { sql: `r2_clk`, type: `number` },
    r2Ctr: { sql: `r2_ctr`, type: `number` }, r2Tos: { sql: `r2_tos`, type: `number` }, r2Units: { sql: `r2_units`, type: `number` },
    r2Roas: { sql: `r2_roas`, type: `number` }, r2RoasCorr: { sql: `r2_roas_corr`, type: `number` }, r2Impr: { sql: `r2_impr`, type: `number` }, r2Acos: { sql: `r2_acos`, type: `number` },
    r3Spend: { sql: `r3_spend`, type: `number` }, r3Cpc: { sql: `r3_cpc`, type: `number` }, r3Clk: { sql: `r3_clk`, type: `number` },
    r3Ctr: { sql: `r3_ctr`, type: `number` }, r3Tos: { sql: `r3_tos`, type: `number` }, r3Units: { sql: `r3_units`, type: `number` },
    r3Roas: { sql: `r3_roas`, type: `number` }, r3RoasCorr: { sql: `r3_roas_corr`, type: `number` }, r3Impr: { sql: `r3_impr`, type: `number` }, r3Acos: { sql: `r3_acos`, type: `number` },
    pkSpend: { sql: `pk_spend`, type: `number` }, pkCpc: { sql: `pk_cpc`, type: `number` }, pkClk: { sql: `pk_clk`, type: `number` },
    pkCtr: { sql: `pk_ctr`, type: `number` }, pkTos: { sql: `pk_tos`, type: `number` }, pkUnits: { sql: `pk_units`, type: `number` },
    pkRoas: { sql: `pk_roas`, type: `number` }, pkRoasCorr: { sql: `pk_roas_corr`, type: `number` }, pkAcos: { sql: `pk_acos`, type: `number` },
  },
});

// cache-bust: PROBE — raise under-clicked (clk3<4) keywords even when dark (2026-07-19 v6)

// cache-bust v7: corrected-ROAS decisions

// cache-bust v8: profitable target holds (no brake) while dark

// cache-bust v9: anchor advances to current LA day within last 2h (2026-07-18)

// cache-bust v10: anchor_date dimension

// cache-bust v11: true impressions for CTR/TOS (targeting report)

// cache-bust v12: FACT-impression fallback when td missing (SB)

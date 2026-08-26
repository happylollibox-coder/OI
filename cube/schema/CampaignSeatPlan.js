// Cube: CampaignSeatPlan — from V_CAMPAIGN_SEAT_PLAN
// How many seats each campaign is entitled to, and what those seats are FOR.
// Brain-layer rule (Ori, 2026-08-25): allowance is EARNED. A campaign clearing its family bar
// earns 20% of its budget as allowance and spends it on unprofitable keywords at $7 a seat; a
// campaign under its bar earns nothing and gets ONE seat aimed at its most profitable keyword,
// with the bid free to move either way toward the campaign's break-even.
// Read by the Weekly Run page (Seats section).
cube(`CampaignSeatPlan`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_CAMPAIGN_SEAT_PLAN\``,

  refreshKey: { every: '1 hour' },

  measures: {
    campaigns:      { sql: `campaign_id`, type: `countDistinct`, description: `Campaigns` },
    seatsAllowed:   { sql: `seats_allowed`, type: `sum`, description: `Seats this campaign may hold` },
    budgetPerDay:   { sql: `budget_per_day`, type: `sum`, description: `Daily budget` },
    allowancePerDay:{ sql: `allowance_per_day`, type: `sum`, description: `20% of budget, only if it clears the bar` },
    settledCost:    { sql: `settled_cost`, type: `sum`, description: `Ad spend over the settled 28 days` },
    settledGrossProfit: { sql: `settled_gross_profit`, type: `sum`, description: `Gross profit over the settled 28 days` },
  },

  dimensions: {
    campaignId:   { sql: `campaign_id`, type: `string`, primaryKey: true, shown: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    family:       { sql: `family`, type: `string` },
    seatPurpose:  { sql: `seat_purpose`, type: `string`,
                    description: `EXPERIMENT (earned allowance), REPAIR (one seat on its best keyword), UNMEASURED` },
    profitable:   { sql: `profitable`, type: `boolean`, description: `Clears its family bar over the settled window` },
    barExempt:    { sql: `bar_exempt`, type: `boolean` },
    adsNetRoas:   { sql: `ads_net_roas`, type: `number` },
    bar:          { sql: `bar`, type: `number` },
    budget:       { sql: `budget_per_day`, type: `number` },
    allowance:    { sql: `allowance_per_day`, type: `number` },
    seats:        { sql: `seats_allowed`, type: `number` },

    // the repair seat's subject — null unless seat_purpose = REPAIR
    repairKeywordId:    { sql: `repair_keyword_id`, type: `string` },
    repairTargetText:   { sql: `repair_target_text`, type: `string` },
    repairGpPerClick:   { sql: `repair_gp_per_click`, type: `number` },
    repairCurrentBid:   { sql: `repair_current_bid`, type: `number` },
    repairTargetCpc:    { sql: `repair_target_cpc`, type: `number` },
    repairAffordableCpc:{ sql: `repair_affordable_cpc`, type: `number`,
                          description: `Uncapped affordable price; the target is bounded to half-to-double the current bid` },
    repairEvidenceOrders:{ sql: `repair_evidence_orders`, type: `number` },
    repairDirection:    { sql: `repair_direction`, type: `string`, description: `RAISE, LOWER or HOLD` },
    repairTargetCapped: { sql: `repair_target_capped`, type: `boolean`,
                          description: `TRUE when the affordable price sits outside the half-to-double band and the target was bounded` },
    sentence:     { sql: `sentence`, type: `string`, description: `The row in one plain sentence (§9)` },
  },
});

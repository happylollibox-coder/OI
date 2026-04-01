// Cube: CoachThresholds - from DE_COACH_THRESHOLDS
// User-editable thresholds for the Ads Coach decision engine
// Exposes all threshold rows for dashboard read (threshold editor on Learn page)
cube(`CoachThresholds`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DE_COACH_THRESHOLDS\``,

  refreshKey: { every: '5 minutes' },

  measures: {
    count: { type: `count`, description: `Number of threshold rows` },
  },

  dimensions: {
    // Key
    thresholdKey: { sql: `threshold_key`, type: `string`, primaryKey: true },
    strategyId: { sql: `strategy_id`, type: `string` },
    productFamily: { sql: `product_family`, type: `string` },

    // Values
    thresholdValue: { sql: `threshold_value`, type: `number` },
    description: { sql: `description`, type: `string` },

    // Suggestions
    suggestedValue: { sql: `suggested_value`, type: `number` },
    suggestedAt: { sql: `CAST(suggested_at AS STRING)`, type: `string` },
    suggestionReason: { sql: `suggestion_reason`, type: `string` },

    // Seasonal
    peakMultiplier: { sql: `peak_multiplier`, type: `number` },
    boostPeakMultiplier: { sql: `boost_peak_multiplier`, type: `number` },

    // Meta
    source: { sql: `source`, type: `string` },
    updatedAt: { sql: `CAST(updated_at AS STRING)`, type: `string` },
    updatedBy: { sql: `updated_by`, type: `string` },
  },
});

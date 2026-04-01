// Cube: ChangeLog - from DIM_EXPERIMENT_CHANGE_LOG
// Used for change_log.json
cube(`ChangeLog`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG\``,

  refreshKey: { every: '15 minutes' },

  measures: {
    count: {
      type: `count`,
      description: `Number of change log entries`,
    },
  },

  dimensions: {
    changeId: {
      sql: `change_id`,
      type: `string`,
      description: `Unique change identifier`,
    },
    experimentId: {
      sql: `experiment_id`,
      type: `string`,
      description: `Experiment that was changed`,
    },
    changeDate: {
      sql: `CAST(change_date AS TIMESTAMP)`,
      type: `time`,
      description: `Date of the change`,
    },
    changeType: {
      sql: `change_type`,
      type: `string`,
      description: `Type of change (e.g. bid, budget, keyword)`,
    },
    campaignId: {
      sql: `campaign_id`,
      type: `string`,
      description: `Campaign affected (if applicable)`,
    },
    fieldChanged: {
      sql: `field_changed`,
      type: `string`,
      description: `Field that was modified`,
    },
    oldValue: {
      sql: `old_value`,
      type: `string`,
      description: `Previous value`,
    },
    newValue: {
      sql: `new_value`,
      type: `string`,
      description: `New value after change`,
    },
    reason: {
      sql: `reason`,
      type: `string`,
      description: `Reason for the change`,
    },
    source: {
      sql: `source`,
      type: `string`,
      description: `Source of the change (manual, automation)`,
    },
    createdAt: {
      sql: `CAST(created_at AS TIMESTAMP)`,
      type: `time`,
      description: `When the record was created`,
    },
  },
});

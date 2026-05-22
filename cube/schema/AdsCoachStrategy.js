cube('AdsCoachStrategy', {
  sql: `
    SELECT
      s.coach_mode,
      s.north_star,
      s.north_star_metric,
      s.north_star_target,
      s.task_id,
      s.task_name,
      s.task_description,
      s.capability,
      s.capability_direction,
      s.display_order,
      s.mitigation,
      s.emoji
    FROM \`onyga-482313.OI.DIM_COACH_STRATEGY\` s
  `,

  dimensions: {
    coachMode: { sql: `coach_mode`, type: `string`, primaryKey: true },
    northStar: { sql: `north_star`, type: `string` },
    northStarMetric: { sql: `north_star_metric`, type: `string` },
    northStarTarget: { sql: `north_star_target`, type: `number` },
    taskId: { sql: `task_id`, type: `string`, primaryKey: true },
    taskName: { sql: `task_name`, type: `string` },
    taskDescription: { sql: `task_description`, type: `string` },
    capability: { sql: `capability`, type: `string` },
    capabilityDirection: { sql: `capability_direction`, type: `string` },
    displayOrder: { sql: `display_order`, type: `number` },
    mitigation: { sql: `mitigation`, type: `string` },
    emoji: { sql: `emoji`, type: `string` },
  },
});

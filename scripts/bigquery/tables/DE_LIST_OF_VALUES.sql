CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_LIST_OF_VALUES`
(
  lov_set STRING OPTIONS(description="The category or set this list of values belongs to, e.g., 'SHIPMENT_TYPES'"),
  lov_desc STRING OPTIONS(description="Description of this list of values set"),
  value_id STRING OPTIONS(description="The primary ID of the item, e.g., 'SLOW_SEA'"),
  value_caption STRING OPTIONS(description="The display name or caption for the item, e.g., 'Slow Sea'"),
  is_default BOOLEAN OPTIONS(description="Whether this is the default selection for this LOV set"),
  attr1_name STRING OPTIONS(description="Name of the first optional attribute"),
  attr1_value STRING OPTIONS(description="Value of the first optional attribute"),
  attr2_name STRING OPTIONS(description="Name of the second optional attribute"),
  attr2_value STRING OPTIONS(description="Value of the second optional attribute"),
  update_date DATETIME OPTIONS(description="The date and time this record was last modified")
)
OPTIONS(
  description="Data Entry table for generic List of Values (LOV) configuration used in applications and dashboards"
);

CREATE TEMP TABLE tmp_budget_pool AS SELECT 'A' AS product, 800 AS remaining_budget;
CREATE TEMP TABLE tmp_type1_inprod AS SELECT 'A' AS product, 300 AS ship_qty;

UPDATE tmp_budget_pool budget SET remaining_budget = remaining_budget - t1.ship_qty
FROM tmp_type1_inprod t1 WHERE budget.product = t1.product;

SELECT * FROM tmp_budget_pool;

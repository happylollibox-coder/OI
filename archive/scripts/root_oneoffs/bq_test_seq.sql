CREATE TEMP TABLE tmp_budget_pool AS SELECT 'A' AS product, 800 AS remaining_budget;
CREATE TEMP TABLE tmp_type1_ready AS SELECT 'A' AS product, 0 AS ship_qty;
CREATE TEMP TABLE tmp_type1_inprod AS SELECT 'A' AS product, 300 AS ship_qty;
CREATE TEMP TABLE tmp_type2 AS SELECT 'A' AS product, 0 AS ship_qty;
CREATE TEMP TABLE tmp_type3_ready AS SELECT 'A' AS product, 0 AS ship_qty;
CREATE TEMP TABLE tmp_type3_inprod AS SELECT 'A' AS product, 70 AS ship_qty;
CREATE TEMP TABLE tmp_type3_po AS SELECT 'A' AS product, 0 AS ship_qty;

UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type1_ready t1 WHERE budget.product = t1.product;
UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type1_inprod t1 WHERE budget.product = t1.product;
UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type2 t1 WHERE budget.product = t1.product;
UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type3_ready t1 WHERE budget.product = t1.product;
UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type3_inprod t1 WHERE budget.product = t1.product;
UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type3_po t1 WHERE budget.product = t1.product;

SELECT * FROM tmp_budget_pool;

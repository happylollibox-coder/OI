CREATE TEMP TABLE tmp_type4 AS SELECT 'A' AS product, 60 AS ship_qty UNION ALL SELECT 'A', 60;
CREATE TEMP TABLE tmp_mfr_pool AS SELECT 'A' AS product, 100 AS remaining_ready;

UPDATE tmp_mfr_pool pool SET pool.remaining_ready = pool.remaining_ready - t4.total_ship_qty
FROM (SELECT product, SUM(ship_qty) AS total_ship_qty FROM tmp_type4 GROUP BY 1) t4 
WHERE pool.product = t4.product AND pool.remaining_ready > 0;

SELECT * FROM tmp_mfr_pool;

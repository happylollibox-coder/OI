-- ═══════════════════════════════════════════════════════════════
-- DIM_PRODUCT_CREATIVES
-- ═══════════════════════════════════════════════════════════════
-- Stores Amazon Ads brand assets and video media IDs per product family.
-- Used to automatically populate creative fields when exporting Bulksheets.

CREATE TABLE IF NOT EXISTS `onyga-482313`.OI.DIM_PRODUCT_CREATIVES (
    product_family STRING OPTIONS(description="Product family (e.g., BOX, ME, FRESH, BOTTLE)"),
    brand_entity_id STRING OPTIONS(description="Amazon Brand Entity ID"),
    brand_name STRING OPTIONS(description="Brand Name used in ads"),
    video_asset_id STRING OPTIONS(description="Amazon Video Media Asset ID"),
    updated_at TIMESTAMP OPTIONS(description="Timestamp of last update")
);

-- Seed initial data from known active Amazon SB Video campaigns
MERGE `onyga-482313`.OI.DIM_PRODUCT_CREATIVES T
USING (
  SELECT 'BOX' as product_family, 'ENTITY1QO3J3WCA4V66' as brand_entity_id, 'Happy Lolli' as brand_name, 'amzn1.assetlibrary.asset1.773ef4f0dbb61e3b6f98fae98eece256:version_v1' as video_asset_id UNION ALL
  SELECT 'ME', 'ENTITY1QO3J3WCA4V66', 'Happy Lolli', 'amzn1.assetlibrary.asset1.e13ef25bafa2ba5112c14eaab4537b6a:version_v1' UNION ALL
  SELECT 'FRESH', 'ENTITY1QO3J3WCA4V66', 'Happy Lolli', 'amzn1.assetlibrary.asset1.36e5d82ad268c5a5732a691e2a25dfbd:version_v1' UNION ALL
  SELECT 'BOTTLE', 'ENTITY1QO3J3WCA4V66', 'Happy Lolli', 'amzn1.assetlibrary.asset1.c3f0828e76072e7d74243fe377e19b58:version_v1'
) S
ON T.product_family = S.product_family
WHEN MATCHED THEN
  UPDATE SET 
    brand_entity_id = S.brand_entity_id,
    brand_name = S.brand_name,
    video_asset_id = S.video_asset_id,
    updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
  INSERT (product_family, brand_entity_id, brand_name, video_asset_id, updated_at)
  VALUES (S.product_family, S.brand_entity_id, S.brand_name, S.video_asset_id, CURRENT_TIMESTAMP());

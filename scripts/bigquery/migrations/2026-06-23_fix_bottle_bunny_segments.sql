-- =============================================
-- Migration: fix mis-derived product segments for Bottle & Bunny (2026-06-23)
-- =============================================
--
-- Problem: SP_DERIVE_PRODUCT_SEGMENTS derived seg_product_type from each family's
--   ad-converting search terms. Some generic/plush terms map to "Toys" in
--   DE_PRODUCT_TYPE_KEYWORDS, so it tagged:
--     Bottle  → "Toys"          (actually a Truth-or-Dare TABLETOP/SOCIAL GAME, ages 10+)
--     Bunny   → "Toys,Keychain" (actually a plush KEYCHAIN / backpack charm)
--   This gave V_RESEARCH_RANKED a wrong +30 pt_score on toy/young-kid terms for them.
--
-- Fix: manual override of seg_product_type (SP_DERIVE only fills NULLs, so manual
--   values are preserved going forward). Labels chosen to match how each family's real
--   converting terms are tagged (truth or dare / sleepover games → "Social Game";
--   keychain cute / plush keychain → "Keychain"), so pt_score now boosts the right terms.
--   Ages left as-is (already tween/teen). V_RESEARCH_RANKED is a live view → reflects immediately.
--
-- Re-run this whenever DIM_PRODUCT is reloaded from source. See [[fact_oi_family_product_identities]].
-- Deeper option (not done): audit DE_PRODUCT_TYPE_KEYWORDS so generic/plush terms stop mapping to Toys.
-- =============================================

UPDATE `onyga-482313.OI.DIM_PRODUCT`
SET seg_product_type = 'Social Game'
WHERE parent_name = 'Bottle' AND is_active = true;

UPDATE `onyga-482313.OI.DIM_PRODUCT`
SET seg_product_type = 'Keychain'
WHERE parent_name = 'Bunny' AND is_active = true;

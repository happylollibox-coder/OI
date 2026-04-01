-- =============================================
-- OI Database Project - Load Product Cost Data
-- =============================================
--
-- Purpose: Load manual product cost and logistics data into staging table
-- This script inserts data from the provided spreadsheet/image
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-01-17 (LolliME cost data added)
--
-- =============================================

-- Clear existing data (optional - comment out if you want to append)
-- TRUNCATE TABLE `onyga-482313.OI.STG_PRODUCT_COST_DATA`;

-- Insert product cost and logistics data
INSERT INTO `onyga-482313.OI.STG_PRODUCT_COST_DATA` 
  (asin, parent_name, sku, cost_of_goods, shipping_cost, manufacture_day, shipment_days)
VALUES
  ('B09XQ56RK5', 'lollibox', 'Purple Box 1', 11.9, 1.9, 32, 30),
  ('B0CR6N3WRC', 'lollibox', 'Pink Box + Card', 11.1, 2.0, 32, 30),
  ('B0C1VLXYBP', 'lollibox', 'White Box + Card', 12.5, 2.6, 32, 30),
  ('B0DJFG5ZJ7', 'fresh', 'Blue LolliBox', 13.0, 2.2, 42, 30),
  ('B0D7N31M6S', 'fresh', 'Fresh in Pink', 10.5, 3.0, 42, 30),
  ('B0D7N2MLDP', 'fresh', 'Fresh in Beige', 5.03, 1.5, 30, 30),
  ('B0F4KCCSWN', 'Truth Or Dare', 'Truth Dare Bottle', 6.9, 2.3, 30, 30),
  ('B0F9XDSVYB', 'LolliME', 'Purple LolliME', 6.9, 2.3, 30, 30),
  ('B0F9XFXQRW', 'LolliME', 'Pink LolliME', 6.9, 2.3, 30, 30),
  ('B0F9X95K5H', 'LolliME', 'Mint LolliME', 6.9, 2.3, 30, 30);

-- Note: All products now have complete cost data (LolliME values updated 2026-01-17)
-- After loading, run SP_UPDATE_PRODUCT_COST_DATA to merge this data into DIM_PRODUCT

-- =============================================
-- To execute this data load and update:
-- =============================================
-- 1. Run this INSERT statement to load data into STG_PRODUCT_COST_DATA
-- 2. Run: CALL `onyga-482313.OI.SP_UPDATE_PRODUCT_COST_DATA`();
-- 3. Verify: SELECT asin, parent_name, sku, cost_of_goods, shipping_cost 
--            FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IN ('B09XQ56RK5', 'B0CR6N3WRC', ...);
-- =============================================


-- =============================================
-- OI Database Project - Admin Queries
-- =============================================
--
-- Purpose: Administrative queries for data exploration, DDL generation, and validation
-- Contents: DDL queries, sample data queries, source data exploration
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
--
-- =============================================
--

--MANUAL SQP CHECK
SELECT 
  Reporting_Date,
  COUNTIF(ASIN = 'B09XQ56RK5') as B09XQ56RK5,
  COUNTIF(ASIN = 'B0C1VLXYBP') as B0C1VLXYBP,
  COUNTIF(ASIN = 'B0CR6N3WRC') as B0CR6N3WRC,
  COUNTIF(ASIN = 'B0D7N2MLDP') as B0D7N2MLDP,
  COUNTIF(ASIN = 'B0D7N31M6S') as B0D7N31M6S,
  COUNTIF(ASIN = 'B0DJFG5ZJ7') as B0DJFG5ZJ7,
  COUNTIF(ASIN = 'B0F4KCCSWN') as B0F4KCCSWN,
  COUNTIF(ASIN = 'B0F9X95K5H') as B0F9X95K5H,
  COUNTIF(ASIN = 'B0F9XDSVYB') as B0F9XDSVYB,
  COUNTIF(ASIN = 'B0F9XFXQRW') as B0F9XFXQRW,
  COUNT(*) as Total
FROM  `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
--WHERE Reporting_Date >= '2025-12-13'
GROUP BY Reporting_Date
ORDER BY Reporting_Date DESC
-- Run the stored procedure to copy da
-- DDL generation queries
  
SELECT 
    table_name,ddl,    CONCAT('DROP VIEW IF EXISTS `', table_schema, '.', table_name, '`;\n', ddl) as full_script

FROM 
    `onyga-482313`.OI.INFORMATION_SCHEMA.TABLES
--WHERE     table_name = '';

----
    
    SELECT * FROM `onyga-482313`.OI.DIM_CURRENCY_RATES
    SELECT * FROM `onyga-482313`.OI.DIM_PAYMENT_SOURCE_HIERARCHY
    SELECT * FROM `onyga-482313`.OI.FACT_FINANCIAL_TRANSACTIONS
    SELECT * FROM `onyga-482313`.OI.GENERAL_CONVERSION
    SELECT * FROM 
    SELECT * FROM 

    
	-- Seller interfaces
	
	SELECT * FROM onyga-482313.OI.V_SRC_Seller_repeat_purchase
    
   ---Ads interfaces
    
    SELECT sum(units) FROM OI.V_SRC_AmazonAds_SearchTerms where  date='2025-11-28'  and keyword_id='486257635411386' 
    SELECT * FROM OI.V_SRC_AmazonAds_keyword
	SELECT * FROM OI.V_SRC_AmazonAds_purchased_product
	SELECT * FROM OI.V_SRC_AmazonAds_negative_keyword
    
  --- sources facts
    
    --ads fact
  	select * FROM fivetran-hl.amazon_ads.search_term_targeting_report st
  	select * FROM fivetran-hl.amazon_ads.search_term_ad_keyword_report
  	select * FROM fivetran-hl.amazon_ads.sb_search_term_report
  	select * FROM fivetran-hl.amazon_ads.sb_target_report  
  	
  	SELECT * FROM fivetran-hl.amazon_ads.purchased_product_targeting_report
	SELECT * FROM fivetran-hl.amazon_ads.purchased_product_keyword_report
	SELECT * FROM fivetran-hl.amazon_ads.sb_purchased_product
		
	
  --- sources Ads Dim  
  	select * from fivetran-hl.amazon_ads.sb_campaign_history
  	select * from fivetran-hl.amazon_ads.campaign_history

  	select * from fivetran-hl.amazon_ads.sb_keyword
  	select * from fivetran-hl.amazon_ads.keyword_history
  	
	SELECT * FROM fivetran-hl.amazon_ads.negative_keyword_history
	SELECT * FROM `fivetran-hl`.amazon_ads.sb_negative_keyword


 

    --sources Seller fact
  	select * FROM	`fivetran-hl`.amazon_selling_partner.sales_and_traffic_business_sku_report_daily
	select *from `fivetran-hl`.amazon_selling_partner.repeat_purchase_report_monthly

--- SQP
 
	
	--SP
	CALL `onyga-482313`.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES();
	CALL `onyga-482313`.OI.SP_FACT_FINANCIAL_TRANSACTIONS();
	
---- update conversion table
	select account_nick_name,transaction_description,payment_source,payment_source_sub_category,payment_source_category ,amount,t.*
	FROM`onyga-482313`.OI.FACT_FINANCIAL_TRANSACTIONS t 
	where
	transaction_description like '%מקס איט פיננ-י%' 
	payment_source like  '%רכב%' 
'Leumi Personal'
	select list_of_values,`SOURCE`,`key`,target FROM `onyga-482313`.OI.GENERAL_CONVERSION 
	where
	--`SOURCE` like '%227800%' and
	--`SOURCE` like '%49923%' and
	--Payoneer Happy Lolli
	 `key`  like  '%מקס איט פיננ-י%' 
		select list_of_values,`SOURCE`,`key`,target FROM `onyga-482313`.OI.GENERAL_CONVERSION where `target`  like '%פיוניר אינק-י%' 

	
	select * FROM `onyga-482313`.OI.DIM_PAYMENT_SOURCE_HIERARCHY where payment_source like '%מס-הכנסה החז-י%' 

----	
	

SELECT date(`_fivetran_synced`),report_date ,count(*)
FROM OI.V_SRC_AmazonAds_SearchTerms
group by date(`_fivetran_synced`),report_date
order by 1 desc,2 desc

SELECT transaction_type, payment_direction, COUNT(*) as count, ROUND(SUM(net_amount), 2) as total_amount 
FROM onyga-482313.OI.V_SRC_BANK_PAYONEER_ADVA_TAL
GROUP BY transaction_type, payment_direction ORDER BY transaction_type, payment_direction
 select * FROM onyga-482313.OI.V_SRC_CURRENCY_CONVERSION

 
 SELECT 
  base_currency, 
  target_currency, 
  exchange_rate, 
  rate_source,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', rate_timestamp) as updated_at
select* FROM onyga-482313.OI.V_SRC_CURRENCY_CONVERSION 
WHERE rate_date = CURRENT_DATE()
ORDER BY base_currency, target_currency;


    select * from (
    SELECT date,ad_group_id,sum(units_sold_14_d ) p_units 
    FROM `fivetran-hl`.amazon_ads.sb_purchased_product 
    where  date='2025-11-28'and  units_sold_14_d>0
    group by date,ad_group_id --having count(*)>1
    )a
     join (
      SELECT date,ad_group_id,sum(units) ST_units 
      FROM OI.V_SRC_AmazonAds_SearchTerms where  date='2025-11-28'and  units>0
    group by date,ad_group_id
    )b on a.ad_group_id=b.ad_group_id
    
    
    SELECT * FROM OI.V_SRC_AmazonAds_SearchTerms 					where  date='2025-11-28' and ad_group_id='291025799038676'  and  units>0 and keyword_id='507278582035908';
        SELECT * FROM `fivetran-hl`.amazon_ads.sb_purchased_product where  date='2025-11-28' and ad_group_id='291025799038676'  and  units>0 --and keyword_id='507278582035908'

        SELECT * FROM `fivetran-hl`.amazon_ads.sb_ad_group_report where  report_date='2025-11-28' and CAST(ad_group_id AS STRING)='291025799038676' 
        
        SELECT * FROM `fivetran-hl`.amazon_ads.sb_keyword_report where  report_date='2025-11-28' and ad_group_id='291025799038676' 
    *
FROM fivetran-hl.amazon_ads.sb_search_term_report st
LEFT JOIN onyga-482313.OI.V_SRC_AmazonAds_keyword k on CAST(st.keyword_id AS STRING)=k.keyword_id
 	where  report_date='2025-11-28' and CAST(st.ad_group_id AS STRING)='291025799038676'     
 	
 	
 SELECT
    a.*,sp.*
FROM  `fivetran-hl`.amazon_ads.sb_ad_report a
 JOIN  `fivetran-hl`.amazon_ads.sb_ad_sub_page sp
  ON a.`_fivetran_id` = sp.`_fivetran_id`;	
 	
 	
 	
 	
    -- compare cost to amazon
      SELECT campaign_name,src_table ,count(*) c, sum(cost)cost
      FROM OI.V_SRC_AmazonAds_SearchTerms
      group by campaign_name,src_table
      order by campaign_name,src_table
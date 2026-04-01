-- =============================================
-- OI Database Project - V_SRC_Seller_repeat_purchase
-- =============================================
--
-- Purpose: Repeat purchase behavior analysis for seller performance
-- Business Logic: Filters out null orders from monthly repeat purchase data
-- Dependencies: fivetran-hl.amazon_selling_partner.repeat_purchase_report_monthly
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_Seller_repeat_purchase`;
CREATE VIEW `onyga-482313.OI.V_SRC_Seller_repeat_purchase`
AS 
 	
select *
from `fivetran-hl`.amazon_selling_partner.repeat_purchase_report_monthly
where orders is not null
-- Test the remote function response format
-- Run this to see what the function actually returns

-- Test 1: Direct call
SELECT `onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`() as direct_response;

-- Test 2: Check if it has replies
SELECT 
  JSON_EXTRACT(`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`(), '$.replies') as has_replies,
  JSON_EXTRACT(`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`(), '$.success') as has_success_direct;

-- Test 3: Extract success value
SELECT 
  JSON_VALUE(`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`(), '$.success') as success_direct,
  JSON_VALUE(JSON_EXTRACT(`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`(), '$.replies[0]'), '$.success') as success_from_replies;

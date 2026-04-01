-- BOOST_KEYWORD_LEAKAGE_CHECK.sql
-- Daily check: Are BROAD campaigns still serving search terms that EXACT_BOOST campaigns should handle?
-- Also shows WTD performance comparison: Boost (EXACT) vs Leak (BROAD/AUTO) for same keywords.
--
-- Actions:
--   ADD_NEGATIVE_NOW  = leaking >$5/week on that term
--   MONITOR           = leaking $2-5/week
--   LOW_PRIORITY      = <$2/week
--   BOOST_NO_DATA     = EXACT campaign has no impressions yet (too early for negatives)
--
-- roas_comparison:
--   BOOST_WINS = EXACT campaign outperforms BROAD on this keyword (expected)
--   LEAK_WINS  = BROAD outperforms EXACT -- investigate bid/placement

SELECT * FROM `onyga-482313.OI.V_BOOST_KEYWORD_LEAKAGE` ORDER BY leak_cost DESC;

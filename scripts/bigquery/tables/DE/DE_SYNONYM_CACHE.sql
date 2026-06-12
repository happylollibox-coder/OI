-- DE_SYNONYM_CACHE
-- Persists Gemini-generated synonyms so they survive Cloud Run restarts
-- and don't require repeated API calls for the same words
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_SYNONYM_CACHE` (
  word STRING NOT NULL,
  synonyms STRING NOT NULL,  -- JSON array, e.g. '["best friend", "bestie"]'
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Comprehensive synonym rows for DE_SYNONYM_CACHE
-- Run: cat scripts/bigquery/seed_synonyms.sql | bq query --project_id=onyga-482313 --use_legacy_sql=false --max_rows=0

INSERT INTO `onyga-482313.OI.DE_SYNONYM_CACHE` (word, synonyms) VALUES
-- teens/tweens variants
('teens', '["teen", "teenager", "teenage", "teenagers"]'),
('teenagers', '["teen", "teens", "teenage"]'),
('tweens', '["tween", "preteen", "pre teen"]'),
('pre teen', '["tween", "preteen", "tweens"]'),

-- age/demographic
('daughter', '["girl", "girls"]'),
('young', '["little", "kid", "kids"]'),
('little', '["young", "small"]'),
('women', '["woman", "ladies", "lady"]'),
('woman', '["women", "ladies", "lady"]'),
('ladies', '["women", "woman", "lady"]'),
('lady', '["women", "woman", "ladies"]'),

-- gift/present variants
('basket', '["baskets", "box", "bundle", "package"]'),
('baskets', '["basket", "boxes", "bundles"]'),
('box', '["boxes", "basket", "package", "bundle"]'),
('boxes', '["box", "baskets", "packages", "bundles"]'),
('bundle', '["bundles", "box", "basket", "package"]'),
('bundles', '["bundle", "boxes", "baskets"]'),
('package', '["packages", "box", "bundle", "basket"]'),
('packages', '["package", "boxes", "bundles"]'),
('stuffer', '["stuffers", "filler", "fillers"]'),
('stuffers', '["stuffer", "fillers"]'),

-- beauty/self-care
('skincare', '["skin care", "beauty", "skin"]'),
('skin care', '["skincare", "beauty"]'),
('beauty', '["skincare", "cosmetic", "cosmetics", "makeup"]'),
('cosmetics', '["cosmetic", "makeup", "make up", "beauty"]'),
('make up', '["makeup", "cosmetic", "cosmetics"]'),
('shower', '["bath", "spa"]'),
('bath bomb', '["bath", "spa", "bath set"]'),
('bath set', '["bath", "spa", "bath bomb"]'),

-- stationery/school
('stationery', '["stationary", "school supplies"]'),
('stationary', '["stationery", "school supplies"]'),
('notebooks', '["notebook", "journals", "diaries"]'),
('diaries', '["diary", "journal", "journals"]'),
('pen', '["pens"]'),
('pens', '["pen"]'),
('stickers', '["sticker"]'),
('sticker', '["stickers"]'),
('scrapbook', '["scrapbooking", "journal", "journaling"]'),
('scrapbooking', '["scrapbook", "journaling"]'),

-- toys/activities
('toy', '["toys", "games", "activities"]'),
('toys', '["toy", "games", "activities"]'),
('game', '["games", "activities", "toys"]'),
('games', '["game", "activities", "toys"]'),
('activities', '["activity", "games", "crafts"]'),
('activity', '["activities", "games"]'),
('slime', '["diy", "craft"]'),
('art', '["arts", "craft", "crafts", "creative"]'),
('arts', '["art", "craft", "crafts", "creative"]'),
('creative', '["art", "arts", "crafts", "diy"]'),

-- occasions
('valentine', '["valentines"]'),
('valentines', '["valentine"]'),
('graduation', '["grad"]'),
('grad', '["graduation"]'),
('easter', '["spring"]'),
('advent', '["christmas", "xmas", "holiday"]'),
('sleepover', '["sleepovers", "slumber", "slumber party"]'),
('sleepovers', '["sleepover", "slumber", "slumber party"]'),
('slumber', '["sleepover", "sleepovers", "slumber party"]'),
('slumber party', '["sleepover", "slumber"]'),
('party', '["parties"]'),
('parties', '["party"]'),
('summer', '["camp"]'),
('camp', '["summer", "camping"]'),
('b day', '["birthday", "bday"]'),
('birdhdays', '["birthday", "bday"]'),

-- style/aesthetic
('preppy', '["trendy", "aesthetic", "cute"]'),
('trendy', '["preppy", "popular", "trending", "cool"]'),
('trending', '["trendy", "popular", "cool"]'),
('aesthetic', '["cute", "preppy", "kawaii"]'),
('cute', '["adorable", "kawaii", "girly"]'),
('kawaii', '["cute", "aesthetic", "adorable"]'),
('girly', '["feminine", "cute", "pink"]'),
('cool', '["trendy", "popular", "fun"]'),
('fun', '["cool", "exciting"]'),
('luxury', '["luxurious", "premium", "fancy"]'),

-- colors
('pink', '["purple", "pastel"]'),
('purple', '["pink", "lavender"]'),
('blue', '["navy", "turquoise"]'),

-- animals/themes
('bunny', '["rabbit", "bunnies"]'),
('rabbit', '["bunny", "bunnies"]'),
('bunnies', '["bunny", "rabbit"]'),
('kitty', '["cat", "kitten"]'),
('cat', '["kitty", "kitten"]'),
('kitten', '["kitty", "cat"]'),

-- accessories
('keychain', '["keychains", "key chain", "key ring"]'),
('keychains', '["keychain", "key chains", "key rings"]'),
('key chain', '["keychain", "keychains"]'),
('back pack', '["backpack", "school bag"]'),
('headband', '["headbands", "hair band", "hair accessories"]'),
('headbands', '["headband", "hair bands", "hair accessories"]'),
('hair', '["hair accessories", "hair care"]'),

-- body care
('body', '["body care", "body wash", "skin"]'),
('skin', '["skincare", "skin care"]'),
('face', '["facial"]'),
('facial', '["face"]'),
('towel', '["towels"]'),
('towels', '["towel"]'),

-- room/decor
('room', '["bedroom", "decor"]'),
('decor', '["decoration", "decorations", "room"]'),
('decorations', '["decoration", "decor"]'),
('decoration', '["decorations", "decor"]'),

-- misc
('friend', '["bff", "bestie", "best friend", "friends"]'),
('friends', '["friend", "bff", "bestie"]'),
('surprise', '["mystery"]'),
('mystery', '["surprise"]'),
('cheap', '["affordable", "budget", "under"]'),
('affordable', '["cheap", "budget", "inexpensive"]'),
('candy', '["sweets", "treats"]'),
('treats', '["candy", "sweets"]'),
('card', '["cards"]'),
('cards', '["card"]'),
('book', '["books"]'),
('books', '["book"]'),
('wrap', '["wrapped", "wrapping"]'),
('wrapped', '["wrap", "wrapping"]'),
('plush', '["plushie", "stuffed animal", "fluffy"]'),
('fluffy', '["fuzzy", "plush", "soft"]'),
('fuzzy', '["fluffy", "plush", "soft"]'),
('mini', '["small", "tiny", "little"]'),
('lock', '["lockable"]'),
('lockable', '["lock", "locking"]'),
('unique', '["special", "one of a kind"]'),
('special', '["unique"]'),

-- Spanish terms (common in data)
('regalos', '["regalo", "gift", "gifts"]'),
('regalo', '["regalos", "gift", "gifts"]'),
('niñas', '["niña", "girl", "girls"]'),
('niña', '["niñas", "girl", "girls"]'),
('cosas', '["things", "stuff", "items"]'),
('caja', '["box", "boxes"]'),
('adolescentes', '["teen", "teens", "teenager"]'),

-- school
('school', '["school supplies", "back to school"]'),
('essentials', '["supplies", "must haves"]'),
('supplies', '["essentials", "kit"]'),
('kit', '["kits", "set", "sets"]'),
('kits', '["kit", "sets"]'),
('sets', '["set", "kits"]'),

-- things/stuff
('things', '["stuff", "items", "cosas"]'),
('stuff', '["things", "items"]'),
('items', '["things", "stuff"]'),

-- care
('care', '["self care", "skincare"]'),
('self care', '["care", "skincare", "self-care"]'),
('self-care', '["self care", "care", "skincare"]')
;

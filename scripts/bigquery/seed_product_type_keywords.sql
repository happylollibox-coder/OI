-- DE_PRODUCT_TYPE_KEYWORDS — comprehensive, data-driven categorization
-- Priority: 5=exact product, 10=specific, 15=standard, 20=broad, 25=generic, 30=catch-all
-- Analyzed from top 200 brand terms + top 100 null-type terms

INSERT INTO `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` (keyword, product_type, priority) VALUES

-- ═══════════════════════════════════════
-- SOCIAL GAMES (5-10) — truth or dare, sleepover games
-- ═══════════════════════════════════════
('truth or dare', 'Social Game', 5),
('sleepover games', 'Social Game', 5),
('sleepover game', 'Social Game', 5),
('slumber party games', 'Social Game', 5),
('party game', 'Social Game', 10),
('party games', 'Social Game', 10),
('uno', 'Social Game', 10),
('uno no mercy', 'Social Game', 5),
('spot it', 'Social Game', 10),
('card game', 'Social Game', 10),
('card games', 'Social Game', 10),

-- ═══════════════════════════════════════
-- BATH & SPA (10-15)
-- ═══════════════════════════════════════
('bath bomb', 'Bath & Spa', 10),
('bath bombs', 'Bath & Spa', 10),
('bath set', 'Bath & Spa', 10),
('bath sets', 'Bath & Spa', 10),
('bath toy', 'Bath & Spa', 10),
('bath toys', 'Bath & Spa', 10),
('bubble bath', 'Bath & Spa', 10),
('bath kit', 'Bath & Spa', 10),
('bath kits', 'Bath & Spa', 10),
('bath fizz', 'Bath & Spa', 10),
('shower bomb', 'Bath & Spa', 10),
('shower bombs', 'Bath & Spa', 10),
('bath salt', 'Bath & Spa', 10),
('bath salts', 'Bath & Spa', 10),
('bath soak', 'Bath & Spa', 10),
('bath soaks', 'Bath & Spa', 10),
('bath crayon', 'Bath & Spa', 10),
('bath crayons', 'Bath & Spa', 10),
('spa kit', 'Bath & Spa', 10),
('spa kits', 'Bath & Spa', 10),
('spa set', 'Bath & Spa', 10),
('spa sets', 'Bath & Spa', 10),
('spa day', 'Bath & Spa', 10),
('power shower', 'Bath & Spa', 10),
('shower set', 'Bath & Spa', 10),
('shower kit', 'Bath & Spa', 10),
('bathroom set', 'Bath & Spa', 10),
('spa', 'Bath & Spa', 15),
('bath', 'Bath & Spa', 15),
('shower', 'Bath & Spa', 20),
('towel', 'Bath & Spa', 15),
('towels', 'Bath & Spa', 15),

-- ═══════════════════════════════════════
-- BEAUTY & SKINCARE (10-15)
-- ═══════════════════════════════════════
('makeup', 'Beauty', 10),
('skincare', 'Beauty', 10),
('skin care', 'Beauty', 10),
('skincare set', 'Beauty', 10),
('lotion', 'Beauty', 10),
('perfume', 'Beauty', 10),
('nail polish', 'Beauty', 10),
('lip gloss', 'Beauty', 10),
('lip balm', 'Beauty', 10),
('beauty', 'Beauty', 15),
('cosmetic', 'Beauty', 10),
('cosmetics', 'Beauty', 10),
('mascara', 'Beauty', 10),
('eyeshadow', 'Beauty', 10),
('blush', 'Beauty', 15),
('moisturizer', 'Beauty', 10),
('face mask', 'Beauty', 10),
('body wash', 'Beauty', 10),
('shampoo', 'Beauty', 10),
('conditioner', 'Beauty', 10),
('hair care', 'Beauty', 10),
('body lotion', 'Beauty', 10),
('sol de janeiro', 'Beauty', 5),
('glow recipe', 'Beauty', 5),
('drunk elephant', 'Beauty', 5),
('tree hut', 'Beauty', 5),
('sephora', 'Beauty', 5),
('self care kit', 'Beauty', 10),
('self care', 'Beauty', 15),
('first period kit', 'Beauty', 10),

-- ═══════════════════════════════════════
-- JOURNAL & DIARY (10-15)
-- ═══════════════════════════════════════
('journal kit', 'Journal & Diary', 5),
('journal set', 'Journal & Diary', 5),
('diy journal', 'Journal & Diary', 5),
('diary with lock', 'Journal & Diary', 5),
('journal with lock', 'Journal & Diary', 5),
('journal', 'Journal & Diary', 10),
('journals', 'Journal & Diary', 10),
('journaling', 'Journal & Diary', 10),
('diary', 'Journal & Diary', 10),
('diaries', 'Journal & Diary', 10),
('notebook', 'Journal & Diary', 10),
('notebooks', 'Journal & Diary', 10),
('planner', 'Journal & Diary', 10),
('scrapbook', 'Journal & Diary', 10),
('scrapbooking', 'Journal & Diary', 10),
('scrapbooking kit', 'Journal & Diary', 5),
('sketchbook', 'Journal & Diary', 10),

-- ═══════════════════════════════════════
-- STATIONERY & SCHOOL (10-15)
-- ═══════════════════════════════════════
('stationary', 'Stationery', 10),
('stationery', 'Stationery', 10),
('stationery set', 'Stationery', 5),
('stationary set', 'Stationery', 5),
('coloring book', 'Stationery', 10),
('sticker book', 'Stationery', 10),
('workbook', 'Stationery', 10),
('colored pencils', 'Stationery', 10),
('markers', 'Stationery', 10),
('post it notes', 'Stationery', 10),
('pen', 'Stationery', 15),
('pens', 'Stationery', 15),

-- ═══════════════════════════════════════
-- BOOKS & READING (15)
-- ═══════════════════════════════════════
('book', 'Books', 15),
('books', 'Books', 15),
('reading', 'Books', 20),
('novel', 'Books', 15),
('manga', 'Books', 15),
('comic', 'Books', 15),

-- ═══════════════════════════════════════
-- TOYS & PLAY (10-15)
-- ═══════════════════════════════════════
('toy', 'Toys', 10),
('toys', 'Toys', 10),
('lego', 'Toys', 10),
('legos', 'Toys', 10),
('playdoh', 'Toys', 10),
('doll', 'Toys', 10),
('dolls', 'Toys', 10),
('action figure', 'Toys', 10),
('nerf', 'Toys', 10),
('puzzle', 'Toys', 10),
('stuffed animal', 'Toys', 10),
('plush', 'Toys', 10),
('plushie', 'Toys', 10),
('squishy', 'Toys', 10),
('squishmallow', 'Toys', 10),
('squishmallows', 'Toys', 10),
('slime', 'Toys', 10),
('fidget', 'Toys', 10),
('fidgets', 'Toys', 10),
('board game', 'Toys', 10),
('barbie', 'Toys', 10),
('barbies', 'Toys', 10),
('hot wheels', 'Toys', 10),
('lol surprise', 'Toys', 10),
('polly pocket', 'Toys', 10),
('tamagotchi', 'Toys', 10),
('bitzee', 'Toys', 10),
('nedoh', 'Toys', 10),
('silly putty', 'Toys', 10),
('mini brands', 'Toys', 10),
('blind box', 'Toys', 10),
('clickeez', 'Toys', 10),
('nano tape', 'Toys', 10),
('nano tape bubble', 'Toys', 5),
('fake money', 'Toys', 10),
('sticki rolls', 'Toys', 10),
('sticky rolls', 'Toys', 10),

-- ═══════════════════════════════════════
-- FOOD & TREATS (10)
-- ═══════════════════════════════════════
('candy', 'Food & Treats', 10),
('chocolate', 'Food & Treats', 10),
('cookie', 'Food & Treats', 10),
('cookies', 'Food & Treats', 10),
('gummy', 'Food & Treats', 10),
('gummies', 'Food & Treats', 10),
('snack', 'Food & Treats', 10),
('snacks', 'Food & Treats', 10),
('food', 'Food & Treats', 10),
('edible', 'Food & Treats', 10),
('popcorn', 'Food & Treats', 10),
('cake', 'Food & Treats', 10),
('cupcake', 'Food & Treats', 10),
('brownie', 'Food & Treats', 10),
('fudge', 'Food & Treats', 10),
('caramel', 'Food & Treats', 10),
('treat box', 'Food & Treats', 10),
('sweets', 'Food & Treats', 10),
('marshmallow', 'Food & Treats', 10),

-- ═══════════════════════════════════════
-- CLOTHING & FASHION (10-15)
-- ═══════════════════════════════════════
('shirt', 'Clothing', 10),
('dress', 'Clothing', 10),
('shoes', 'Clothing', 10),
('clothing', 'Clothing', 10),
('clothes', 'Clothing', 10),
('hoodie', 'Clothing', 10),
('pajamas', 'Clothing', 10),
('pjs', 'Clothing', 10),
('socks', 'Clothing', 10),
('jacket', 'Clothing', 10),
('leggings', 'Clothing', 10),
('outfit', 'Clothing', 10),
('costume', 'Clothing', 10),
('beanie', 'Clothing', 10),
('scarf', 'Clothing', 10),
('gloves', 'Clothing', 10),
('backpack', 'Clothing', 10),
('purse', 'Clothing', 10),
('handbag', 'Clothing', 10),
('sneakers', 'Clothing', 10),
('boots', 'Clothing', 10),

-- ═══════════════════════════════════════
-- CRAFTS & DIY (10-15)
-- ═══════════════════════════════════════
('craft', 'Crafts & DIY', 10),
('crafts', 'Crafts & DIY', 10),
('art kit', 'Crafts & DIY', 10),
('art kits', 'Crafts & DIY', 10),
('art set', 'Crafts & DIY', 10),
('art sets', 'Crafts & DIY', 10),
('drawing', 'Crafts & DIY', 10),
('paint', 'Crafts & DIY', 10),
('painting', 'Crafts & DIY', 10),
('beads', 'Crafts & DIY', 10),
('bracelet making', 'Crafts & DIY', 10),
('jewelry making', 'Crafts & DIY', 10),
('diy', 'Crafts & DIY', 15),
('sewing', 'Crafts & DIY', 10),
('embroidery', 'Crafts & DIY', 10),
('crochet', 'Crafts & DIY', 10),
('origami', 'Crafts & DIY', 10),
('stickers', 'Crafts & DIY', 15),
('sticker', 'Crafts & DIY', 15),
('make it real', 'Crafts & DIY', 10),

-- ═══════════════════════════════════════
-- ACCESSORIES & JEWELRY (10-15)
-- ═══════════════════════════════════════
('jewelry', 'Accessories', 10),
('jewellery', 'Accessories', 10),
('necklace', 'Accessories', 10),
('bracelet', 'Accessories', 10),
('bracelets', 'Accessories', 10),
('earrings', 'Accessories', 10),
('anklet', 'Accessories', 10),
('pendant', 'Accessories', 10),
('keychain', 'Accessories', 10),
('keyring', 'Accessories', 10),
('sunglasses', 'Accessories', 10),
('scrunchie', 'Accessories', 10),
('scrunchies', 'Accessories', 10),
('hair clip', 'Accessories', 10),
('hair clips', 'Accessories', 10),
('hair accessories', 'Accessories', 10),
('headband', 'Accessories', 10),
('headbands', 'Accessories', 10),
('hair band', 'Accessories', 10),
('hair bands', 'Accessories', 10),
('accessories', 'Accessories', 15),

-- ═══════════════════════════════════════
-- HOME & DECOR (10-15)
-- ═══════════════════════════════════════
('decor', 'Home & Room', 10),
('decoration', 'Home & Room', 10),
('decorations', 'Home & Room', 10),
('poster', 'Home & Room', 10),
('wall art', 'Home & Room', 10),
('tapestry', 'Home & Room', 10),
('lamp', 'Home & Room', 10),
('candle', 'Home & Room', 10),
('pillow', 'Home & Room', 10),
('blanket', 'Home & Room', 10),
('bedding', 'Home & Room', 10),
('room decor', 'Home & Room', 5),
('neon sign', 'Home & Room', 10),
('fairy lights', 'Home & Room', 10),

-- ═══════════════════════════════════════
-- ELECTRONICS & TECH (10)
-- ═══════════════════════════════════════
('headphones', 'Electronics', 10),
('earbuds', 'Electronics', 10),
('phone case', 'Electronics', 10),
('tablet', 'Electronics', 10),
('kindle', 'Electronics', 10),
('ipad', 'Electronics', 10),
('airpods', 'Electronics', 10),
('speaker', 'Electronics', 10),
('smartwatch', 'Electronics', 10),
('camera', 'Electronics', 10),
('gaming', 'Electronics', 10),
('nintendo', 'Electronics', 10),
('xbox', 'Electronics', 10),
('playstation', 'Electronics', 10),
('ps5', 'Electronics', 10),

-- ═══════════════════════════════════════
-- PARTY SUPPLIES (10-15)
-- ═══════════════════════════════════════
('party supplies', 'Party Supplies', 10),
('party decorations', 'Party Supplies', 10),
('party favors', 'Party Supplies', 10),
('party favor', 'Party Supplies', 10),
('sleepover party supplies', 'Party Supplies', 5),
('slumber party supplies', 'Party Supplies', 5),
('wrapping paper', 'Party Supplies', 10),
('gift wrap', 'Party Supplies', 10),

-- ═══════════════════════════════════════
-- CARDS & STATIONERY (10-15)
-- ═══════════════════════════════════════
('christmas cards', 'Cards', 5),
('valentines day cards', 'Cards', 5),
('birthday card', 'Cards', 10),
('birthday cards', 'Cards', 10),
('greeting card', 'Cards', 10),
('greeting cards', 'Cards', 10),
('card', 'Cards', 25),
('cards', 'Cards', 25),

-- ═══════════════════════════════════════
-- GIFT SETS & BOXES (15-25)
-- ═══════════════════════════════════════
('gift set', 'Gift Sets', 10),
('gift box', 'Gift Sets', 10),
('gift basket', 'Gift Sets', 10),
('gift bag', 'Gift Sets', 10),
('gift kit', 'Gift Sets', 10),
('surprise box', 'Gift Sets', 10),
('mystery box', 'Gift Sets', 10),
('care package', 'Gift Sets', 10),
('subscription box', 'Gift Sets', 10),
('advent calendar', 'Gift Sets', 10),
('lollibox', 'Gift Sets', 5),
('lolli box', 'Gift Sets', 5),
('basket', 'Gift Sets', 20),
('baskets', 'Gift Sets', 20),
('gift', 'Gift Sets', 25),
('gifts', 'Gift Sets', 25),
('present', 'Gift Sets', 25),
('presents', 'Gift Sets', 25),
('stocking stuffer', 'Gift Sets', 15),
('stocking stuffers', 'Gift Sets', 15),
('quinceanera', 'Gift Sets', 15),

-- ═══════════════════════════════════════
-- GENERAL (30) — broadest catch-all
-- ═══════════════════════════════════════
('stuff', 'General', 30),
('things', 'General', 30),
('ideas', 'General', 30),
('essentials', 'General', 30),
('supplies', 'General', 30),
('items', 'General', 30),
('products', 'General', 30),
('trendy', 'General', 30)
;

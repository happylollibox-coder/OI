"""
Seed DE_PRODUCT_PHRASE_NEGATIVES with curated negative phrase lists.

Usage:
    python tools/seed_product_phrase_negatives.py

Requires: google-cloud-bigquery
"""
import uuid
from google.cloud import bigquery

PROJECT = "onyga-482313"
DATASET = "OI"
TABLE = "DE_PRODUCT_PHRASE_NEGATIVES"
FULL_TABLE = f"{PROJECT}.{DATASET}.{TABLE}"

# ─── ALL PRODUCTS (parent_name = '_ALL') ───
ALL_PHRASES = [
    "lol", "loli", "lolli", "lollibox", "lollime", "lollipop", "lolly", "loly",
    "sex", "harry potter", "barbie", "hello kitty", "taylor", "rapunzel", "stitch",
]

# ─── BOX (parent_name = 'Lollibox') ───
BOX_PHRASES = [
    "33 year old girl gifts", "1 dollar", "10 dollar", "10 dollars", "11 dollar",
    "11 dollars", "12 dollar", "12 dollars", "13 dollar", "13 dollars", "14 dollar",
    "14 dollars", "15 dollar", "15 dollars", "16", "17", "17th", "18", "18th",
    "18yo", "19", "19th", "20", "20th", "21", "22", "23", "24", "25", "26", "27",
    "28", "29", "30", "31", "32", "4", "5", "5 dollar", "6", "7 dollar",
    "7 dollars", "8 dollar", "8 dollars", "9 dollar", "9 dollars", "accessories",
    "age 2", "age 3", "age 4", "baby", "baking", "ball", "beach", "bed", "bedroom",
    "blanket", "boy", "boys", "case", "cheap", "clothes", "clothing", "college",
    "cute", "decor", "disney", "doll", "dollar", "dollars", "dollhouse", "dolls",
    "dress", "décor", "foot", "gadget", "hair", "hoodies", "jewelry", "kid", "kids",
    "kitchen", "kitty", "light", "lotion", "man", "men", "mermaid", "musical",
    "necklace", "orange", "outfit", "perfume", "phone", "pretend", "purse", "random",
    "rapunzel", "ring", "room", "shirt", "shoes", "size", "soccer", "sport",
    "stitch", "stocking", "stuff", "stuffers", "teacher", "tech", "thing", "things",
    "toddler", "toy", "toys", "under 10 dollars", "vanity", "wallet", "wallets",
    "wash", "watch", "wear", "woman", "women", "yellow", "crafts", "journal",
    "power shower", "quinceanera", "sephora", "stuffer", "dance",
]

BOX_EXACTS = [
    "girl stuff", "stuff for girls 10-12", "things for girls 10-12",
]

# ─── FRESH (parent_name = 'Fresh') ───
FRESH_PHRASES = [
    "1", "1 dollar", "10 dollar", "10 dollars", "11 dollar", "11 dollars",
    "12 dollar", "12 dollars", "13 dollar", "13 dollars", "14 dollar", "14 dollars",
    "15 dollar", "15 dollars", "16 dollar", "16 dollars", "17", "17 dollar",
    "17 dollars", "17th", "18", "18th", "18yo", "19", "19th", "2", "2 dollar",
    "20", "20th", "21", "22", "23", "24", "25", "26", "26 dollar", "26 dollars",
    "27", "27 dollar", "27 dollars", "28", "28 dollar", "28 dollars", "29",
    "29 dollar", "29 dollars", "3", "30", "30 dollar", "30 dollars", "31", "32",
    "4", "5", "5 dollar", "6", "7", "7 dollar", "7 dollars", "8", "8 dollar",
    "8 dollars", "9", "9 dollar", "9 dollars", "accessories", "age 2", "age 3",
    "age 4", "baby", "baking", "ball", "beach", "bed", "bedroom", "blanket", "boy",
    "boys", "case", "cheap", "clothes", "clothing", "cute", "deals", "decor",
    "decorations", "disney", "doll", "dollhouse", "dolls", "dress", "décor", "foot",
    "gadget", "hair", "hoodies", "jewelry", "journal", "kid", "kids", "kitchen",
    "kitty", "light", "lotion", "man", "men", "musical", "necklace", "orange",
    "outfit", "perfume", "phone", "pretend", "purse", "random", "rapunzel", "ring",
    "room", "shirt", "shoes", "size", "soccer", "sport", "stitch", "stocking",
    "stuff", "stuffers", "teacher", "tech", "thing", "things", "toddler", "toy",
    "toys", "under 10 dollars", "vanity", "wallet", "wallets", "watch", "wear",
    "woman", "women", "yellow",
]

FRESH_EXACTS = [
    "33 year old girl gifts",
]

# ─── ME (parent_name = 'LolliME') ───
ME_PHRASES = [
    "1", "1 dollar", "10 dollar", "10 dollars", "11 dollar", "11 dollars",
    "12 dollar", "12 dollars", "13 dollar", "13 dollars", "14 dollar", "14 dollars",
    "15", "15 dollar", "15 dollars", "15th", "16", "16th", "17", "17th", "18",
    "18th", "19", "19th", "2", "2 dollar", "2 dollars", "20", "21", "3", "3 dollar",
    "4", "5", "5 dollar", "5 year", "6 dollar", "6 dollars", "7 dollar", "7 dollars",
    "8 dollar", "8 dollars", "9 dollar", "9 dollars", "adult", "adults", "age 3",
    "age 4", "baby", "baking", "ball", "beach", "bear", "bed", "blanket", "body",
    "boy", "boys", "case", "cheap", "cloth", "clothes", "clothing", "college",
    "cute", "deals", "dress", "extreme", "foot", "gadget", "hair", "hoodies",
    "kitchen", "kitty", "light", "lollipop", "lotion", "mermaid", "notebooks",
    "outfit", "phone", "pretend", "purse", "random", "room", "shirt", "shoes",
    "size", "soccer", "spiral", "sport", "stuff", "supplies", "teacher", "thing",
    "things", "toddler", "toy", "toys", "under 10 dollars", "voice", "wash",
    "watch", "wear",
]

# ─── TRUTH_OR_DARE (parent_name = 'Bottle') ───
BOTTLE_PHRASES = [
    "1 dollar", "10 dollar", "10 dollars", "11 dollar", "11 dollars", "12 dollar",
    "12 dollars", "13 dollar", "13 dollars", "14 dollar", "14 dollars", "4", "5",
    "5 dollar", "6", "7", "7 dollar", "7 dollars", "8", "8 dollar", "8 dollars",
    "9", "9 dollar", "9 dollars", "accessories", "adult", "adults", "advent",
    "age 2", "age 3", "age 4", "baby", "baking", "ball", "beach", "bed", "blanket",
    "boy", "boys", "calendar", "case", "cheap", "clothes", "clothing", "college",
    "couples", "crafts", "cute", "deals", "decor", "decorations", "doll",
    "dollhouse", "dolls", "dress", "drink", "drinking", "décor", "extreme", "foot",
    "fresh", "gadget", "girl stuff", "hair", "happy lolli", "hoodies", "jewelry",
    "journal", "kid", "kids", "kitchen", "kitty", "light", "lotion", "man", "men",
    "mermaid", "musical", "necklace", "night", "orange", "outfit", "perfume",
    "phone", "power shower", "pretend", "purse", "quinceanera", "random", "rapunzel",
    "ring", "room", "sephora", "shirt", "shoes", "size", "soccer", "sport",
    "stitch", "stocking", "stuffer", "stuffers", "teacher", "tech", "toddler",
    "toy", "toys", "under 10 dollars", "vanity", "wallet", "wallets", "wash",
    "watch", "wear", "woman", "women", "yellow",
]

# ─── BUNNY (parent_name = 'Bunny') ───
BUNNY_PHRASES = [
    "1 dollar", "2 dollar", "3 dollar", "4 dollar", "5 dollar", "6 dollar",
    "7 dollar", "8 dollar", "1 dollars", "2 dollars", "3 dollars", "4 dollars",
    "5 dollars", "6 dollars", "7 dollars", "8 dollars", "adult", "adults", "age 2",
    "age 3", "age 4", "baby", "baking", "beach", "bed", "blanket", "boy", "boys",
    "case", "college", "couples", "decorations", "dress", "drink", "drinking",
    "foot", "gadget", "hoodies", "jewelry", "journal", "kitchen", "kitty", "light",
    "lotion", "man", "men", "musical", "night", "orange", "outfit", "perfume",
    "phone", "power shower", "pretend", "purse", "quinceanera", "sephora", "shirt",
    "shoes", "size", "soccer", "sport", "teacher", "tech", "toddler", "toy", "toys",
    "vanity", "wallet", "wallets", "wash", "watch", "wear", "woman", "women",
    "yellow",
]

# ─── LOLLIBALL (parent_name = 'LolliBall') ───
LOLLIBALL_PHRASES = [
    "1 dollar", "2 dollar", "3 dollar", "4 dollar", "5 dollar", "6 dollar",
    "7 dollar", "8 dollar", "1 dollars", "2 dollars", "3 dollars", "4 dollars",
    "5 dollars", "6 dollars", "7 dollars", "8 dollars", "adult", "adults", "age 2",
    "age 3", "age 4", "baby", "baking", "beach", "bed", "blanket", "boy", "boys",
    "case", "college", "couples", "decorations", "dress", "drink", "drinking",
    "foot", "gadget", "hoodies", "jewelry", "journal", "kitchen", "kitty", "light",
    "lotion", "man", "men", "musical", "night", "orange", "outfit", "perfume",
    "phone", "power shower", "pretend", "purse", "quinceanera", "sephora", "shirt",
    "shoes", "size", "soccer", "sport", "teacher", "tech", "toddler", "toy", "toys",
    "vanity", "wallet", "wallets", "wash", "watch", "wear", "woman", "women",
    "yellow", "hair", "necklace", "random", "ring",
]


def build_rows():
    """Build all rows for DE_PRODUCT_PHRASE_NEGATIVES."""
    rows = []

    def add(parent_name, phrases, match_type="Negative Phrase", product_short_name=None):
        for phrase in phrases:
            phrase = phrase.strip()
            if not phrase:
                continue
            rows.append({
                "id": str(uuid.uuid4()),
                "parent_name": parent_name,
                "product_short_name": product_short_name,
                "phrase": phrase.lower(),
                "match_type": match_type,
                "source": "MANUAL",
                "status": "ACTIVE",
            })

    # ALL products
    add("_ALL", ALL_PHRASES)

    # BOX = Lollibox
    add("Lollibox", BOX_PHRASES)
    add("Lollibox", BOX_EXACTS, match_type="Negative Exact")

    # FRESH
    add("Fresh", FRESH_PHRASES)
    add("Fresh", FRESH_EXACTS, match_type="Negative Exact")

    # ME = LolliME
    add("LolliME", ME_PHRASES)

    # TRUTH_OR_DARE = Bottle
    add("Bottle", BOTTLE_PHRASES)

    # BUNNY
    add("Bunny", BUNNY_PHRASES)

    # LOLLIBALL
    add("LolliBall", LOLLIBALL_PHRASES)

    return rows


def main():
    client = bigquery.Client(project=PROJECT)

    # Clear existing data
    print("Clearing existing rows...")
    client.query(f"DELETE FROM `{FULL_TABLE}` WHERE TRUE").result()

    # Build rows
    rows = build_rows()
    print(f"Built {len(rows)} rows:")

    # Count per family
    from collections import Counter
    family_counts = Counter(r["parent_name"] for r in rows)
    for family, count in sorted(family_counts.items()):
        match_types = Counter(r["match_type"] for r in rows if r["parent_name"] == family)
        mt_str = ", ".join(f"{mt}: {c}" for mt, c in match_types.items())
        print(f"  {family}: {count} ({mt_str})")

    # Insert via load_table_from_json
    job_config = bigquery.LoadJobConfig(
        schema=[
            bigquery.SchemaField("id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("parent_name", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("product_short_name", "STRING", mode="NULLABLE"),
            bigquery.SchemaField("phrase", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("match_type", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("source", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("status", "STRING", mode="REQUIRED"),
        ],
        write_disposition="WRITE_APPEND",
    )

    job = client.load_table_from_json(rows, FULL_TABLE, job_config=job_config)
    job.result()

    if job.errors:
        print(f"Errors: {job.errors}")
    else:
        print(f"✓ Loaded {len(rows)} rows into {FULL_TABLE}")

    # Verify
    result = client.query(
        f"SELECT parent_name, match_type, COUNT(*) as cnt FROM `{FULL_TABLE}` GROUP BY 1, 2 ORDER BY 1, 2"
    ).result()
    print("\nVerification:")
    for row in result:
        print(f"  {row.parent_name} | {row.match_type} | {row.cnt}")


if __name__ == "__main__":
    main()

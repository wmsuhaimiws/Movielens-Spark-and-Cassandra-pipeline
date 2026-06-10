"""
schemas.py
==========
Explicit Spark schemas for the three MovieLens 100k source files.

Defining schemas explicitly (instead of `inferSchema=True`) gives us:
  * deterministic, documented column types,
  * a single full pass over the data instead of two (infer + read),
  * an early, loud failure if the raw file shape ever changes.

These StructTypes are imported by the notebook so the parsing logic and
the analytics share one authoritative definition.
"""

from pyspark.sql.types import (
    StructType, StructField, IntegerType, StringType, LongType,
)
from genres import GENRE_COLUMNS


# ---------------------------------------------------------------------------
# u.user : user_id | age | gender | occupation | zip_code   (pipe-delimited)
# ---------------------------------------------------------------------------
USER_SCHEMA = StructType([
    StructField("user_id",    IntegerType(), nullable=False),
    StructField("age",        IntegerType(), nullable=True),
    StructField("gender",     StringType(),  nullable=True),
    StructField("occupation", StringType(),  nullable=True),
    StructField("zip_code",   StringType(),  nullable=True),  # keep as string: leading zeros / non-numeric ZIPs
])


# ---------------------------------------------------------------------------
# u.data : user_id | item_id | rating | timestamp           (tab-delimited)
# ---------------------------------------------------------------------------
RATING_SCHEMA = StructType([
    StructField("user_id",   IntegerType(), nullable=False),
    StructField("item_id",   IntegerType(), nullable=False),
    StructField("rating",    IntegerType(), nullable=False),
    StructField("timestamp", LongType(),    nullable=True),   # Unix epoch seconds
])


# ---------------------------------------------------------------------------
# u.item : item_id | title | release_date | video_date | imdb_url | <19 genre flags>
#          (pipe-delimited, latin-1 encoded)
# ---------------------------------------------------------------------------
def build_item_schema():
    """Item schema = 5 fixed metadata columns + 19 genre flag columns."""
    fields = [
        StructField("item_id",      IntegerType(), nullable=False),
        StructField("title",        StringType(),  nullable=True),
        StructField("release_date", StringType(),  nullable=True),
        StructField("video_date",   StringType(),  nullable=True),  # almost always empty in 100k
        StructField("imdb_url",     StringType(),  nullable=True),
    ]
    # The 19 genre flags are stored as 0/1 integers.
    fields += [StructField(g, IntegerType(), nullable=True) for g in GENRE_COLUMNS]
    return StructType(fields)


ITEM_SCHEMA = build_item_schema()

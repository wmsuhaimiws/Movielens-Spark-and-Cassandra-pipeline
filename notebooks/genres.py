"""
genres.py
=========
Single source of truth for the 19 MovieLens genre columns.

The MovieLens 100k `u.item` file encodes genres as 19 trailing binary
flag columns (0/1). Their order is FIXED by the dataset's `u.genre`
file and must never be reordered, otherwise every genre label shifts.

Importing GENRE_COLUMNS everywhere guarantees the schema, the cleaning
code and the analytics all agree on the same ordering.
"""

# Order is taken verbatim from the MovieLens 100k `u.genre` file.
GENRE_COLUMNS = [
    "unknown", "Action", "Adventure", "Animation", "Children", "Comedy",
    "Crime", "Documentary", "Drama", "Fantasy", "Film_Noir", "Horror",
    "Musical", "Mystery", "Romance", "Sci_Fi", "Thriller", "War", "Western",
]

# Number of genre flag columns (used for validation / sanity checks).
N_GENRES = len(GENRE_COLUMNS)
assert N_GENRES == 19, "MovieLens 100k must expose exactly 19 genre flags."

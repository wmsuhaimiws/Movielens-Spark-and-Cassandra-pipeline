# Verified Results & Interpretation

All figures below are taken from a **real end-to-end run** on MovieLens 100k
(HDFS → Spark → Cassandra → read-back). They are embedded in the interpretation cells of
`notebooks/movielens_pipeline.ipynb`.

## Cleaning summary

| Table | Before → after | Note |
|---|---|---|
| `users` | 943 → 943 | already clean |
| `ratings` | 100000 → 100000 | no duplicate (user, item) pairs |
| `items` | 1682 → 1682 | one blank-title row tolerated; latin-1 titles preserved |

MovieLens 100k is already clean, so counts do not move — the validation steps are defensive
engineering that would matter on dirtier feeds.

## Task (i) — Average rating per movie

All 1,682 catalogue items receive at least one rating. The **number** of ratings is extremely
uneven (a long tail): a few blockbusters draw hundreds while most draw a handful. Means over very
small samples are dominated by noise, so the rating count is retained for support-weighting.

## Task (ii) — Top 10 movies (≥50-rating support threshold)

| # | Title | Avg | n |
|---|---|---|---|
| 1 | Close Shave, A (1995) | 4.491 | 112 |
| 2 | Schindler's List (1993) | 4.466 | 298 |
| 3 | Wrong Trousers, The (1993) | 4.466 | 118 |
| 4 | Casablanca (1942) | 4.457 | 243 |
| 5 | Wallace & Gromit: The Best of Aardman Animation (1996) | 4.448 | 67 |
| 6 | Shawshank Redemption, The (1994) | 4.445 | 283 |
| 7 | Rear Window (1954) | 4.388 | 209 |
| 8 | Usual Suspects, The (1995) | 4.386 | 267 |
| 9 | Star Wars (1977) | 4.358 | 583 |
| 10 | 12 Angry Men (1957) | 4.344 | 125 |

The ≥50-rating threshold is decisive — without it the head of the list is taken over by
single-vote 5.0 oddities. Scores are compressed into a narrow band (4.34–4.49), so the precise
within-top-10 order is statistically fragile; *Star Wars* alone pairs a top average with mass
popularity (583 ratings).

## Task (iii) — Power users (≥50 ratings) and favourite genre

- **Power users:** 568 of 943 (≈60%).
- **Favourite-genre distribution:** Drama 368 · Comedy 100 · Action 80 · Thriller 15 · Horror 4 · Children 2.

Drama's dominance largely reflects **catalogue supply** (Drama is the most common genre flag),
not unbiased preference — a supply-normalised measure would be a stronger taste signal. Multi-genre
films are credited to every active genre via flag explosion; ties are broken deterministically.

## Task (iv) — Users younger than 20

77 of 943 users (≈8%); youngest is 7. Dominated by the `student` occupation. The segment is small
and per-item sparse, so age-targeted modelling would need pooling or regularisation; ages are
self-reported and unverifiable.

## Task (v) — Scientists aged 30–40 (inclusive)

16 users match. `scientist` is uncommon (~31 users total); all 16 are male in this sample. The
compound predicate (categorical equality + numeric range) motivates the `users_by_occ_age`
Cassandra table (partition by `occupation`, cluster by `age`), turning the query into a
single-partition contiguous slice with no `ALLOW FILTERING`.

## Discussion & limitations (summary)

- **Popularity is heavily skewed** → quality measures must be support-weighted.
- **Genre preference is confounded by supply** → Drama's lead is partly an artefact of the catalogue.
- **Demographic segments are small and self-reported** → useful for exploration, not confident modelling.
- **Validity:** MovieLens 100k is a filtered, self-reported, late-1990s Western-cinema sample;
  results are internally valid but should not be generalised.
- **Storage design:** Cassandra (query-first, pre-sorted) serves rankings/slices without
  `ALLOW FILTERING`; HBase needs a scan + client-side sort; MongoDB is most ergonomic for
  heterogeneous results but trades scan performance.

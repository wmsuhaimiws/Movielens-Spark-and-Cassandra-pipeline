# How to Run — Two Options

Two notebooks are provided, and the **same analytical results** are produced by both:

| Notebook | Where it is run | Datastores |
|---|---|---|
| `movielens_pipeline.ipynb` | Local machine / real cluster | HDFS + Cassandra (+ HBase + MongoDB) |
| `movielens_pipeline_colab.ipynb` | Google Colab | In-VM HDFS + Cassandra (+ optional MongoDB; HBase = documentation only) |

Whichever option matches the available environment may be chosen. Option B (Colab) is the
quickest to get working and has been verified end-to-end on real MovieLens 100k data.

---

## Option A — Local machine / cluster (`movielens_pipeline.ipynb`)

This is the "real" deployment, in which the files are stored in HDFS and Spark and
Cassandra are run as services.

**Prerequisites.** Java 11, Python 3.10, Hadoop/HDFS, Apache Cassandra 4.1, and
`pip install pyspark==3.5.1 matplotlib happybase pymongo cassandra-driver`. (Full details
are given in `README.md`; a complete Windows-11/WSL2 walkthrough is given in
`SETUP_WINDOWS_WSL.md`.)

1. **The files are kept together** in one folder:
   `movielens_pipeline.ipynb`, `schemas.py`, `genres.py`.
2. **The data is obtained:**
   ```bash
   wget https://files.grouplens.org/datasets/movielens/ml-100k.zip
   unzip ml-100k.zip -d ~/data
   ```
3. **HDFS is started and the files are landed:**
   ```bash
   start-dfs.sh
   hdfs dfs -mkdir -p /movielens
   hdfs dfs -put -f ~/data/ml-100k/u.user ~/data/ml-100k/u.data ~/data/ml-100k/u.item /movielens/
   ```
   (These commands are also issued by the notebook's load cell, which auto-locates the local
   folder, so this step may be skipped. The notebook reads `hdfs://localhost:9000/movielens/...`.)
4. **Cassandra is started:**
   ```bash
   sudo systemctl start cassandra      # or: $CASSANDRA_HOME/bin/cassandra -f &
   cqlsh 127.0.0.1 9042 -e "SELECT release_version FROM system.local;"
   ```
5. **(Optional) HBase + MongoDB are started** for the extension:
   ```bash
   start-hbase.sh && hbase thrift start &
   sudo systemctl start mongod
   ```
   If these are skipped, the extension cells at the foot of the notebook are simply left
   un-executed.
6. **The notebook is launched and run top-to-bottom:**
   ```bash
   jupyter notebook movielens_pipeline.ipynb
   ```
   On the first run the Spark↔Cassandra/Mongo connectors are downloaded from Maven
   (internet required).

**Run order inside the notebook:** imports → HDFS paths → RDD parse → DataFrames →
cleaning → Tasks (i)–(v) → Cassandra create/write → read-back validation →
(optional) HBase + MongoDB.

> **On WSL2, one command does all of the above setup:** `~/start-movielens.sh` starts SSH,
> HDFS, Cassandra (and HBase/MongoDB if installed) with readiness checks, then launches
> Jupyter. The services stop when Ubuntu is closed, so the script is run each session; HDFS
> data persists across restarts provided `hadoop.tmp.dir` is set per `SETUP_WINDOWS_WSL.md`.

---

## Option B — Google Colab (`movielens_pipeline_colab.ipynb`)

The notebook is self-contained: Java/Hadoop/Cassandra are installed, the data is
downloaded, and the helper modules are written into the VM by the notebook itself.
**Nothing has to be uploaded.**

1. The notebook is uploaded at **https://colab.research.google.com** via
   **File ▸ Upload notebook**.
   (`schemas.py`/`genres.py` do **not** need to be uploaded — they are generated in
   Setup 4.)
2. *(Recommended)* A Python 3 runtime is selected via **Runtime ▸ Change runtime type**
   (CPU is sufficient).
3. **Runtime ▸ Run all** is selected, or the cells are run top-to-bottom. The setup cells
   require a few minutes:
   - **Setup 1–2:** Java 11 is installed, `JAVA_HOME` is set, and PySpark is installed.
   - **Setup 3:** MovieLens 100k is downloaded to `/content/ml-100k`.
   - **Setup 4:** `genres.py` and `schemas.py` are written into the VM.
   - **Setup 5:** Hadoop is downloaded, a single-node **HDFS** is started, and the three
     files are loaded into it — **Requirement 2 is satisfied here.**
   - **Setup 6:** Cassandra is downloaded, configured for loopback, and started; readiness
     is then confirmed with the native `cassandra-driver`.
4. The pipeline cells are then run exactly as in Option A, with the data read from
   `hdfs://localhost:9000/...`.
5. **MongoDB extension (optional):** the "Optional Extension A" cells are run if MongoDB is
   wanted; otherwise they are skipped.
6. **HBase:** it is not run on Colab — it is provided as documentation only (it is
   impractical to stand up in a single VM).

### Colab caveats and known issues (all already handled in the notebook)

- **The VM is temporary.** When the runtime is reset or disconnected, Cassandra, MongoDB
  and all files are discarded; the setup cells must therefore be re-run each session.
- **The Hadoop download must not hang.** A timeout and progress bar are used in Setup 5, so
  a stalled mirror is failed fast and the cell can simply be re-run (the download is
  resumed with `-c`).
- **Cassandra boots slowly on a loaded VM.** The readiness cell waits up to ~6 minutes; if
  it is still reported as "not ready", the last 40 log lines are printed. If `NORMAL` /
  `Finish joining ring` is seen in the log, Cassandra is already up and the readiness cell
  is simply re-run (the launch cell must **not** be re-run, or a second instance would be
  started).
- **`cqlsh` is not used.** The bundled `cqlsh` crashes on Colab's newer Python
  (`No module named 'six.moves'`), so the keyspace, tables and readiness checks are all
  performed with the native `cassandra-driver` instead.

---

## What is produced

The same five tasks are answered by both notebooks, and the Cassandra round-trip is
validated:
(i) per-movie averages, (ii) top-10 movies (≥50-rating threshold), (iii) power users and
their favourite genre, (iv) users under 20, (v) scientists aged 30–40.

The verified figures from a real MovieLens 100k run are: 568 power users (favourite genres
Drama 368 / Comedy 100 / Action 80 / Thriller 15 / Horror 4 / Children 2), 77 users under
20, and 16 scientists aged 30–40; the top-rated film is *A Close Shave (1995)* at 4.491
over 112 ratings. These figures are embedded in the interpretation cells of
`movielens_pipeline.ipynb`.

## Quick troubleshooting

| Symptom | Resolution |
|---|---|
| `connector not found` / Ivy error | Internet is required on the first run so that `spark.jars.packages` can be resolved. |
| WSL: `NameNode` missing after restart (`Connection refused :9000`) | HDFS storage on `/tmp` was wiped; set `hadoop.tmp.dir` to a persistent folder and reformat once (`SETUP_WINDOWS_WSL.md`). |
| WSL: `Incomplete HDFS URI, no host` | Use the full authority `hdfs://localhost:9000/movielens` (the notebook already does). |
| WSL: load cell `path does not exist` | Local files are elsewhere; confirm with `ls ~/data/ml-100k ~/ml-100k`. The load cell auto-locates both. |
| `NoHostAvailable` (Cassandra) | It should be confirmed that Cassandra is up; on a loaded VM it may still be booting. |
| Garbled film titles | `u.item` must be read as **latin-1** (this is handled in the RDD cell). |
| Java version error | Java 11 is required by Spark 3.5 and Cassandra 4.1. |
| Colab: Setup 5 appears to hang | The download cell is re-run; the timeout fails a stalled mirror fast. |
| Colab: `ModuleNotFoundError: genres` | Setup 4 (the `%%writefile` cells) and the `sys.path.insert` cell are re-run. |
| Colab: `cqlsh` crash (`six.moves`) | `cqlsh` is not used; the native `cassandra-driver` cells should be run instead. |
| WSL HBase: `command not found` / `happybase` hangs | Start HBase + Thrift; the notebook's HBase bootstrap cell handles PATH, startup and a 20s timeout. See `SETUP_WINDOWS_WSL.md` Step 7. |
| WSL HBase write: `servers with issues: null` | Apply the standalone `hbase-site.xml` (`hbase.regionserver.hostname=localhost`) and wait for "active master" before writing. |
| WSL MongoDB: `Connection refused :27017` | `mongod` is down (not persistent across restarts). Start it each session via `start-movielens.sh` or `sudo mongod --fork --logpath ~/mongod.log`. |

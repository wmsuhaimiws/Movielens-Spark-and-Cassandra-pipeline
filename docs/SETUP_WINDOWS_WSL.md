# Setting up Option A on Windows 11 (via WSL2)

**Target machine:** AMD Ryzen AI 7 350, 16 GB RAM (13.8 GB usable), ~217 GB free disk,
Windows 11. This is more than enough — MovieLens 100k is a tiny dataset; the only real
constraint is RAM if every datastore is started at once, which this guide manages.

**Why WSL2 (not native Windows):** Hadoop/HDFS, Cassandra, HBase and the Spark connectors
are built for Linux. Running them natively on Windows needs `winutils.exe` hacks and breaks
constantly. WSL2 provides a real Ubuntu inside Windows where the standard Linux instructions
work directly.

> **Quick path:** after the one-time install below, every session can be started with a
> single command — `~/start-movielens.sh` (see *Daily start-up*). The persistence fix in
> Step 3 is what makes HDFS survive WSL restarts, so the dataset is loaded only once.

---

## Step 0 — Install WSL2 + Ubuntu (one time, in Windows)

Open **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-22.04
```

Reboot if prompted. On first launch a Linux username and password are created — keep the
password (it is needed for `sudo`). Confirm WSL **2**:

```powershell
wsl -l -v        # the VERSION column should read 2
```

### Cap WSL memory so Windows stays responsive
Create `C:\Users\hp\.wslconfig` (Notepad) with:

```ini
[wsl2]
memory=12GB
processors=6
swap=4GB
```

Then in PowerShell run `wsl --shutdown` and reopen Ubuntu. This leaves ~4 GB for Windows.

> **Work inside the Linux home (`~`), not `/mnt/c/...`** — the Windows-mounted drive is slow
> for Hadoop/Cassandra. Final outputs are copied back to Windows only when done.

---

## Step 1 — Base packages (inside Ubuntu)

```bash
sudo apt update && sudo apt upgrade -y
# Java 11 satisfies BOTH Spark 3.5 and Cassandra 4.1
sudo apt install -y openjdk-11-jdk-headless python3-pip python3-venv \
                    openssh-server wget unzip curl

# Pin JAVA_HOME for every shell
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
java -version    # -> openjdk version "11..."
```

### Python libraries

```bash
pip install --user pyspark==3.5.1 matplotlib happybase pymongo cassandra-driver jupyter
```

(`pyspark` ships its own Spark 3.5 — no separate Spark download is needed. `cassandra-driver`
is the fallback for creating the keyspace if the bundled `cqlsh` is incompatible with the
installed Python — see Troubleshooting.)

---

## Step 2 — Passwordless SSH to localhost (Hadoop needs this)

```bash
sudo service ssh start
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
ssh -o StrictHostKeyChecking=no localhost "echo ssh-ok"   # should print: ssh-ok
```

---

## Step 3 — Install Hadoop / HDFS (pseudo-distributed, **persistent**)

```bash
cd ~
wget https://archive.apache.org/dist/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
tar xzf hadoop-3.3.6.tar.gz
echo 'export HADOOP_HOME=$HOME/hadoop-3.3.6' >> ~/.bashrc
echo 'export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Tell Hadoop where Java is
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh
mkdir -p ~/hdfs-tmp
```

**`core-site.xml`** — edit `~/hadoop-3.3.6/etc/hadoop/core-site.xml`. The `hadoop.tmp.dir`
property is essential: without it, HDFS storage defaults to `/tmp`, which WSL wipes on every
restart, after which the NameNode refuses to start. Pointing it at `~/hdfs-tmp` makes HDFS —
and the loaded dataset — persist across restarts.

```xml
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://localhost:9000</value>
  </property>
  <property>
    <name>hadoop.tmp.dir</name>
    <value>/home/YOURUSER/hdfs-tmp</value>
  </property>
</configuration>
```

> Replace `YOURUSER` with the output of `echo $HOME` (e.g. `/home/hp1/hdfs-tmp`).

**`hdfs-site.xml`** — single replica:

```xml
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
</configuration>
```

**Format once, then start HDFS:**

```bash
hdfs namenode -format -force
start-dfs.sh
jps    # expect: NameNode, DataNode, SecondaryNameNode (+ Jps)
```

If `start-dfs.sh` complains about JAVA_HOME, re-check the `hadoop-env.sh` line above. The HDFS
web UI is at `http://localhost:9870` in the Windows browser. **All three daemons (especially
`NameNode`) must appear in `jps`** — if `NameNode` is missing, see Troubleshooting.

---

## Step 4 — Install & start Cassandra 4.1

```bash
cd ~
wget https://archive.apache.org/dist/cassandra/4.1.4/apache-cassandra-4.1.4-bin.tar.gz
tar xzf apache-cassandra-4.1.4-bin.tar.gz

# Cap the heap so Cassandra does not grab a quarter of RAM
echo 'MAX_HEAP_SIZE="2G"'   >> ~/apache-cassandra-4.1.4/conf/cassandra-env.sh
echo 'HEAP_NEWSIZE="400M"'  >> ~/apache-cassandra-4.1.4/conf/cassandra-env.sh
echo 'export PATH=$HOME/apache-cassandra-4.1.4/bin:$PATH' >> ~/.bashrc && source ~/.bashrc

# Start it in the background, then confirm after ~30-60s
~/apache-cassandra-4.1.4/bin/cassandra > ~/cassandra.log 2>&1 &
nodetool status        # 'UN' = up/normal once ready
```

Cassandra's data persists in its own folder under the tarball, so the keyspace/tables created
by the notebook survive restarts.

---

## Step 5 — Get the data into HDFS

```bash
cd ~
wget https://files.grouplens.org/datasets/movielens/ml-100k.zip
unzip ml-100k.zip -d ~/data         # -> ~/data/ml-100k/{u.user,u.data,u.item,...}

hdfs dfs -mkdir -p /movielens
hdfs dfs -put -f ~/data/ml-100k/u.user ~/data/ml-100k/u.data ~/data/ml-100k/u.item /movielens/
hdfs dfs -ls -h /movielens          # the three files are confirmed
```

The notebook reads `hdfs://localhost:9000/movielens/...` (the full host:port authority is
required — a bare `hdfs:///` has no host and fails). The notebook's load cell also auto-locates
`~/data/ml-100k` (or `~/ml-100k`), so this step may be skipped once the files are in HDFS.

---

## Step 6 — Copy the project files into Ubuntu and run

```bash
mkdir -p ~/movielens-project && cd ~/movielens-project
cp "/mnt/c/Users/hp/OneDrive/Documents/Claude/Data Management_2/movielens_pipeline.ipynb" .
cp "/mnt/c/Users/hp/OneDrive/Documents/Claude/Data Management_2/schemas.py" .
cp "/mnt/c/Users/hp/OneDrive/Documents/Claude/Data Management_2/genres.py" .
cp "/mnt/c/Users/hp/OneDrive/Documents/Claude/Data Management_2/start-movielens.sh" ~/ && chmod +x ~/start-movielens.sh

jupyter notebook --no-browser --port 8888
```

Jupyter prints a URL like `http://localhost:8888/?token=...` — paste it into the Windows
browser (WSL2 forwards localhost). Open `movielens_pipeline.ipynb` and run the cells top to
bottom. The first run downloads the Spark↔Cassandra connector from Maven (internet, ~1 min).

> **Re-copying the notebook later:** if an updated notebook is copied over, close the Jupyter
> browser tab first — Jupyter autosaves an open notebook and would overwrite the new file.

---

## Step 7 (optional) — HBase + MongoDB for the extension

Only needed for the added-value section. **Do not run these alongside a heavy job** — together
they add ~2–3 GB RAM.

**HBase 2.5 — install:**
```bash
cd ~
wget https://archive.apache.org/dist/hbase/2.5.8/hbase-2.5.8-bin.tar.gz
tar xzf hbase-2.5.8-bin.tar.gz
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> ~/hbase-2.5.8/conf/hbase-env.sh
echo 'export HBASE_HOME=$HOME/hbase-2.5.8' >> ~/.bashrc
echo 'export PATH=$HBASE_HOME/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
pip install --user happybase
```

**HBase 2.5 — standalone config (required on WSL).** HBase standalone is pinned to the local
filesystem and **loopback**; without this, region assignment fails on WSL with
*"servers with issues: null"* (the regionserver registers under the WSL hostname, which the
client cannot reach). This config is written once:

```bash
cat > ~/hbase-2.5.8/conf/hbase-site.xml <<XML
<configuration>
  <property><name>hbase.cluster.distributed</name><value>false</value></property>
  <property><name>hbase.rootdir</name><value>file://$HOME/hbase-data</value></property>
  <property><name>hbase.zookeeper.property.dataDir</name><value>$HOME/hbase-zk</value></property>
  <property><name>hbase.unsafe.stream.capability.enforce</name><value>false</value></property>
  <property><name>hbase.regionserver.hostname</name><value>localhost</value></property>
</configuration>
XML
```

**HBase 2.5 — start (and wait until the master is active before any write):**
```bash
start-hbase.sh
# wait for "active master" — writing before this causes 'servers with issues: null'
for i in $(seq 1 30); do echo status | hbase shell -n 2>/dev/null | grep -q "active master" && break; sleep 4; done
hbase thrift start > ~/hbase-thrift.log 2>&1 &   # happybase connects here (port 9090)
sleep 6
jps    # expect HMaster + ThriftServer
```

> The notebook's **HBase bootstrap cell** writes this same `hbase-site.xml`, starts HBase,
> waits for the active master, and starts Thrift automatically — so re-running the notebook
> reproduces a working HBase. For the `%%bash` HBase cell to find `hbase`, Jupyter must be
> launched from a shell where `HBASE_HOME/bin` is on PATH (the `start-movielens.sh` script,
> and the notebook's bootstrap cell, both handle this).
>
> If a previous broken attempt left stale state, do a clean reset:
> `stop-hbase.sh; pkill -f thrift; rm -rf ~/hbase-data ~/hbase-zk /tmp/hbase-$USER` then re-start.

**MongoDB 7.0:**
```bash
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
  sudo gpg -o /usr/share/keyrings/mongodb.gpg --dearmor
echo "deb [signed-by=/usr/share/keyrings/mongodb.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
  sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update && sudo apt install -y mongodb-org
sudo mkdir -p /data/db && sudo mongod --fork --logpath ~/mongod.log
```

---

## Daily start-up (after the first install)

Each time Ubuntu is reopened, the services are stopped (but HDFS data and the Cassandra
keyspace persist). The simplest way to bring everything back is the bundled script:

```bash
~/start-movielens.sh
```

It exports the environment, starts SSH + HDFS (and verifies the NameNode actually came up),
reloads the dataset only if missing, starts Cassandra (and HBase + MongoDB if installed) with
readiness checks, then launches Jupyter. To start the extensions, uncomment their lines near
the top/bottom of the script.

Equivalent manual sequence:

```bash
sudo service ssh start
start-dfs.sh
jps                                          # NameNode, DataNode, SecondaryNameNode must all appear
~/apache-cassandra-4.1.4/bin/cassandra > ~/cassandra.log 2>&1 &
# (optional) start-hbase.sh ; hbase thrift start & ; sudo mongod --fork --logpath ~/mongod.log
cd ~/movielens-project && jupyter notebook --no-browser --port 8888
```

## Shut down cleanly

```bash
stop-dfs.sh
pkill -f CassandraDaemon
# (optional) stop-hbase.sh ; pkill -f mongod
# wsl --shutdown   (from PowerShell, frees all RAM back to Windows)
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| **`NameNode` missing from `jps` after a WSL restart** (and `Connection refused` to `localhost:9000`) | HDFS storage was on `/tmp` and got wiped. Ensure `hadoop.tmp.dir = ~/hdfs-tmp` in `core-site.xml` (Step 3), then `stop-dfs.sh; rm -rf /tmp/hadoop-* ~/hdfs-tmp/dfs; hdfs namenode -format -force; start-dfs.sh`. With the persistent dir set, this is a one-time recovery. |
| `Incomplete HDFS URI, no host: hdfs:///...` | The URI lacks a host. Use the full authority `hdfs://localhost:9000/movielens` (the notebook's `HDFS_BASE` already does). |
| `Input path does not exist` / load cell fails | The local files are not where expected. Confirm with `ls ~/data/ml-100k ~/ml-100k 2>/dev/null`; the notebook's load cell auto-locates both. |
| `cqlsh` crashes with `No module named 'six.moves'` | The bundled `cqlsh` is incompatible with newer Python. Create the keyspace/tables with the native `cassandra-driver` (the snippet used in the Colab notebook) instead. |
| `JAVA_HOME is not set` (Hadoop) | Re-add the export to `hadoop-env.sh` (Step 3). |
| `start-dfs.sh` asks for a password | The SSH key step (Step 2) did not take; re-run it until `ssh localhost "echo ok"` needs no password. |
| `NoHostAvailable` (Cassandra) | Still booting — wait, then check `nodetool status` and `~/cassandra.log`. |
| HBase cell: `hbase: command not found` (exit 127) | HBase is not installed or not on PATH. Install per Step 7 and launch Jupyter via `start-movielens.sh` so `HBASE_HOME/bin` is on PATH (the notebook's HBase bootstrap cell also exports it). |
| HBase `happybase` cell hangs forever | The Thrift gateway (port 9090) is not up. Run `hbase thrift start &` and confirm `ThriftServer` in `jps`. The notebook adds a 20s `timeout` so it errors instead of hanging. |
| HBase write fails: `Failed N actions ... servers with issues: null` | The regionserver had not assigned the region (WSL hostname issue). Apply the standalone `hbase-site.xml` in Step 7 (`hbase.regionserver.hostname=localhost`) and **wait for "active master"** before writing. A clean reset clears stale state. |
| MongoDB cell: `Connection refused :27017` | `mongod` is not running (it does not survive a WSL restart). Start it each session: `sudo mongod --fork --logpath ~/mongod.log` — or let `start-movielens.sh` start it. If it will not start, clear a stale lock: `sudo rm -f /tmp/mongodb-27017.sock /data/db/mongod.lock`. |
| `WARN NativeCodeLoader: Unable to load native-hadoop library` | Harmless — Spark falls back to built-in Java classes; results are identical. To silence it, `spark.sparkContext.setLogLevel("ERROR")`. |
| Cassandra OOM / laptop sluggish | Lower `MAX_HEAP_SIZE` to `1G`; do not run HBase + MongoDB at the same time. |
| Garbled film titles | `u.item` must be read latin-1 (the notebook already does this via `binaryFiles`). |
| Jupyter URL won't open in Windows | Use the `127.0.0.1:8888` form with the token; WSL2 forwards localhost. |
| Everything slow | Keep project files in `~/` inside Ubuntu, not under `/mnt/c`. |

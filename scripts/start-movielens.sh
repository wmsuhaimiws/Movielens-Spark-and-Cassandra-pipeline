#!/usr/bin/env bash
# =============================================================================
# start-movielens.sh — one-command startup for the MovieLens cluster pipeline
# Run once per WSL session:   ~/start-movielens.sh
#
# Core services : SSH, HDFS, Cassandra  (always started)
# Extensions    : HBase + Thrift, MongoDB  (started if installed)
#
# Before first use, run the ONE-TIME HDFS persistence fix (see README/chat) so
# the NameNode and HDFS data survive WSL restarts.
# =============================================================================

# --- Environment (so this works even if ~/.bashrc is not sourced) ------------
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=$HOME/hadoop-3.3.6
export CASSANDRA_HOME=$HOME/apache-cassandra-4.1.4
export HBASE_HOME=$HOME/hbase-2.5.8
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$CASSANDRA_HOME/bin:$HBASE_HOME/bin:$JAVA_HOME/bin:$PATH

say(){ echo -e "\n>> $*"; }

# --- 1. SSH (Hadoop's start-dfs.sh needs passwordless ssh to localhost) ------
say "Starting SSH service..."
sudo service ssh start

# --- 2. HDFS -----------------------------------------------------------------
say "Starting HDFS (NameNode + DataNode)..."
start-dfs.sh
sleep 6
say "Java daemons:"; jps

if ! jps | grep -q NameNode; then
  echo
  echo "!! NameNode did NOT start. Run the ONE-TIME fix:"
  echo "     stop-dfs.sh"
  echo "     # ensure hadoop.tmp.dir = ~/hdfs-tmp in core-site.xml"
  echo "     rm -rf /tmp/hadoop-* \$HOME/hdfs-tmp/dfs"
  echo "     hdfs namenode -format -force && start-dfs.sh"
  echo "   Then re-run this script."
  exit 1
fi

say "Waiting until HDFS accepts connections..."
until hdfs dfs -ls / >/dev/null 2>&1; do sleep 2; done
echo "   HDFS is reachable."

# --- 3. Ensure the dataset is present in HDFS (reload only if missing) --------
if hdfs dfs -test -e /movielens/u.item 2>/dev/null; then
  say "Dataset already present in HDFS."
else
  say "Dataset missing in HDFS — locating local copy and loading..."
  SRC=""
  for d in "$HOME/ml-100k" "$HOME/data/ml-100k" "$HOME/movielens-project/ml-100k"; do
    [ -f "$d/u.user" ] && SRC="$d" && break
  done
  if [ -z "$SRC" ]; then
    echo "!! Local ml-100k folder not found. Run: ls \$HOME/ml-100k \$HOME/data/ml-100k 2>/dev/null"
    exit 1
  fi
  echo "   Local source: $SRC"
  hdfs dfs -mkdir -p /movielens
  hdfs dfs -put -f "$SRC"/u.user "$SRC"/u.data "$SRC"/u.item /movielens/
fi
say "HDFS /movielens contents:"; hdfs dfs -ls -h /movielens

# --- 4. Cassandra (started only if it is not already up) ---------------------
if nodetool status >/dev/null 2>&1; then
  say "Cassandra already running."
else
  say "Starting Cassandra..."
  nohup "$CASSANDRA_HOME/bin/cassandra" > "$HOME/cassandra.log" 2>&1 &
  echo "   Waiting for Cassandra (30-60s)..."
  for i in $(seq 1 40); do nodetool status >/dev/null 2>&1 && break; sleep 3; done
  nodetool status >/dev/null 2>&1 && echo "   Cassandra is up." \
    || echo "!! Cassandra not ready — check: tail -40 ~/cassandra.log"
fi

# --- 5. EXTENSION A: HBase + Thrift (for the happybase cells) ----------------
if [ -x "$HBASE_HOME/bin/start-hbase.sh" ]; then
  if jps | grep -q HMaster; then
    say "HBase already running."
  else
    say "Starting HBase..."
    start-hbase.sh
    sleep 6
    jps | grep -q HMaster && echo "   HBase HMaster up." \
      || echo "!! HBase did not start — check: tail -40 \$HBASE_HOME/logs/*master*.log"
  fi
  # Thrift gateway (port 9090) is required by happybase.
  if ! pgrep -f "thrift" >/dev/null; then
    echo "   Starting HBase Thrift gateway (port 9090)..."
    nohup hbase thrift start > "$HOME/hbase-thrift.log" 2>&1 &
    sleep 4
  fi
else
  say "HBase not installed — Extension A cells will be skipped. (Optional.)"
fi

# --- 5. EXTENSION B: MongoDB --------------------------------------------------
if command -v mongod >/dev/null 2>&1; then
  if pgrep -x mongod >/dev/null; then
    say "MongoDB already running."
  else
    say "Starting MongoDB (port 27017)..."
    sudo mkdir -p /data/db
    sudo mongod --fork --logpath "$HOME/mongod.log"
    sleep 3
    pgrep -x mongod >/dev/null && echo "   MongoDB is up." \
      || echo "!! MongoDB did not start — check: tail -40 ~/mongod.log"
  fi
else
  say "MongoDB not installed — Extension B cells will be skipped. (Optional.)"
fi

# --- 6. Jupyter --------------------------------------------------------------
say "Launching Jupyter (open the printed 127.0.0.1:8888 URL in your browser)..."
cd "$HOME/movielens-project" || { echo "!! ~/movielens-project not found"; exit 1; }
jupyter notebook --no-browser --port 8888

//! A network that survives a restart.
//!
//! A [`Node`] holds one [`Network`] and its traffic simulator, and answers [`rpc`] calls. Opened on
//! a directory, it appends every call that changes the network to `journal.ndjson` and flushes it
//! to disk before running the call, so an answer is never given for a change that could be lost.
//! Opening the directory again loads `snapshot.json` and replays the journal after it. The network
//! does no I/O and reads no clock, so replaying the same calls gives the same network, ledger
//! included.
//!
//! [`Node::compact`] writes a new snapshot and empties the journal. Every journal line carries a
//! sequence number and the snapshot records the last one it contains, so a crash between the two
//! steps never applies a call twice.
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::metering::Simulator;
use crate::network::Network;
use crate::rpc::{self, Call};
use crate::RtnError;

const SNAPSHOT: &str = "snapshot.json";
const JOURNAL: &str = "journal.ndjson";
/// Journal lines after which the node compacts by itself.
pub const COMPACT_EVERY: u64 = 20_000;
/// The simulator's seed in a new node.
pub const SIMULATOR_SEED: u64 = 42;

#[derive(Serialize, Deserialize)]
struct Snapshot {
    seq: u64,
    network: Network,
    simulator: Simulator,
    simulating: bool,
}

#[derive(Serialize, Deserialize)]
struct Line {
    seq: u64,
    call: Value,
}

struct Store {
    dir: PathBuf,
    journal: File,
    seq: u64,
    since_compaction: u64,
}

pub struct Node {
    net: Network,
    sim: Simulator,
    simulating: bool,
    store: Option<Store>,
}

impl Node {
    /// A node that keeps nothing on disk.
    pub fn in_memory() -> Self {
        Self { net: Network::new(), sim: Simulator::new(SIMULATOR_SEED), simulating: false, store: None }
    }

    /// An in-memory node holding `net`.
    pub fn from_network(net: Network) -> Self {
        Self { net, sim: Simulator::new(SIMULATOR_SEED), simulating: false, store: None }
    }

    /// Opens (or starts) the node kept in `dir`.
    pub fn open(dir: impl AsRef<Path>) -> io::Result<Self> {
        let dir = dir.as_ref().to_path_buf();
        fs::create_dir_all(&dir)?;
        let mut node = Self::in_memory();
        let mut seq = 0;
        let snapshot_path = dir.join(SNAPSHOT);
        if snapshot_path.exists() {
            let snapshot: Snapshot = serde_json::from_slice(&fs::read(&snapshot_path)?)
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("{SNAPSHOT}: {e}")))?;
            node.net = Network::from_json(&serde_json::to_string(&snapshot.network)?)?;
            node.sim = snapshot.simulator;
            node.simulating = snapshot.simulating;
            seq = snapshot.seq;
        }
        let journal_path = dir.join(JOURNAL);
        let mut since_compaction = 0;
        if journal_path.exists() {
            let mut valid_len = 0u64;
            for raw in BufReader::new(File::open(&journal_path)?).split(b'\n') {
                let raw = raw?;
                // A line cut short by a crash is the end of the journal; it was never answered.
                let Ok(line) = serde_json::from_slice::<Line>(&raw) else { break };
                valid_len += raw.len() as u64 + 1;
                since_compaction += 1;
                if line.seq <= seq {
                    continue;
                }
                seq = line.seq;
                if let Ok(call) = serde_json::from_value::<Call>(line.call) {
                    let _ = node.dispatch(call);
                }
            }
            let file = OpenOptions::new().write(true).open(&journal_path)?;
            if file.metadata()?.len() > valid_len {
                file.set_len(valid_len)?;
                file.sync_all()?;
            }
        }
        let journal = OpenOptions::new().create(true).append(true).open(&journal_path)?;
        node.store = Some(Store { dir, journal, seq, since_compaction });
        Ok(node)
    }

    pub fn network(&self) -> &Network {
        &self.net
    }

    pub fn simulating(&self) -> bool {
        self.simulating
    }

    /// Runs one call given as JSON, journalling it first when it changes the network.
    pub fn run(&mut self, request: Value) -> Result<Value, RtnError> {
        let call: Call =
            serde_json::from_value(request.clone()).map_err(|e| RtnError::InvalidRequest { reason: e.to_string() })?;
        if call.changes_state() {
            self.journal(request).map_err(|e| RtnError::InvalidRequest { reason: format!("journal: {e}") })?;
        }
        let answer = self.dispatch(call);
        if self.store.as_ref().is_some_and(|s| s.since_compaction >= COMPACT_EVERY) {
            // A failed compaction leaves the journal as it was, which is still correct.
            let _ = self.compact();
        }
        answer
    }

    /// [`run`](Self::run) for a request in text, answered in text: `{"ok": …}` or `{"error": …}`.
    /// Never panics on bad input.
    pub fn handle_json(&mut self, request: &str) -> String {
        let answer = match serde_json::from_str::<Value>(request) {
            Ok(value) => match self.run(value) {
                Ok(value) => json!({ "ok": value }),
                Err(error) => rpc::error_json(&error),
            },
            Err(parse) => rpc::error_json(&RtnError::InvalidRequest { reason: parse.to_string() }),
        };
        answer.to_string()
    }

    fn journal(&mut self, call: Value) -> io::Result<()> {
        let Some(store) = self.store.as_mut() else { return Ok(()) };
        let line = Line { seq: store.seq + 1, call };
        let mut bytes = serde_json::to_vec(&line)?;
        bytes.push(b'\n');
        store.journal.write_all(&bytes)?;
        store.journal.sync_data()?;
        store.seq += 1;
        store.since_compaction += 1;
        Ok(())
    }

    fn dispatch(&mut self, call: Call) -> Result<Value, RtnError> {
        match call {
            Call::Simulate { seconds, now } => {
                Ok(serde_json::to_value(self.sim.tick(&mut self.net, now, seconds.clamp(1, 3_600))).expect("JSON"))
            }
            Call::Tick { now } => {
                let report = if self.simulating {
                    self.sim.tick(&mut self.net, now, 1)
                } else {
                    crate::TickReport { sms_delivered: self.net.deliver_sms(now).delivered, ..Default::default() }
                };
                Ok(serde_json::to_value(report).expect("JSON"))
            }
            Call::SetSimulator { running } => {
                self.simulating = running;
                Ok(json!({ "running": running }))
            }
            Call::Simulator => Ok(json!({ "running": self.simulating })),
            other => rpc::dispatch(&mut self.net, other),
        }
    }

    /// Writes a snapshot of everything and empties the journal.
    pub fn compact(&mut self) -> io::Result<()> {
        let Some(store) = self.store.as_mut() else { return Ok(()) };
        let snapshot = Snapshot {
            seq: store.seq,
            network: self.net.clone(),
            simulator: self.sim.clone(),
            simulating: self.simulating,
        };
        let path = store.dir.join(SNAPSHOT);
        let temp = store.dir.join(format!("{SNAPSHOT}.tmp"));
        {
            let mut file = File::create(&temp)?;
            serde_json::to_writer(&mut file, &snapshot)?;
            file.sync_all()?;
        }
        fs::rename(&temp, &path)?;
        if let Ok(dir) = File::open(&store.dir) {
            let _ = dir.sync_all();
        }
        store.journal.set_len(0)?;
        store.journal.sync_all()?;
        store.since_compaction = 0;
        Ok(())
    }
}

impl Drop for Node {
    fn drop(&mut self) {
        if let Some(store) = self.store.as_mut() {
            let _ = store.journal.sync_all();
        }
    }
}

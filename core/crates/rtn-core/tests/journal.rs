//! The durable node: every call that changes the network is appended to a journal before it is
//! answered, and opening the same directory again replays it to the same network.
use rtn_core::node::Node;
use rtn_core::rpc::Call;
use serde_json::{json, Value};

const T0: u64 = 1_800_000_000_000;

fn dir(name: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!("rtn-journal-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    path
}

fn call(node: &mut Node, value: Value) -> Value {
    let answer: Value = serde_json::from_str(&node.handle_json(&value.to_string())).unwrap();
    answer
}

#[test]
fn a_reopened_node_has_the_same_network() {
    let path = dir("reopen");
    let before = {
        let mut node = Node::open(&path).unwrap();
        call(&mut node, json!({"method": "seed", "count": 5, "seed": 1, "now": T0}));
        call(&mut node, json!({"method": "simulate", "seconds": 30, "now": T0 + 30_000}));
        let out = call(
            &mut node,
            json!({"method": "apply", "request_id": "b1", "now": T0 + 31_000,
                   "op": {"type": "buy_bundle", "msisdn": "2349990000001", "bundle_id": "daily-100mb"}}),
        );
        assert!(out.get("ok").is_some(), "{out}");
        call(&mut node, json!({"method": "snapshot"}))
    };
    let mut node = Node::open(&path).unwrap();
    assert_eq!(call(&mut node, json!({"method": "snapshot"})), before);
    let _ = std::fs::remove_dir_all(&path);
}

#[test]
fn compaction_keeps_the_network_and_empties_the_journal() {
    let path = dir("compact");
    let mut node = Node::open(&path).unwrap();
    call(&mut node, json!({"method": "seed", "count": 3, "seed": 2, "now": T0}));
    let before = call(&mut node, json!({"method": "snapshot"}));
    node.compact().unwrap();
    assert_eq!(std::fs::metadata(path.join("journal.ndjson")).unwrap().len(), 0);
    call(&mut node, json!({"method": "set_attached", "msisdn": "2349990000002", "attached": false, "now": T0}));
    drop(node);
    let mut node = Node::open(&path).unwrap();
    let after = call(&mut node, json!({"method": "subscriber", "msisdn": "2349990000002"}));
    assert_eq!(after["ok"]["attached"], false);
    assert_eq!(before["ok"]["subscribers"].as_object().unwrap().len(), 3);
    let _ = std::fs::remove_dir_all(&path);
}

#[test]
fn a_journal_line_already_in_the_snapshot_is_not_applied_twice() {
    let path = dir("twice");
    let mut node = Node::open(&path).unwrap();
    call(&mut node, json!({"method": "seed", "count": 1, "seed": 2, "now": T0}));
    call(
        &mut node,
        json!({"method": "apply", "request_id": "t1", "now": T0,
               "op": {"type": "top_up", "msisdn": "2349990000001", "amount": 100}}),
    );
    let entries =
        call(&mut node, json!({"method": "history", "msisdn": "2349990000001"}))["ok"].as_array().unwrap().len();
    // A crash between writing the snapshot and truncating the journal: put the old journal back.
    let journal = std::fs::read(path.join("journal.ndjson")).unwrap();
    node.compact().unwrap();
    drop(node);
    std::fs::write(path.join("journal.ndjson"), journal).unwrap();
    let mut node = Node::open(&path).unwrap();
    let history = call(&mut node, json!({"method": "history", "msisdn": "2349990000001"}));
    assert_eq!(history["ok"].as_array().unwrap().len(), entries, "each journalled call applied once");
    let _ = std::fs::remove_dir_all(&path);
}

#[test]
fn reads_are_not_journalled() {
    let path = dir("reads");
    let mut node = Node::open(&path).unwrap();
    call(&mut node, json!({"method": "catalog"}));
    call(&mut node, json!({"method": "subscribers"}));
    assert_eq!(std::fs::metadata(path.join("journal.ndjson")).unwrap().len(), 0);
    assert!(!Call::Catalog.changes_state());
    let _ = std::fs::remove_dir_all(&path);
}

#[test]
fn an_in_memory_node_needs_no_directory() {
    let mut node = Node::in_memory();
    let out = call(&mut node, json!({"method": "seed", "count": 2, "seed": 1, "now": T0}));
    assert_eq!(out["ok"].as_array().unwrap().len(), 2);
}

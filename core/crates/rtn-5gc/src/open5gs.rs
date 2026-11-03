//! RTN subscribers in Open5GS's subscriber database.
//!
//! Open5GS's UDR (5G) and HSS (4G) read subscribers from MongoDB, database
//! `open5gs`, collection `subscribers`, one document per IMSI. The document
//! here has the shape Open5GS's own provisioning script writes
//! (`misc/db/open5gs-dbctl add`, Open5GS 2.8.0): one slice (SST 1) with one
//! IPv4v4 session to the `internet` DNN, and the SIM's `K` and `OPc`. The
//! line's number goes in `msisdn`, which the core hands the SMF as its GPSI.

use std::collections::{HashMap, HashSet};

use futures_util::TryStreamExt;
use mongodb::bson::{doc, Bson, Document};
use mongodb::{Client, Collection};
use rtn_core::{Imsi, Status, Subscriber};

use crate::{BridgeError, SimFactory, SimKeys};

/// What the core holds for one subscriber, as far as the bridge cares.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CoreSubscriber {
    pub imsi: String,
    pub msisdn: Vec<String>,
    pub k: String,
    pub opc: String,
}

/// One change to the core's subscriber database.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Change {
    /// Write this line (add it, or bring it up to date).
    Upsert { imsi: Imsi, msisdn: String, keys: SimKeys },
    /// Take this IMSI out of the core, so it can no longer attach.
    Remove { imsi: String },
}

/// The subscriber document for an RTN line with these SIM keys.
pub fn subscriber_document(imsi: &Imsi, msisdn: &str, keys: &SimKeys) -> Document {
    let gigabit = || doc! { "value": 1_000_000_000_i32, "unit": 0_i32 };
    doc! {
        "schema_version": 1_i32,
        "imsi": imsi.as_str(),
        "msisdn": [msisdn],
        "imeisv": [],
        "mme_host": [],
        "mm_realm": [],
        "purge_flag": [],
        "slice": [{
            "sst": 1_i32,
            "default_indicator": true,
            "session": [{
                "name": "internet",
                "type": 3_i32,
                "qos": {
                    "index": 9_i32,
                    "arp": {
                        "priority_level": 8_i32,
                        "pre_emption_capability": 1_i32,
                        "pre_emption_vulnerability": 2_i32,
                    },
                },
                "ambr": { "downlink": gigabit(), "uplink": gigabit() },
                "pcc_rule": [],
            }],
        }],
        "security": {
            "k": keys.k_hex(),
            "op": Bson::Null,
            "opc": keys.opc_hex(),
            "amf": "8000",
        },
        "ambr": { "downlink": gigabit(), "uplink": gigabit() },
        // The script writes these as plain shell numbers, which MongoDB stores as doubles.
        "access_restriction_data": 32.0,
        "network_access_mode": 0.0,
        "subscriber_status": 0.0,
        "operator_determined_barring": 0.0,
        "subscribed_rau_tau_timer": 12.0,
        "__v": 0.0,
    }
}

/// What to change so that the core holds exactly RTN's active lines.
///
/// - an active line the core lacks, or holds with another number or other
///   keys, is written;
/// - a barred line is taken out, so its SIM cannot attach;
/// - an IMSI under RTN's PLMN that RTN no longer has is taken out;
/// - IMSIs outside RTN's PLMN are not RTN's and are left alone.
pub fn plan(rtn: &[Subscriber], core: &[CoreSubscriber], sims: &SimFactory) -> Vec<Change> {
    let held: HashMap<&str, &CoreSubscriber> = core.iter().map(|entry| (entry.imsi.as_str(), entry)).collect();
    let mut changes = Vec::new();
    for line in rtn {
        let imsi = line.imsi.as_str();
        match line.status {
            Status::Active => {
                let keys = sims.keys(&line.imsi);
                let msisdn = line.msisdn.to_string();
                let current = held.get(imsi).is_some_and(|entry| {
                    entry.msisdn == [msisdn.clone()] && entry.k == keys.k_hex() && entry.opc == keys.opc_hex()
                });
                if !current {
                    changes.push(Change::Upsert { imsi: line.imsi.clone(), msisdn, keys });
                }
            }
            Status::Barred => {
                if held.contains_key(imsi) {
                    changes.push(Change::Remove { imsi: imsi.to_owned() });
                }
            }
        }
    }
    let known: HashSet<&str> = rtn.iter().map(|line| line.imsi.as_str()).collect();
    for entry in core {
        if entry.imsi.starts_with(Imsi::PREFIX) && !known.contains(entry.imsi.as_str()) {
            changes.push(Change::Remove { imsi: entry.imsi.clone() });
        }
    }
    changes
}

/// Open5GS's subscriber database.
pub struct Open5gs {
    subscribers: Collection<Document>,
}

impl Open5gs {
    /// Connects to `uri` (e.g. `mongodb://127.0.0.1:27117`) and uses its
    /// `open5gs` database.
    pub async fn connect(uri: &str) -> Result<Self, BridgeError> {
        let client = Client::with_uri_str(uri).await?;
        Ok(Self { subscribers: client.database("open5gs").collection("subscribers") })
    }

    /// Every subscriber in the core.
    pub async fn list(&self) -> Result<Vec<CoreSubscriber>, BridgeError> {
        let mut cursor = self.subscribers.find(doc! {}).await?;
        let mut found = Vec::new();
        while let Some(document) = cursor.try_next().await? {
            let text = |document: &Document, key: &str| document.get_str(key).unwrap_or_default().to_owned();
            let security = document.get_document("security").cloned().unwrap_or_default();
            found.push(CoreSubscriber {
                imsi: text(&document, "imsi"),
                msisdn: document
                    .get_array("msisdn")
                    .map(|numbers| numbers.iter().filter_map(|number| number.as_str().map(str::to_owned)).collect())
                    .unwrap_or_default(),
                k: text(&security, "k"),
                opc: text(&security, "opc"),
            });
        }
        Ok(found)
    }

    /// Applies `changes`, and returns how many documents were written and removed.
    ///
    /// A line that is already there is replaced whole, which also resets the
    /// authentication sequence number the core keeps in it: a SIM whose keys
    /// changed starts its sequence again.
    pub async fn apply(&self, changes: &[Change]) -> Result<(usize, usize), BridgeError> {
        let (mut written, mut removed) = (0, 0);
        for change in changes {
            match change {
                Change::Upsert { imsi, msisdn, keys } => {
                    self.subscribers
                        .replace_one(doc! { "imsi": imsi.as_str() }, subscriber_document(imsi, msisdn, keys))
                        .upsert(true)
                        .await?;
                    written += 1;
                }
                Change::Remove { imsi } => {
                    removed += self.subscribers.delete_many(doc! { "imsi": imsi }).await?.deleted_count as usize;
                }
            }
        }
        Ok((written, removed))
    }

    /// Brings the core in line with RTN's registry: [`plan`], then [`Open5gs::apply`].
    pub async fn sync(&self, rtn: &[Subscriber], sims: &SimFactory) -> Result<(usize, usize), BridgeError> {
        let changes = plan(rtn, &self.list().await?, sims);
        self.apply(&changes).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rtn_core::Msisdn;

    fn sims() -> SimFactory {
        SimFactory::new(b"rtn test network operator secret", *b"RTN-OP-TEST-ONLY").unwrap()
    }

    fn line(n: u64, status: Status) -> Subscriber {
        Subscriber {
            msisdn: Msisdn::parse(&format!("234999{n:07}")).unwrap(),
            imsi: Imsi::issue(n),
            name: format!("Line {n}"),
            plan_id: "classic".into(),
            status,
            attached: true,
            loan_limit: 0,
            created_at: 0,
        }
    }

    fn in_core(subscriber: &Subscriber) -> CoreSubscriber {
        let keys = sims().keys(&subscriber.imsi);
        CoreSubscriber {
            imsi: subscriber.imsi.to_string(),
            msisdn: vec![subscriber.msisdn.to_string()],
            k: keys.k_hex(),
            opc: keys.opc_hex(),
        }
    }

    #[test]
    fn the_document_has_the_shape_open5gs_writes() {
        let keys = SimKeys { k: [0x46; 16], opc: [0xe8; 16] };
        let document = subscriber_document(&Imsi::issue(1), "2349990000001", &keys);
        assert_eq!(document.get_str("imsi").unwrap(), "999700000000001");
        assert_eq!(document.get_i32("schema_version").unwrap(), 1);
        let msisdn = document.get_array("msisdn").unwrap();
        assert_eq!(msisdn, &vec![Bson::String("2349990000001".into())]);
        let security = document.get_document("security").unwrap();
        assert_eq!(security.get_str("k").unwrap(), "46464646464646464646464646464646");
        assert_eq!(security.get_str("opc").unwrap(), "E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8");
        assert_eq!(security.get("op"), Some(&Bson::Null));
        assert_eq!(security.get_str("amf").unwrap(), "8000");
        let slice = document.get_array("slice").unwrap()[0].as_document().unwrap();
        assert_eq!(slice.get_i32("sst").unwrap(), 1);
        assert!(slice.get_bool("default_indicator").unwrap());
        let session = slice.get_array("session").unwrap()[0].as_document().unwrap();
        assert_eq!(session.get_str("name").unwrap(), "internet");
        assert_eq!(session.get_i32("type").unwrap(), 3, "IPv4v6");
        assert_eq!(session.get_document("qos").unwrap().get_i32("index").unwrap(), 9);
        assert!(document.get_document("ambr").unwrap().contains_key("downlink"));
        assert_eq!(document.get_f64("subscriber_status").unwrap(), 0.0);
        assert_eq!(document.get_f64("access_restriction_data").unwrap(), 32.0);
    }

    #[test]
    fn writes_active_lines_the_core_lacks() {
        let rtn = vec![line(1, Status::Active), line(2, Status::Active)];
        let changes = plan(&rtn, &[in_core(&rtn[0])], &sims());
        assert_eq!(
            changes,
            vec![Change::Upsert { imsi: Imsi::issue(2), msisdn: "2349990000002".into(), keys: sims().keys(&Imsi::issue(2)) }]
        );
    }

    #[test]
    fn a_core_in_line_with_rtn_needs_nothing() {
        let rtn = vec![line(1, Status::Active), line(2, Status::Active)];
        let core: Vec<_> = rtn.iter().map(in_core).collect();
        assert!(plan(&rtn, &core, &sims()).is_empty());
    }

    #[test]
    fn rewrites_a_line_with_another_number_or_other_keys() {
        let rtn = vec![line(1, Status::Active), line(2, Status::Active)];
        let mut core: Vec<_> = rtn.iter().map(in_core).collect();
        core[0].msisdn = vec!["2349990009999".into()];
        core[1].k = "00000000000000000000000000000000".into();
        let changes = plan(&rtn, &core, &sims());
        assert_eq!(changes.len(), 2);
        assert!(changes.iter().all(|change| matches!(change, Change::Upsert { .. })));
    }

    #[test]
    fn takes_barred_lines_out() {
        let rtn = vec![line(1, Status::Barred), line(2, Status::Barred)];
        let changes = plan(&rtn, &[in_core(&rtn[0])], &sims());
        assert_eq!(changes, vec![Change::Remove { imsi: "999700000000001".into() }]);
    }

    #[test]
    fn takes_out_rtn_imsis_rtn_no_longer_has_and_leaves_others_alone() {
        let gone = in_core(&line(9, Status::Active));
        let foreign = CoreSubscriber { imsi: "001010000000001".into(), msisdn: vec![], k: "AA".into(), opc: "BB".into() };
        let changes = plan(&[], &[gone, foreign], &sims());
        assert_eq!(changes, vec![Change::Remove { imsi: "999700000000009".into() }]);
    }
}

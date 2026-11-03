//! End to end on a real 5G core: RTN lines provisioned into Open5GS attach from
//! a UERANSIM phone and carry data through the UPF; a barred line cannot attach.
//!
//! Needs Docker and the images `net/5gc/up.sh` names. Without them the test
//! says so and passes without running. It brings the test network up with
//! `net/5gc/up.sh` and takes it down again (set RTN_5GC_KEEP=1 to keep it).

use std::path::{Path, PathBuf};
use std::process::Command;

use rtn_5gc::{ueransim, Open5gs, SimFactory};
use rtn_core::{Msisdn, Network, NewSubscriber, Status};

const MONGO: &str = "mongodb://127.0.0.1:27117";
const IMAGES: [&str; 3] = ["gradiant/open5gs:2.8.0", "gradiant/ueransim:3.3.0", "mongo:7.0"];

fn net_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../net/5gc").canonicalize().unwrap()
}

fn docker_ready() -> Result<(), String> {
    let docker = |args: &[&str]| Command::new("docker").args(args).output().is_ok_and(|out| out.status.success());
    if !docker(&["info"]) {
        return Err("Docker is not available".into());
    }
    match IMAGES.iter().find(|image| !docker(&["image", "inspect", image])) {
        Some(image) => Err(format!("the image {image} is not pulled")),
        None => Ok(()),
    }
}

fn run(program: &Path, args: &[&str]) -> (bool, String) {
    let out = Command::new(program).args(args).output().expect("run a script");
    let text = format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    (out.status.success(), text)
}

fn docker(args: &[&str]) -> (bool, String) {
    run(Path::new("docker"), args)
}

/// Takes the test network down when the test ends, however it ends.
struct Network5g(PathBuf);

impl Drop for Network5g {
    fn drop(&mut self) {
        for name in ["rtn5g-ue-e2e-1", "rtn5g-ue-e2e-3"] {
            let _ = docker(&["rm", "-f", name]);
        }
        if std::env::var_os("RTN_5GC_KEEP").is_none() {
            let _ = run(&self.0.join("down.sh"), &[]);
        }
    }
}

fn line(network: &mut Network, number: &str, name: &str) -> rtn_core::Subscriber {
    let new = NewSubscriber {
        msisdn: Msisdn::parse(number).unwrap(),
        imsi: None,
        name: name.into(),
        plan_id: None,
        pin: "1234".into(),
    };
    network.add_subscriber(new, 0).unwrap()
}

#[tokio::test(flavor = "multi_thread")]
async fn rtn_lines_attach_to_open5gs_and_a_barred_line_cannot() {
    if let Err(reason) = docker_ready() {
        eprintln!("skipped: {reason}");
        return;
    }
    let net = net_dir();
    let (up, log) = run(&net.join("up.sh"), &[]);
    assert!(up, "net/5gc/up.sh failed:\n{log}");
    let _network = Network5g(net.clone());

    // RTN's registry: three lines, the third barred.
    let mut rtn = Network::new();
    let first = line(&mut rtn, "2349990000001", "Ada Okafor");
    let second = line(&mut rtn, "2349990000002", "Bayo Adeyemi");
    let third = line(&mut rtn, "2349990000003", "Chioma Eze");
    rtn.set_status(&third.msisdn, Status::Barred).unwrap();
    let lines: Vec<_> = rtn.subscribers().cloned().collect();

    let sims = SimFactory::new(b"rtn 5g end-to-end test secret!!", *b"RTN-OP-TEST-ONLY").unwrap();
    let core = Open5gs::connect(MONGO).await.unwrap();
    core.sync(&lines, &sims).await.unwrap();

    let held = core.list().await.unwrap();
    for active in [&first, &second] {
        let entry = held.iter().find(|entry| entry.imsi == active.imsi.as_str()).expect("an active line is in the core");
        assert_eq!(entry.msisdn, vec![active.msisdn.to_string()]);
        assert_eq!(entry.k, sims.keys(&active.imsi).k_hex());
    }
    assert!(!held.iter().any(|entry| entry.imsi == third.imsi.as_str()), "a barred line is not in the core");
    // A second sync has nothing to do.
    assert_eq!(core.sync(&lines, &sims).await.unwrap(), (0, 0));

    // The first line's phone attaches, gets an address from the UPF's pool and reaches the UPF.
    let scratch = std::env::temp_dir().join(format!("rtn-5gc-e2e-{}", std::process::id()));
    std::fs::create_dir_all(&scratch).unwrap();
    let config = |subscriber: &rtn_core::Subscriber| {
        let path = scratch.join(format!("ue-{}.yaml", subscriber.msisdn));
        std::fs::write(&path, ueransim::ue_config(&subscriber.imsi, &sims.keys(&subscriber.imsi), "10.99.0.10")).unwrap();
        path
    };
    let first_config = config(&first);
    let (attached, log) = run(&net.join("ue.sh"), &["e2e-1", first_config.to_str().unwrap()]);
    assert!(attached, "the active line did not get a PDU session:\n{log}");
    assert!(log.contains("10.45."), "the UE's address is from the UPF's pool: {log}");
    let (pinged, log) = docker(&["exec", "rtn5g-ue-e2e-1", "ping", "-c", "3", "-I", "uesimtun0", "10.45.0.1"]);
    assert!(pinged && log.contains("3 received"), "no data through the UPF:\n{log}");

    // The barred line's phone is refused.
    let third_config = config(&third);
    let (attached, log) = run(&net.join("ue.sh"), &["e2e-3", third_config.to_str().unwrap()]);
    assert!(!attached, "a barred line got a PDU session:\n{log}");
    let (_, ue_log) = docker(&["logs", "rtn5g-ue-e2e-3"]);
    assert!(ue_log.contains("Registration Reject") || ue_log.contains("Authentication Reject") || ue_log.contains("failed"), "{ue_log}");
    let _ = std::fs::remove_dir_all(&scratch);
}

mod support;
use rtn_core::{seed, Network, Simulator};
use support::*;

#[test]
fn seeding_creates_subscribers_with_known_pins_on_the_first_five() {
    let mut net = Network::new();
    let seeded = seed::populate(&mut net, 20, 7, T0).unwrap();
    assert_eq!(seeded.len(), 20);
    assert_eq!(net.subscribers().count(), 20);
    assert!(seeded[..5].iter().all(|s| s.pin == "1234"));
    assert!(net.verify_pin(&seeded[0].msisdn, "1234", T0).is_ok());
    assert!(net.balance(&seeded[0].msisdn, T0).unwrap().airtime > 0);
}

#[test]
fn the_simulator_is_deterministic_for_a_seed() {
    let run = |seed_value: u64| {
        let mut net = Network::new();
        seed::populate(&mut net, 30, 1, T0).unwrap();
        let mut sim = Simulator::new(seed_value);
        let mut now = T0;
        let mut reports = Vec::new();
        for _ in 0..60 {
            now += 1_000;
            reports.push(sim.tick(&mut net, now, 1));
        }
        (reports, net.ledger().len(), net.totals())
    };
    assert_eq!(run(42), run(42));
    assert_ne!(run(42).1, 0);
}

#[test]
fn the_simulator_produces_live_traffic() {
    let mut net = Network::new();
    seed::populate(&mut net, 40, 3, T0).unwrap();
    let mut sim = Simulator::new(9);
    let mut now = T0;
    for _ in 0..30 {
        now += 1_000;
        sim.tick(&mut net, now, 1);
    }
    let traffic = net.traffic(now);
    assert!(traffic.totals.data_bytes > 0);
    assert!(traffic.totals.sms > 0);
    assert!(traffic.totals.charges > 0);
    assert_eq!(traffic.series.len(), 60);
    assert!(traffic.series.iter().any(|s| s.data_bytes > 0));
    assert_eq!(traffic.subscribers, 40);
}

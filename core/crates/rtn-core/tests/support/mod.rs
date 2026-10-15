#![allow(dead_code)]
use rtn_core::{Msisdn, Network, NewSubscriber, Op};

pub const T0: u64 = 1_800_000_000_000;

pub fn msisdn(last: u32) -> Msisdn {
    Msisdn::parse(&format!("234999{last:07}")).unwrap()
}

/// A network with `count` active subscribers on the default plan, PIN 1234, each topped up
/// with `airtime` minor units.
pub fn network_with(count: u32, airtime: u64) -> Network {
    let mut net = Network::new();
    for n in 1..=count {
        net.add_subscriber(
            NewSubscriber {
                msisdn: msisdn(n),
                imsi: None,
                name: format!("Subscriber {n}"),
                plan_id: None,
                pin: "1234".into(),
            },
            T0,
        )
        .unwrap();
        if airtime > 0 {
            net.apply(&format!("seed-{n}"), Op::TopUp { msisdn: msisdn(n), amount: airtime, via: None }, T0).unwrap();
        }
    }
    net
}

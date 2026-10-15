mod support;
use rtn_core::{Imsi, Msisdn, Network, NewSubscriber, RtnError, Status};
use support::*;

#[test]
fn msisdn_normalises_local_and_international_forms() {
    let full = Msisdn::parse("2349990000001").unwrap();
    assert_eq!(Msisdn::parse("+2349990000001").unwrap(), full);
    assert_eq!(Msisdn::parse("09990000001").unwrap(), full);
    assert_eq!(Msisdn::parse(" 234 999 000 0001 ").unwrap(), full);
    assert!(Msisdn::parse("12ab").is_err());
    assert!(Msisdn::parse("123").is_err());
}

#[test]
fn imsi_is_fifteen_digits() {
    assert!(Imsi::parse("999700000000001").is_ok());
    assert!(Imsi::parse("99970000000000").is_err());
    assert!(Imsi::parse("99970000000000x").is_err());
}

#[test]
fn adds_and_finds_subscribers_by_msisdn_and_imsi() {
    let net = network_with(3, 0);
    let sub = net.subscriber(&msisdn(2)).unwrap();
    assert_eq!(sub.name, "Subscriber 2");
    assert_eq!(net.subscriber_by_imsi(&sub.imsi).unwrap().msisdn, msisdn(2));
    assert_eq!(net.subscribers().count(), 3);
}

#[test]
fn refuses_duplicate_msisdn_and_imsi() {
    let mut net = network_with(1, 0);
    let existing = net.subscriber(&msisdn(1)).unwrap().imsi.clone();
    let again =
        NewSubscriber { msisdn: msisdn(1), imsi: None, name: "Again".into(), plan_id: None, pin: "1234".into() };
    assert!(matches!(net.add_subscriber(again, T0), Err(RtnError::DuplicateSubscriber)));
    let same_imsi = NewSubscriber {
        msisdn: msisdn(9),
        imsi: Some(existing),
        name: "Clone".into(),
        plan_id: None,
        pin: "1234".into(),
    };
    assert!(matches!(net.add_subscriber(same_imsi, T0), Err(RtnError::DuplicateImsi)));
}

#[test]
fn pin_must_be_four_to_six_digits() {
    let mut net = Network::new();
    let bad = NewSubscriber { msisdn: msisdn(1), imsi: None, name: "A".into(), plan_id: None, pin: "12a4".into() };
    assert!(matches!(net.add_subscriber(bad, T0), Err(RtnError::InvalidPin)));
}

#[test]
fn wrong_pins_lock_the_subscriber_for_a_while() {
    let mut net = network_with(1, 0);
    assert!(net.verify_pin(&msisdn(1), "1234", T0).is_ok());
    for _ in 0..3 {
        assert!(matches!(net.verify_pin(&msisdn(1), "0000", T0), Err(RtnError::WrongPin)));
    }
    assert!(matches!(net.verify_pin(&msisdn(1), "1234", T0), Err(RtnError::PinLocked { .. })));
    assert!(net.verify_pin(&msisdn(1), "1234", T0 + 5 * 60_000 + 1).is_ok());
}

#[test]
fn barring_a_subscriber_stops_charging_but_not_top_ups() {
    let mut net = network_with(2, 10_000);
    net.set_status(&msisdn(1), Status::Barred).unwrap();
    let data = net.apply("d1", rtn_core::Op::DataUsage { msisdn: msisdn(1), bytes: 1000 }, T0);
    assert!(matches!(data, Err(RtnError::Barred)));
    assert!(net.apply("t1", rtn_core::Op::TopUp { msisdn: msisdn(1), amount: 100, via: None }, T0).is_ok());
}

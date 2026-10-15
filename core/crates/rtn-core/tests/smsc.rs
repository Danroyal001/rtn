mod support;
use rtn_core::{segments, Detail, Op, RtnError, SmsState};
use support::*;

#[test]
fn counts_segments_like_a_handset() {
    assert_eq!(segments("hello"), 1);
    assert_eq!(segments(&"a".repeat(160)), 1);
    assert_eq!(segments(&"a".repeat(161)), 2);
    assert_eq!(segments(&"a".repeat(306)), 2);
    assert_eq!(segments(&"a".repeat(307)), 3);
    // ₦ is not in GSM-7, so the message is UCS-2.
    assert_eq!(segments(&"₦".repeat(70)), 1);
    assert_eq!(segments(&"₦".repeat(71)), 2);
    // Extension characters take two septets.
    assert_eq!(segments(&"€".repeat(80)), 1);
    assert_eq!(segments(&"€".repeat(81)), 2);
}

#[test]
fn delivers_to_an_attached_subscriber_and_reports_back() {
    let mut net = network_with(2, 10_000);
    let price = net.catalog().plan("pulse").unwrap().sms_per_segment;
    let out = net.apply("m1", Op::SmsSubmit { from: msisdn(1), to: msisdn(2), text: "hi".into() }, T0).unwrap();
    assert_eq!(out.charged, price);
    let Detail::Sms { message_id, segments } = out.detail else { panic!() };
    assert_eq!(segments, 1);
    let run = net.deliver_sms(T0);
    assert_eq!(run.delivered, 1);
    let inbox = net.inbox(&msisdn(2));
    assert_eq!(inbox.len(), 1);
    assert_eq!(inbox[0].text, "hi");
    let sent = net.message(&message_id).unwrap();
    assert_eq!(sent.state, SmsState::Delivered);
    let reports = net.delivery_reports(&msisdn(1));
    assert_eq!(reports.len(), 1);
    assert_eq!(reports[0].message_id, message_id);
    assert_eq!(reports[0].state, SmsState::Delivered);
}

#[test]
fn stores_while_detached_and_forwards_on_attach() {
    let mut net = network_with(2, 10_000);
    net.set_attached(&msisdn(2), false, T0).unwrap();
    net.apply("m1", Op::SmsSubmit { from: msisdn(1), to: msisdn(2), text: "later".into() }, T0).unwrap();
    let run = net.deliver_sms(T0);
    assert_eq!((run.delivered, run.retried), (0, 1));
    assert!(net.inbox(&msisdn(2)).is_empty());
    net.set_attached(&msisdn(2), true, T0 + 1_000).unwrap();
    assert_eq!(net.inbox(&msisdn(2)).len(), 1);
}

#[test]
fn expires_after_the_validity_period_and_reports_failure() {
    let mut net = network_with(2, 10_000);
    net.set_attached(&msisdn(2), false, T0).unwrap();
    let out = net.apply("m1", Op::SmsSubmit { from: msisdn(1), to: msisdn(2), text: "x".into() }, T0).unwrap();
    let Detail::Sms { message_id, .. } = out.detail else { panic!() };
    let mut now = T0;
    for _ in 0..100 {
        now += 15 * 60_000;
        net.deliver_sms(now);
    }
    assert_eq!(net.message(&message_id).unwrap().state, SmsState::Expired);
    assert_eq!(net.delivery_reports(&msisdn(1))[0].state, SmsState::Expired);
}

#[test]
fn refuses_empty_too_long_and_unaffordable_messages() {
    let mut net = network_with(2, 0);
    assert!(matches!(
        net.apply("a", Op::SmsSubmit { from: msisdn(1), to: msisdn(2), text: "hi".into() }, T0),
        Err(RtnError::InsufficientFunds { .. })
    ));
    net.apply("t", Op::TopUp { msisdn: msisdn(1), amount: 100_000, via: None }, T0).unwrap();
    assert!(matches!(
        net.apply("b", Op::SmsSubmit { from: msisdn(1), to: msisdn(2), text: String::new() }, T0),
        Err(RtnError::InvalidMessage { .. })
    ));
    assert!(matches!(
        net.apply("c", Op::SmsSubmit { from: msisdn(1), to: msisdn(2), text: "a".repeat(2_000) }, T0),
        Err(RtnError::InvalidMessage { .. })
    ));
}

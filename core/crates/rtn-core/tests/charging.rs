mod support;
use rtn_core::{Detail, EntryKind, Op, RtnError, MB};
use support::*;

#[test]
fn top_up_adds_airtime_and_writes_the_ledger() {
    let mut net = network_with(1, 0);
    let out = net.apply("t1", Op::TopUp { msisdn: msisdn(1), amount: 50_000 }, T0).unwrap();
    assert_eq!(out.balance.airtime, 50_000);
    let history = net.history(&msisdn(1));
    assert_eq!(history.len(), 1);
    assert_eq!(history[0].kind, EntryKind::TopUp);
    assert_eq!(history[0].airtime_after, 50_000);
}

#[test]
fn replaying_a_request_returns_the_first_result_and_charges_once() {
    let mut net = network_with(1, 100_000);
    let first = net.apply("b1", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "daily-100mb".into() }, T0).unwrap();
    let again = net.apply("b1", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "daily-100mb".into() }, T0 + 9).unwrap();
    assert_eq!(first, again);
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().airtime, 100_000 - 10_000);
}

#[test]
fn reusing_a_request_id_for_a_different_operation_is_refused() {
    let mut net = network_with(1, 100_000);
    net.apply("x", Op::TopUp { msisdn: msisdn(1), amount: 1 }, T0).unwrap();
    let other = net.apply("x", Op::TopUp { msisdn: msisdn(1), amount: 2 }, T0);
    assert!(matches!(other, Err(RtnError::RequestConflict)));
}

#[test]
fn bundles_are_bought_from_airtime_and_used_before_airtime() {
    let mut net = network_with(1, 100_000);
    net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "daily-100mb".into() }, T0).unwrap();
    let out = net.apply("d", Op::DataUsage { msisdn: msisdn(1), bytes: 40 * MB }, T0).unwrap();
    assert_eq!(out.charged, 0);
    assert_eq!(out.balance.data_bytes, 60 * MB);
    // 70 MB more: 60 from the bundle, 10 MB pay-as-you-go.
    let out = net.apply("d2", Op::DataUsage { msisdn: msisdn(1), bytes: 70 * MB }, T0).unwrap();
    let rate = net.catalog().plan("pulse").unwrap().data_per_mb;
    assert_eq!(out.charged, 10 * rate);
    assert_eq!(out.balance.data_bytes, 0);
}

#[test]
fn data_that_cannot_be_paid_for_changes_nothing() {
    let mut net = network_with(1, 100);
    let before = net.balance(&msisdn(1), T0).unwrap();
    let out = net.apply("d", Op::DataUsage { msisdn: msisdn(1), bytes: 500 * MB }, T0);
    assert!(matches!(out, Err(RtnError::InsufficientFunds { .. })));
    assert_eq!(net.balance(&msisdn(1), T0).unwrap(), before);
}

#[test]
fn bundles_expire_with_a_ledger_entry() {
    let mut net = network_with(1, 100_000);
    net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "daily-100mb".into() }, T0).unwrap();
    let later = T0 + 24 * 3_600_000 + 1;
    assert_eq!(net.balance(&msisdn(1), later).unwrap().data_bytes, 0);
    assert_eq!(net.history(&msisdn(1)).last().unwrap().kind, EntryKind::BundleExpired);
}

#[test]
fn voice_reserves_then_bills_exact_seconds_and_releases_the_rest() {
    let mut net = network_with(2, 10_000);
    let rate = net.catalog().plan("pulse").unwrap().voice_per_second;
    let start = net.apply("call-1", Op::VoiceStart { msisdn: msisdn(1), callee: msisdn(2).to_string() }, T0).unwrap();
    let Detail::VoiceGranted { granted_seconds, .. } = start.detail else { panic!("{start:?}") };
    assert!(granted_seconds > 0);
    assert_eq!(start.balance.reserved, granted_seconds * rate);
    let end =
        net.apply("call-1:end", Op::VoiceEnd { session_id: "call-1".into(), used_seconds: 37 }, T0 + 37_000).unwrap();
    assert_eq!(end.charged, 37 * rate);
    assert_eq!(end.balance.reserved, 0);
    assert_eq!(end.balance.airtime, 10_000 - 37 * rate);
}

#[test]
fn a_call_is_cut_at_its_grant() {
    let mut net = network_with(2, 1_000);
    let rate = net.catalog().plan("pulse").unwrap().voice_per_second;
    let start = net.apply("c", Op::VoiceStart { msisdn: msisdn(1), callee: "08031234567".into() }, T0).unwrap();
    let Detail::VoiceGranted { granted_seconds, .. } = start.detail else { panic!() };
    assert_eq!(granted_seconds, 1_000 / rate);
    let end = net.apply("c:end", Op::VoiceEnd { session_id: "c".into(), used_seconds: 99_999 }, T0).unwrap();
    assert_eq!(end.charged, granted_seconds * rate);
}

#[test]
fn reserved_airtime_cannot_be_spent_twice() {
    let mut net = network_with(2, 1_000);
    net.apply("c", Op::VoiceStart { msisdn: msisdn(1), callee: "x".into() }, T0).unwrap();
    let out = net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "daily-100mb".into() }, T0);
    assert!(matches!(out, Err(RtnError::InsufficientFunds { .. })));
}

#[test]
fn transfer_moves_airtime_and_charges_a_fee() {
    let mut net = network_with(2, 100_000);
    let out = net.apply("tr", Op::Transfer { from: msisdn(1), to: msisdn(2), amount: 20_000 }, T0).unwrap();
    let Detail::Transfer { fee, .. } = out.detail else { panic!() };
    assert_eq!(out.balance.airtime, 100_000 - 20_000 - fee);
    assert_eq!(net.balance(&msisdn(2), T0).unwrap().airtime, 120_000);
    assert!(matches!(
        net.apply("self", Op::Transfer { from: msisdn(1), to: msisdn(1), amount: 20_000 }, T0),
        Err(RtnError::SelfTransfer)
    ));
    assert!(matches!(
        net.apply("tiny", Op::Transfer { from: msisdn(1), to: msisdn(2), amount: 1 }, T0),
        Err(RtnError::InvalidAmount { .. })
    ));
}

#[test]
fn borrowing_lends_airtime_and_the_next_top_up_repays_it_with_a_fee() {
    let mut net = network_with(1, 0);
    let out = net.apply("loan", Op::Borrow { msisdn: msisdn(1), amount: 20_000 }, T0).unwrap();
    assert_eq!(out.balance.airtime, 20_000);
    assert_eq!(out.balance.loan, 22_000);
    assert!(matches!(
        net.apply("loan2", Op::Borrow { msisdn: msisdn(1), amount: 1_000 }, T0),
        Err(RtnError::LoanOutstanding { .. })
    ));
    let out = net.apply("top", Op::TopUp { msisdn: msisdn(1), amount: 50_000 }, T0).unwrap();
    assert_eq!(out.balance.loan, 0);
    assert_eq!(out.balance.airtime, 20_000 + 50_000 - 22_000);
    let kinds: Vec<EntryKind> = net.history(&msisdn(1)).iter().map(|e| e.kind).collect();
    assert_eq!(kinds, vec![EntryKind::Loan, EntryKind::TopUp, EntryKind::LoanRepayment]);
}

#[test]
fn borrowing_above_the_limit_is_refused() {
    let mut net = network_with(1, 0);
    let limit = net.balance(&msisdn(1), T0).unwrap().loan_limit;
    assert!(matches!(
        net.apply("l", Op::Borrow { msisdn: msisdn(1), amount: limit + 1 }, T0),
        Err(RtnError::LoanLimit { .. })
    ));
}

#[test]
fn unknown_things_are_named() {
    let mut net = network_with(1, 100_000);
    assert!(matches!(
        net.apply("u", Op::TopUp { msisdn: msisdn(77), amount: 1 }, T0),
        Err(RtnError::UnknownSubscriber)
    ));
    assert!(matches!(
        net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "nope".into() }, T0),
        Err(RtnError::UnknownBundle)
    ));
    assert!(matches!(
        net.apply("v", Op::VoiceEnd { session_id: "nope".into(), used_seconds: 1 }, T0),
        Err(RtnError::UnknownSession)
    ));
}

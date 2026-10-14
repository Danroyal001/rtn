//! Charging invariants, checked against random sequences of operations.
mod support;
use proptest::prelude::*;
use rtn_core::{Network, Op, MB};
use support::*;

const SUBS: u32 = 4;

fn op_strategy() -> impl Strategy<Value = (u8, Op, u64)> {
    let who = 1..=SUBS;
    let op = prop_oneof![
        (who.clone(), 0u64..200_000).prop_map(|(n, amount)| Op::TopUp { msisdn: msisdn(n), amount }),
        (who.clone(), prop::sample::select(vec!["daily-100mb", "weekly-1gb", "monthly-3gb", "nope"]))
            .prop_map(|(n, b)| Op::BuyBundle { msisdn: msisdn(n), bundle_id: b.into() }),
        (who.clone(), who.clone(), 0u64..60_000)
            .prop_map(|(a, b, amount)| Op::Transfer { from: msisdn(a), to: msisdn(b), amount }),
        (who.clone(), 0u64..60_000).prop_map(|(n, amount)| Op::Borrow { msisdn: msisdn(n), amount }),
        (who.clone(), 0u64..(300 * MB)).prop_map(|(n, bytes)| Op::DataUsage { msisdn: msisdn(n), bytes }),
        (who.clone(), 0u32..8).prop_map(|(n, k)| Op::VoiceStart { msisdn: msisdn(n), callee: format!("call-{k}") }),
        (0u32..8, 0u64..2_000).prop_map(|(k, used)| Op::VoiceEnd { session_id: format!("v{k}"), used_seconds: used }),
        (who.clone(), who, "[a-z ]{0,400}")
            .prop_map(|(a, b, text)| Op::SmsSubmit { from: msisdn(a), to: msisdn(b), text }),
    ];
    // (request id slot, op, time step in seconds). A small id space makes replays common.
    (0u8..40, op, 0u64..7_200)
}

fn request_id(slot: u8, op: &Op) -> String {
    match op {
        // Voice sessions are named by the request that started them.
        Op::VoiceStart { callee, .. } => format!("v{}", &callee[5..]),
        Op::VoiceEnd { session_id, .. } => format!("{session_id}:end"),
        _ => format!("r{slot}"),
    }
}

fn check_invariants(net: &mut Network, now: u64) {
    let mut total_airtime = 0u64;
    for n in 1..=SUBS {
        let b = net.balance(&msisdn(n), now).unwrap();
        assert!(b.reserved <= b.airtime, "reserved {} > airtime {}", b.reserved, b.airtime);
        let (mut air, mut data, mut loan) = (0i128, 0i128, 0i128);
        for e in net.history(&msisdn(n)) {
            air += e.airtime_delta as i128;
            data += e.data_delta as i128;
            loan += e.loan_delta as i128;
        }
        assert_eq!(air, b.airtime as i128, "airtime equals the sum of its ledger");
        assert_eq!(data, b.data_bytes as i128, "data equals the sum of its ledger");
        assert_eq!(loan, b.loan as i128, "loan equals the sum of its ledger");
        total_airtime += b.airtime;
    }
    let t = net.totals();
    assert_eq!(
        total_airtime as u128 + t.revenue as u128 + t.repaid as u128,
        t.topped_up as u128 + t.lent as u128,
        "money is conserved"
    );
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 256, ..ProptestConfig::default() })]

    #[test]
    fn invariants_hold_for_any_sequence(steps in prop::collection::vec(op_strategy(), 1..120)) {
        let mut net = network_with(SUBS, 0);
        let mut now = T0;
        for (slot, op, step) in steps {
            now += step * 1000;
            let id = request_id(slot, &op);
            let _ = net.apply(&id, op, now);
            net.deliver_sms(now);
            check_invariants(&mut net, now);
        }
    }

    #[test]
    fn replaying_a_successful_request_changes_nothing(steps in prop::collection::vec(op_strategy(), 1..60)) {
        let mut net = network_with(SUBS, 100_000);
        let mut now = T0;
        for (slot, op, step) in steps {
            now += step * 1000;
            let id = request_id(slot, &op);
            if let Ok(first) = net.apply(&id, op.clone(), now) {
                let ledger_len = net.ledger().len();
                let totals = net.totals();
                let again = net.apply(&id, op, now).unwrap();
                prop_assert_eq!(first, again);
                prop_assert_eq!(ledger_len, net.ledger().len());
                prop_assert_eq!(totals, net.totals());
            }
        }
    }

    #[test]
    fn transfers_conserve_money(amount in 0u64..300_000, start in 0u64..300_000) {
        let mut net = network_with(2, start);
        let before = net.balance(&msisdn(1), T0).unwrap().airtime + net.balance(&msisdn(2), T0).unwrap().airtime;
        let revenue = net.totals().revenue;
        let result = net.apply("t", Op::Transfer { from: msisdn(1), to: msisdn(2), amount }, T0);
        let after = net.balance(&msisdn(1), T0).unwrap().airtime + net.balance(&msisdn(2), T0).unwrap().airtime;
        let fee = net.totals().revenue - revenue;
        prop_assert_eq!(before, after + fee);
        if result.is_err() { prop_assert_eq!(fee, 0); }
    }
}

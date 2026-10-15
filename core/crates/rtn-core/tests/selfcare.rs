//! What the MyRTN app needs from the core beyond milestone 1: one-time codes over the SMS centre,
//! recharge vouchers, recharges from a payment channel, bundle gifts, data sharing, loyalty
//! points, notifications and line management.
mod support;
use rtn_core::{Detail, EntryKind, Msisdn, Op, RtnError, Status, MB};
use support::*;

fn service() -> Msisdn {
    Msisdn::service()
}

fn last_code(net: &rtn_core::Network, to: &Msisdn) -> String {
    let text = net.inbox(to).last().expect("a message").text.clone();
    text.chars().filter(char::is_ascii_digit).take(6).collect()
}

// ----- one-time codes ----------------------------------------------------------------------

#[test]
fn a_sign_in_code_arrives_by_sms_from_the_service_number_and_works_once() {
    let mut net = network_with(1, 0);
    let issued = net.request_otp(&msisdn(1), 7, T0).unwrap();
    assert_eq!(issued.expires_at, T0 + rtn_core::OTP_VALIDITY_MS);
    net.deliver_sms(T0);
    let inbox = net.inbox(&msisdn(1));
    assert_eq!(inbox.len(), 1);
    assert_eq!(inbox[0].from, service());
    let code = last_code(&net, &msisdn(1));
    assert_eq!(code.len(), 6);
    net.verify_otp(&msisdn(1), &code, T0 + 1_000).unwrap();
    assert_eq!(net.verify_otp(&msisdn(1), &code, T0 + 2_000), Err(RtnError::CodeExpired));
}

#[test]
fn sign_in_codes_cost_the_subscriber_nothing() {
    let mut net = network_with(1, 5_000);
    net.request_otp(&msisdn(1), 1, T0).unwrap();
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().airtime, 5_000);
}

#[test]
fn a_wrong_code_is_refused_and_five_wrong_codes_burn_it() {
    let mut net = network_with(1, 0);
    net.request_otp(&msisdn(1), 9, T0).unwrap();
    net.deliver_sms(T0);
    let code = last_code(&net, &msisdn(1));
    let wrong = if code == "000000" { "111111" } else { "000000" };
    for _ in 0..4 {
        assert_eq!(net.verify_otp(&msisdn(1), wrong, T0), Err(RtnError::WrongCode));
    }
    assert_eq!(net.verify_otp(&msisdn(1), wrong, T0), Err(RtnError::CodeExpired));
    assert_eq!(net.verify_otp(&msisdn(1), &code, T0), Err(RtnError::CodeExpired));
}

#[test]
fn codes_expire_and_cannot_be_requested_back_to_back() {
    let mut net = network_with(1, 0);
    net.request_otp(&msisdn(1), 1, T0).unwrap();
    assert!(matches!(net.request_otp(&msisdn(1), 2, T0 + 1_000), Err(RtnError::TooSoon { .. })));
    net.deliver_sms(T0);
    let code = last_code(&net, &msisdn(1));
    assert_eq!(net.verify_otp(&msisdn(1), &code, T0 + rtn_core::OTP_VALIDITY_MS), Err(RtnError::CodeExpired));
    net.request_otp(&msisdn(1), 3, T0 + rtn_core::OTP_RESEND_MS).unwrap();
}

#[test]
fn codes_are_for_subscribers_only() {
    let mut net = network_with(1, 0);
    assert_eq!(net.request_otp(&msisdn(9), 1, T0).err(), Some(RtnError::UnknownSubscriber));
}

// ----- vouchers and recharges ------------------------------------------------------------

#[test]
fn a_voucher_recharges_once_and_repays_a_loan_first() {
    let mut net = network_with(2, 0);
    let batch = net.issue_vouchers(3, 50_000, 11, T0).unwrap();
    assert_eq!(batch.len(), 3);
    assert!(batch.iter().all(|v| v.pin.len() == 16 && v.amount == 50_000));
    net.apply("loan", Op::Borrow { msisdn: msisdn(1), amount: 10_000 }, T0).unwrap();
    let out = net.apply("v1", Op::RedeemVoucher { msisdn: msisdn(1), pin: batch[0].pin.clone() }, T0).unwrap();
    assert_eq!(out.detail, Detail::Voucher { serial: batch[0].serial.clone(), amount: 50_000, repaid: 11_000 });
    assert_eq!(out.balance.airtime, 10_000 + 50_000 - 11_000);
    let again = net.apply("v2", Op::RedeemVoucher { msisdn: msisdn(2), pin: batch[0].pin.clone() }, T0);
    assert_eq!(again.err(), Some(RtnError::VoucherUsed));
    let listed = net.vouchers();
    assert_eq!(listed.iter().filter(|v| v.used_by.is_some()).count(), 1);
    assert_eq!(net.totals().topped_up, 50_000);
}

#[test]
fn voucher_pins_are_typed_with_spaces_or_dashes_and_guessing_locks_the_line_out() {
    let mut net = network_with(1, 0);
    let batch = net.issue_vouchers(1, 10_000, 5, T0).unwrap();
    let spaced: String = batch[0]
        .pin
        .chars()
        .enumerate()
        .flat_map(|(i, c)| if i > 0 && i % 4 == 0 { vec![' ', c] } else { vec![c] })
        .collect();
    for n in 0..5 {
        let r =
            net.apply(&format!("g{n}"), Op::RedeemVoucher { msisdn: msisdn(1), pin: "1234123412341234".into() }, T0);
        assert_eq!(r.err(), Some(RtnError::UnknownVoucher));
    }
    let locked = net.apply("ok", Op::RedeemVoucher { msisdn: msisdn(1), pin: spaced.clone() }, T0);
    assert!(matches!(locked, Err(RtnError::VoucherLocked { .. })));
    let later = T0 + rtn_core::VOUCHER_LOCK_MS;
    net.apply("ok2", Op::RedeemVoucher { msisdn: msisdn(1), pin: spaced }, later).unwrap();
}

#[test]
fn a_recharge_names_its_channel_in_the_ledger() {
    let mut net = network_with(1, 0);
    net.apply("card-1", Op::TopUp { msisdn: msisdn(1), amount: 20_000, via: Some("card •••• 4242".into()) }, T0)
        .unwrap();
    let entry = net.history(&msisdn(1)).last().copied().unwrap().clone();
    assert_eq!(entry.kind, EntryKind::TopUp);
    assert!(entry.note.contains("card •••• 4242"), "{}", entry.note);
}

// ----- gifts and sharing ------------------------------------------------------------------

#[test]
fn a_bundle_can_be_bought_for_someone_else() {
    let mut net = network_with(2, 100_000);
    let out = net
        .apply(
            "gift",
            Op::BuyBundle { msisdn: msisdn(1), bundle_id: "weekly-1gb".into(), beneficiary: Some(msisdn(2)) },
            T0,
        )
        .unwrap();
    assert_eq!(out.charged, 50_000);
    assert_eq!(out.balance.airtime, 50_000);
    assert_eq!(out.balance.data_bytes, 0);
    let theirs = net.balance(&msisdn(2), T0).unwrap();
    assert_eq!(theirs.data_bytes, 1024 * MB);
    assert_eq!(theirs.airtime, 100_000);
    let kinds: Vec<EntryKind> = net.history(&msisdn(2)).iter().map(|e| e.kind).collect();
    assert!(kinds.contains(&EntryKind::BundleReceived));
}

#[test]
fn data_can_be_shared_from_bundles_and_is_conserved() {
    let mut net = network_with(2, 100_000);
    net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "weekly-1gb".into(), beneficiary: None }, T0).unwrap();
    let out = net.apply("s", Op::ShareData { from: msisdn(1), to: msisdn(2), bytes: 200 * MB }, T0).unwrap();
    assert_eq!(out.charged, 0);
    assert_eq!(out.balance.data_bytes, 824 * MB);
    assert_eq!(net.balance(&msisdn(2), T0).unwrap().data_bytes, 200 * MB);
    let too_much = net.apply("s2", Op::ShareData { from: msisdn(1), to: msisdn(2), bytes: 900 * MB }, T0);
    assert!(matches!(too_much, Err(RtnError::InsufficientData { .. })));
    let tiny = net.apply("s3", Op::ShareData { from: msisdn(1), to: msisdn(2), bytes: MB }, T0);
    assert!(matches!(tiny, Err(RtnError::InvalidAmount { .. })));
    let me = net.apply("s4", Op::ShareData { from: msisdn(1), to: msisdn(1), bytes: 100 * MB }, T0);
    assert_eq!(me.err(), Some(RtnError::SelfTransfer));
}

// ----- loyalty ---------------------------------------------------------------------------

#[test]
fn spending_earns_points_and_points_buy_data() {
    let mut net = network_with(1, 0);
    net.apply("t", Op::TopUp { msisdn: msisdn(1), amount: 500_000, via: None }, T0).unwrap();
    // ₦5,000 top-up: one point per ₦10.
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().points, 500);
    net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "monthly-3gb".into(), beneficiary: None }, T0)
        .unwrap();
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().points, 650);
    let reward = net.catalog().rewards()[0].clone();
    let out = net.apply("r", Op::RedeemPoints { msisdn: msisdn(1), reward_id: reward.id.clone() }, T0).unwrap();
    assert_eq!(out.balance.points, 650 - reward.points);
    assert_eq!(out.balance.data_bytes, 3 * 1024 * MB + reward.data_bytes);
    let entry = net.history(&msisdn(1)).last().copied().unwrap().clone();
    assert_eq!(entry.kind, EntryKind::RewardRedeemed);
    assert_eq!(entry.points_delta, -(reward.points as i64));
}

#[test]
fn points_cannot_go_below_zero() {
    let mut net = network_with(1, 0);
    let reward = net.catalog().rewards()[0].clone();
    let out = net.apply("r", Op::RedeemPoints { msisdn: msisdn(1), reward_id: reward.id }, T0);
    assert!(matches!(out, Err(RtnError::InsufficientPoints { .. })));
}

// ----- notifications ---------------------------------------------------------------------

#[test]
fn money_and_data_arriving_send_a_notification_that_can_be_marked_read() {
    let mut net = network_with(2, 100_000);
    net.apply("tx", Op::Transfer { from: msisdn(1), to: msisdn(2), amount: 10_000 }, T0).unwrap();
    net.deliver_sms(T0);
    let notes = net.notifications(&msisdn(2));
    assert_eq!(notes.len(), 1);
    assert!(notes[0].text.contains("received"), "{}", notes[0].text);
    assert!(!notes[0].read);
    let id = notes[0].id.clone();
    assert_eq!(net.mark_read(&msisdn(2), std::slice::from_ref(&id)), 1);
    assert!(net.notifications(&msisdn(2))[0].read);
    // Somebody else's message is not theirs to mark.
    assert_eq!(net.mark_read(&msisdn(1), &[id]), 0);
}

// ----- line management -------------------------------------------------------------------

#[test]
fn a_pin_is_changed_with_the_old_one() {
    let mut net = network_with(1, 0);
    assert_eq!(net.change_pin(&msisdn(1), "9999", "4321", T0), Err(RtnError::WrongPin));
    net.change_pin(&msisdn(1), "1234", "4321", T0).unwrap();
    net.verify_pin(&msisdn(1), "4321", T0).unwrap();
    assert_eq!(net.change_pin(&msisdn(1), "4321", "12", T0), Err(RtnError::InvalidPin));
}

#[test]
fn a_sim_swap_issues_a_new_imsi_and_keeps_the_number() {
    let mut net = network_with(1, 1_000);
    let old = net.subscriber(&msisdn(1)).unwrap().imsi.clone();
    let swapped = net.swap_sim(&msisdn(1), "1234", T0).unwrap();
    assert_ne!(swapped.imsi, old);
    assert!(net.subscriber_by_imsi(&old).is_none());
    assert_eq!(net.subscriber_by_imsi(&swapped.imsi).unwrap().msisdn, msisdn(1));
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().airtime, 1_000);
}

#[test]
fn a_subscriber_can_suspend_a_lost_line_but_only_the_operator_lifts_it() {
    let mut net = network_with(1, 1_000);
    net.suspend_line(&msisdn(1), "1234", T0).unwrap();
    assert_eq!(net.subscriber(&msisdn(1)).unwrap().status, Status::Barred);
    let refused =
        net.apply("b", Op::BuyBundle { msisdn: msisdn(1), bundle_id: "daily-100mb".into(), beneficiary: None }, T0);
    assert_eq!(refused.err(), Some(RtnError::Barred));
    net.set_status(&msisdn(1), Status::Active).unwrap();
}

#[test]
fn names_and_plans_can_be_changed_by_the_subscriber() {
    let mut net = network_with(1, 0);
    net.set_name(&msisdn(1), "  Ada Lovelace ").unwrap();
    assert_eq!(net.subscriber(&msisdn(1)).unwrap().name, "Ada Lovelace");
    assert!(net.set_name(&msisdn(1), "   ").is_err());
    net.set_plan(&msisdn(1), "steady").unwrap();
    assert_eq!(net.subscriber(&msisdn(1)).unwrap().plan_id, "steady");
}

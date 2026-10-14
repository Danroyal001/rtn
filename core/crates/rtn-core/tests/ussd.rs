mod support;
use rtn_core::Op;
use support::*;

fn dial(net: &mut rtn_core::Network, session: &str, input: &str) -> rtn_core::UssdReply {
    net.ussd(session, &msisdn(1), input, T0).unwrap()
}

#[test]
fn main_menu_lists_the_services() {
    let mut net = network_with(2, 50_000);
    let reply = dial(&mut net, "s1", "*123#");
    assert!(!reply.end);
    for item in ["1. Balance", "2. Data bundles", "3. Transfer airtime", "4. Borrow airtime", "5. My number"] {
        assert!(reply.text.contains(item), "{}", reply.text);
    }
}

#[test]
fn balance_from_the_menu_and_the_shortcut() {
    let mut net = network_with(2, 50_000);
    dial(&mut net, "s1", "*123#");
    let reply = dial(&mut net, "s1", "1");
    assert!(reply.end);
    assert!(reply.text.contains("₦500.00"), "{}", reply.text);
    let reply = dial(&mut net, "s2", "*123*1#");
    assert!(reply.end && reply.text.contains("₦500.00"));
}

#[test]
fn buying_a_bundle_through_ussd_charges_once_even_if_the_step_is_resent() {
    let mut net = network_with(2, 50_000);
    dial(&mut net, "s1", "*312#");
    let confirm = dial(&mut net, "s1", "1");
    assert!(!confirm.end && confirm.text.contains("1. Confirm"), "{}", confirm.text);
    let done = dial(&mut net, "s1", "1");
    assert!(done.end, "{}", done.text);
    assert!(done.text.contains("100MB"), "{}", done.text);
    let b = net.balance(&msisdn(1), T0).unwrap();
    assert_eq!(b.airtime, 40_000);
    assert_eq!(b.bundles.len(), 1);
}

#[test]
fn transfer_by_menu_asks_for_number_amount_and_pin() {
    let mut net = network_with(2, 50_000);
    dial(&mut net, "s", "*123#");
    assert!(dial(&mut net, "s", "3").text.contains("number"));
    assert!(dial(&mut net, "s", &msisdn(2).to_string()).text.contains("amount"));
    assert!(dial(&mut net, "s", "100").text.contains("PIN"));
    let done = dial(&mut net, "s", "1234");
    assert!(done.end && done.text.contains("₦100.00"), "{}", done.text);
    assert_eq!(net.balance(&msisdn(2), T0).unwrap().airtime, 60_000);
}

#[test]
fn transfer_shortcut_and_a_wrong_pin() {
    let mut net = network_with(2, 50_000);
    let to = msisdn(2).to_string();
    let bad = dial(&mut net, "a", &format!("*321*{to}*100*9999#"));
    assert!(bad.end && bad.text.contains("Wrong PIN"), "{}", bad.text);
    let good = dial(&mut net, "b", &format!("*321*{to}*100*1234#"));
    assert!(good.end && good.text.contains("sent"), "{}", good.text);
}

#[test]
fn borrow_menu_offers_amounts_up_to_the_limit() {
    let mut net = network_with(1, 0);
    let menu = dial(&mut net, "s", "*303#");
    assert!(!menu.end && menu.text.contains("₦100.00"), "{}", menu.text);
    let done = dial(&mut net, "s", "1");
    assert!(done.end && done.text.contains("borrowed"), "{}", done.text);
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().loan, 11_000);
}

#[test]
fn back_invalid_choices_unknown_codes_and_timeouts() {
    let mut net = network_with(1, 0);
    dial(&mut net, "s", "*123#");
    dial(&mut net, "s", "2");
    assert!(dial(&mut net, "s", "0").text.contains("1. Balance"));
    let invalid = dial(&mut net, "s", "9");
    assert!(!invalid.end && invalid.text.contains("Invalid"), "{}", invalid.text);
    let unknown = dial(&mut net, "u", "*999#");
    assert!(unknown.end);
    dial(&mut net, "t", "*123#");
    let late = net.ussd("t", &msisdn(1), "1", T0 + 181_000).unwrap();
    assert!(late.end && late.text.contains("timed out"), "{}", late.text);
}

#[test]
fn my_number_and_unknown_subscriber() {
    let mut net = network_with(1, 0);
    let reply = dial(&mut net, "s", "*123*5#");
    assert!(reply.text.contains(&msisdn(1).to_string()));
    assert!(net.ussd("z", &msisdn(55), "*123#", T0).is_err());
    let _ = Op::TopUp { msisdn: msisdn(1), amount: 1 };
}

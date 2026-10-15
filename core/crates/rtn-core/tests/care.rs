//! Customer care: a chat per subscriber, answered by an assistant until an agent takes over.
mod support;
use rtn_core::{CareAuthor, Op};
use support::*;

#[test]
fn the_assistant_answers_a_balance_question_with_the_real_balance() {
    let mut net = network_with(1, 123_450);
    let thread = net.care_send(&msisdn(1), "what is my balance?", T0).unwrap();
    assert_eq!(thread.len(), 2);
    assert_eq!(thread[0].author, CareAuthor::Subscriber);
    assert_eq!(thread[1].author, CareAuthor::Assistant);
    assert!(thread[1].text.contains("₦1,234.50"), "{}", thread[1].text);
}

#[test]
fn the_assistant_knows_the_common_topics_and_offers_an_agent_otherwise() {
    let mut net = network_with(1, 0);
    for (question, needle) in [
        ("how do I borrow airtime", "*303#"),
        ("my data is finishing", "bundle"),
        ("I lost my sim", "suspend"),
        ("forgot my pin", "PIN"),
        ("can I talk to a human", "agent"),
    ] {
        let thread = net.care_send(&msisdn(1), question, T0).unwrap();
        let reply = &thread.last().unwrap().text;
        assert!(reply.contains(needle), "{question:?} -> {reply:?}");
    }
}

#[test]
fn once_an_agent_replies_the_assistant_steps_back() {
    let mut net = network_with(1, 0);
    net.care_send(&msisdn(1), "hello", T0).unwrap();
    net.care_reply(&msisdn(1), "Hi, this is Funmi from RTN care.", T0 + 1).unwrap();
    let thread = net.care_send(&msisdn(1), "thanks", T0 + 2).unwrap();
    assert_eq!(thread.last().unwrap().author, CareAuthor::Subscriber);
    let summary = net.care_threads();
    assert_eq!(summary.len(), 1);
    assert!(summary[0].waiting, "the subscriber spoke last");
    assert_eq!(summary[0].messages, 4);
}

#[test]
fn empty_and_huge_messages_are_refused() {
    let mut net = network_with(1, 0);
    assert!(net.care_send(&msisdn(1), "   ", T0).is_err());
    assert!(net.care_send(&msisdn(1), &"x".repeat(2_001), T0).is_err());
    assert!(net.care_reply(&msisdn(9), "hi", T0).is_err());
}

#[test]
fn care_never_touches_a_balance() {
    let mut net = network_with(1, 5_000);
    net.care_send(&msisdn(1), "balance", T0).unwrap();
    net.apply("t", Op::TopUp { msisdn: msisdn(1), amount: 1, via: None }, T0).unwrap();
    assert_eq!(net.balance(&msisdn(1), T0).unwrap().airtime, 5_001);
}

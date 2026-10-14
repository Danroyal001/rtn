//! One JSON entry point over the whole network, for callers that hold a [`Network`] in-process
//! (the C ABI in `rtn-ffi`). Every call names a `method`; the answer is `{"ok": …}` or
//! `{"error": {"code": …, "message": …}}`.
use serde::Deserialize;
use serde_json::{json, Value};

use crate::network::{Network, NewSubscriber, Op, Status};
use crate::types::Msisdn;
use crate::{seed, RtnError};

#[derive(Debug, Deserialize)]
#[serde(tag = "method", rename_all = "snake_case")]
pub enum Call {
    Apply { request_id: String, op: Op, now: u64 },
    Balance { msisdn: Msisdn, now: u64 },
    History { msisdn: Msisdn },
    Ussd { session_id: String, msisdn: Msisdn, input: String, now: u64 },
    AddSubscriber { subscriber: NewSubscriber, now: u64 },
    Subscriber { msisdn: Msisdn },
    Subscribers,
    SetStatus { msisdn: Msisdn, status: Status },
    SetAttached { msisdn: Msisdn, attached: bool, now: u64 },
    VerifyPin { msisdn: Msisdn, pin: String, now: u64 },
    Seed { count: u32, seed: u64, now: u64 },
    DeliverSms { now: u64 },
    Inbox { msisdn: Msisdn },
    Catalog,
    Traffic { now: u64 },
    Totals,
    Snapshot,
}

fn to_value<T: serde::Serialize>(value: T) -> Value {
    serde_json::to_value(value).expect("core types always serialise")
}

pub fn dispatch(net: &mut Network, call: Call) -> Result<Value, RtnError> {
    Ok(match call {
        Call::Apply { request_id, op, now } => to_value(net.apply(&request_id, op, now)?),
        Call::Balance { msisdn, now } => to_value(net.balance(&msisdn, now)?),
        Call::History { msisdn } => to_value(net.history(&msisdn)),
        Call::Ussd { session_id, msisdn, input, now } => to_value(net.ussd(&session_id, &msisdn, &input, now)?),
        Call::AddSubscriber { subscriber, now } => to_value(net.add_subscriber(subscriber, now)?),
        Call::Subscriber { msisdn } => to_value(net.subscriber(&msisdn).ok_or(RtnError::UnknownSubscriber)?),
        Call::Subscribers => to_value(net.subscribers().collect::<Vec<_>>()),
        Call::SetStatus { msisdn, status } => to_value(net.set_status(&msisdn, status)?),
        Call::SetAttached { msisdn, attached, now } => to_value(net.set_attached(&msisdn, attached, now)?),
        Call::VerifyPin { msisdn, pin, now } => to_value(net.verify_pin(&msisdn, &pin, now)?),
        Call::Seed { count, seed: seed_value, now } => to_value(seed::populate(net, count, seed_value, now)?),
        Call::DeliverSms { now } => to_value(net.deliver_sms(now)),
        Call::Inbox { msisdn } => to_value(net.inbox(&msisdn)),
        Call::Catalog => to_value(net.catalog()),
        Call::Traffic { now } => to_value(net.traffic(now)),
        Call::Totals => to_value(net.totals()),
        Call::Snapshot => serde_json::from_str(&net.to_json()).expect("a snapshot is JSON"),
    })
}

pub fn error_json(error: &RtnError) -> Value {
    json!({ "error": { "code": error.code(), "message": error.to_string(), "detail": error } })
}

/// Parses a call, runs it, and answers in JSON. Never panics on bad input.
pub fn handle_json(net: &mut Network, request: &str) -> String {
    let answer = match serde_json::from_str::<Call>(request) {
        Ok(call) => match dispatch(net, call) {
            Ok(value) => json!({ "ok": value }),
            Err(error) => error_json(&error),
        },
        Err(parse) => error_json(&RtnError::InvalidRequest { reason: parse.to_string() }),
    };
    answer.to_string()
}

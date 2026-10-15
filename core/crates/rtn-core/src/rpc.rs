//! One JSON entry point over the whole network, for callers that hold a [`Network`] in-process
//! (the C ABI in `rtn-ffi`, and `POST /v1/admin/rpc` in `rtn-api`). Every call names a `method`;
//! the answer is `{"ok": …}` or `{"error": {"code": …, "message": …}}`.
//!
//! Calls that change the network are the ones [`Call::changes_state`] says so; a
//! [`Node`](crate::node::Node) writes those, and only those, to its journal.
use serde::Deserialize;
use serde_json::{json, Value};

use crate::catalog::{Bundle, RatingPlan};
use crate::network::{Network, NewSubscriber, Op, Status};
use crate::types::{Msisdn, Units};
use crate::{seed, RtnError};

fn default_limit() -> usize {
    50
}

#[derive(Debug, Deserialize)]
#[serde(tag = "method", rename_all = "snake_case")]
pub enum Call {
    // ----- charging and reads -----
    Apply {
        request_id: String,
        op: Op,
        now: u64,
    },
    Balance {
        msisdn: Msisdn,
        now: u64,
    },
    /// A line, its plan and its balances: what the app's home screen shows.
    Line {
        msisdn: Msisdn,
        now: u64,
    },
    History {
        msisdn: Msisdn,
        #[serde(default)]
        limit: Option<usize>,
    },
    LedgerEntry {
        seq: u64,
    },
    Ledger {
        #[serde(default = "default_limit")]
        limit: usize,
    },
    Totals,
    Traffic {
        now: u64,
    },
    Catalog,
    // ----- registry -----
    AddSubscriber {
        subscriber: NewSubscriber,
        now: u64,
    },
    Subscriber {
        msisdn: Msisdn,
    },
    Subscribers,
    SubscriberPage {
        #[serde(default)]
        q: String,
        #[serde(default)]
        status: Option<Status>,
        #[serde(default)]
        offset: usize,
        #[serde(default = "default_limit")]
        limit: usize,
        now: u64,
    },
    SetStatus {
        msisdn: Msisdn,
        status: Status,
    },
    SetAttached {
        msisdn: Msisdn,
        attached: bool,
        now: u64,
    },
    SetPlan {
        msisdn: Msisdn,
        plan_id: String,
    },
    SetLoanLimit {
        msisdn: Msisdn,
        limit: Units,
    },
    SetPin {
        msisdn: Msisdn,
        pin: String,
    },
    SetName {
        msisdn: Msisdn,
        name: String,
    },
    VerifyPin {
        msisdn: Msisdn,
        pin: String,
        now: u64,
    },
    ChangePin {
        msisdn: Msisdn,
        old: String,
        new: String,
        now: u64,
    },
    SwapSim {
        msisdn: Msisdn,
        pin: String,
        now: u64,
    },
    SuspendLine {
        msisdn: Msisdn,
        pin: String,
        now: u64,
    },
    Seed {
        count: u32,
        seed: u64,
        now: u64,
    },
    // ----- sign-in codes and vouchers -----
    RequestOtp {
        msisdn: Msisdn,
        nonce: u64,
        now: u64,
    },
    VerifyOtp {
        msisdn: Msisdn,
        code: String,
        now: u64,
    },
    IssueVouchers {
        count: u32,
        amount: Units,
        nonce: u64,
        now: u64,
    },
    Vouchers {
        #[serde(default = "default_limit")]
        limit: usize,
    },
    // ----- catalogue -----
    UpsertPlan {
        plan: RatingPlan,
    },
    UpsertBundle {
        bundle: Bundle,
    },
    // ----- messages -----
    Ussd {
        session_id: String,
        msisdn: Msisdn,
        input: String,
        now: u64,
    },
    DeliverSms {
        now: u64,
    },
    Inbox {
        msisdn: Msisdn,
    },
    Outbox {
        msisdn: Msisdn,
    },
    Notifications {
        msisdn: Msisdn,
    },
    MarkRead {
        msisdn: Msisdn,
        ids: Vec<String>,
    },
    SmsLog {
        #[serde(default = "default_limit")]
        limit: usize,
    },
    // ----- care -----
    CareSend {
        msisdn: Msisdn,
        text: String,
        now: u64,
    },
    CareReply {
        msisdn: Msisdn,
        text: String,
        now: u64,
    },
    CareThread {
        msisdn: Msisdn,
    },
    CareThreads,
    // ----- the node -----
    /// Runs the traffic simulator for some seconds, whether or not it is switched on.
    Simulate {
        seconds: u64,
        now: u64,
    },
    /// One second of background work: the simulator when it is on, an SMS delivery pass always.
    Tick {
        now: u64,
    },
    SetSimulator {
        running: bool,
    },
    Simulator,
    Snapshot,
}

impl Call {
    /// Whether answering this call can change the network. Reads are not journalled.
    pub fn changes_state(&self) -> bool {
        !matches!(
            self,
            Call::Balance { .. }
                | Call::Line { .. }
                | Call::History { .. }
                | Call::LedgerEntry { .. }
                | Call::Ledger { .. }
                | Call::Totals
                | Call::Traffic { .. }
                | Call::Catalog
                | Call::Subscriber { .. }
                | Call::Subscribers
                | Call::SubscriberPage { .. }
                | Call::Vouchers { .. }
                | Call::Inbox { .. }
                | Call::Outbox { .. }
                | Call::Notifications { .. }
                | Call::SmsLog { .. }
                | Call::CareThread { .. }
                | Call::CareThreads
                | Call::Simulator
                | Call::Snapshot
        )
    }
}

fn to_value<T: serde::Serialize>(value: T) -> Value {
    serde_json::to_value(value).expect("core types always serialise")
}

/// Runs a call that needs only the network. The simulator calls answer `invalid_request` here;
/// a [`Node`](crate::node::Node) answers them.
pub fn dispatch(net: &mut Network, call: Call) -> Result<Value, RtnError> {
    Ok(match call {
        Call::Apply { request_id, op, now } => to_value(net.apply(&request_id, op, now)?),
        Call::Balance { msisdn, now } => to_value(net.peek_balance(&msisdn, now)?),
        Call::Line { msisdn, now } => {
            let balance = net.peek_balance(&msisdn, now)?;
            let subscriber = net.subscriber(&msisdn).cloned().ok_or(RtnError::UnknownSubscriber)?;
            let plan = net.catalog().plan(&subscriber.plan_id).cloned();
            json!({ "subscriber": subscriber, "plan": plan, "balance": balance })
        }
        Call::History { msisdn, limit } => {
            let limit = limit.unwrap_or(usize::MAX);
            to_value(net.history(&msisdn).into_iter().rev().take(limit).collect::<Vec<_>>())
        }
        Call::LedgerEntry { seq } => to_value(
            net.ledger_entry(seq)
                .ok_or(RtnError::InvalidRequest { reason: "no ledger entry has that number".into() })?,
        ),
        Call::Ledger { limit } => to_value(net.ledger().iter().rev().take(limit.min(1_000)).collect::<Vec<_>>()),
        Call::Totals => to_value(net.totals()),
        Call::Traffic { now } => to_value(net.traffic(now)),
        Call::Catalog => to_value(net.catalog()),
        Call::AddSubscriber { subscriber, now } => to_value(net.add_subscriber(subscriber, now)?),
        Call::Subscriber { msisdn } => to_value(net.subscriber(&msisdn).ok_or(RtnError::UnknownSubscriber)?),
        Call::Subscribers => to_value(net.subscribers().collect::<Vec<_>>()),
        Call::SubscriberPage { q, status, offset, limit, now } => {
            let needle = q.trim().to_lowercase();
            let matching: Vec<Msisdn> = net
                .subscribers()
                .filter(|s| status.is_none_or(|status| s.status == status))
                .filter(|s| {
                    needle.is_empty()
                        || s.msisdn.as_str().contains(&needle)
                        || s.imsi.as_str().contains(&needle)
                        || s.name.to_lowercase().contains(&needle)
                })
                .map(|s| s.msisdn.clone())
                .collect();
            let total = matching.len();
            let mut items = Vec::new();
            for msisdn in matching.into_iter().skip(offset).take(limit.min(500)) {
                let balance = net.peek_balance(&msisdn, now)?;
                items.push(json!({ "subscriber": net.subscriber(&msisdn), "balance": balance }));
            }
            json!({ "total": total, "offset": offset, "items": items })
        }
        Call::SetStatus { msisdn, status } => to_value(net.set_status(&msisdn, status)?),
        Call::SetAttached { msisdn, attached, now } => to_value(net.set_attached(&msisdn, attached, now)?),
        Call::SetPlan { msisdn, plan_id } => to_value(net.set_plan(&msisdn, &plan_id)?),
        Call::SetLoanLimit { msisdn, limit } => to_value(net.set_loan_limit(&msisdn, limit)?),
        Call::SetPin { msisdn, pin } => to_value(net.set_pin(&msisdn, &pin)?),
        Call::SetName { msisdn, name } => to_value(net.set_name(&msisdn, &name)?),
        Call::VerifyPin { msisdn, pin, now } => to_value(net.verify_pin(&msisdn, &pin, now)?),
        Call::ChangePin { msisdn, old, new, now } => to_value(net.change_pin(&msisdn, &old, &new, now)?),
        Call::SwapSim { msisdn, pin, now } => to_value(net.swap_sim(&msisdn, &pin, now)?),
        Call::SuspendLine { msisdn, pin, now } => to_value(net.suspend_line(&msisdn, &pin, now)?),
        Call::Seed { count, seed: seed_value, now } => to_value(seed::populate(net, count, seed_value, now)?),
        Call::RequestOtp { msisdn, nonce, now } => to_value(net.request_otp(&msisdn, nonce, now)?),
        Call::VerifyOtp { msisdn, code, now } => to_value(net.verify_otp(&msisdn, &code, now)?),
        Call::IssueVouchers { count, amount, nonce, now } => to_value(net.issue_vouchers(count, amount, nonce, now)?),
        Call::Vouchers { limit } => to_value(net.vouchers().into_iter().take(limit).collect::<Vec<_>>()),
        Call::UpsertPlan { plan } => {
            net.catalog_mut().upsert_plan(plan.clone())?;
            to_value(plan)
        }
        Call::UpsertBundle { bundle } => {
            net.catalog_mut().upsert_bundle(bundle.clone())?;
            to_value(bundle)
        }
        Call::Ussd { session_id, msisdn, input, now } => to_value(net.ussd(&session_id, &msisdn, &input, now)?),
        Call::DeliverSms { now } => to_value(net.deliver_sms(now)),
        Call::Inbox { msisdn } => to_value(net.inbox(&msisdn)),
        Call::Outbox { msisdn } => to_value(net.outbox(&msisdn)),
        Call::Notifications { msisdn } => to_value(net.notifications(&msisdn)),
        Call::MarkRead { msisdn, ids } => to_value(net.mark_read(&msisdn, &ids)),
        Call::SmsLog { limit } => to_value(net.sms_log(limit.min(1_000))),
        Call::CareSend { msisdn, text, now } => to_value(net.care_send(&msisdn, &text, now)?),
        Call::CareReply { msisdn, text, now } => to_value(net.care_reply(&msisdn, &text, now)?),
        Call::CareThread { msisdn } => to_value(net.care_thread(&msisdn)),
        Call::CareThreads => to_value(net.care_threads()),
        Call::Snapshot => serde_json::from_str(&net.to_json()).expect("a snapshot is JSON"),
        Call::Simulate { .. } | Call::Tick { .. } | Call::SetSimulator { .. } | Call::Simulator => {
            return Err(RtnError::InvalidRequest { reason: "the simulator belongs to a node".into() })
        }
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

//! RTN's network core.
//!
//! One [`Network`] holds the subscriber registry, the rating catalogue, every account's balances,
//! the ledger, the USSD sessions, the SMS centre's store and the traffic counters. It does no I/O
//! and reads no clock: every call that depends on time is handed `now` in Unix milliseconds, so
//! the same calls in the same order always give the same network.

mod catalog;
mod error;
mod network;
mod smsc;
mod traffic;
mod types;
mod ussd;

pub mod metering;
pub mod rpc;
pub mod seed;

pub use catalog::{Bundle, Catalog, RatingPlan};
pub use error::RtnError;
pub use metering::{Simulator, TickReport};
pub use network::{
    Balance, BundleBalance, Detail, EntryKind, LedgerEntry, Network, NewSubscriber, Op, Outcome, Status, Subscriber,
    Totals,
};
pub use smsc::{segments, DeliveryReport, DeliveryRun, SmsMessage, SmsState};
pub use traffic::{TrafficCounters, TrafficView};
pub use types::{format_naira, Imsi, Msisdn, Units, MB};
pub use ussd::UssdReply;

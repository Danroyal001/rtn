//! RTN's network core.
//!
//! One [`Network`] holds the subscriber registry, the rating catalogue, every account's balances,
//! the ledger, the USSD sessions, the SMS centre's store and the traffic counters. It does no I/O
//! and reads no clock: every call that depends on time is handed `now` in Unix milliseconds, so
//! the same calls in the same order always give the same network.

mod care;
mod catalog;
mod error;
mod network;
mod selfcare;
mod smsc;
mod traffic;
mod types;
mod ussd;

pub mod metering;
pub mod node;
pub mod rpc;
pub mod seed;

pub use care::{CareAuthor, CareMessage, CareThread, CARE_MESSAGE_MAX};
pub use catalog::{Bundle, Catalog, RatingPlan, Reward};
pub use error::RtnError;
pub use metering::{Simulator, TickReport};
pub use network::{
    format_bytes, Balance, BundleBalance, Detail, EntryKind, LedgerEntry, Network, NewSubscriber, Op, Outcome, Status,
    Subscriber, Totals, LOAN_FEE_PERCENT, SHARE_MAX, SHARE_MIN, TRANSFER_FEE, TRANSFER_MAX, TRANSFER_MIN,
    UNITS_PER_POINT,
};
pub use selfcare::{
    IssuedVoucher, OtpIssued, Voucher, OTP_RESEND_MS, OTP_VALIDITY_MS, VOUCHER_ATTEMPTS, VOUCHER_LOCK_MS,
};
pub use smsc::{segments, DeliveryReport, DeliveryRun, SmsMessage, SmsState};
pub use traffic::{TrafficCounters, TrafficView};
pub use types::{format_naira, Imsi, Msisdn, Units, MB, SERVICE_NUMBER};
pub use ussd::UssdReply;

use serde::Serialize;
use thiserror::Error;

use crate::types::{format_naira, Units};

/// Everything the core can refuse, each with a stable machine-readable [`code`](RtnError::code).
#[derive(Clone, Debug, Error, PartialEq, Eq, Serialize)]
#[serde(tag = "code", rename_all = "snake_case")]
pub enum RtnError {
    #[error("that is not a phone number")]
    InvalidMsisdn,
    #[error("an IMSI is 15 digits")]
    InvalidImsi,
    #[error("a PIN is 4 to 6 digits")]
    InvalidPin,
    #[error("no subscriber has that number")]
    UnknownSubscriber,
    #[error("that number is already a subscriber")]
    DuplicateSubscriber,
    #[error("that IMSI is already in use")]
    DuplicateImsi,
    #[error("this line is barred")]
    Barred,
    #[error("not enough airtime: {} needed, {} available", format_naira(*needed), format_naira(*available))]
    InsufficientFunds { needed: Units, available: Units },
    #[error("no rating plan has that id")]
    UnknownPlan,
    #[error("no bundle has that id")]
    UnknownBundle,
    #[error("no call session has that id")]
    UnknownSession,
    #[error("no message has that id")]
    UnknownMessage,
    #[error("{reason}")]
    InvalidAmount { reason: String },
    #[error("{reason}")]
    InvalidMessage { reason: String },
    #[error("{reason}")]
    InvalidRequest { reason: String },
    #[error("you cannot send airtime to yourself")]
    SelfTransfer,
    #[error("repay the {} you owe first", format_naira(*owed))]
    LoanOutstanding { owed: Units },
    #[error("you can borrow up to {}", format_naira(*limit))]
    LoanLimit { limit: Units },
    #[error("wrong PIN")]
    WrongPin,
    #[error("too many wrong PINs; try again in {} minutes", seconds.div_ceil(60))]
    PinLocked { seconds: u64 },
    #[error("that request id was already used for a different operation")]
    RequestConflict,
}

impl RtnError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidMsisdn => "invalid_msisdn",
            Self::InvalidImsi => "invalid_imsi",
            Self::InvalidPin => "invalid_pin",
            Self::UnknownSubscriber => "unknown_subscriber",
            Self::DuplicateSubscriber => "duplicate_subscriber",
            Self::DuplicateImsi => "duplicate_imsi",
            Self::Barred => "barred",
            Self::InsufficientFunds { .. } => "insufficient_funds",
            Self::UnknownPlan => "unknown_plan",
            Self::UnknownBundle => "unknown_bundle",
            Self::UnknownSession => "unknown_session",
            Self::UnknownMessage => "unknown_message",
            Self::InvalidAmount { .. } => "invalid_amount",
            Self::InvalidMessage { .. } => "invalid_message",
            Self::InvalidRequest { .. } => "invalid_request",
            Self::SelfTransfer => "self_transfer",
            Self::LoanOutstanding { .. } => "loan_outstanding",
            Self::LoanLimit { .. } => "loan_limit",
            Self::WrongPin => "wrong_pin",
            Self::PinLocked { .. } => "pin_locked",
            Self::RequestConflict => "request_conflict",
        }
    }
}

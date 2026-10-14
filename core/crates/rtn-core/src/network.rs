use std::collections::{BTreeMap, HashMap};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::catalog::Catalog;
use crate::smsc::{segments, Smsc, MAX_SEGMENTS};
use crate::traffic::Traffic;
use crate::types::{format_naira, Imsi, Msisdn, Units, MB};
use crate::ussd::UssdSession;
use crate::RtnError;

/// Longest a single voice grant runs before the call is cut, in seconds.
pub const MAX_GRANT_SECONDS: u64 = 600;
/// Flat fee for an airtime transfer.
pub const TRANSFER_FEE: Units = 1_000;
/// Smallest and largest airtime transfer.
pub const TRANSFER_MIN: Units = 5_000;
pub const TRANSFER_MAX: Units = 5_000_000;
/// Smallest loan, the default loan limit, and the service fee in percent.
pub const LOAN_MIN: Units = 1_000;
pub const DEFAULT_LOAN_LIMIT: Units = 50_000;
pub const LOAN_FEE_PERCENT: Units = 10;
/// Largest single top-up.
pub const TOP_UP_MAX: Units = 10_000_000;
/// Wrong PINs before a lock, and how long the lock lasts.
pub const PIN_ATTEMPTS: u32 = 3;
pub const PIN_LOCK_MS: u64 = 5 * 60_000;
const DAY_MS: u64 = 86_400_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Active,
    Barred,
}

/// One line in the registry: what an HLR/HSS keeps about a subscriber.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Subscriber {
    pub msisdn: Msisdn,
    pub imsi: Imsi,
    pub name: String,
    pub plan_id: String,
    pub status: Status,
    /// Whether the handset is on the network; the SMS centre holds messages while it is not.
    pub attached: bool,
    pub loan_limit: Units,
    pub created_at: u64,
}

/// What it takes to add a subscriber. Without an IMSI the network issues the next free one.
#[derive(Clone, Debug, Deserialize)]
pub struct NewSubscriber {
    pub msisdn: Msisdn,
    #[serde(default)]
    pub imsi: Option<Imsi>,
    pub name: String,
    #[serde(default)]
    pub plan_id: Option<String>,
    pub pin: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct Credential {
    pin_hash: String,
    failures: u32,
    locked_until: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct HeldBundle {
    bundle_id: String,
    name: String,
    bytes_left: u64,
    expires_at: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct Account {
    airtime: Units,
    reserved: Units,
    bundles: Vec<HeldBundle>,
    loan: Units,
}

impl Account {
    fn available(&self) -> Units {
        self.airtime - self.reserved
    }

    fn data_bytes(&self) -> u64 {
        self.bundles.iter().map(|b| b.bytes_left).sum()
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct VoiceSession {
    msisdn: Msisdn,
    callee: String,
    rate: Units,
    granted_seconds: u64,
    started_at: u64,
}

/// A charging operation. Each one is applied through [`Network::apply`] under a request id.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Op {
    TopUp {
        msisdn: Msisdn,
        amount: Units,
    },
    BuyBundle {
        msisdn: Msisdn,
        bundle_id: String,
    },
    Transfer {
        from: Msisdn,
        to: Msisdn,
        amount: Units,
    },
    Borrow {
        msisdn: Msisdn,
        amount: Units,
    },
    DataUsage {
        msisdn: Msisdn,
        bytes: u64,
    },
    /// Opens a credit-control session for a call; the request id names the session.
    VoiceStart {
        msisdn: Msisdn,
        callee: String,
    },
    VoiceEnd {
        session_id: String,
        used_seconds: u64,
    },
    SmsSubmit {
        from: Msisdn,
        to: Msisdn,
        text: String,
    },
}

/// What an operation did besides change a balance.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Detail {
    TopUp { repaid: Units },
    Bundle { bundle_id: String, expires_at: u64 },
    Transfer { to: Msisdn, amount: Units, fee: Units },
    Loan { borrowed: Units, owed: Units },
    Data { from_bundle: u64, payg_bytes: u64 },
    VoiceGranted { session_id: String, granted_seconds: u64 },
    VoiceEnded { session_id: String, billed_seconds: u64 },
    Sms { message_id: String, segments: u32 },
}

/// The result of an applied operation. Replaying the request returns this same value.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Outcome {
    pub request_id: String,
    /// What the network earned from this operation.
    pub charged: Units,
    /// The balance of the subscriber who made the request, right after it.
    pub balance: Balance,
    pub detail: Detail,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BundleBalance {
    pub bundle_id: String,
    pub name: String,
    pub bytes_left: u64,
    pub expires_at: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Balance {
    pub msisdn: Msisdn,
    pub plan_id: String,
    pub status: Status,
    pub airtime: Units,
    /// Held for calls in progress.
    pub reserved: Units,
    pub available: Units,
    pub data_bytes: u64,
    pub bundles: Vec<BundleBalance>,
    pub loan: Units,
    pub loan_limit: Units,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EntryKind {
    TopUp,
    LoanRepayment,
    Loan,
    BundlePurchase,
    BundleExpired,
    TransferOut,
    TransferIn,
    Voice,
    Sms,
    Data,
}

/// One balance change. An account's balances are always the sum of its entries' deltas.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LedgerEntry {
    pub seq: u64,
    pub at: u64,
    pub request_id: String,
    pub msisdn: Msisdn,
    pub kind: EntryKind,
    pub airtime_delta: i64,
    pub data_delta: i64,
    pub loan_delta: i64,
    pub airtime_after: Units,
    pub data_after: u64,
    pub loan_after: Units,
    pub note: String,
}

/// Network-wide money flows. `sum(airtime) + revenue + repaid == topped_up + lent` always.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Totals {
    pub topped_up: Units,
    pub lent: Units,
    /// Loan repayments, service fee included.
    pub repaid: Units,
    /// Usage, bundles and transfer fees.
    pub revenue: Units,
}

/// The whole network's state. See the crate docs.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Network {
    pub(crate) subscribers: BTreeMap<Msisdn, Subscriber>,
    credentials: BTreeMap<Msisdn, Credential>,
    pub(crate) accounts: BTreeMap<Msisdn, Account>,
    pub(crate) catalog: Catalog,
    ledger: Vec<LedgerEntry>,
    requests: HashMap<String, (Op, Outcome)>,
    pub(crate) calls: BTreeMap<String, VoiceSession>,
    pub(crate) ussd_sessions: BTreeMap<String, UssdSession>,
    pub(crate) smsc: Smsc,
    totals: Totals,
    next_imsi: u64,
    #[serde(skip)]
    by_imsi: BTreeMap<Imsi, Msisdn>,
    #[serde(skip)]
    ledger_index: BTreeMap<Msisdn, Vec<usize>>,
    #[serde(skip)]
    pub(crate) traffic: Traffic,
}

fn pin_hash(msisdn: &Msisdn, pin: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"rtn-pin:");
    hasher.update(msisdn.as_str());
    hasher.update(b":");
    hasher.update(pin);
    hex::encode(hasher.finalize())
}

fn valid_pin(pin: &str) -> bool {
    (4..=6).contains(&pin.len()) && pin.bytes().all(|b| b.is_ascii_digit())
}

fn constant_time_eq(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

fn delta(amount: u64) -> i64 {
    i64::try_from(amount).expect("amounts fit in i64")
}

/// "1.5GB", "100MB", "512KB".
pub fn format_bytes(bytes: u64) -> String {
    if bytes >= 1024 * MB {
        let tenths = bytes * 10 / (1024 * MB);
        if tenths % 10 == 0 {
            format!("{}GB", tenths / 10)
        } else {
            format!("{}.{}GB", tenths / 10, tenths % 10)
        }
    } else if bytes >= MB {
        format!("{}MB", bytes / MB)
    } else {
        format!("{}KB", bytes.div_ceil(1024))
    }
}

impl Network {
    /// An empty network with the default catalogue.
    pub fn new() -> Self {
        Self { next_imsi: 1, ..Self::default() }
    }

    /// Restores a network from [`to_json`](Self::to_json).
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        let mut net: Network = serde_json::from_str(json)?;
        net.reindex();
        Ok(net)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).expect("the network always serialises")
    }

    fn reindex(&mut self) {
        self.by_imsi = self.subscribers.values().map(|s| (s.imsi.clone(), s.msisdn.clone())).collect();
        self.ledger_index.clear();
        for (i, entry) in self.ledger.iter().enumerate() {
            self.ledger_index.entry(entry.msisdn.clone()).or_default().push(i);
        }
    }

    // ----- registry -------------------------------------------------------------------------

    pub fn add_subscriber(&mut self, new: NewSubscriber, now: u64) -> Result<Subscriber, RtnError> {
        let name = new.name.trim();
        if name.is_empty() || name.chars().count() > 80 {
            return Err(RtnError::InvalidRequest { reason: "a name is 1 to 80 characters".into() });
        }
        if !valid_pin(&new.pin) {
            return Err(RtnError::InvalidPin);
        }
        let plan_id = new.plan_id.unwrap_or_else(|| self.catalog.default_plan.clone());
        if self.catalog.plan(&plan_id).is_none() {
            return Err(RtnError::UnknownPlan);
        }
        if self.subscribers.contains_key(&new.msisdn) {
            return Err(RtnError::DuplicateSubscriber);
        }
        let imsi = match new.imsi {
            Some(imsi) if self.by_imsi.contains_key(&imsi) => return Err(RtnError::DuplicateImsi),
            Some(imsi) => imsi,
            None => loop {
                let candidate = Imsi::issue(self.next_imsi);
                self.next_imsi += 1;
                if !self.by_imsi.contains_key(&candidate) {
                    break candidate;
                }
            },
        };
        let subscriber = Subscriber {
            msisdn: new.msisdn.clone(),
            imsi: imsi.clone(),
            name: name.to_owned(),
            plan_id,
            status: Status::Active,
            attached: true,
            loan_limit: DEFAULT_LOAN_LIMIT,
            created_at: now,
        };
        self.credentials.insert(
            new.msisdn.clone(),
            Credential { pin_hash: pin_hash(&new.msisdn, &new.pin), ..Credential::default() },
        );
        self.by_imsi.insert(imsi, new.msisdn.clone());
        self.accounts.insert(new.msisdn.clone(), Account::default());
        self.subscribers.insert(new.msisdn, subscriber.clone());
        Ok(subscriber)
    }

    pub fn subscriber(&self, msisdn: &Msisdn) -> Option<&Subscriber> {
        self.subscribers.get(msisdn)
    }

    pub fn subscriber_by_imsi(&self, imsi: &Imsi) -> Option<&Subscriber> {
        self.by_imsi.get(imsi).and_then(|m| self.subscribers.get(m))
    }

    /// Every subscriber, in number order.
    pub fn subscribers(&self) -> impl Iterator<Item = &Subscriber> {
        self.subscribers.values()
    }

    fn subscriber_mut(&mut self, msisdn: &Msisdn) -> Result<&mut Subscriber, RtnError> {
        self.subscribers.get_mut(msisdn).ok_or(RtnError::UnknownSubscriber)
    }

    pub fn set_status(&mut self, msisdn: &Msisdn, status: Status) -> Result<(), RtnError> {
        self.subscriber_mut(msisdn)?.status = status;
        Ok(())
    }

    pub fn set_plan(&mut self, msisdn: &Msisdn, plan_id: &str) -> Result<(), RtnError> {
        if self.catalog.plan(plan_id).is_none() {
            return Err(RtnError::UnknownPlan);
        }
        self.subscriber_mut(msisdn)?.plan_id = plan_id.to_owned();
        Ok(())
    }

    pub fn set_loan_limit(&mut self, msisdn: &Msisdn, limit: Units) -> Result<(), RtnError> {
        self.subscriber_mut(msisdn)?.loan_limit = limit;
        Ok(())
    }

    /// Marks the handset attached or detached. Attaching delivers the messages held for it.
    pub fn set_attached(&mut self, msisdn: &Msisdn, attached: bool, now: u64) -> Result<(), RtnError> {
        self.subscriber_mut(msisdn)?.attached = attached;
        if attached {
            self.deliver_to(msisdn, now);
        }
        Ok(())
    }

    pub fn set_pin(&mut self, msisdn: &Msisdn, pin: &str) -> Result<(), RtnError> {
        if !self.subscribers.contains_key(msisdn) {
            return Err(RtnError::UnknownSubscriber);
        }
        if !valid_pin(pin) {
            return Err(RtnError::InvalidPin);
        }
        self.credentials
            .insert(msisdn.clone(), Credential { pin_hash: pin_hash(msisdn, pin), ..Credential::default() });
        Ok(())
    }

    /// Checks a PIN. Three wrong PINs in a row lock the line's PIN for five minutes.
    pub fn verify_pin(&mut self, msisdn: &Msisdn, pin: &str, now: u64) -> Result<(), RtnError> {
        if !self.subscribers.contains_key(msisdn) {
            return Err(RtnError::UnknownSubscriber);
        }
        let credential = self.credentials.entry(msisdn.clone()).or_default();
        if credential.locked_until > now {
            return Err(RtnError::PinLocked { seconds: (credential.locked_until - now).div_ceil(1000) });
        }
        if constant_time_eq(&credential.pin_hash, &pin_hash(msisdn, pin)) {
            credential.failures = 0;
            return Ok(());
        }
        credential.failures += 1;
        if credential.failures >= PIN_ATTEMPTS {
            credential.failures = 0;
            credential.locked_until = now + PIN_LOCK_MS;
        }
        Err(RtnError::WrongPin)
    }

    // ----- catalogue --------------------------------------------------------------------------

    pub fn catalog(&self) -> &Catalog {
        &self.catalog
    }

    pub fn catalog_mut(&mut self) -> &mut Catalog {
        &mut self.catalog
    }

    // ----- balances and ledger ----------------------------------------------------------------

    fn active(&self, msisdn: &Msisdn) -> Result<&Subscriber, RtnError> {
        let subscriber = self.subscribers.get(msisdn).ok_or(RtnError::UnknownSubscriber)?;
        if subscriber.status == Status::Barred {
            return Err(RtnError::Barred);
        }
        Ok(subscriber)
    }

    fn account(&mut self, msisdn: &Msisdn) -> &mut Account {
        self.accounts.entry(msisdn.clone()).or_default()
    }

    /// Expires bundles whose validity has run out, each with a ledger entry, and drops empty ones.
    fn touch(&mut self, msisdn: &Msisdn, now: u64) {
        let account = self.account(msisdn);
        account.bundles.retain(|b| b.bytes_left > 0);
        let expired: Vec<HeldBundle> = account.bundles.iter().filter(|b| b.expires_at <= now).cloned().collect();
        if expired.is_empty() {
            return;
        }
        account.bundles.retain(|b| b.expires_at > now);
        for bundle in expired {
            let id = format!("expire:{}:{}", msisdn, self.ledger.len());
            self.post(
                &id,
                msisdn,
                EntryKind::BundleExpired,
                0,
                -delta(bundle.bytes_left),
                0,
                now,
                format!("{} expired", bundle.name),
            );
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn post(
        &mut self,
        request_id: &str,
        msisdn: &Msisdn,
        kind: EntryKind,
        airtime_delta: i64,
        data_delta: i64,
        loan_delta: i64,
        now: u64,
        note: String,
    ) {
        let (airtime_after, data_after, loan_after) =
            self.accounts.get(msisdn).map_or((0, 0, 0), |a| (a.airtime, a.data_bytes(), a.loan));
        let entry = LedgerEntry {
            seq: self.ledger.len() as u64 + 1,
            at: now,
            request_id: request_id.to_owned(),
            msisdn: msisdn.clone(),
            kind,
            airtime_delta,
            data_delta,
            loan_delta,
            airtime_after,
            data_after,
            loan_after,
            note,
        };
        self.ledger_index.entry(msisdn.clone()).or_default().push(self.ledger.len());
        self.ledger.push(entry);
    }

    fn view(&self, msisdn: &Msisdn) -> Balance {
        let subscriber = &self.subscribers[msisdn];
        let empty = Account::default();
        let account = self.accounts.get(msisdn).unwrap_or(&empty);
        let mut bundles: Vec<BundleBalance> = account
            .bundles
            .iter()
            .filter(|b| b.bytes_left > 0)
            .map(|b| BundleBalance {
                bundle_id: b.bundle_id.clone(),
                name: b.name.clone(),
                bytes_left: b.bytes_left,
                expires_at: b.expires_at,
            })
            .collect();
        bundles.sort_by_key(|b| b.expires_at);
        Balance {
            msisdn: msisdn.clone(),
            plan_id: subscriber.plan_id.clone(),
            status: subscriber.status,
            airtime: account.airtime,
            reserved: account.reserved,
            available: account.available(),
            data_bytes: account.data_bytes(),
            bundles,
            loan: account.loan,
            loan_limit: subscriber.loan_limit,
        }
    }

    /// A subscriber's balances, after expiring any bundle whose validity has run out.
    pub fn balance(&mut self, msisdn: &Msisdn, now: u64) -> Result<Balance, RtnError> {
        if !self.subscribers.contains_key(msisdn) {
            return Err(RtnError::UnknownSubscriber);
        }
        self.touch(msisdn, now);
        Ok(self.view(msisdn))
    }

    /// A subscriber's ledger entries, oldest first.
    pub fn history(&self, msisdn: &Msisdn) -> Vec<&LedgerEntry> {
        self.ledger_index.get(msisdn).map(|ix| ix.iter().map(|&i| &self.ledger[i]).collect()).unwrap_or_default()
    }

    /// Every ledger entry, in order.
    pub fn ledger(&self) -> &[LedgerEntry] {
        &self.ledger
    }

    pub fn totals(&self) -> Totals {
        self.totals
    }

    /// Calls in progress.
    pub fn active_calls(&self) -> usize {
        self.calls.len()
    }

    // ----- charging ---------------------------------------------------------------------------

    /// Applies a charging operation once. A request id that was applied before returns the first
    /// outcome without charging again; reusing it for a different operation is refused. A refused
    /// operation changes no balance.
    pub fn apply(&mut self, request_id: &str, op: Op, now: u64) -> Result<Outcome, RtnError> {
        if request_id.is_empty() || request_id.len() > 128 {
            return Err(RtnError::InvalidRequest { reason: "a request id is 1 to 128 characters".into() });
        }
        if let Some((seen, outcome)) = self.requests.get(request_id) {
            return if *seen == op { Ok(outcome.clone()) } else { Err(RtnError::RequestConflict) };
        }
        let revenue_before = self.totals.revenue;
        let result = match op.clone() {
            Op::TopUp { msisdn, amount } => self.top_up(request_id, &msisdn, amount, now),
            Op::BuyBundle { msisdn, bundle_id } => self.buy_bundle(request_id, &msisdn, &bundle_id, now),
            Op::Transfer { from, to, amount } => self.transfer(request_id, &from, &to, amount, now),
            Op::Borrow { msisdn, amount } => self.borrow(request_id, &msisdn, amount, now),
            Op::DataUsage { msisdn, bytes } => self.data_usage(request_id, &msisdn, bytes, now),
            Op::VoiceStart { msisdn, callee } => self.voice_start(request_id, &msisdn, &callee, now),
            Op::VoiceEnd { session_id, used_seconds } => self.voice_end(request_id, &session_id, used_seconds, now),
            Op::SmsSubmit { from, to, text } => self.sms_submit(request_id, &from, &to, &text, now),
        };
        let revenue = self.totals.revenue - revenue_before;
        match &result {
            Ok(outcome) => {
                self.traffic.record(now, |c| {
                    c.charges += 1;
                    c.revenue += revenue;
                    match (&op, &outcome.detail) {
                        (Op::DataUsage { bytes, .. }, _) => c.data_bytes += bytes,
                        (_, Detail::VoiceEnded { billed_seconds, .. }) => c.voice_seconds += billed_seconds,
                        (_, Detail::Sms { .. }) => c.sms += 1,
                        _ => {}
                    }
                });
                self.requests.insert(request_id.to_owned(), (op, outcome.clone()));
            }
            Err(_) => self.traffic.record(now, |c| c.failures += 1),
        }
        result
    }

    fn outcome(&self, request_id: &str, msisdn: &Msisdn, charged: Units, detail: Detail) -> Outcome {
        Outcome { request_id: request_id.to_owned(), charged, balance: self.view(msisdn), detail }
    }

    fn top_up(&mut self, id: &str, msisdn: &Msisdn, amount: Units, now: u64) -> Result<Outcome, RtnError> {
        if !self.subscribers.contains_key(msisdn) {
            return Err(RtnError::UnknownSubscriber);
        }
        if amount == 0 || amount > TOP_UP_MAX {
            return Err(RtnError::InvalidAmount { reason: format!("a top-up is up to {}", format_naira(TOP_UP_MAX)) });
        }
        self.touch(msisdn, now);
        self.account(msisdn).airtime += amount;
        self.totals.topped_up += amount;
        self.post(
            id,
            msisdn,
            EntryKind::TopUp,
            delta(amount),
            0,
            0,
            now,
            format!("Top-up of {}", format_naira(amount)),
        );
        let account = self.account(msisdn);
        let repaid = account.loan.min(account.available());
        if repaid > 0 {
            account.airtime -= repaid;
            account.loan -= repaid;
            self.totals.repaid += repaid;
            self.post(
                id,
                msisdn,
                EntryKind::LoanRepayment,
                -delta(repaid),
                0,
                -delta(repaid),
                now,
                "Airtime loan repaid".into(),
            );
        }
        Ok(self.outcome(id, msisdn, 0, Detail::TopUp { repaid }))
    }

    fn buy_bundle(&mut self, id: &str, msisdn: &Msisdn, bundle_id: &str, now: u64) -> Result<Outcome, RtnError> {
        self.active(msisdn)?;
        let bundle = self.catalog.bundle(bundle_id).cloned().ok_or(RtnError::UnknownBundle)?;
        self.touch(msisdn, now);
        let account = self.account(msisdn);
        if account.available() < bundle.price {
            return Err(RtnError::InsufficientFunds { needed: bundle.price, available: account.available() });
        }
        let expires_at = now + u64::from(bundle.validity_days) * DAY_MS;
        account.airtime -= bundle.price;
        account.bundles.push(HeldBundle {
            bundle_id: bundle.id.clone(),
            name: bundle.name.clone(),
            bytes_left: bundle.data_bytes,
            expires_at,
        });
        self.totals.revenue += bundle.price;
        self.post(
            id,
            msisdn,
            EntryKind::BundlePurchase,
            -delta(bundle.price),
            delta(bundle.data_bytes),
            0,
            now,
            bundle.name.clone(),
        );
        Ok(self.outcome(id, msisdn, bundle.price, Detail::Bundle { bundle_id: bundle.id, expires_at }))
    }

    fn transfer(&mut self, id: &str, from: &Msisdn, to: &Msisdn, amount: Units, now: u64) -> Result<Outcome, RtnError> {
        if from == to {
            return Err(RtnError::SelfTransfer);
        }
        self.active(from)?;
        self.active(to)?;
        if !(TRANSFER_MIN..=TRANSFER_MAX).contains(&amount) {
            return Err(RtnError::InvalidAmount {
                reason: format!("you can send {} to {}", format_naira(TRANSFER_MIN), format_naira(TRANSFER_MAX)),
            });
        }
        self.touch(from, now);
        self.touch(to, now);
        let sender = self.account(from);
        if sender.loan > 0 {
            return Err(RtnError::LoanOutstanding { owed: sender.loan });
        }
        let needed = amount + TRANSFER_FEE;
        if sender.available() < needed {
            return Err(RtnError::InsufficientFunds { needed, available: sender.available() });
        }
        sender.airtime -= needed;
        self.post(
            id,
            from,
            EntryKind::TransferOut,
            -delta(needed),
            0,
            0,
            now,
            format!("Sent {} to {to}", format_naira(amount)),
        );
        self.account(to).airtime += amount;
        self.post(
            id,
            to,
            EntryKind::TransferIn,
            delta(amount),
            0,
            0,
            now,
            format!("Received {} from {from}", format_naira(amount)),
        );
        self.totals.revenue += TRANSFER_FEE;
        Ok(self.outcome(id, from, TRANSFER_FEE, Detail::Transfer { to: to.clone(), amount, fee: TRANSFER_FEE }))
    }

    fn borrow(&mut self, id: &str, msisdn: &Msisdn, amount: Units, now: u64) -> Result<Outcome, RtnError> {
        let limit = self.active(msisdn)?.loan_limit;
        self.touch(msisdn, now);
        let account = self.account(msisdn);
        if account.loan > 0 {
            return Err(RtnError::LoanOutstanding { owed: account.loan });
        }
        if amount < LOAN_MIN {
            return Err(RtnError::InvalidAmount { reason: format!("the smallest loan is {}", format_naira(LOAN_MIN)) });
        }
        if amount > limit {
            return Err(RtnError::LoanLimit { limit });
        }
        let owed = amount + amount * LOAN_FEE_PERCENT / 100;
        account.airtime += amount;
        account.loan = owed;
        self.totals.lent += amount;
        self.post(
            id,
            msisdn,
            EntryKind::Loan,
            delta(amount),
            0,
            delta(owed),
            now,
            format!("Borrowed {}", format_naira(amount)),
        );
        Ok(self.outcome(id, msisdn, 0, Detail::Loan { borrowed: amount, owed }))
    }

    fn data_usage(&mut self, id: &str, msisdn: &Msisdn, bytes: u64, now: u64) -> Result<Outcome, RtnError> {
        let rate = {
            let subscriber = self.active(msisdn)?;
            self.catalog.plan(&subscriber.plan_id).ok_or(RtnError::UnknownPlan)?.data_per_mb
        };
        if bytes == 0 {
            return Err(RtnError::InvalidAmount { reason: "usage is at least one byte".into() });
        }
        self.touch(msisdn, now);
        let account = self.account(msisdn);
        let from_bundle = bytes.min(account.data_bytes());
        let payg_bytes = bytes - from_bundle;
        let cost = u64::try_from((u128::from(payg_bytes) * u128::from(rate)).div_ceil(u128::from(MB)))
            .map_err(|_| RtnError::InvalidAmount { reason: "too much data in one report".into() })?;
        if cost > account.available() {
            return Err(RtnError::InsufficientFunds { needed: cost, available: account.available() });
        }
        account.bundles.sort_by_key(|b| b.expires_at);
        let mut left = from_bundle;
        for bundle in &mut account.bundles {
            let take = left.min(bundle.bytes_left);
            bundle.bytes_left -= take;
            left -= take;
        }
        account.bundles.retain(|b| b.bytes_left > 0);
        account.airtime -= cost;
        self.totals.revenue += cost;
        self.post(
            id,
            msisdn,
            EntryKind::Data,
            -delta(cost),
            -delta(from_bundle),
            0,
            now,
            format!("{} of data", format_bytes(bytes)),
        );
        Ok(self.outcome(id, msisdn, cost, Detail::Data { from_bundle, payg_bytes }))
    }

    fn voice_start(&mut self, id: &str, msisdn: &Msisdn, callee: &str, now: u64) -> Result<Outcome, RtnError> {
        let rate = {
            let subscriber = self.active(msisdn)?;
            self.catalog.plan(&subscriber.plan_id).ok_or(RtnError::UnknownPlan)?.voice_per_second
        };
        let callee = callee.trim();
        if callee.is_empty() || callee.len() > 32 {
            return Err(RtnError::InvalidRequest { reason: "a callee is 1 to 32 characters".into() });
        }
        if self.calls.contains_key(id) {
            return Err(RtnError::RequestConflict);
        }
        self.touch(msisdn, now);
        let account = self.account(msisdn);
        let granted_seconds = (account.available() / rate).min(MAX_GRANT_SECONDS);
        if granted_seconds == 0 {
            return Err(RtnError::InsufficientFunds { needed: rate, available: account.available() });
        }
        account.reserved += granted_seconds * rate;
        self.calls.insert(
            id.to_owned(),
            VoiceSession { msisdn: msisdn.clone(), callee: callee.to_owned(), rate, granted_seconds, started_at: now },
        );
        Ok(self.outcome(id, msisdn, 0, Detail::VoiceGranted { session_id: id.to_owned(), granted_seconds }))
    }

    fn voice_end(&mut self, id: &str, session_id: &str, used_seconds: u64, now: u64) -> Result<Outcome, RtnError> {
        let session = self.calls.remove(session_id).ok_or(RtnError::UnknownSession)?;
        let billed_seconds = used_seconds.min(session.granted_seconds);
        let cost = billed_seconds * session.rate;
        let account = self.account(&session.msisdn);
        account.reserved -= session.granted_seconds * session.rate;
        account.airtime -= cost;
        self.totals.revenue += cost;
        let _ = session.started_at;
        self.post(
            id,
            &session.msisdn,
            EntryKind::Voice,
            -delta(cost),
            0,
            0,
            now,
            format!("Call to {}, {billed_seconds}s", session.callee),
        );
        Ok(self.outcome(
            id,
            &session.msisdn,
            cost,
            Detail::VoiceEnded { session_id: session_id.to_owned(), billed_seconds },
        ))
    }

    fn sms_submit(&mut self, id: &str, from: &Msisdn, to: &Msisdn, text: &str, now: u64) -> Result<Outcome, RtnError> {
        let rate = {
            let subscriber = self.active(from)?;
            self.catalog.plan(&subscriber.plan_id).ok_or(RtnError::UnknownPlan)?.sms_per_segment
        };
        if !self.subscribers.contains_key(to) {
            return Err(RtnError::UnknownSubscriber);
        }
        if text.is_empty() {
            return Err(RtnError::InvalidMessage { reason: "the message is empty".into() });
        }
        let parts = segments(text);
        if parts > MAX_SEGMENTS {
            return Err(RtnError::InvalidMessage {
                reason: format!("a message is at most {MAX_SEGMENTS} parts; this one is {parts}"),
            });
        }
        self.touch(from, now);
        let cost = u64::from(parts) * rate;
        let account = self.account(from);
        if cost > account.available() {
            return Err(RtnError::InsufficientFunds { needed: cost, available: account.available() });
        }
        account.airtime -= cost;
        self.totals.revenue += cost;
        let plural = if parts == 1 { "" } else { "s" };
        self.post(id, from, EntryKind::Sms, -delta(cost), 0, 0, now, format!("SMS to {to}, {parts} part{plural}"));
        let message_id = self.smsc.submit(from, to, text, parts, now);
        Ok(self.outcome(id, from, cost, Detail::Sms { message_id, segments: parts }))
    }
}

//! What a subscriber does for themselves: signs in with a one-time code sent by SMS, recharges
//! from a voucher, manages their line, and reads the notifications RTN sends them.
//!
//! Nothing here reads a clock or a random number generator. A code or a voucher PIN is derived
//! from a `nonce` the caller passes in, so replaying the same calls gives the same network.
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::network::{Network, Status, Subscriber, TOP_UP_MAX};
use crate::smsc::{segments, SmsMessage};
use crate::types::{format_naira, Imsi, Msisdn, Units};
use crate::RtnError;

/// How long a sign-in code works.
pub const OTP_VALIDITY_MS: u64 = 5 * 60_000;
/// How soon after one code another may be asked for.
pub const OTP_RESEND_MS: u64 = 30_000;
/// Wrong tries before a code is thrown away.
pub const OTP_ATTEMPTS: u32 = 5;
/// Wrong voucher PINs before a line is locked out of recharging, and for how long.
pub const VOUCHER_ATTEMPTS: u32 = 5;
pub const VOUCHER_LOCK_MS: u64 = 30 * 60_000;
/// Most vouchers printed in one batch.
pub const VOUCHER_BATCH_MAX: u32 = 1_000;

fn digest(parts: &[&[u8]]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    for part in parts {
        hasher.update(part);
        hasher.update(b"\x1f");
    }
    hasher.finalize().into()
}

fn number(digest: &[u8; 32], digits: u32) -> String {
    let value = u128::from_be_bytes(digest[..16].try_into().expect("16 bytes"));
    format!("{:0width$}", value % 10u128.pow(digits), width = digits as usize)
}

fn hex_digest(parts: &[&[u8]]) -> String {
    hex::encode(digest(parts))
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Otp {
    code_hash: String,
    issued_at: u64,
    expires_at: u64,
    failures: u32,
}

/// A sign-in code on its way.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OtpIssued {
    pub message_id: String,
    pub expires_at: u64,
}

/// A recharge voucher as the operator sees it. The PIN is never kept, only its hash.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Voucher {
    pub serial: String,
    pub amount: Units,
    pub created_at: u64,
    pub used_by: Option<Msisdn>,
    pub used_at: Option<u64>,
}

/// A voucher as it is printed: the only time its PIN is shown.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct IssuedVoucher {
    pub serial: String,
    pub pin: String,
    pub amount: Units,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct Vouchers {
    next_serial: u64,
    by_pin: BTreeMap<String, String>,
    list: BTreeMap<String, Voucher>,
    failures: BTreeMap<Msisdn, (u32, u64)>,
}

impl Network {
    // ----- sign-in codes ------------------------------------------------------------------------

    /// Sends a six-digit sign-in code to `msisdn` by SMS from RTN's service number. It works once,
    /// for five minutes, and costs the subscriber nothing.
    pub fn request_otp(&mut self, msisdn: &Msisdn, nonce: u64, now: u64) -> Result<OtpIssued, RtnError> {
        if self.subscriber(msisdn).is_none() {
            return Err(RtnError::UnknownSubscriber);
        }
        if let Some(previous) = self.otps.get(msisdn) {
            let ready_at = previous.issued_at + OTP_RESEND_MS;
            if ready_at > now {
                return Err(RtnError::TooSoon { seconds: (ready_at - now).div_ceil(1000) });
            }
        }
        let code =
            number(&digest(&[b"rtn-otp", msisdn.as_str().as_bytes(), &nonce.to_be_bytes(), &now.to_be_bytes()]), 6);
        let expires_at = now + OTP_VALIDITY_MS;
        self.otps.insert(
            msisdn.clone(),
            Otp {
                code_hash: hex_digest(&[b"rtn-otp-hash", msisdn.as_str().as_bytes(), code.as_bytes()]),
                issued_at: now,
                expires_at,
                failures: 0,
            },
        );
        let text = format!("{code} is your RTN sign-in code. It expires in 5 minutes. RTN will never ask you for it.");
        let message_id = self.notify(msisdn, &text, now);
        Ok(OtpIssued { message_id, expires_at })
    }

    /// Checks a sign-in code. A right code is used up; five wrong ones throw it away.
    pub fn verify_otp(&mut self, msisdn: &Msisdn, code: &str, now: u64) -> Result<(), RtnError> {
        let Some(otp) = self.otps.get_mut(msisdn) else { return Err(RtnError::CodeExpired) };
        if otp.expires_at <= now {
            self.otps.remove(msisdn);
            return Err(RtnError::CodeExpired);
        }
        let given = hex_digest(&[b"rtn-otp-hash", msisdn.as_str().as_bytes(), code.trim().as_bytes()]);
        if crate::network::constant_time_eq(&given, &otp.code_hash) {
            self.otps.remove(msisdn);
            return Ok(());
        }
        otp.failures += 1;
        if otp.failures >= OTP_ATTEMPTS {
            self.otps.remove(msisdn);
            return Err(RtnError::CodeExpired);
        }
        Err(RtnError::WrongCode)
    }

    // ----- vouchers -----------------------------------------------------------------------------

    /// Prints `count` vouchers of `amount` each. The PINs are in the answer and nowhere else.
    pub fn issue_vouchers(
        &mut self,
        count: u32,
        amount: Units,
        nonce: u64,
        now: u64,
    ) -> Result<Vec<IssuedVoucher>, RtnError> {
        if count == 0 || count > VOUCHER_BATCH_MAX {
            return Err(RtnError::InvalidAmount { reason: format!("a batch is 1 to {VOUCHER_BATCH_MAX} vouchers") });
        }
        if !(10_000..=TOP_UP_MAX).contains(&amount) {
            return Err(RtnError::InvalidAmount {
                reason: format!("a voucher is worth {} to {}", format_naira(10_000), format_naira(TOP_UP_MAX)),
            });
        }
        let mut issued = Vec::with_capacity(count as usize);
        for _ in 0..count {
            self.vouchers.next_serial += 1;
            let serial = format!("RTN{:010}", self.vouchers.next_serial);
            let mut salt = 0u64;
            let (pin, key) = loop {
                let pin = number(
                    &digest(&[b"rtn-voucher", serial.as_bytes(), &nonce.to_be_bytes(), &salt.to_be_bytes()]),
                    16,
                );
                let key = hex_digest(&[b"rtn-voucher-pin", pin.as_bytes()]);
                if !self.vouchers.by_pin.contains_key(&key) {
                    break (pin, key);
                }
                salt += 1;
            };
            self.vouchers.by_pin.insert(key, serial.clone());
            self.vouchers.list.insert(
                serial.clone(),
                Voucher { serial: serial.clone(), amount, created_at: now, used_by: None, used_at: None },
            );
            issued.push(IssuedVoucher { serial, pin, amount });
        }
        Ok(issued)
    }

    /// Every voucher, newest first.
    pub fn vouchers(&self) -> Vec<&Voucher> {
        self.vouchers.list.values().rev().collect()
    }

    /// The voucher behind a PIN, after the line's guesses are counted. Used by
    /// [`Op::RedeemVoucher`](crate::Op::RedeemVoucher).
    pub(crate) fn redeem_voucher(
        &mut self,
        id: &str,
        msisdn: &Msisdn,
        pin: &str,
        now: u64,
    ) -> Result<crate::Outcome, RtnError> {
        self.active(msisdn)?;
        if let Some(&(_, locked_until)) = self.vouchers.failures.get(msisdn) {
            if locked_until > now {
                return Err(RtnError::VoucherLocked { seconds: (locked_until - now).div_ceil(1000) });
            }
        }
        let digits: String = pin.chars().filter(|c| !matches!(c, ' ' | '-')).collect();
        let serial = (digits.len() == 16 && digits.bytes().all(|b| b.is_ascii_digit()))
            .then(|| self.vouchers.by_pin.get(&hex_digest(&[b"rtn-voucher-pin", digits.as_bytes()])).cloned())
            .flatten();
        let Some(serial) = serial else {
            let entry = self.vouchers.failures.entry(msisdn.clone()).or_insert((0, 0));
            entry.0 += 1;
            if entry.0 >= VOUCHER_ATTEMPTS {
                *entry = (0, now + VOUCHER_LOCK_MS);
            }
            return Err(RtnError::UnknownVoucher);
        };
        let voucher = self.vouchers.list.get_mut(&serial).expect("every PIN names a voucher");
        if voucher.used_by.is_some() {
            return Err(RtnError::VoucherUsed);
        }
        voucher.used_by = Some(msisdn.clone());
        voucher.used_at = Some(now);
        let amount = voucher.amount;
        self.vouchers.failures.remove(msisdn);
        let repaid =
            self.credit(id, msisdn, amount, format!("Voucher recharge of {} ({serial})", format_naira(amount)), now);
        let text = format!(
            "Your line was recharged with {} from voucher {serial}. Airtime: {}.",
            format_naira(amount),
            format_naira(self.peek_balance(msisdn, now)?.airtime)
        );
        self.notify(msisdn, &text, now);
        let balance = self.peek_balance(msisdn, now)?;
        Ok(crate::Outcome {
            request_id: id.to_owned(),
            charged: 0,
            balance,
            detail: crate::Detail::Voucher { serial, amount, repaid },
        })
    }

    // ----- the line -----------------------------------------------------------------------------

    /// Changes a PIN, given the one in use now.
    pub fn change_pin(&mut self, msisdn: &Msisdn, old: &str, new: &str, now: u64) -> Result<(), RtnError> {
        self.verify_pin(msisdn, old, now)?;
        self.set_pin(msisdn, new)
    }

    /// Moves the number to a new SIM: a new IMSI, the same number, balances and history.
    pub fn swap_sim(&mut self, msisdn: &Msisdn, pin: &str, now: u64) -> Result<Subscriber, RtnError> {
        self.verify_pin(msisdn, pin, now)?;
        let imsi = loop {
            let candidate = Imsi::issue(self.next_imsi);
            self.next_imsi += 1;
            if !self.by_imsi.contains_key(&candidate) {
                break candidate;
            }
        };
        let subscriber = self.subscribers.get_mut(msisdn).ok_or(RtnError::UnknownSubscriber)?;
        let old = std::mem::replace(&mut subscriber.imsi, imsi.clone());
        let swapped = subscriber.clone();
        self.by_imsi.remove(&old);
        self.by_imsi.insert(imsi, msisdn.clone());
        self.notify(
            msisdn,
            "Your number is now on a new SIM. If you did not ask for this, call RTN care at once.",
            now,
        );
        Ok(swapped)
    }

    /// Bars a lost or stolen line at its owner's request. Only the operator lifts it.
    pub fn suspend_line(&mut self, msisdn: &Msisdn, pin: &str, now: u64) -> Result<(), RtnError> {
        self.verify_pin(msisdn, pin, now)?;
        self.set_status(msisdn, Status::Barred)
    }

    /// The name on the line.
    pub fn set_name(&mut self, msisdn: &Msisdn, name: &str) -> Result<(), RtnError> {
        let name = name.trim();
        if name.is_empty() || name.chars().count() > 80 {
            return Err(RtnError::InvalidRequest { reason: "a name is 1 to 80 characters".into() });
        }
        self.subscribers.get_mut(msisdn).ok_or(RtnError::UnknownSubscriber)?.name = name.to_owned();
        Ok(())
    }

    // ----- notifications ------------------------------------------------------------------------

    /// Sends `text` to `to` from RTN's service number, free of charge. Returns the message id.
    pub(crate) fn notify(&mut self, to: &Msisdn, text: &str, now: u64) -> String {
        let parts = segments(text);
        self.smsc.submit(&Msisdn::service(), to, text, parts, now)
    }

    /// What RTN has told a subscriber, oldest first.
    pub fn notifications(&self, msisdn: &Msisdn) -> Vec<&SmsMessage> {
        self.inbox(msisdn).into_iter().filter(|m| m.from.is_service()).collect()
    }
}

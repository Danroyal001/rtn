//! The SMS centre: store-and-forward with retries, expiry and delivery reports.
use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::network::Network;
use crate::types::Msisdn;

/// How long a message is kept for a recipient who is not attached.
pub const VALIDITY_MS: u64 = 24 * 3_600_000;
/// The most segments one message may be split into.
pub const MAX_SEGMENTS: u32 = 6;
/// Finished messages are forgotten this long after they were submitted.
const RETENTION_MS: u64 = 2 * VALIDITY_MS;
/// Messages kept per inbox and reports kept per sender.
const INBOX_CAP: usize = 200;

const GSM7_BASIC: &str = "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà";
const GSM7_EXTENSION: &str = "^{}\\[~]|€\u{000C}";

/// How many segments a handset would split `text` into: GSM-7 when every character is in the
/// GSM 03.38 alphabet (160 septets, 153 per part when split), UCS-2 otherwise (70, 67 per part).
pub fn segments(text: &str) -> u32 {
    let mut septets = 0usize;
    let mut gsm7 = true;
    for c in text.chars() {
        match gsm7_septets(c) {
            Some(n) => septets += n,
            None => {
                gsm7 = false;
                break;
            }
        }
    }
    let (units, single, part) = if gsm7 { (septets, 160, 153) } else { (text.encode_utf16().count(), 70, 67) };
    let count = if units <= single { 1 } else { units.div_ceil(part) };
    u32::try_from(count).unwrap_or(u32::MAX)
}

/// Septets a character takes in GSM-7, or `None` when it is not in the alphabet.
fn gsm7_septets(c: char) -> Option<usize> {
    if c.is_ascii() {
        return match c {
            '^' | '{' | '}' | '\\' | '[' | '~' | ']' | '|' | '\u{000C}' => Some(2),
            '`' => None,
            '\n' | '\r' => Some(1),
            c if c.is_ascii_control() => None,
            _ => Some(1),
        };
    }
    if GSM7_BASIC.contains(c) {
        Some(1)
    } else if GSM7_EXTENSION.contains(c) {
        Some(2)
    } else {
        None
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SmsState {
    Queued,
    Delivered,
    Expired,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SmsMessage {
    pub id: String,
    pub from: Msisdn,
    pub to: Msisdn,
    pub text: String,
    pub segments: u32,
    pub submitted_at: u64,
    pub state: SmsState,
    pub attempts: u32,
    pub next_attempt_at: u64,
    pub finished_at: Option<u64>,
}

/// Told to the sender when a message is delivered or given up on.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeliveryReport {
    pub message_id: String,
    pub to: Msisdn,
    pub state: SmsState,
    pub at: u64,
}

/// What one delivery pass did.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeliveryRun {
    pub delivered: u32,
    pub retried: u32,
    pub expired: u32,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct Smsc {
    next_id: u64,
    messages: BTreeMap<String, SmsMessage>,
    queued: BTreeSet<String>,
    inboxes: BTreeMap<Msisdn, Vec<String>>,
    outboxes: BTreeMap<Msisdn, Vec<String>>,
    reports: BTreeMap<Msisdn, Vec<DeliveryReport>>,
}

fn backoff(attempts: u32) -> u64 {
    (30_000u64 << attempts.min(7)).min(3_600_000)
}

fn push_capped<T>(list: &mut Vec<T>, item: T) {
    list.push(item);
    if list.len() > INBOX_CAP {
        list.remove(0);
    }
}

impl Smsc {
    pub(crate) fn submit(&mut self, from: &Msisdn, to: &Msisdn, text: &str, segments: u32, now: u64) -> String {
        self.next_id += 1;
        let id = format!("msg-{:08}", self.next_id);
        self.messages.insert(
            id.clone(),
            SmsMessage {
                id: id.clone(),
                from: from.clone(),
                to: to.clone(),
                text: text.to_owned(),
                segments,
                submitted_at: now,
                state: SmsState::Queued,
                attempts: 0,
                next_attempt_at: now,
                finished_at: None,
            },
        );
        self.queued.insert(id.clone());
        push_capped(self.outboxes.entry(from.clone()).or_default(), id.clone());
        id
    }

    fn finish(&mut self, id: &str, state: SmsState, now: u64) {
        let Some(message) = self.messages.get_mut(id) else { return };
        message.state = state;
        message.finished_at = Some(now);
        self.queued.remove(id);
        let (from, to) = (message.from.clone(), message.to.clone());
        if state == SmsState::Delivered {
            push_capped(self.inboxes.entry(to.clone()).or_default(), id.to_owned());
        }
        push_capped(
            self.reports.entry(from).or_default(),
            DeliveryReport { message_id: id.to_owned(), to, state, at: now },
        );
    }

    pub(crate) fn queued_len(&self) -> usize {
        self.queued.len()
    }

    fn forget_old(&mut self, now: u64) {
        let cutoff = now.saturating_sub(RETENTION_MS);
        let old: Vec<String> = self
            .messages
            .values()
            .filter(|m| m.state != SmsState::Queued && m.submitted_at < cutoff)
            .map(|m| m.id.clone())
            .collect();
        if old.is_empty() {
            return;
        }
        for id in &old {
            self.messages.remove(id);
        }
        let messages = &self.messages;
        for list in self.inboxes.values_mut().chain(self.outboxes.values_mut()) {
            list.retain(|id| messages.contains_key(id));
        }
    }
}

impl Network {
    /// One store-and-forward pass: delivers every due message whose recipient is attached, backs
    /// off the rest, and gives up on those past the validity period.
    pub fn deliver_sms(&mut self, now: u64) -> DeliveryRun {
        let mut run = DeliveryRun::default();
        let due: Vec<String> =
            self.smsc.queued.iter().filter(|id| self.smsc.messages[*id].next_attempt_at <= now).cloned().collect();
        for id in due {
            let (to, submitted_at) = {
                let m = &self.smsc.messages[&id];
                (m.to.clone(), m.submitted_at)
            };
            if now >= submitted_at + VALIDITY_MS {
                self.smsc.finish(&id, SmsState::Expired, now);
                run.expired += 1;
            } else if self.subscribers.get(&to).is_some_and(|s| s.attached) {
                self.smsc.finish(&id, SmsState::Delivered, now);
                run.delivered += 1;
            } else {
                let m = self.smsc.messages.get_mut(&id).expect("queued messages exist");
                m.attempts += 1;
                m.next_attempt_at = now + backoff(m.attempts);
                run.retried += 1;
            }
        }
        self.smsc.forget_old(now);
        run
    }

    /// Delivers what is held for one recipient, as when their handset attaches.
    pub(crate) fn deliver_to(&mut self, msisdn: &Msisdn, now: u64) {
        let held: Vec<String> =
            self.smsc.queued.iter().filter(|id| self.smsc.messages[*id].to == *msisdn).cloned().collect();
        for id in held {
            let state = if now >= self.smsc.messages[&id].submitted_at + VALIDITY_MS {
                SmsState::Expired
            } else {
                SmsState::Delivered
            };
            self.smsc.finish(&id, state, now);
        }
    }

    pub fn message(&self, id: &str) -> Option<&SmsMessage> {
        self.smsc.messages.get(id)
    }

    /// Messages delivered to a subscriber, oldest first.
    pub fn inbox(&self, msisdn: &Msisdn) -> Vec<&SmsMessage> {
        self.list(self.smsc.inboxes.get(msisdn))
    }

    /// Messages a subscriber sent, oldest first, whatever their state.
    pub fn outbox(&self, msisdn: &Msisdn) -> Vec<&SmsMessage> {
        self.list(self.smsc.outboxes.get(msisdn))
    }

    fn list(&self, ids: Option<&Vec<String>>) -> Vec<&SmsMessage> {
        ids.map(|ids| ids.iter().filter_map(|id| self.smsc.messages.get(id)).collect()).unwrap_or_default()
    }

    /// Delivery reports for messages a subscriber sent, oldest first.
    pub fn delivery_reports(&self, msisdn: &Msisdn) -> Vec<&DeliveryReport> {
        self.smsc.reports.get(msisdn).map(|r| r.iter().collect()).unwrap_or_default()
    }

    pub fn queued_sms(&self) -> usize {
        self.smsc.queued_len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_ascii_fast_path_agrees_with_the_alphabet_tables() {
        for byte in 0u8..128 {
            let c = char::from(byte);
            let from_tables = if GSM7_BASIC.contains(c) {
                Some(1)
            } else if GSM7_EXTENSION.contains(c) {
                Some(2)
            } else {
                None
            };
            assert_eq!(gsm7_septets(c), from_tables, "{c:?}");
        }
    }
}

//! Customer care: one conversation per subscriber. An assistant answers the common questions
//! from the subscriber's own line until an agent replies; from then on it stays quiet.
use serde::{Deserialize, Serialize};

use crate::network::{format_bytes, Network};
use crate::types::{format_naira, Msisdn};
use crate::RtnError;

/// Longest message either side may send.
pub const CARE_MESSAGE_MAX: usize = 2_000;
/// Messages kept per conversation.
const CARE_KEEP: usize = 200;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CareAuthor {
    Subscriber,
    Assistant,
    Agent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CareMessage {
    pub at: u64,
    pub author: CareAuthor,
    pub text: String,
}

/// One conversation as the care desk lists it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CareThread {
    pub msisdn: Msisdn,
    pub name: String,
    pub messages: usize,
    pub last_at: u64,
    pub last_text: String,
    /// The subscriber spoke last and nobody has answered.
    pub waiting: bool,
}

fn checked(text: &str) -> Result<String, RtnError> {
    let text = text.trim();
    if text.is_empty() || text.chars().count() > CARE_MESSAGE_MAX {
        return Err(RtnError::InvalidMessage { reason: format!("a message is 1 to {CARE_MESSAGE_MAX} characters") });
    }
    Ok(text.to_owned())
}

fn push(thread: &mut Vec<CareMessage>, message: CareMessage) {
    thread.push(message);
    if thread.len() > CARE_KEEP {
        thread.remove(0);
    }
}

impl Network {
    /// A subscriber writes to care. Returns the conversation, with the assistant's answer when
    /// no agent has joined.
    pub fn care_send(&mut self, msisdn: &Msisdn, text: &str, now: u64) -> Result<Vec<CareMessage>, RtnError> {
        if self.subscriber(msisdn).is_none() {
            return Err(RtnError::UnknownSubscriber);
        }
        let text = checked(text)?;
        let agent_joined = self.care.get(msisdn).is_some_and(|t| t.iter().any(|m| m.author == CareAuthor::Agent));
        let answer = (!agent_joined).then(|| self.assistant(msisdn, &text, now));
        let thread = self.care.entry(msisdn.clone()).or_default();
        push(thread, CareMessage { at: now, author: CareAuthor::Subscriber, text });
        if let Some(answer) = answer {
            push(thread, CareMessage { at: now, author: CareAuthor::Assistant, text: answer });
        }
        Ok(thread.clone())
    }

    /// An agent answers a subscriber.
    pub fn care_reply(&mut self, msisdn: &Msisdn, text: &str, now: u64) -> Result<Vec<CareMessage>, RtnError> {
        if self.subscriber(msisdn).is_none() {
            return Err(RtnError::UnknownSubscriber);
        }
        let text = checked(text)?;
        let thread = self.care.entry(msisdn.clone()).or_default();
        push(thread, CareMessage { at: now, author: CareAuthor::Agent, text });
        Ok(thread.clone())
    }

    /// A subscriber's conversation, oldest first.
    pub fn care_thread(&self, msisdn: &Msisdn) -> Vec<CareMessage> {
        self.care.get(msisdn).cloned().unwrap_or_default()
    }

    /// Every conversation, the ones waiting for an answer first, then the most recent.
    pub fn care_threads(&self) -> Vec<CareThread> {
        let mut threads: Vec<CareThread> = self
            .care
            .iter()
            .filter_map(|(msisdn, thread)| {
                let last = thread.last()?;
                Some(CareThread {
                    msisdn: msisdn.clone(),
                    name: self.subscriber(msisdn).map(|s| s.name.clone()).unwrap_or_default(),
                    messages: thread.len(),
                    last_at: last.at,
                    last_text: last.text.clone(),
                    waiting: last.author == CareAuthor::Subscriber,
                })
            })
            .collect();
        threads.sort_by(|a, b| b.waiting.cmp(&a.waiting).then(b.last_at.cmp(&a.last_at)));
        threads
    }

    fn assistant(&self, msisdn: &Msisdn, question: &str, now: u64) -> String {
        let q = question.to_lowercase();
        let has = |words: &[&str]| words.iter().any(|w| q.contains(w));
        if has(&["human", "agent", "person", "someone"]) {
            return "I have asked an agent to join. They will answer here; you can close the app and come back.".into();
        }
        if has(&["lost", "stolen", "steal"]) {
            return "Sorry to hear that. Open Account and suspend the line so nobody else can use it. \
                    An agent can lift the suspension when you have your new SIM."
                .into();
        }
        if has(&["pin"]) {
            return "You can change your PIN under Account. If you have forgotten it, ask for an agent here \
                    and they will reset it after checking it is you."
                .into();
        }
        if has(&["borrow", "loan", "credit"]) {
            let limit = self.subscriber(msisdn).map_or(0, |s| s.loan_limit);
            return format!(
                "You can borrow up to {} from the Borrow page or by dialling *303#. \
                 It is repaid from your next recharge with a 10% fee.",
                format_naira(limit)
            );
        }
        if has(&["data", "bundle", "internet", "mb", "gb"]) {
            let data = self.peek_balance(msisdn, now).map(|b| b.data_bytes).unwrap_or(0);
            return format!(
                "You have {} of data left. You can buy a bundle on the Data page or by dialling *312#.",
                format_bytes(data)
            );
        }
        if has(&["balance", "airtime", "money", "how much"]) {
            return match self.peek_balance(msisdn, now) {
                Ok(b) => format!(
                    "Your airtime is {} and you have {} of data.{}",
                    format_naira(b.airtime),
                    format_bytes(b.data_bytes),
                    if b.loan > 0 { format!(" You owe {}.", format_naira(b.loan)) } else { String::new() }
                ),
                Err(_) => "I could not read your balance just now.".into(),
            };
        }
        if has(&["recharge", "top up", "topup", "voucher", "card"]) {
            return "Recharge on the Recharge page with a voucher PIN or a card, or dial *555*PIN#.".into();
        }
        "I am RTN's assistant. I can help with your balance, data, borrowing, recharges, PINs and lost SIMs. \
         Ask for an agent if you would like a person."
            .into()
    }
}

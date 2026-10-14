//! The USSD gateway: a menu state machine per session, answered the way aggregators expect,
//! `CON` text when it wants more input and `END` text when the session is over.
use serde::{Deserialize, Serialize};

use crate::network::{format_bytes, Detail, Network, Op};
use crate::types::{format_naira, Msisdn, Units};
use crate::RtnError;

/// A session closes when nothing arrives for this long.
pub const SESSION_TIMEOUT_MS: u64 = 180_000;
/// Amounts offered by the borrow menu, before the subscriber's limit.
const LOAN_OFFERS: [Units; 3] = [10_000, 20_000, 50_000];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct UssdReply {
    pub text: String,
    /// True when the session is over (`END`), false when it waits for input (`CON`).
    pub end: bool,
}

impl UssdReply {
    fn more(text: impl Into<String>) -> Self {
        Self { text: text.into(), end: false }
    }

    fn done(text: impl Into<String>) -> Self {
        Self { text: text.into(), end: true }
    }

    /// The reply in the `CON …`/`END …` form aggregators send back to the handset.
    pub fn wire(&self) -> String {
        format!("{} {}", if self.end { "END" } else { "CON" }, self.text)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "at", rename_all = "snake_case")]
enum Menu {
    Main,
    Bundles,
    BundleConfirm { bundle_id: String },
    TransferNumber,
    TransferAmount { to: Msisdn },
    TransferPin { to: Msisdn, amount: Units },
    Borrow { offers: Vec<Units> },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct UssdSession {
    msisdn: Msisdn,
    menu: Menu,
    last_at: u64,
}

const MAIN_MENU: &str = "RTN\n1. Balance\n2. Data bundles\n3. Transfer airtime\n4. Borrow airtime\n5. My number";

fn sentence(error: &RtnError) -> String {
    let text = error.to_string();
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => format!("{}{}.", first.to_uppercase(), chars.as_str()),
        None => String::new(),
    }
}

/// Naira typed on a keypad ("100", "100.50") in minor units.
fn parse_naira(input: &str) -> Option<Units> {
    let (whole, fraction) = input.split_once('.').unwrap_or((input, ""));
    if whole.is_empty() || whole.len() > 9 || fraction.len() > 2 {
        return None;
    }
    if !whole.bytes().chain(fraction.bytes()).all(|b| b.is_ascii_digit()) {
        return None;
    }
    let fraction: Units = format!("{fraction:0<2}").parse().ok()?;
    Some(whole.parse::<Units>().ok()? * 100 + fraction)
}

impl Network {
    /// Handles one USSD request. A new session starts with a dial string (`*123#`); later
    /// requests in the same session carry the subscriber's reply.
    pub fn ussd(&mut self, session_id: &str, msisdn: &Msisdn, input: &str, now: u64) -> Result<UssdReply, RtnError> {
        if !self.subscribers.contains_key(msisdn) {
            return Err(RtnError::UnknownSubscriber);
        }
        if session_id.is_empty() || session_id.len() > 128 {
            return Err(RtnError::InvalidRequest { reason: "a session id is 1 to 128 characters".into() });
        }
        self.traffic.record(now, |c| c.ussd += 1);
        self.ussd_sessions.retain(|_, s| s.last_at + SESSION_TIMEOUT_MS >= now);
        let input = input.trim();
        let menu = match self.ussd_sessions.get(session_id) {
            Some(session) if session.msisdn == *msisdn => Some(session.menu.clone()),
            Some(_) => {
                return Err(RtnError::InvalidRequest { reason: "that session belongs to another number".into() })
            }
            None => None,
        };
        let (reply, next) = match menu {
            Some(menu) => self.ussd_step(session_id, msisdn, menu, input, now),
            None if input.starts_with('*') && input.ends_with('#') => self.ussd_dial(session_id, msisdn, input, now),
            None if input.is_empty() || input.starts_with('*') => (UssdReply::done("Unknown service code."), None),
            None => (UssdReply::done("Your session timed out. Dial *123# to start again."), None),
        };
        match (reply.end, next) {
            (false, Some(menu)) => {
                self.ussd_sessions
                    .insert(session_id.to_owned(), UssdSession { msisdn: msisdn.clone(), menu, last_at: now });
            }
            _ => {
                self.ussd_sessions.remove(session_id);
            }
        }
        Ok(reply)
    }

    fn ussd_dial(&mut self, session: &str, msisdn: &Msisdn, dial: &str, now: u64) -> (UssdReply, Option<Menu>) {
        let code: Vec<&str> = dial.trim_start_matches('*').trim_end_matches('#').split('*').collect();
        match code.as_slice() {
            ["123"] => (UssdReply::more(MAIN_MENU), Some(Menu::Main)),
            ["123", choice] => self.ussd_step(session, msisdn, Menu::Main, choice, now),
            ["312"] => self.ussd_step(session, msisdn, Menu::Main, "2", now),
            ["303"] => self.ussd_step(session, msisdn, Menu::Main, "4", now),
            ["321", to, amount, pin] => {
                let Ok(to) = Msisdn::parse(to) else {
                    return (UssdReply::done("That is not a phone number."), None);
                };
                let Some(amount) = parse_naira(amount) else {
                    return (UssdReply::done("That is not an amount."), None);
                };
                (self.ussd_transfer(session, msisdn, &to, amount, pin, now), None)
            }
            _ => (UssdReply::done("Unknown service code."), None),
        }
    }

    fn bundle_menu(&self) -> String {
        let mut text = String::from("Data bundles");
        for (i, b) in self.catalog.bundles().iter().enumerate() {
            text.push_str(&format!("\n{}. {} {}", i + 1, b.name, format_naira(b.price)));
        }
        text.push_str("\n0. Back");
        text
    }

    fn ussd_step(
        &mut self,
        session: &str,
        msisdn: &Msisdn,
        menu: Menu,
        input: &str,
        now: u64,
    ) -> (UssdReply, Option<Menu>) {
        let invalid = |text: String, menu: Menu| (UssdReply::more(format!("Invalid choice.\n{text}")), Some(menu));
        if input == "0" && menu != Menu::Main {
            return (UssdReply::more(MAIN_MENU), Some(Menu::Main));
        }
        match menu {
            Menu::Main => match input {
                "1" => match self.balance(msisdn, now) {
                    Ok(b) => {
                        let mut text =
                            format!("Airtime: {}\nData: {}", format_naira(b.airtime), format_bytes(b.data_bytes));
                        if b.loan > 0 {
                            text.push_str(&format!("\nLoan: {}", format_naira(b.loan)));
                        }
                        (UssdReply::done(text), None)
                    }
                    Err(e) => (UssdReply::done(sentence(&e)), None),
                },
                "2" => (UssdReply::more(self.bundle_menu()), Some(Menu::Bundles)),
                "3" => (UssdReply::more("Enter the recipient's number\n0. Back"), Some(Menu::TransferNumber)),
                "4" => {
                    let limit = self.subscribers[msisdn].loan_limit;
                    let offers: Vec<Units> = LOAN_OFFERS.iter().copied().filter(|&a| a <= limit).collect();
                    if offers.is_empty() {
                        return (UssdReply::done("You cannot borrow airtime on this line."), None);
                    }
                    let mut text = String::from("Borrow airtime (10% service fee)");
                    for (i, amount) in offers.iter().enumerate() {
                        text.push_str(&format!("\n{}. {}", i + 1, format_naira(*amount)));
                    }
                    text.push_str("\n0. Back");
                    (UssdReply::more(text), Some(Menu::Borrow { offers }))
                }
                "5" => (UssdReply::done(format!("Your number is {msisdn}.")), None),
                _ => invalid(MAIN_MENU.into(), Menu::Main),
            },
            Menu::Bundles => {
                let chosen = input
                    .parse::<usize>()
                    .ok()
                    .and_then(|n| n.checked_sub(1))
                    .and_then(|i| self.catalog.bundles().get(i));
                match chosen {
                    Some(b) => {
                        let days =
                            if b.validity_days == 1 { "1 day".to_owned() } else { format!("{} days", b.validity_days) };
                        let text =
                            format!("{} for {}, valid {days}.\n1. Confirm\n0. Back", b.name, format_naira(b.price));
                        (UssdReply::more(text), Some(Menu::BundleConfirm { bundle_id: b.id.clone() }))
                    }
                    None => invalid(self.bundle_menu(), Menu::Bundles),
                }
            }
            Menu::BundleConfirm { bundle_id } => {
                if input != "1" {
                    return invalid("1. Confirm\n0. Back".into(), Menu::BundleConfirm { bundle_id });
                }
                let id = format!("ussd:{session}:bundle:{bundle_id}");
                match self.apply(&id, Op::BuyBundle { msisdn: msisdn.clone(), bundle_id: bundle_id.clone() }, now) {
                    Ok(out) => {
                        let name = self.catalog.bundle(&bundle_id).map(|b| b.name.clone()).unwrap_or(bundle_id);
                        (
                            UssdReply::done(format!(
                                "You bought {name}. Data: {}. Airtime: {}.",
                                format_bytes(out.balance.data_bytes),
                                format_naira(out.balance.airtime)
                            )),
                            None,
                        )
                    }
                    Err(e) => (UssdReply::done(sentence(&e)), None),
                }
            }
            Menu::TransferNumber => match Msisdn::parse(input) {
                Ok(to) => (UssdReply::more("Enter the amount in naira\n0. Back"), Some(Menu::TransferAmount { to })),
                Err(_) => invalid("Enter the recipient's number\n0. Back".into(), Menu::TransferNumber),
            },
            Menu::TransferAmount { to } => match parse_naira(input) {
                Some(amount) => (
                    UssdReply::more(format!(
                        "Send {} to {to}?\nEnter your PIN to confirm\n0. Back",
                        format_naira(amount)
                    )),
                    Some(Menu::TransferPin { to, amount }),
                ),
                None => invalid("Enter the amount in naira\n0. Back".into(), Menu::TransferAmount { to }),
            },
            Menu::TransferPin { to, amount } => (self.ussd_transfer(session, msisdn, &to, amount, input, now), None),
            Menu::Borrow { offers } => {
                let chosen =
                    input.parse::<usize>().ok().and_then(|n| n.checked_sub(1)).and_then(|i| offers.get(i)).copied();
                let Some(amount) = chosen else {
                    return invalid("Choose an amount\n0. Back".into(), Menu::Borrow { offers });
                };
                let id = format!("ussd:{session}:borrow");
                match self.apply(&id, Op::Borrow { msisdn: msisdn.clone(), amount }, now) {
                    Ok(out) => {
                        let Detail::Loan { owed, .. } = out.detail else { unreachable!("a loan outcome") };
                        (
                            UssdReply::done(format!(
                                "You borrowed {}. You will repay {} from your next top-up.",
                                format_naira(amount),
                                format_naira(owed)
                            )),
                            None,
                        )
                    }
                    Err(e) => (UssdReply::done(sentence(&e)), None),
                }
            }
        }
    }

    fn ussd_transfer(
        &mut self,
        session: &str,
        from: &Msisdn,
        to: &Msisdn,
        amount: Units,
        pin: &str,
        now: u64,
    ) -> UssdReply {
        if let Err(e) = self.verify_pin(from, pin, now) {
            return UssdReply::done(sentence(&e));
        }
        let id = format!("ussd:{session}:transfer");
        match self.apply(&id, Op::Transfer { from: from.clone(), to: to.clone(), amount }, now) {
            Ok(out) => UssdReply::done(format!(
                "{} sent to {to}. Fee {}. Airtime: {}.",
                format_naira(amount),
                format_naira(out.charged),
                format_naira(out.balance.airtime)
            )),
            Err(e) => UssdReply::done(sentence(&e)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_naira_typed_on_a_keypad() {
        assert_eq!(parse_naira("100"), Some(10_000));
        assert_eq!(parse_naira("100.5"), Some(10_050));
        assert_eq!(parse_naira("0.05"), Some(5));
        assert_eq!(parse_naira("1.234"), None);
        assert_eq!(parse_naira("abc"), None);
        assert_eq!(parse_naira(""), None);
    }

    #[test]
    fn wire_format_is_con_or_end() {
        assert_eq!(UssdReply::more("x").wire(), "CON x");
        assert_eq!(UssdReply::done("y").wire(), "END y");
    }
}

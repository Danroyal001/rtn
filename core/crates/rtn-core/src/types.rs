use std::fmt;

use serde::{Deserialize, Serialize};

use crate::RtnError;

/// Money in minor units: 100 units are ₦1.
pub type Units = u64;

/// One megabyte, as data bundles and rates count it.
pub const MB: u64 = 1_048_576;

/// "₦1,234.50" for 123_450 units.
pub fn format_naira(units: Units) -> String {
    let whole = (units / 100).to_string();
    let mut grouped = String::with_capacity(whole.len() + whole.len() / 3);
    for (i, digit) in whole.chars().enumerate() {
        if i > 0 && (whole.len() - i) % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(digit);
    }
    format!("₦{grouped}.{:02}", units % 100)
}

/// A subscriber's number in international form without the `+`: `2349990000001`.
///
/// Parsing accepts `+234…`, `234…`, a local `0…` number (taken as Nigerian), and spaces or dashes
/// between digits.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Msisdn(String);

impl Msisdn {
    pub fn parse(input: &str) -> Result<Self, RtnError> {
        let mut digits = String::with_capacity(16);
        for (i, c) in input.trim().chars().enumerate() {
            match c {
                '0'..='9' => digits.push(c),
                '+' if i == 0 => {}
                ' ' | '-' => {}
                _ => return Err(RtnError::InvalidMsisdn),
            }
        }
        if digits.len() == 11 && digits.starts_with('0') {
            digits = format!("234{}", &digits[1..]);
        }
        if !(10..=15).contains(&digits.len()) || digits.starts_with('0') {
            return Err(RtnError::InvalidMsisdn);
        }
        Ok(Self(digits))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for Msisdn {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl TryFrom<String> for Msisdn {
    type Error = RtnError;
    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::parse(&value)
    }
}

impl From<Msisdn> for String {
    fn from(value: Msisdn) -> Self {
        value.0
    }
}

/// A SIM's identity: 15 digits, MCC + MNC + subscriber number. RTN issues IMSIs under MCC 999,
/// which ITU reserves for private networks.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Imsi(String);

impl Imsi {
    pub const PREFIX: &'static str = "99970";

    pub fn parse(input: &str) -> Result<Self, RtnError> {
        let trimmed = input.trim();
        if trimmed.len() != 15 || !trimmed.bytes().all(|b| b.is_ascii_digit()) {
            return Err(RtnError::InvalidImsi);
        }
        Ok(Self(trimmed.to_owned()))
    }

    /// The IMSI RTN issues for its `serial`th SIM.
    pub fn issue(serial: u64) -> Self {
        Self(format!("{}{:010}", Self::PREFIX, serial % 10_000_000_000))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for Imsi {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl TryFrom<String> for Imsi {
    type Error = RtnError;
    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::parse(&value)
    }
}

impl From<Imsi> for String {
    fn from(value: Imsi) -> Self {
        value.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_naira_with_grouping() {
        assert_eq!(format_naira(0), "₦0.00");
        assert_eq!(format_naira(5), "₦0.05");
        assert_eq!(format_naira(123_450), "₦1,234.50");
        assert_eq!(format_naira(100_000_000), "₦1,000,000.00");
    }

    #[test]
    fn issues_imsis_under_the_private_mcc() {
        assert_eq!(Imsi::issue(7).as_str(), "999700000000007");
    }
}

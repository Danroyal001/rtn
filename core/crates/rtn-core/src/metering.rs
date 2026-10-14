//! A seeded traffic simulator: data sessions, calls, SMS, top-ups and handsets coming and going,
//! all applied through the charging engine as a real network's nodes would.
use serde::{Deserialize, Serialize};

use crate::network::{Detail, Network, Op, Status};
use crate::types::{Msisdn, MB};

/// SplitMix64: small, fast, and the same sequence on every platform and every version.
#[derive(Clone, Debug)]
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Self(seed)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in `low..high`.
    pub fn range(&mut self, low: u64, high: u64) -> u64 {
        low + self.next_u64() % (high - low).max(1)
    }

    /// True with probability `per_million` / 1,000,000.
    pub fn chance(&mut self, per_million: u64) -> bool {
        self.next_u64() % 1_000_000 < per_million
    }
}

/// Per-subscriber, per-second probabilities, in parts per million.
const DATA_PPM: u64 = 50_000;
const CALL_PPM: u64 = 4_000;
const SMS_PPM: u64 = 5_000;
const TOP_UP_PPM: u64 = 20_000;
const BUNDLE_PPM: u64 = 2_000;
const ATTACH_FLIP_PPM: u64 = 1_000;

const TEXTS: [&str; 8] = [
    "On my way",
    "Call me when you're free",
    "Did you see the match?",
    "Abeg send the address",
    "Happy birthday! 🎉",
    "Meeting moved to 3pm",
    "I don land",
    "Thanks, received with gratitude",
];

/// What one tick did.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TickReport {
    pub data_sessions: u32,
    pub calls_started: u32,
    pub calls_ended: u32,
    pub sms_sent: u32,
    pub sms_delivered: u32,
    pub top_ups: u32,
    pub bundles_bought: u32,
    pub attach_changes: u32,
    pub refused: u32,
}

#[derive(Clone, Debug)]
struct Call {
    session_id: String,
    msisdn: Msisdn,
    ends_at: u64,
    duration: u64,
}

/// Generates traffic for every active subscriber. Two simulators with the same seed, run against
/// the same network, produce the same ledger.
#[derive(Clone, Debug)]
pub struct Simulator {
    rng: Rng,
    seed: u64,
    counter: u64,
    calls: Vec<Call>,
}

impl Simulator {
    pub fn new(seed: u64) -> Self {
        Self { rng: Rng::new(seed), seed, counter: 0, calls: Vec::new() }
    }

    fn next_id(&mut self, kind: &str) -> String {
        self.counter += 1;
        format!("sim{}:{kind}:{}", self.seed, self.counter)
    }

    /// Simulates `seconds` seconds of traffic ending at `now`.
    pub fn tick(&mut self, net: &mut Network, now: u64, seconds: u64) -> TickReport {
        let mut report = TickReport::default();
        let everyone: Vec<Msisdn> = net.subscribers().map(|s| s.msisdn.clone()).collect();
        let active: Vec<Msisdn> =
            net.subscribers().filter(|s| s.status == Status::Active).map(|s| s.msisdn.clone()).collect();
        for _ in 0..seconds {
            for msisdn in &active {
                self.subscriber_second(net, msisdn, &everyone, now, &mut report);
            }
        }
        let (ended, ongoing): (Vec<Call>, Vec<Call>) =
            std::mem::take(&mut self.calls).into_iter().partition(|c| c.ends_at <= now);
        self.calls = ongoing;
        for call in ended {
            let id = format!("{}:end", call.session_id);
            let _ = call.msisdn;
            match net.apply(&id, Op::VoiceEnd { session_id: call.session_id, used_seconds: call.duration }, now) {
                Ok(_) => report.calls_ended += 1,
                Err(_) => report.refused += 1,
            }
        }
        report.sms_delivered = net.deliver_sms(now).delivered;
        report
    }

    fn subscriber_second(
        &mut self,
        net: &mut Network,
        msisdn: &Msisdn,
        everyone: &[Msisdn],
        now: u64,
        report: &mut TickReport,
    ) {
        let count = |r: Result<_, _>, ok: &mut u32, refused: &mut u32| match r {
            Ok(_) => *ok += 1,
            Err(_) => *refused += 1,
        };
        if self.rng.chance(DATA_PPM) {
            // Mostly small fetches, now and then a video.
            let bytes =
                if self.rng.chance(100_000) { self.rng.range(5 * MB, 60 * MB) } else { self.rng.range(20_000, 3 * MB) };
            let id = self.next_id("data");
            count(
                net.apply(&id, Op::DataUsage { msisdn: msisdn.clone(), bytes }, now),
                &mut report.data_sessions,
                &mut report.refused,
            );
        }
        let on_call = self.calls.iter().any(|c| c.msisdn == *msisdn);
        if !on_call && self.rng.chance(CALL_PPM) {
            let callee = &everyone[self.rng.range(0, everyone.len() as u64) as usize];
            let id = self.next_id("call");
            match net.apply(&id, Op::VoiceStart { msisdn: msisdn.clone(), callee: callee.to_string() }, now) {
                Ok(out) => {
                    let Detail::VoiceGranted { granted_seconds, .. } = out.detail else {
                        unreachable!("a voice grant")
                    };
                    let duration = self.rng.range(5, 240);
                    let ends_at = now + duration.min(granted_seconds) * 1000;
                    self.calls.push(Call { session_id: id, msisdn: msisdn.clone(), ends_at, duration });
                    report.calls_started += 1;
                }
                Err(_) => report.refused += 1,
            }
        }
        if self.rng.chance(SMS_PPM) {
            let to = everyone[self.rng.range(0, everyone.len() as u64) as usize].clone();
            if to != *msisdn {
                let text = TEXTS[self.rng.range(0, TEXTS.len() as u64) as usize].to_owned();
                let id = self.next_id("sms");
                count(
                    net.apply(&id, Op::SmsSubmit { from: msisdn.clone(), to, text }, now),
                    &mut report.sms_sent,
                    &mut report.refused,
                );
            }
        }
        let balance = net.balance(msisdn, now).ok();
        if balance.as_ref().is_some_and(|b| b.available < 20_000) && self.rng.chance(TOP_UP_PPM) {
            let amount = self.rng.range(1, 21) * 10_000;
            let id = self.next_id("topup");
            count(
                net.apply(&id, Op::TopUp { msisdn: msisdn.clone(), amount }, now),
                &mut report.top_ups,
                &mut report.refused,
            );
        }
        if balance.as_ref().is_some_and(|b| b.data_bytes == 0) && self.rng.chance(BUNDLE_PPM) {
            let bundles = net.catalog().bundles();
            let bundle_id = bundles[self.rng.range(0, bundles.len() as u64) as usize].id.clone();
            let id = self.next_id("bundle");
            count(
                net.apply(&id, Op::BuyBundle { msisdn: msisdn.clone(), bundle_id }, now),
                &mut report.bundles_bought,
                &mut report.refused,
            );
        }
        if self.rng.chance(ATTACH_FLIP_PPM) {
            let attached = net.subscriber(msisdn).is_some_and(|s| s.attached);
            if net.set_attached(msisdn, !attached, now).is_ok() {
                report.attach_changes += 1;
            }
        }
    }
}

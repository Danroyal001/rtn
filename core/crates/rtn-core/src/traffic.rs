//! Per-second traffic counters for the live view.
use std::collections::VecDeque;

use serde::{Deserialize, Serialize};

use crate::network::{Network, Status};
use crate::types::Units;

/// Seconds of history kept, and seconds shown in a [`TrafficView`].
const KEEP_SECONDS: u64 = 300;
const SERIES_SECONDS: u64 = 60;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrafficCounters {
    pub data_bytes: u64,
    pub voice_seconds: u64,
    pub sms: u64,
    pub ussd: u64,
    /// Charging operations applied.
    pub charges: u64,
    pub revenue: Units,
    /// Charging operations refused.
    pub failures: u64,
}

impl TrafficCounters {
    fn add(&mut self, other: &Self) {
        self.data_bytes += other.data_bytes;
        self.voice_seconds += other.voice_seconds;
        self.sms += other.sms;
        self.ussd += other.ussd;
        self.charges += other.charges;
        self.revenue += other.revenue;
        self.failures += other.failures;
    }
}

#[derive(Clone, Debug, Default)]
pub(crate) struct Traffic {
    buckets: VecDeque<(u64, TrafficCounters)>,
    totals: TrafficCounters,
}

impl Traffic {
    pub(crate) fn record(&mut self, now_ms: u64, change: impl FnOnce(&mut TrafficCounters)) {
        let second = now_ms / 1000;
        let mut delta = TrafficCounters::default();
        change(&mut delta);
        self.totals.add(&delta);
        match self.buckets.back_mut() {
            Some((s, counters)) if *s == second => counters.add(&delta),
            Some((s, _)) if *s > second => {
                // Late event: count it in the bucket it belongs to, if we still have one.
                if let Some((_, counters)) = self.buckets.iter_mut().find(|(s, _)| *s == second) {
                    counters.add(&delta);
                }
            }
            _ => {
                self.buckets.push_back((second, delta));
                while self.buckets.front().is_some_and(|(s, _)| *s + KEEP_SECONDS <= second) {
                    self.buckets.pop_front();
                }
            }
        }
    }
}

/// The live view: totals since the process started, the last minute second by second, and what
/// is happening right now.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrafficView {
    pub at: u64,
    pub totals: TrafficCounters,
    /// Unix second of `series[0]`.
    pub series_from: u64,
    /// One entry per second, oldest first, ending at the second of `at`.
    pub series: Vec<TrafficCounters>,
    pub subscribers: usize,
    pub active_subscribers: usize,
    pub attached: usize,
    pub active_calls: usize,
    pub queued_sms: usize,
    pub ussd_sessions: usize,
}

impl Network {
    pub fn traffic(&self, now: u64) -> TrafficView {
        let last = now / 1000;
        let first = last + 1 - SERIES_SECONDS;
        let mut series = vec![TrafficCounters::default(); SERIES_SECONDS as usize];
        for (second, counters) in &self.traffic.buckets {
            if (first..=last).contains(second) {
                series[(second - first) as usize] = *counters;
            }
        }
        TrafficView {
            at: now,
            totals: self.traffic.totals,
            series_from: first,
            series,
            subscribers: self.subscribers.len(),
            active_subscribers: self.subscribers.values().filter(|s| s.status == Status::Active).count(),
            attached: self.subscribers.values().filter(|s| s.attached).count(),
            active_calls: self.calls.len(),
            queued_sms: self.smsc.queued_len(),
            ussd_sessions: self.ussd_sessions.len(),
        }
    }
}

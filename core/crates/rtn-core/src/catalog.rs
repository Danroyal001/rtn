use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::types::{Units, MB};
use crate::RtnError;

/// How a subscriber is charged for pay-as-you-go use.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RatingPlan {
    pub id: String,
    pub name: String,
    /// Units per second of voice, billed per second.
    pub voice_per_second: Units,
    /// Units per SMS segment.
    pub sms_per_segment: Units,
    /// Units per MB of data outside a bundle, billed per byte, rounded up.
    pub data_per_mb: Units,
}

/// A data bundle bought from airtime.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Bundle {
    pub id: String,
    pub name: String,
    pub data_bytes: u64,
    pub price: Units,
    pub validity_days: u32,
    /// A line shown with the bundle when it is on offer, such as "Best value".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub offer: Option<String>,
}

/// Data bought with loyalty points.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reward {
    pub id: String,
    pub name: String,
    pub points: u64,
    pub data_bytes: u64,
    pub validity_days: u32,
}

/// Rating plans, the bundle catalogue and the loyalty rewards.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Catalog {
    plans: BTreeMap<String, RatingPlan>,
    bundles: Vec<Bundle>,
    pub default_plan: String,
    #[serde(default = "default_rewards")]
    rewards: Vec<Reward>,
}

fn default_rewards() -> Vec<Reward> {
    let reward = |id: &str, name: &str, points: u64, mb: u64, days: u32| Reward {
        id: id.into(),
        name: name.into(),
        points,
        data_bytes: mb * MB,
        validity_days: days,
    };
    vec![
        reward("points-250mb", "Bonus 250MB", 100, 250, 3),
        reward("points-1gb", "Bonus 1GB", 350, 1024, 7),
        reward("points-3gb", "Bonus 3GB", 900, 3 * 1024, 14),
    ]
}

impl Default for Catalog {
    fn default() -> Self {
        let plans = [
            RatingPlan {
                id: "pulse".into(),
                name: "Pulse".into(),
                voice_per_second: 20,
                sms_per_segment: 400,
                data_per_mb: 500,
            },
            RatingPlan {
                id: "steady".into(),
                name: "Steady".into(),
                voice_per_second: 15,
                sms_per_segment: 500,
                data_per_mb: 400,
            },
        ];
        let bundle = |id: &str, name: &str, mb: u64, naira: u64, days: u32| Bundle {
            id: id.into(),
            name: name.into(),
            data_bytes: mb * MB,
            price: naira * 100,
            validity_days: days,
            offer: None,
        };
        let offer = |mut b: Bundle, text: &str| {
            b.offer = Some(text.into());
            b
        };
        Self {
            plans: plans.into_iter().map(|p| (p.id.clone(), p)).collect(),
            bundles: vec![
                bundle("daily-100mb", "Daily 100MB", 100, 100, 1),
                bundle("weekly-1gb", "Weekly 1GB", 1024, 500, 7),
                bundle("monthly-3gb", "Monthly 3GB", 3 * 1024, 1_500, 30),
                offer(bundle("monthly-10gb", "Monthly 10GB", 10 * 1024, 3_500, 30), "Best value"),
                offer(bundle("weekend-2gb", "Weekend 2GB", 2 * 1024, 400, 3), "Friday to Sunday"),
                bundle("monthly-25gb", "Monthly 25GB", 25 * 1024, 7_500, 30),
            ],
            default_plan: "pulse".into(),
            rewards: default_rewards(),
        }
    }
}

fn check_id(id: &str) -> Result<(), RtnError> {
    let ok = !id.is_empty()
        && id.len() <= 40
        && id.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-');
    if ok {
        Ok(())
    } else {
        Err(RtnError::InvalidRequest { reason: "an id is 1 to 40 lowercase letters, digits or dashes".into() })
    }
}

impl Catalog {
    pub fn plan(&self, id: &str) -> Option<&RatingPlan> {
        self.plans.get(id)
    }

    pub fn plans(&self) -> impl Iterator<Item = &RatingPlan> {
        self.plans.values()
    }

    pub fn bundle(&self, id: &str) -> Option<&Bundle> {
        self.bundles.iter().find(|b| b.id == id)
    }

    pub fn bundles(&self) -> &[Bundle] {
        &self.bundles
    }

    pub fn rewards(&self) -> &[Reward] {
        &self.rewards
    }

    pub fn reward(&self, id: &str) -> Option<&Reward> {
        self.rewards.iter().find(|r| r.id == id)
    }

    /// Adds a plan or replaces the one with its id. A rate change applies to the next charge;
    /// a call in progress keeps the rate it was granted at.
    pub fn upsert_plan(&mut self, plan: RatingPlan) -> Result<(), RtnError> {
        check_id(&plan.id)?;
        if plan.name.trim().is_empty() {
            return Err(RtnError::InvalidRequest { reason: "a plan needs a name".into() });
        }
        if plan.voice_per_second == 0 {
            return Err(RtnError::InvalidAmount { reason: "voice cannot be free".into() });
        }
        self.plans.insert(plan.id.clone(), plan);
        Ok(())
    }

    /// Adds a bundle or replaces the one with its id. Bundles already bought keep what they were
    /// sold with.
    pub fn upsert_bundle(&mut self, bundle: Bundle) -> Result<(), RtnError> {
        check_id(&bundle.id)?;
        if bundle.name.trim().is_empty() {
            return Err(RtnError::InvalidRequest { reason: "a bundle needs a name".into() });
        }
        if bundle.data_bytes == 0 || bundle.price == 0 || bundle.validity_days == 0 {
            return Err(RtnError::InvalidAmount { reason: "a bundle needs data, a price and a validity".into() });
        }
        match self.bundles.iter_mut().find(|b| b.id == bundle.id) {
            Some(existing) => *existing = bundle,
            None => self.bundles.push(bundle),
        }
        Ok(())
    }
}

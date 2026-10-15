//! Demo subscribers.
use serde::Serialize;

use crate::metering::Rng;
use crate::network::{Network, NewSubscriber, Op};
use crate::types::Msisdn;
use crate::RtnError;

const FIRST: [&str; 20] = [
    "Adaeze", "Tunde", "Ngozi", "Emeka", "Funmi", "Ibrahim", "Chioma", "Segun", "Aisha", "Uche", "Bisi", "Musa",
    "Kemi", "Obinna", "Zainab", "Femi", "Amaka", "Yusuf", "Ifeoma", "Dayo",
];
const LAST: [&str; 12] = [
    "Okafor", "Adeyemi", "Bello", "Eze", "Ogunleye", "Abubakar", "Nwosu", "Balogun", "Okon", "Effiong", "Danjuma",
    "Udo",
];

/// The first number RTN gives out: its own test range, which no real operator uses.
pub const FIRST_NUMBER: u64 = 2_349_990_000_001;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Seeded {
    pub msisdn: Msisdn,
    pub name: String,
    pub pin: String,
}

/// Adds `count` subscribers on the next free numbers, tops each up, gives some a bundle, and
/// detaches a few. The first five get PIN 1234 so a demo can sign in as them.
pub fn populate(net: &mut Network, count: u32, seed: u64, now: u64) -> Result<Vec<Seeded>, RtnError> {
    let mut rng = Rng::new(seed);
    let mut seeded = Vec::with_capacity(count as usize);
    let mut number = FIRST_NUMBER;
    let plans: Vec<String> = net.catalog().plans().map(|p| p.id.clone()).collect();
    while seeded.len() < count as usize {
        let msisdn = Msisdn::parse(&number.to_string())?;
        number += 1;
        if net.subscriber(&msisdn).is_some() {
            continue;
        }
        let name = format!(
            "{} {}",
            FIRST[rng.range(0, FIRST.len() as u64) as usize],
            LAST[rng.range(0, LAST.len() as u64) as usize]
        );
        let pin = if seeded.len() < 5 { "1234".to_owned() } else { format!("{:04}", rng.range(0, 10_000)) };
        let plan_id = plans[seeded.len() % plans.len()].clone();
        net.add_subscriber(
            NewSubscriber {
                msisdn: msisdn.clone(),
                imsi: None,
                name: name.clone(),
                plan_id: Some(plan_id),
                pin: pin.clone(),
            },
            now,
        )?;
        let amount = rng.range(5, 51) * 10_000;
        net.apply(&format!("seed:{msisdn}:topup"), Op::TopUp { msisdn: msisdn.clone(), amount, via: None }, now)?;
        if rng.chance(330_000) {
            let _ = net.apply(
                &format!("seed:{msisdn}:bundle"),
                Op::BuyBundle { msisdn: msisdn.clone(), bundle_id: "weekly-1gb".into(), beneficiary: None },
                now,
            );
        }
        if rng.chance(100_000) {
            net.set_attached(&msisdn, false, now)?;
        }
        seeded.push(Seeded { msisdn, name, pin });
    }
    Ok(seeded)
}

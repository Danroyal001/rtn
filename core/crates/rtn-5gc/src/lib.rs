//! RTN's bridge into a 5G core.
//!
//! RTN's registry already issues IMSIs under the test PLMN 999/70. This crate
//! gives each line the rest of what a SIM and the core's authentication centre
//! share (the key `K` and `OPc`, [`sim`]), writes RTN's subscribers into the
//! subscriber database Open5GS's UDR reads ([`open5gs`]), and writes the
//! matching UERANSIM UE configuration ([`ueransim`]), so a simulated phone
//! attaches to the 5G core as an RTN line.
//!
//! Open5GS's 5G core has no charging interface to plug into (its SMF speaks
//! Diameter Gy only for 4G sessions, and it has no CHF); see docs/M3-SPIKE.md.

pub mod milenage;
pub mod open5gs;
pub mod sim;
pub mod ueransim;

pub use open5gs::{plan, Change, CoreSubscriber, Open5gs};
pub use sim::{SimFactory, SimKeys};

/// What can go wrong talking to the core.
#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("subscriber database: {0}")]
    Database(#[from] mongodb::error::Error),
    #[error("invalid key material: {0}")]
    Key(String),
}

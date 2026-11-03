//! A line's SIM keys: the subscriber key `K` and `OPc`, which the SIM and the
//! core's authentication centre share and never send over the air.
//!
//! A real operator gets `K` from the SIM vendor's encrypted output file and
//! keeps it in an HSM. On RTN's test network a [`SimFactory`] derives `K` from
//! an operator secret and the IMSI (HMAC-SHA-256), so the bridge can provision
//! the core and write the matching UE configuration without storing keys
//! anywhere. `OPc` is derived from `K` and the network's `OP` as MILENAGE says.

use hmac::{Hmac, Mac};
use rtn_core::Imsi;
use sha2::Sha256;

use crate::{milenage, BridgeError};

/// The keys one SIM shares with the core.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SimKeys {
    pub k: [u8; 16],
    pub opc: [u8; 16],
}

impl SimKeys {
    /// `K` as the core and UERANSIM write it: 32 upper-case hex digits.
    pub fn k_hex(&self) -> String {
        hex::encode_upper(self.k)
    }

    /// `OPc` as 32 upper-case hex digits.
    pub fn opc_hex(&self) -> String {
        hex::encode_upper(self.opc)
    }
}

/// Makes the SIM keys for RTN's lines from an operator secret and `OP`.
#[derive(Clone)]
pub struct SimFactory {
    secret: Vec<u8>,
    op: [u8; 16],
}

impl SimFactory {
    /// The shortest operator secret accepted, in bytes.
    pub const MIN_SECRET: usize = 16;

    pub fn new(secret: &[u8], op: [u8; 16]) -> Result<Self, BridgeError> {
        if secret.len() < Self::MIN_SECRET {
            return Err(BridgeError::Key(format!(
                "the operator secret must be at least {} bytes",
                Self::MIN_SECRET
            )));
        }
        Ok(Self { secret: secret.to_vec(), op })
    }

    /// Reads the secret and `OP` as hex, the way they sit in an environment file.
    pub fn from_hex(secret_hex: &str, op_hex: &str) -> Result<Self, BridgeError> {
        let secret = hex::decode(secret_hex.trim())
            .map_err(|error| BridgeError::Key(format!("the operator secret is not hex: {error}")))?;
        let op: [u8; 16] = hex::decode(op_hex.trim())
            .map_err(|error| BridgeError::Key(format!("OP is not hex: {error}")))?
            .try_into()
            .map_err(|_| BridgeError::Key("OP must be 16 bytes (32 hex digits)".into()))?;
        Self::new(&secret, op)
    }

    /// The keys of the SIM with this IMSI.
    pub fn keys(&self, imsi: &Imsi) -> SimKeys {
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.secret).expect("HMAC takes a key of any length");
        mac.update(b"rtn-sim-k:");
        mac.update(imsi.as_str().as_bytes());
        let digest = mac.finalize().into_bytes();
        let mut k = [0u8; 16];
        k.copy_from_slice(&digest[..16]);
        SimKeys { k, opc: milenage::opc(&k, &self.op) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: &[u8] = b"rtn test network operator secret";
    const OP: [u8; 16] = *b"RTN-OP-TEST-ONLY";

    #[test]
    fn the_same_sim_always_gets_the_same_keys() {
        let sims = SimFactory::new(SECRET, OP).unwrap();
        assert_eq!(sims.keys(&Imsi::issue(1)), sims.keys(&Imsi::issue(1)));
    }

    #[test]
    fn every_sim_gets_its_own_key() {
        let sims = SimFactory::new(SECRET, OP).unwrap();
        let keys: std::collections::HashSet<[u8; 16]> = (1..=500).map(|n| sims.keys(&Imsi::issue(n)).k).collect();
        assert_eq!(keys.len(), 500);
    }

    #[test]
    fn opc_is_derived_from_k_and_op_as_milenage_says() {
        let sims = SimFactory::new(SECRET, OP).unwrap();
        let keys = sims.keys(&Imsi::issue(7));
        assert_eq!(keys.opc, milenage::opc(&keys.k, &OP));
    }

    #[test]
    fn another_operator_secret_gives_other_keys() {
        let ours = SimFactory::new(SECRET, OP).unwrap();
        let theirs = SimFactory::new(b"a different secret, same length", OP).unwrap();
        assert_ne!(ours.keys(&Imsi::issue(1)).k, theirs.keys(&Imsi::issue(1)).k);
    }

    #[test]
    fn a_short_secret_is_refused() {
        assert!(SimFactory::new(b"too short", OP).is_err());
    }

    #[test]
    fn reads_hex_and_writes_upper_case_hex() {
        let sims = SimFactory::from_hex(&hex::encode(SECRET), &hex::encode(OP)).unwrap();
        let keys = sims.keys(&Imsi::issue(1));
        assert_eq!(keys, SimFactory::new(SECRET, OP).unwrap().keys(&Imsi::issue(1)));
        assert_eq!(keys.k_hex().len(), 32);
        assert_eq!(keys.k_hex(), keys.k_hex().to_uppercase());
        assert!(SimFactory::from_hex("not hex", &hex::encode(OP)).is_err());
        assert!(SimFactory::from_hex(&hex::encode(SECRET), "abcd").is_err());
    }
}

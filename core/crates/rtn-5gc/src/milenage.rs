//! The one piece of 3GPP MILENAGE (TS 35.206) the provisioning side needs:
//! deriving a SIM's `OPc` from its key `K` and the operator's `OP`.

/// `OPc = AES-128(K, OP) XOR OP` (TS 35.206, section 4.1).
pub fn opc(k: &[u8; 16], op: &[u8; 16]) -> [u8; 16] {
    use aes::cipher::{BlockEncrypt, KeyInit};
    let cipher = aes::Aes128::new(k.into());
    let mut block = aes::Block::from(*op);
    cipher.encrypt_block(&mut block);
    let mut out = [0u8; 16];
    for (index, byte) in out.iter_mut().enumerate() {
        *byte = block[index] ^ op[index];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bytes(hex_text: &str) -> [u8; 16] {
        hex::decode(hex_text).unwrap().try_into().unwrap()
    }

    // TS 35.208 (MILENAGE conformance), test sets 1, 2 and 6.
    #[test]
    fn matches_the_3gpp_conformance_test_sets() {
        let sets = [
            ("465b5ce8b199b49faa5f0a2ee238a6bc", "cdc202d5123e20f62b6d676ac72cb318", "cd63cb71954a9f4e48a5994e37a02baf"),
            ("0396eb317b6d1c36f19c1c84cd6ffd16", "ff53bade17df5d4e793073ce9d7579fa", "53c15671c60a4b731c55b4a441c0bde2"),
            ("6c38a116ac280c454f59332ee35c8c4f", "1ba00a1a7c6700ac8c3ff3e96ad08725", "3803ef5363b947c6aaa225e58fae3934"),
        ];
        for (k, op, expected) in sets {
            assert_eq!(opc(&bytes(k), &bytes(op)), bytes(expected), "K {k}");
        }
    }
}

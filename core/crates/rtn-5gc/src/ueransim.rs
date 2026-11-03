//! UERANSIM UE configuration for an RTN line.

use rtn_core::Imsi;

use crate::SimKeys;

/// The `nr-ue` configuration that makes a simulated phone the SIM with `imsi`
/// and `keys`, on RTN's test PLMN (999/70), searching for the gNB at `gnb_ip`
/// and opening one IPv4 PDU session to the `internet` DNN on slice SST 1.
pub fn ue_config(imsi: &Imsi, keys: &SimKeys, gnb_ip: &str) -> String {
    let k = keys.k_hex();
    let opc = keys.opc_hex();
    format!(
        "# UERANSIM UE for the RTN line with IMSI {imsi}. Written by `rtn 5g ue-config`.
supi: 'imsi-{imsi}'
mcc: '999'
mnc: '70'
key: '{k}'
op: '{opc}'
opType: 'OPC'
amf: '8000'
imei: '356938035643803'
imeiSv: '4370816125816151'
gnbSearchList: ['{gnb_ip}']
uacAic: {{mps: false, mcs: false}}
uacAcc: {{normalClass: 0, class11: false, class12: false, class13: false, class14: false, class15: false}}
sessions:
  - type: 'IPv4'
    apn: 'internet'
    slice: {{sst: 1}}
configured-nssai: [{{sst: 1}}]
default-nssai: [{{sst: 1, sd: 1}}]
integrity: {{IA1: true, IA2: true, IA3: true}}
ciphering: {{EA1: true, EA2: true, EA3: true}}
integrityMaxRate: {{uplink: 'full', downlink: 'full'}}
"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_the_sim_its_keys_and_the_gnb() {
        let keys = SimKeys { k: [0x11; 16], opc: [0xab; 16] };
        let yaml = ue_config(&Imsi::issue(42), &keys, "10.99.0.10");
        assert!(yaml.contains("supi: 'imsi-999700000000042'"), "{yaml}");
        assert!(yaml.contains("mcc: '999'"));
        assert!(yaml.contains("mnc: '70'"));
        assert!(yaml.contains("key: '11111111111111111111111111111111'"));
        assert!(yaml.contains("op: 'ABABABABABABABABABABABABABABABAB'"));
        assert!(yaml.contains("opType: 'OPC'"));
        assert!(yaml.contains("gnbSearchList: ['10.99.0.10']"));
        assert!(yaml.contains("apn: 'internet'"));
    }
}

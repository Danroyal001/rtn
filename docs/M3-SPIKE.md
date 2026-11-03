# Milestone 3 spike: a simulated phone on a real 5G core

Goal: move RTN from simulated traffic to real 4G/5G-style sessions without radios. Bring up an
open-source 5G core with a simulated gNB and UE, find out from the running system and its source
where charging and subscriber data plug in, and build the first RTN network function in Rust at
the smallest real integration point.

Everything here was run on 2026-11-03 on an Ubuntu VPS (kernel 7.0, Docker 29.1.3). Nothing below
is from memory: each fact names the file, log line or command it came from.

## What runs

| Part | Version | Image |
|---|---|---|
| Open5GS 5G core (NRF, SCP, AMF, SMF, UPF, AUSF, UDM, UDR, PCF, NSSF, BSF) | v2.8.0 | `gradiant/open5gs:2.8.0` |
| UERANSIM gNB and UE | v3.3.0 | `gradiant/ueransim:3.3.0` |
| MongoDB (the core's subscriber database) | 7.0 | `mongo:7.0` |
| free5GC control plane (for the charging interface) | v4.3.0 | `free5gc/{nrf,amf,smf,ausf,udm,udr,pcf,nssf,chf,webui}:v4.3.0` |

Source read alongside: Open5GS `main` at `cfd25ad2`, free5GC `smf` at `79962afc` and `chf` at
`163d381d` (all 2026-10-28 to 2026-11-03).

The test network is RTN's own: PLMN **999/70** (MCC 999 is ITU's code for private networks),
TAC 1, slice SST 1, DNN `internet`, UE pool `10.45.0.0/16`. RTN's registry already issues IMSIs
under this PLMN (`Imsi::issue(7)` is `999700000000007`).

## 1. A UE registers, opens a PDU session and pings through the UPF

`net/5gc/` holds the configs and scripts:

- `open5gs/*.yaml`: Open5GS's own sample configs (`configs/open5gs/*.yaml.in`) with the paths
  filled in and file logging off. They use loopback addresses (AMF `127.0.0.5`, SMF `127.0.0.4`,
  UPF `127.0.0.7`, NRF `127.0.0.10`, SCP `127.0.0.200`) and already name PLMN 999/70.
- `up.sh`: MongoDB, the core (one container, `open5gs/run-core.sh` starts the NFs in order) and the
  gNB share one network namespace on a private bridge (`10.99.0.10`), so the loopback addresses
  work unchanged. MongoDB is published on `127.0.0.1:27117`.
- `ue.sh <name> <ue.yaml>`: a UE in **its own** network namespace on the bridge, so its packets
  really cross the radio-link simulation, GTP-U (N3) and the UPF. (A UE in the core's namespace
  could reach `10.45.0.1` through the local kernel and prove nothing.)
- `down.sh`: removes every container and the bridge.

One gotcha: the image sets `DB_URI=mongodb://mongo/open5gs`, which overrides `db_uri` in the
configs; `up.sh` passes `-e DB_URI=mongodb://127.0.0.1/open5gs`.

```text
$ net/5gc/up.sh
rtn5g is up: Open5GS core, gNB (NG Setup done), MongoDB on 127.0.0.1:27117

core log:
[pfcp] INFO: pfcp_server() [127.0.0.7]:8805
[upf] INFO: PFCP associated [127.0.0.4]:8805
[smf] INFO: PFCP associated [127.0.0.7]:8805
[sctp] INFO: AMF initialize...done

$ net/5gc/ue.sh test ue-test.yaml          # a hand-written subscriber, first run
[nas] [info] Initial Registration is successful
[nas] [info] PDU Session establishment is successful PSI[1]
[app] [info] Connection setup for PDU session[1] is successful, TUN interface[uesimtun0, 10.45.0.2] is up.

$ docker exec rtn5g-ue-test ping -c 3 -I uesimtun0 10.45.0.1
3 packets transmitted, 3 received, 0% packet loss
$ docker exec rtn5g-ue-test ping -c 3 -I uesimtun0 8.8.8.8      # N6, through the UPF's NAT
3 packets transmitted, 3 received, 0% packet loss
```

## 2. Where charging and subscriber data plug in

### Open5GS

- **Subscriber and auth data: MongoDB.** The UDR (5G) and HSS (4G) read database `open5gs`,
  collection `subscribers` (`lib/dbi/ogs-mongoc.c:169`, `lib/dbi/subscription.c`), one document per
  IMSI with `security.k`, `security.opc` (or `op`), `security.amf`, `msisdn[]` and `slice[].session[]`.
  The shape is the one `misc/db/open5gs-dbctl add` writes. No Nudr/Nudm hook is needed: whatever
  writes that document provisions the subscriber.
- **Charging: Diameter Gy, 4G only. No CHF.** The SMF has a Gy client (`src/smf/gy-path.c`,
  `gy-handler.c`, application id 4, `lib/diameter/gy/message.h:34`). It sends a CCR-Initial only
  from `send_ccr_init_req_gx_gy()` (`src/smf/gsm-sm.c:112`), which is called only for GTPv1 Create
  PDP Context (Gn) and GTPv2 Create Session on E-UTRAN (S5-C) (`gsm-sm.c:322`, `:343`, `:555`), that
  is, for 4G/3G sessions. A 5G PDU session (the SBI path through
  `smf_gsm_state_wait_5gc_sm_policy_association`) never opens a Gy session. Open5GS has no CHF
  (`src/` has amf, ausf, bsf, eir, hss, mme, nrf, nssf, pcf, pcrf, scp, sepp, sgwc, sgwu, smf, udm,
  udr, upf). `smf.ctf.enabled` (`auto|yes|no`, `src/smf/context.c:52`) only matters for 4G.
- So on Open5GS's 5G core there is **no interface where an external OCS can grant data quota**.
  A Rust Gy server would charge 4G sessions only, and UERANSIM is 5G-only.

### free5GC

- **Charging: Nchf_ConvergedCharging over HTTP/2 (SBI), selected through the NRF.** The SMF finds a
  CHF with an NRF discovery for NF type `CHF` (`internal/sbi/consumer/nrf_service.go:463`,
  `CHFSelection`), takes the first instance's `nchf-convergedcharging` service `apiPrefix`, and
  calls `POST /nchf-convergedcharging/v3/chargingdata` (create), `…/{ref}/update` and
  `…/{ref}/release` (`internal/sbi/consumer/chf_service.go`; CHF routes in
  `chf/internal/sbi/api_convergedcharging.go:36-46`). The request carries the SUPI, the GPSI
  (MSISDN), the PDU session and slice, and `multipleUnitUsage`; the answer's `multipleUnitInformation`
  grants `grantedUnit.totalVolume` per rating group, with triggers (quota threshold, quota
  exhausted, validity time). Online vs offline charging per slice/flow comes from the subscriber's
  policy data (`policyData.ues.chargingData`, written by the webconsole) through the PCF; the SMF
  binds a PFCP URR to each rating group and the UPF's usage reports drive the updates
  (`internal/sbi/processor/charging_trigger.go`).
- Inside free5GC's own CHF, quota and rating are Diameter again: `abmfDiameter` (port 3868) and
  `rfDiameter` (3869) in `chfcfg.yaml`.
- **Subscriber data:** MongoDB database `free5gc`, about a dozen collections
  (`subscriptionData.authenticationData.authenticationSubscription`, `subscriptionData.provisionedData.{am,sm,smfSelectionSubscription}Data`,
  `policyData.ues.{am,sm,charging}Data`, …), written through the webconsole's
  `POST /api/subscriber/{ueId}/{plmnId}`.

Seen running (`net/5gc/free5gc/up.sh`: free5GC control plane, Open5GS UPF, UERANSIM gNB, an
online-charged subscriber posted to the webconsole):

```text
UE:   [nas] [info] Initial Registration is successful
SMF:  CHF Selection for SMContext SUPI[imsi-999700000000001] PDUSessionID[1]
SMF:  Send Charging Data Request[Init] successfully
CHF:  | 201 | 10.98.0.12 | POST | /nchf-convergedcharging/v3/chargingdata |
SMF:  [AddChargingRules] ChargingInfo bind URR[7] -> RG=1 ... method=ONLINE_CHARGING
SMF:  PFCP Session Establishment failed: ... PFCP request to 10.98.0.20:8805 timed out
UPF:  [core] WARNING: Unknown TLV type [109]
UPF:  [core] ERROR: Invalid TLV length 1. It should be 2
UPF:  [pfcp] ERROR: ogs_pfcp_parse_msg: Expectation `rv == OGS_OK' failed.
UE:   [nas] [error] PDU Session Establishment Reject received [NETWORK_FAILURE]
```

So the charging interface is verified from a running SMF, but **this mix has no data plane**:
Open5GS 2.8.0's UPF cannot parse free5GC v4.3.0's PFCP Session Establishment Request (it fails the
same way with no charging data at all, so it is not the URRs; IE 109 is QER ID), and free5GC's own
UPF needs the out-of-tree `gtp5g` kernel module, which was not loaded on a shared production
machine. free5GC's SMF also opened a charging session on every attempt and never released it after
the N4 failure.

## 3. The first RTN network function: `rtn-5gc`, a provisioning bridge

Because Open5GS's 5G core has no pluggable charging and the free5GC route has no working user plane
here, the smallest real integration point is the subscriber database. `core/crates/rtn-5gc`:

- `milenage::opc`: `OPc = AES-128(K, OP) XOR OP` (TS 35.206), checked against TS 35.208 test sets 1, 2
  and 6.
- `sim::SimFactory`: each line's `K` is HMAC-SHA-256(operator secret, IMSI) truncated to 128 bits,
  and `OPc` comes from `K` and the network's `OP`. On a test network this means no key is stored
  anywhere; a real operator takes `K` from the SIM vendor's output file and keeps it in an HSM.
- `open5gs::plan`: what to change so the core holds exactly RTN's active lines. Active lines the
  core lacks, or holds with another number or other keys, are written; barred lines are removed
  (their SIMs can no longer attach); IMSIs under 99970 that RTN no longer has are removed; IMSIs
  outside RTN's PLMN are left alone. `Open5gs::sync` applies it to MongoDB.
- `ueransim::ue_config`: the matching UERANSIM UE file.
- CLI: `rtn 5g sync` (reads every line from a running `rtn serve`, then syncs the core) and
  `rtn 5g ue-config <msisdn>`. The SIM secret and OP come from `RTN_SIM_SECRET` and `RTN_SIM_OP`.

### End to end

`core/crates/rtn-5gc/tests/open5gs_attach.rs` runs against the Docker core and UERANSIM (it skips
with a message when Docker or the images are missing): it builds an RTN registry with three lines,
bars the third, syncs, checks the documents, attaches the first line's phone, pings through the UPF,
and checks that the barred line's phone is refused.

```text
$ cd core && cargo test -p rtn-5gc
test milenage::tests::matches_the_3gpp_conformance_test_sets ... ok
test open5gs::tests::the_document_has_the_shape_open5gs_writes ... ok
test open5gs::tests::writes_active_lines_the_core_lacks ... ok
test open5gs::tests::a_core_in_line_with_rtn_needs_nothing ... ok
test open5gs::tests::rewrites_a_line_with_another_number_or_other_keys ... ok
test open5gs::tests::takes_barred_lines_out ... ok
test open5gs::tests::takes_out_rtn_imsis_rtn_no_longer_has_and_leaves_others_alone ... ok
test sim::tests::... (6 tests) ... ok
test ueransim::tests::names_the_sim_its_keys_and_the_gnb ... ok
test result: ok. 14 passed; 0 failed
     Running tests/open5gs_attach.rs
test rtn_lines_attach_to_open5gs_and_a_barred_line_cannot ... ok
test result: ok. 1 passed; 0 failed; finished in 43.73s
```

The whole workspace (`cargo test --workspace`): 107 tests pass; `cargo clippy --workspace --all-targets -- -D warnings`
is clean.

The same thing by hand, with the CLI against a running `rtn serve` (secrets random for the run):

```text
$ net/5gc/up.sh
rtn5g is up: Open5GS core, gNB (NG Setup done), MongoDB on 127.0.0.1:27117
$ rtn serve --addr 127.0.0.1:18700 --seed 5 &
$ rtn 5g sync
5 RTN lines; wrote 5 to the core and removed 0.
$ rtn 5g sync   # again: nothing to do
5 RTN lines; wrote 0 to the core and removed 0.
$ rtn 5g ue-config 2349990000001 > ue-0001.yaml
$ net/5gc/ue.sh 0001 ue-0001.yaml
[app] [info] Connection setup for PDU session[1] is successful, TUN interface[uesimtun0, 10.45.0.2] is up.
$ docker exec rtn5g-ue-0001 ping -c 3 -I uesimtun0 10.45.0.1
3 packets transmitted, 3 received, 0% packet loss
$ rtn bar 2349990000002 && rtn 5g sync
5 RTN lines; wrote 0 to the core and removed 1.
$ net/5gc/ue.sh 0002 ue-0002.yaml   # the barred line
[nas] [error] Initial Registration failed [FIVEG_SERVICES_NOT_ALLOWED]

core log:
[gmm] INFO: [imsi-999700000000001] Registration complete
[smf] INFO: UE SUPI[imsi-999700000000001] DNN[internet] IPv4[10.45.0.2] IPv6[]
[dbi] INFO: [imsi-999700000000002] Cannot find IMSI in DB
[udr] WARNING: [imsi-999700000000002] Cannot find SUPI in DB
```

## 4. What is missing for charging, and the plan

Data usage does not reach RTN's ledger yet, because no core that ran here both exposes charging for
5G sessions and carries data. The way to get there, in order of cost:

1. **An RTN CHF** (`rtn-chf`): Nchf_ConvergedCharging v3 over HTTP/2 cleartext, registering itself
   with the NRF as NF type `CHF` (NFRegister and heartbeats), answering create/update/release with
   `grantedUnit.totalVolume` from RTN's OCS. `rtn-core` needs a data credit-control session (reserve
   on create, commit used units and re-reserve on update, commit and release on release, the same
   shape as voice today) so a granted quota cannot be spent twice. The SMF side to test against is
   free5GC's; its create call was seen above.
2. **A user plane that free5GC's SMF can drive:** free5GC's UPF with `gtp5g` on a machine where
   loading a kernel module is acceptable (a throwaway VM), or a UPF that speaks free5GC's PFCP
   (eUPF, eBPF/XDP, unverified here), or RTN's own UPF (below). With that, usage reports flow and
   step 1 can be tested end to end.
3. **Diameter Gy** for 4G: Open5GS's SMF already sends Gy for EPC sessions, so a Rust Gy server over
   the same credit-control session is a second front end, testable with a 4G RAN simulator
   (srsRAN 4G with ZeroMQ, unverified here).

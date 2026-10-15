# RTN core

The Rust half of RTN: one cargo workspace.

| Crate | What it is |
|---|---|
| `rtn-core` | The network: subscriber registry, rating catalogue, online charging with an idempotent ledger, USSD gateway, SMS centre with one-time sign-in codes and notifications, vouchers, loyalty points, customer care, traffic simulator. No I/O, no clock of its own. `rtn_core::node::Node` adds the journal that makes it durable. |
| `rtn-api` | The HTTP/JSON API ([docs/API.md](../docs/API.md)) over one `Node`. |
| `rtn-cli` | The `rtn` binary: `serve`, `seed`, `simulate`, and client commands. |
| `rtn-ffi` | A C ABI (`include/rtn.h`) over one `Node`, JSON in and JSON out, for in-process callers such as the MyRTN backend. |

```sh
cargo test --workspace                     # unit, integration and property tests
cargo clippy --workspace --all-targets -- -D warnings
cargo bench -p rtn-core                    # criterion benchmarks
cargo run -p rtn-cli -- serve --seed 50 --simulate --data rtn-data
```

With the server running (`RTN_ADMIN_TOKEN` set for both):

```sh
rtn subscribers --q okafor
rtn topup 2349990000001 500
rtn ussd 2349990000001 '*123#'
rtn sms 2349990000001 2349990000002 'Abeg send the address'
rtn simulate --seconds 60
rtn vouchers --count 3 --naira 500
rtn inbox 2349990000001          # sign-in codes and notifications arrive here
rtn traffic
```

## What the tests hold it to

- Every account's airtime, data and loan equal the sum of its ledger entries.
- Money is conserved: `sum(airtime) + revenue + repaid == topped_up + lent`.
- Reserved airtime never exceeds airtime, so a call in progress cannot be spent twice.
- Replaying any successful request returns the same outcome and changes nothing.
- A refused operation changes no balance.
- Loyalty points equal the sum of their ledger entries, and data moved between lines (gifts,
  sharing) is conserved.
- A node opened again on its directory has the same network, and a journal line already in the
  snapshot is never applied twice (`crates/rtn-core/tests/journal.rs`).

The first group are `proptest` properties over random sequences of top-ups, bundles (bought and
gifted), transfers, data sharing, loans, rewards, data, calls and SMS
(`crates/rtn-core/tests/properties.rs`), next to example tests for each module and HTTP tests for
every route group.

## Benchmarks

`cargo bench -p rtn-core` on a shared machine with other builds running, so read them as orders
of magnitude (measured in milestone 1):

| Benchmark | Time |
|---|---|
| Charge a data event (1,000 subscribers, ledger growing) | ~6 µs |
| Replay a request already applied | ~0.25 µs |
| Voice call: reserve, then bill per second | ~10 µs |
| Airtime transfer | ~9 µs |
| USSD: open the menu and read the balance | ~1.1 µs |
| Submit and deliver 100 SMS | ~0.8 ms |
| Simulate one second of 1,000 subscribers | ~4 ms |

The core is single-threaded behind one lock in the API; sharding it is milestone 5. A durable
node also writes and flushes one journal line per change, which costs far more than the change
itself on most disks.

use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion, Throughput};
use rtn_core::{seed, Msisdn, Network, Op, Simulator, MB};

const T0: u64 = 1_800_000_000_000;

fn seeded(count: u32) -> (Network, Vec<Msisdn>) {
    let mut net = Network::new();
    let subs = seed::populate(&mut net, count, 1, T0).unwrap();
    let numbers: Vec<Msisdn> = subs.into_iter().map(|s| s.msisdn).collect();
    for (i, m) in numbers.iter().enumerate() {
        net.apply(&format!("bench-topup-{i}"), Op::TopUp { msisdn: m.clone(), amount: 10_000_000 }, T0).unwrap();
    }
    (net, numbers)
}

fn charging(c: &mut Criterion) {
    let mut group = c.benchmark_group("charging");
    group.throughput(Throughput::Elements(1));
    let (mut net, subs) = seeded(1_000);
    let mut n = 0u64;
    group.bench_function("data_usage", |b| {
        b.iter(|| {
            n += 1;
            let m = subs[(n % subs.len() as u64) as usize].clone();
            black_box(net.apply(&format!("d{n}"), Op::DataUsage { msisdn: m, bytes: 10_000 }, T0).ok());
        })
    });
    group.bench_function("replayed_request", |b| {
        let m = subs[0].clone();
        net.apply("replay", Op::DataUsage { msisdn: m.clone(), bytes: 10 }, T0).unwrap();
        b.iter(|| black_box(net.apply("replay", Op::DataUsage { msisdn: m.clone(), bytes: 10 }, T0).ok()))
    });
    group.bench_function("voice_call_start_and_end", |b| {
        b.iter(|| {
            n += 1;
            let m = subs[(n % subs.len() as u64) as usize].clone();
            let id = format!("v{n}");
            net.apply(&id, Op::VoiceStart { msisdn: m, callee: "x".into() }, T0).unwrap();
            black_box(net.apply(&format!("{id}:end"), Op::VoiceEnd { session_id: id, used_seconds: 60 }, T0).ok());
        })
    });
    group.bench_function("transfer", |b| {
        b.iter(|| {
            n += 1;
            let from = subs[(n % 500) as usize].clone();
            let to = subs[500 + (n % 500) as usize].clone();
            black_box(net.apply(&format!("t{n}"), Op::Transfer { from, to, amount: 5_000 }, T0).ok());
        })
    });
    group.finish();
}

fn ussd(c: &mut Criterion) {
    let (mut net, subs) = seeded(100);
    let mut n = 0u64;
    c.bench_function("ussd/balance_menu_round_trip", |b| {
        b.iter(|| {
            n += 1;
            let id = format!("s{n}");
            net.ussd(&id, &subs[0], "*123#", T0).unwrap();
            black_box(net.ussd(&id, &subs[0], "1", T0).unwrap());
        })
    });
}

fn sms(c: &mut Criterion) {
    let mut group = c.benchmark_group("sms");
    group.bench_function("submit_and_deliver_100", |b| {
        b.iter_batched(
            || seeded(100),
            |(mut net, subs)| {
                for i in 0..100usize {
                    let op = Op::SmsSubmit {
                        from: subs[i].clone(),
                        to: subs[(i + 1) % 100].clone(),
                        text: "Meeting moved to 3pm".into(),
                    };
                    net.apply(&format!("m{i}"), op, T0).unwrap();
                }
                black_box(net.deliver_sms(T0))
            },
            BatchSize::LargeInput,
        )
    });
    group.bench_function("segments_long_text", |b| {
        let text = "a".repeat(900);
        b.iter(|| black_box(rtn_core::segments(&text)))
    });
    group.finish();
}

fn simulator(c: &mut Criterion) {
    c.bench_function("simulator/one_second_of_1000_subscribers", |b| {
        b.iter_batched(
            || (seeded(1_000).0, Simulator::new(7)),
            |(mut net, mut sim)| black_box(sim.tick(&mut net, T0 + 1_000, 1)),
            BatchSize::LargeInput,
        )
    });
    let _ = MB;
}

criterion_group!(benches, charging, ussd, sms, simulator);
criterion_main!(benches);

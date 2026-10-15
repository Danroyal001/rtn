//! `rtn`: run the network, or talk to a running one.
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use rtn_api::{router, run_background, system_clock, AppState, Config};
use rtn_core::node::Node;
use rtn_core::{format_naira, Msisdn};
use serde_json::{json, Value};

#[derive(Parser)]
#[command(name = "rtn", version, about = "RTN: a small mobile network, in Rust.")]
struct Cli {
    /// The API to talk to (client commands).
    #[arg(long, global = true, env = "RTN_API", default_value = "http://127.0.0.1:8700")]
    api: String,
    /// The operator's token.
    #[arg(long, global = true, env = "RTN_ADMIN_TOKEN", hide_env_values = true, default_value = "")]
    token: String,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run the network and its HTTP API.
    Serve {
        #[arg(long, env = "RTN_ADDR", default_value = "127.0.0.1:8700")]
        addr: String,
        /// Keep the network in this directory: a journal of every change, written before it is
        /// answered, and a snapshot. Without it the network lives in memory only.
        #[arg(long, env = "RTN_DATA")]
        data: Option<PathBuf>,
        /// Add this many demo subscribers when the network starts empty.
        #[arg(long, default_value_t = 0)]
        seed: u32,
        /// Start the traffic simulator.
        #[arg(long)]
        simulate: bool,
    },
    /// Add demo subscribers to a running network.
    Seed {
        #[arg(long, default_value_t = 50)]
        count: u32,
        #[arg(long, default_value_t = 1)]
        seed: u64,
    },
    /// Simulate traffic: some seconds now, or switch the background simulator on or off.
    Simulate {
        #[arg(long, default_value_t = 10)]
        seconds: u64,
        #[arg(long, conflicts_with = "off")]
        on: bool,
        #[arg(long)]
        off: bool,
    },
    /// List subscribers.
    Subscribers {
        /// Number, IMSI or name to search for.
        #[arg(long)]
        q: Option<String>,
        #[arg(long, default_value_t = 50)]
        limit: usize,
    },
    /// One subscriber's line, balance and recent history.
    Show { msisdn: String },
    /// Add a subscriber.
    Add {
        msisdn: String,
        name: String,
        #[arg(long)]
        pin: String,
        #[arg(long)]
        plan: Option<String>,
    },
    /// Top up a subscriber, in naira.
    Topup { msisdn: String, naira: String },
    /// Bar a line.
    Bar { msisdn: String },
    /// Lift a bar.
    Unbar { msisdn: String },
    /// Dial a USSD code as a subscriber; keep answering until the session ends.
    Ussd {
        msisdn: String,
        #[arg(default_value = "*123#")]
        code: String,
    },
    /// Send an SMS between two subscribers.
    Sms { from: String, to: String, text: String },
    /// Live traffic and money totals.
    Traffic,
    /// Print recharge vouchers.
    Vouchers {
        #[arg(long, default_value_t = 5)]
        count: u32,
        /// Each voucher's value, in naira.
        #[arg(long, default_value = "500")]
        naira: String,
    },
    /// The messages delivered to a number, newest first (sign-in codes arrive here).
    Inbox { msisdn: String },
    /// Write a snapshot and empty the journal now.
    Snapshot,
}

fn now_ms() -> u64 {
    (system_clock())()
}

fn naira_to_units(text: &str) -> Result<u64, String> {
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    if fraction.len() > 2 || whole.is_empty() || !whole.chars().chain(fraction.chars()).all(|c| c.is_ascii_digit()) {
        return Err(format!("{text} is not an amount in naira"));
    }
    let whole: u64 = whole.parse().map_err(|_| format!("{text} is too large"))?;
    let fraction: u64 = format!("{fraction:0<2}").parse().unwrap_or(0);
    Ok(whole * 100 + fraction)
}

struct Client {
    agent: ureq::Agent,
    api: String,
    token: String,
}

impl Client {
    fn new(api: &str, token: &str) -> Self {
        let agent = ureq::Agent::config_builder().http_status_as_error(false).build().into();
        Self { agent, api: api.trim_end_matches('/').to_owned(), token: token.to_owned() }
    }

    fn send(&self, method: &str, path: &str, body: Option<Value>) -> Result<Value, String> {
        let url = format!("{}{path}", self.api);
        let auth = format!("Bearer {}", self.token);
        let result = match (method, body) {
            ("GET", _) => self.agent.get(&url).header("Authorization", &auth).call(),
            ("POST", Some(b)) => self.agent.post(&url).header("Authorization", &auth).send_json(&b),
            ("POST", None) => self.agent.post(&url).header("Authorization", &auth).send_empty(),
            ("PATCH", Some(b)) => self.agent.patch(&url).header("Authorization", &auth).send_json(&b),
            _ => unreachable!("only the methods above are used"),
        };
        let mut response = result.map_err(|e| format!("cannot reach {}: {e}", self.api))?;
        let status = response.status();
        let value: Value = response.body_mut().read_json().map_err(|e| format!("bad answer from the API: {e}"))?;
        if status.is_success() {
            Ok(value)
        } else {
            Err(value["error"]["message"].as_str().unwrap_or("the API refused").to_owned())
        }
    }
}

fn print_json(value: &Value) {
    println!("{}", serde_json::to_string_pretty(value).unwrap_or_default());
}

async fn serve(
    addr: String,
    data: Option<PathBuf>,
    seed_count: u32,
    simulate: bool,
    token: String,
) -> Result<(), String> {
    let node = match &data {
        Some(dir) => Node::open(dir).map_err(|e| format!("cannot open {}: {e}", dir.display()))?,
        None => Node::in_memory(),
    };
    let empty = node.network().subscribers().next().is_none();
    if token.is_empty() {
        eprintln!("rtn: no RTN_ADMIN_TOKEN set; the admin routes are closed");
    }
    let app_state = AppState::new(node, Config { admin_token: token, clock: system_clock(), simulate });
    if seed_count > 0 && empty {
        let seeded = app_state
            .run(json!({ "method": "seed", "count": seed_count, "seed": 1, "now": now_ms() }))
            .map_err(|e| e.to_string())?;
        let seeded = seeded.as_array().cloned().unwrap_or_default();
        eprintln!("rtn: seeded {} subscribers; sign in as any of these with PIN 1234:", seeded.len());
        for s in seeded.iter().take(5) {
            eprintln!("       {}  {}", s["msisdn"].as_str().unwrap_or(""), s["name"].as_str().unwrap_or(""));
        }
    }
    let listener = tokio::net::TcpListener::bind(&addr).await.map_err(|e| format!("cannot listen on {addr}: {e}"))?;
    eprintln!("rtn: listening on http://{addr}{}", if simulate { " with the traffic simulator on" } else { "" });
    let background = tokio::spawn(run_background(app_state.clone()));
    axum::serve(listener, router(app_state.clone()))
        .with_graceful_shutdown(async {
            let ctrl_c = tokio::signal::ctrl_c();
            #[cfg(unix)]
            {
                let mut term =
                    tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).expect("signal handler");
                tokio::select! { _ = ctrl_c => {}, _ = term.recv() => {} }
            }
            #[cfg(not(unix))]
            let _ = ctrl_c.await;
        })
        .await
        .map_err(|e| e.to_string())?;
    background.abort();
    if let Some(dir) = &data {
        app_state.compact().map_err(|e| format!("could not write the snapshot: {e}"))?;
        eprintln!("rtn: wrote a snapshot to {}", dir.display());
    }
    Ok(())
}

fn ussd_session(client: &Client, msisdn: &str, code: &str) -> Result<(), String> {
    let session = format!("cli-{}", now_ms());
    let mut input = code.to_owned();
    let stdin = std::io::stdin();
    loop {
        let reply = client.send(
            "POST",
            "/v1/ussd",
            Some(json!({ "session_id": session, "msisdn": msisdn, "input": input })),
        )?;
        println!("{}", reply["text"].as_str().unwrap_or_default());
        if reply["end"].as_bool().unwrap_or(true) {
            return Ok(());
        }
        print!("> ");
        std::io::stdout().flush().ok();
        input.clear();
        if stdin.lock().read_line(&mut input).map_err(|e| e.to_string())? == 0 {
            return Ok(());
        }
        input = input.trim().to_owned();
    }
}

fn run(cli: Cli) -> Result<(), String> {
    let client = Client::new(&cli.api, &cli.token);
    match cli.command {
        Command::Serve { addr, data, seed, simulate } => {
            let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
            runtime.block_on(serve(addr, data, seed, simulate, cli.token))
        }
        Command::Seed { count, seed } => {
            let seeded = client.send("POST", "/v1/admin/seed", Some(json!({ "count": count, "seed": seed })))?;
            for s in seeded.as_array().into_iter().flatten() {
                println!(
                    "{}  PIN {}  {}",
                    s["msisdn"].as_str().unwrap_or(""),
                    s["pin"].as_str().unwrap_or(""),
                    s["name"].as_str().unwrap_or("")
                );
            }
            Ok(())
        }
        Command::Simulate { seconds, on, off } => {
            if on || off {
                print_json(&client.send("PATCH", "/v1/admin/simulator", Some(json!({ "running": on })))?);
            } else {
                print_json(&client.send("POST", "/v1/admin/simulator/tick", Some(json!({ "seconds": seconds })))?);
            }
            Ok(())
        }
        Command::Subscribers { q, limit } => {
            let query = q.map(|q| format!("&q={}", q.replace(' ', "%20"))).unwrap_or_default();
            let list = client.send("GET", &format!("/v1/admin/subscribers?limit={limit}{query}"), None)?;
            println!("{:<15} {:<24} {:<8} {:>14} {:>10}", "NUMBER", "NAME", "STATUS", "AIRTIME", "DATA MB");
            for item in list["items"].as_array().into_iter().flatten() {
                let (s, b) = (&item["subscriber"], &item["balance"]);
                println!(
                    "{:<15} {:<24} {:<8} {:>14} {:>10}",
                    s["msisdn"].as_str().unwrap_or(""),
                    s["name"].as_str().unwrap_or(""),
                    s["status"].as_str().unwrap_or(""),
                    format_naira(b["airtime"].as_u64().unwrap_or(0)),
                    b["data_bytes"].as_u64().unwrap_or(0) / rtn_core::MB
                );
            }
            println!("{} of {}", list["items"].as_array().map_or(0, Vec::len), list["total"]);
            Ok(())
        }
        Command::Show { msisdn } => {
            print_json(&client.send("GET", &format!("/v1/admin/subscribers/{msisdn}"), None)?);
            Ok(())
        }
        Command::Add { msisdn, name, pin, plan } => {
            print_json(&client.send(
                "POST",
                "/v1/admin/subscribers",
                Some(json!({ "msisdn": msisdn, "name": name, "pin": pin, "plan_id": plan })),
            )?);
            Ok(())
        }
        Command::Topup { msisdn, naira } => {
            let amount = naira_to_units(&naira)?;
            let out = client.send(
                "POST",
                &format!("/v1/admin/subscribers/{msisdn}/topup"),
                Some(json!({ "amount": amount })),
            )?;
            println!(
                "Topped up {}. Airtime now {}.",
                format_naira(amount),
                format_naira(out["balance"]["airtime"].as_u64().unwrap_or(0))
            );
            Ok(())
        }
        Command::Bar { msisdn } => {
            client.send("PATCH", &format!("/v1/admin/subscribers/{msisdn}"), Some(json!({ "status": "barred" })))?;
            println!("{msisdn} is barred.");
            Ok(())
        }
        Command::Unbar { msisdn } => {
            client.send("PATCH", &format!("/v1/admin/subscribers/{msisdn}"), Some(json!({ "status": "active" })))?;
            println!("{msisdn} is active.");
            Ok(())
        }
        Command::Ussd { msisdn, code } => ussd_session(&client, &msisdn, &code),
        Command::Sms { from, to, text } => {
            let op = json!({ "type": "sms_submit", "from": from, "to": to, "text": text });
            let out = client.send(
                "POST",
                "/v1/admin/charge",
                Some(json!({ "request_id": format!("cli-{}", now_ms()), "op": op })),
            )?;
            println!(
                "Queued {} ({} part(s)), charged {}.",
                out["detail"]["message_id"].as_str().unwrap_or(""),
                out["detail"]["segments"],
                format_naira(out["charged"].as_u64().unwrap_or(0))
            );
            Ok(())
        }
        Command::Traffic => {
            print_json(&client.send("GET", "/v1/admin/traffic", None)?);
            Ok(())
        }
        Command::Vouchers { count, naira } => {
            let amount = naira_to_units(&naira)?;
            let batch = client.send("POST", "/v1/admin/vouchers", Some(json!({ "count": count, "amount": amount })))?;
            println!("{:<14} {:<19} {:>12}", "SERIAL", "PIN", "VALUE");
            for v in batch.as_array().into_iter().flatten() {
                let pin = v["pin"].as_str().unwrap_or("");
                let grouped: Vec<&str> = (0..pin.len()).step_by(4).map(|i| &pin[i..(i + 4).min(pin.len())]).collect();
                println!(
                    "{:<14} {:<19} {:>12}",
                    v["serial"].as_str().unwrap_or(""),
                    grouped.join(" "),
                    format_naira(v["amount"].as_u64().unwrap_or(0))
                );
            }
            Ok(())
        }
        Command::Inbox { msisdn } => {
            let msisdn = Msisdn::parse(&msisdn).map_err(|e| e.to_string())?;
            let inbox = client.send("POST", "/v1/admin/rpc", Some(json!({ "method": "inbox", "msisdn": msisdn })))?;
            for m in inbox.as_array().into_iter().flatten().rev().take(20) {
                let from = m["from"].as_str().unwrap_or("");
                let from = if from == rtn_core::SERVICE_NUMBER { "RTN" } else { from };
                println!("{from:<15} {}", m["text"].as_str().unwrap_or(""));
            }
            Ok(())
        }
        Command::Snapshot => {
            print_json(&client.send("POST", "/v1/admin/snapshot", None)?);
            Ok(())
        }
    }
}

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("rtn: {message}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_naira() {
        assert_eq!(naira_to_units("100"), Ok(10_000));
        assert_eq!(naira_to_units("1.5"), Ok(150));
        assert!(naira_to_units("1.555").is_err());
        assert!(naira_to_units("-1").is_err());
    }
}

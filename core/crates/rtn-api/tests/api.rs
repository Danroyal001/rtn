use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use rtn_api::{router, AppState, Config};
use rtn_core::node::Node;
use serde_json::{json, Value};
use tower::ServiceExt;

const ADMIN: &str = "test-admin-token";

struct Harness {
    app: axum::Router,
    clock: Arc<AtomicU64>,
}

fn harness() -> Harness {
    harness_on(Node::in_memory(), true)
}

fn harness_on(node: Node, seed: bool) -> Harness {
    let clock = Arc::new(AtomicU64::new(1_800_000_000_000));
    let tick = clock.clone();
    let state = AppState::new(
        node,
        Config { admin_token: ADMIN.into(), clock: Arc::new(move || tick.load(Ordering::SeqCst)), simulate: false },
    );
    if seed {
        state.run(json!({ "method": "seed", "count": 5, "seed": 1, "now": clock.load(Ordering::SeqCst) })).unwrap();
    }
    Harness { app: router(state), clock }
}

impl Harness {
    async fn call(&self, method: &str, path: &str, token: Option<&str>, body: Option<Value>) -> (StatusCode, Value) {
        let mut req = Request::builder().method(method).uri(path);
        if let Some(token) = token {
            req = req.header("authorization", format!("Bearer {token}"));
        }
        let req = match body {
            Some(body) => req.header("content-type", "application/json").body(Body::from(body.to_string())),
            None => req.body(Body::empty()),
        }
        .unwrap();
        let res = self.app.clone().oneshot(req).await.unwrap();
        let status = res.status();
        let bytes = res.into_body().collect().await.unwrap().to_bytes();
        (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
    }

    async fn login(&self, msisdn: &str) -> String {
        let (status, body) =
            self.call("POST", "/v1/auth/login", None, Some(json!({ "msisdn": msisdn, "pin": "1234" }))).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        body["token"].as_str().unwrap().to_owned()
    }
}

const ADA: &str = "2349990000001";
const BOLA: &str = "2349990000002";

#[tokio::test]
async fn health_and_public_catalogue() {
    let h = harness();
    let (status, body) = h.call("GET", "/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["subscribers"], 5);
    let (_, bundles) = h.call("GET", "/v1/bundles", None, None).await;
    assert!(bundles.as_array().unwrap().len() >= 4);
}

#[tokio::test]
async fn sign_in_and_read_my_balance() {
    let h = harness();
    let (status, body) =
        h.call("POST", "/v1/auth/login", None, Some(json!({ "msisdn": "09990000001", "pin": "0000" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["error"]["code"], "wrong_pin");
    let token = h.login(ADA).await;
    let (status, me) = h.call("GET", "/v1/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(me["subscriber"]["msisdn"], ADA);
    assert!(me["balance"]["airtime"].as_u64().unwrap() > 0);
    let (status, _) = h.call("GET", "/v1/me", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn buying_a_bundle_is_idempotent_by_request_id() {
    let h = harness();
    let token = h.login(ADA).await;
    let body = json!({ "bundle_id": "daily-100mb", "request_id": "app-1" });
    let (status, first) = h.call("POST", "/v1/me/bundles", Some(&token), Some(body.clone())).await;
    assert_eq!(status, StatusCode::OK, "{first}");
    let (_, again) = h.call("POST", "/v1/me/bundles", Some(&token), Some(body)).await;
    assert_eq!(first, again);
    let (_, history) = h.call("GET", "/v1/me/history?limit=5", Some(&token), None).await;
    let purchases = history
        .as_array()
        .unwrap()
        .iter()
        .filter(|e| e["kind"] == "bundle_purchase" && e["request_id"].as_str().unwrap().ends_with("app-1"))
        .count();
    assert_eq!(purchases, 1);
}

#[tokio::test]
async fn transfer_needs_the_pin_and_moves_airtime() {
    let h = harness();
    let token = h.login(ADA).await;
    let (status, body) = h
        .call("POST", "/v1/me/transfer", Some(&token), Some(json!({ "to": BOLA, "amount": 10_000, "pin": "9999" })))
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
    let (status, out) = h
        .call("POST", "/v1/me/transfer", Some(&token), Some(json!({ "to": BOLA, "amount": 10_000, "pin": "1234" })))
        .await;
    assert_eq!(status, StatusCode::OK, "{out}");
    assert_eq!(out["detail"]["type"], "transfer");
}

#[tokio::test]
async fn ussd_through_the_gateway() {
    let h = harness();
    let token = h.login(ADA).await;
    let ussd = |input: &str| json!({ "session_id": "web-1", "msisdn": ADA, "input": input });
    let (status, reply) = h.call("POST", "/v1/ussd", Some(&token), Some(ussd("*123#"))).await;
    assert_eq!(status, StatusCode::OK, "{reply}");
    assert_eq!(reply["end"], false);
    assert!(reply["wire"].as_str().unwrap().starts_with("CON "));
    let (_, reply) = h.call("POST", "/v1/ussd", Some(&token), Some(ussd("1"))).await;
    assert_eq!(reply["end"], true);
    assert!(reply["text"].as_str().unwrap().contains("Airtime"));
    // A subscriber cannot speak for another number.
    let other = json!({ "session_id": "x", "msisdn": BOLA, "input": "*123#" });
    let (status, _) = h.call("POST", "/v1/ussd", Some(&token), Some(other.clone())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = h.call("POST", "/v1/ussd", Some(ADMIN), Some(other)).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn sms_is_charged_stored_and_delivered() {
    let h = harness();
    let ada = h.login(ADA).await;
    let bola = h.login(BOLA).await;
    let (status, out) =
        h.call("POST", "/v1/me/sms", Some(&ada), Some(json!({ "to": BOLA, "text": "Hello from the API" }))).await;
    assert_eq!(status, StatusCode::OK, "{out}");
    h.call("POST", "/v1/admin/sms/deliver", Some(ADMIN), None).await;
    let (_, sms) = h.call("GET", "/v1/me/sms", Some(&bola), None).await;
    assert_eq!(sms["inbox"][0]["text"], "Hello from the API");
}

#[tokio::test]
async fn admin_routes_need_the_admin_token() {
    let h = harness();
    let (status, _) = h.call("GET", "/v1/admin/subscribers", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let ada = h.login(ADA).await;
    let (status, _) = h.call("GET", "/v1/admin/subscribers", Some(&ada), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, list) = h.call("GET", "/v1/admin/subscribers?q=999000000", Some(ADMIN), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list["total"], 5);
}

#[tokio::test]
async fn admin_manages_subscribers_plans_and_bundles() {
    let h = harness();
    let new = json!({ "msisdn": "2349991234567", "name": "New Person", "pin": "4321" });
    let (status, sub) = h.call("POST", "/v1/admin/subscribers", Some(ADMIN), Some(new.clone())).await;
    assert_eq!(status, StatusCode::OK, "{sub}");
    assert!(sub["imsi"].as_str().unwrap().starts_with("99970"));
    let (status, dup) = h.call("POST", "/v1/admin/subscribers", Some(ADMIN), Some(new)).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(dup["error"]["code"], "duplicate_subscriber");

    let (status, _) = h
        .call("POST", "/v1/admin/subscribers/2349991234567/topup", Some(ADMIN), Some(json!({ "amount": 25_000 })))
        .await;
    assert_eq!(status, StatusCode::OK);
    let (status, changed) = h
        .call(
            "PATCH",
            "/v1/admin/subscribers/2349991234567",
            Some(ADMIN),
            Some(json!({ "status": "barred", "plan_id": "steady" })),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{changed}");
    assert_eq!(changed["status"], "barred");
    let (_, detail) = h.call("GET", "/v1/admin/subscribers/2349991234567", Some(ADMIN), None).await;
    assert_eq!(detail["balance"]["airtime"], 25_000);

    let plan = json!({ "id": "ignored", "name": "Night owl", "voice_per_second": 10, "sms_per_segment": 300, "data_per_mb": 200 });
    let (status, saved) = h.call("PUT", "/v1/admin/plans/night-owl", Some(ADMIN), Some(plan)).await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved["id"], "night-owl");
    let bundle = json!({ "id": "x", "name": "Weekend 2GB", "data_bytes": 2_147_483_648u64, "price": 40_000, "validity_days": 2 });
    let (status, _) = h.call("PUT", "/v1/admin/bundles/weekend-2gb", Some(ADMIN), Some(bundle)).await;
    assert_eq!(status, StatusCode::OK);
    let (_, catalog) = h.call("GET", "/v1/admin/catalog", Some(ADMIN), None).await;
    assert!(catalog["bundles"].as_array().unwrap().iter().any(|b| b["id"] == "weekend-2gb"));
}

#[tokio::test]
async fn network_charging_and_live_traffic() {
    let h = harness();
    let charge = json!({ "request_id": "pgw-1", "op": { "type": "data_usage", "msisdn": ADA, "bytes": 1_048_576 } });
    let (status, out) = h.call("POST", "/v1/admin/charge", Some(ADMIN), Some(charge)).await;
    assert_eq!(status, StatusCode::OK, "{out}");
    h.clock.fetch_add(1_000, Ordering::SeqCst);
    let (_, tick) = h.call("POST", "/v1/admin/simulator/tick", Some(ADMIN), Some(json!({ "seconds": 30 }))).await;
    assert!(tick["data_sessions"].as_u64().is_some());
    let (status, traffic) = h.call("GET", "/v1/admin/traffic", Some(ADMIN), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(traffic["totals"]["data_bytes"].as_u64().unwrap() >= 1_048_576);
    assert_eq!(traffic["series"].as_array().unwrap().len(), 60);
    assert_eq!(traffic["simulator_running"], false);
}

#[tokio::test]
async fn bad_input_is_answered_in_the_api_error_shape() {
    let h = harness();
    let (status, body) = h.call("POST", "/v1/auth/login", None, Some(json!({ "msisdn": 5 }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["error"]["code"], "invalid_request");
    let (status, body) = h.call("GET", "/nope", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["error"]["code"], "not_found");
}

#[tokio::test]
async fn sessions_expire() {
    let h = harness();
    let token = h.login(ADA).await;
    h.clock.fetch_add(rtn_api::SESSION_MS + 1, Ordering::SeqCst);
    let (status, _) = h.call("GET", "/v1/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn sign_in_with_a_code_sent_by_sms() {
    let h = harness();
    let (status, sent) = h.call("POST", "/v1/auth/otp", None, Some(json!({ "msisdn": ADA }))).await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    h.call("POST", "/v1/admin/sms/deliver", Some(ADMIN), None).await;
    let (_, log) = h.call("GET", "/v1/admin/sms?limit=5", Some(ADMIN), None).await;
    let text = log[0]["text"].as_str().unwrap().to_owned();
    let code: String = text.chars().take(6).collect();
    let (status, _) =
        h.call("POST", "/v1/auth/otp/verify", None, Some(json!({ "msisdn": ADA, "code": "000000" }))).await;
    assert!(status == StatusCode::UNAUTHORIZED || code == "000000");
    let (status, session) =
        h.call("POST", "/v1/auth/otp/verify", None, Some(json!({ "msisdn": ADA, "code": code }))).await;
    assert_eq!(status, StatusCode::OK, "{session}");
    let token = session["token"].as_str().unwrap();
    let (status, _) = h.call("GET", "/v1/me", Some(token), None).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn the_rpc_route_runs_any_call_for_the_operator_only() {
    let h = harness();
    let call = json!({ "method": "line", "msisdn": ADA, "now": 1_800_000_000_000u64 });
    let (status, _) = h.call("POST", "/v1/admin/rpc", None, Some(call.clone())).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, line) = h.call("POST", "/v1/admin/rpc", Some(ADMIN), Some(call)).await;
    assert_eq!(status, StatusCode::OK, "{line}");
    assert_eq!(line["subscriber"]["msisdn"], ADA);
    let (status, refused) = h
        .call(
            "POST",
            "/v1/admin/rpc",
            Some(ADMIN),
            Some(json!({ "method": "verify_otp", "msisdn": ADA, "code": "1", "now": 1 })),
        )
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(refused["error"]["code"], "code_expired");
}

#[tokio::test]
async fn vouchers_are_printed_by_the_operator_and_redeemed_by_subscribers() {
    let h = harness();
    let (status, batch) =
        h.call("POST", "/v1/admin/vouchers", Some(ADMIN), Some(json!({ "count": 2, "amount": 100_000 }))).await;
    assert_eq!(status, StatusCode::OK, "{batch}");
    let pin = batch[0]["pin"].as_str().unwrap();
    let token = h.login(ADA).await;
    let (status, out) = h.call("POST", "/v1/me/recharge", Some(&token), Some(json!({ "pin": pin }))).await;
    assert_eq!(status, StatusCode::OK, "{out}");
    assert_eq!(out["detail"]["type"], "voucher");
    let (status, again) = h.call("POST", "/v1/me/recharge", Some(&token), Some(json!({ "pin": pin }))).await;
    assert_eq!(status, StatusCode::CONFLICT, "{again}");
    let (_, listed) = h.call("GET", "/v1/admin/vouchers", Some(ADMIN), None).await;
    assert!(listed.as_array().unwrap().iter().all(|v| v.get("pin").is_none()), "PINs are never listed");
}

#[tokio::test]
async fn care_chat_both_ways() {
    let h = harness();
    let token = h.login(ADA).await;
    let (status, thread) = h.call("POST", "/v1/me/care", Some(&token), Some(json!({ "text": "my balance?" }))).await;
    assert_eq!(status, StatusCode::OK, "{thread}");
    assert_eq!(thread[1]["author"], "assistant");
    let (_, desk) = h.call("GET", "/v1/admin/care", Some(ADMIN), None).await;
    assert_eq!(desk[0]["msisdn"], ADA);
    let (status, _) =
        h.call("POST", &format!("/v1/admin/care/{ADA}"), Some(ADMIN), Some(json!({ "text": "Hi" }))).await;
    assert_eq!(status, StatusCode::OK);
    let (_, thread) = h.call("GET", "/v1/me/care", Some(&token), None).await;
    assert_eq!(thread.as_array().unwrap().last().unwrap()["author"], "agent");
}

#[tokio::test]
async fn a_server_started_on_the_same_directory_has_the_same_network() {
    let dir = std::env::temp_dir().join(format!("rtn-api-durable-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    {
        let h = harness_on(Node::open(&dir).unwrap(), true);
        let token = h.login(ADA).await;
        let (status, _) = h
            .call(
                "POST",
                "/v1/me/bundles",
                Some(&token),
                Some(json!({ "bundle_id": "weekly-1gb", "request_id": "d1" })),
            )
            .await;
        assert_eq!(status, StatusCode::OK);
    }
    let h = harness_on(Node::open(&dir).unwrap(), false);
    let (_, history) = h.call("GET", &format!("/v1/admin/ledger?msisdn={ADA}"), Some(ADMIN), None).await;
    assert!(history.as_array().unwrap().iter().any(|e| e["request_id"].as_str().unwrap().ends_with(":d1")));
    let _ = std::fs::remove_dir_all(&dir);
}

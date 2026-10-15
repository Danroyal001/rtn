//! RTN's HTTP/JSON API.
//!
//! One [`AppState`] holds one [`Node`] behind a mutex: the network, its simulator and, when the
//! server was started with a data directory, its journal. Every handler turns its request into one
//! [`rtn_core::rpc`] call and runs it through the node, so whatever changes the network is written
//! to the journal before it is answered. See `docs/API.md` in the repository for every route.
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::extract::rejection::JsonRejection;
use axum::extract::{FromRequest, FromRequestParts, Path, Query, Request, State};
use axum::http::request::Parts;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
use axum::{Json, Router};
use parking_lot::Mutex;
use rand::RngCore;
use rtn_core::node::Node;
use rtn_core::{rpc, Msisdn, RtnError, Status, Units};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

/// How long a subscriber's sign-in lasts.
pub const SESSION_MS: u64 = 12 * 3_600_000;

pub type Clock = Arc<dyn Fn() -> u64 + Send + Sync>;

pub fn system_clock() -> Clock {
    Arc::new(|| SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0))
}

struct SubscriberSession {
    msisdn: Msisdn,
    expires_at: u64,
}

pub struct AppState {
    node: Mutex<Node>,
    sessions: Mutex<HashMap<String, SubscriberSession>>,
    admin_token: String,
    clock: Clock,
}

pub struct Config {
    pub admin_token: String,
    pub clock: Clock,
    /// Switch the traffic simulator on at start.
    pub simulate: bool,
}

fn nonce() -> u64 {
    rand::thread_rng().next_u64()
}

impl AppState {
    pub fn new(node: Node, config: Config) -> Arc<Self> {
        let state = Arc::new(Self {
            node: Mutex::new(node),
            sessions: Mutex::new(HashMap::new()),
            admin_token: config.admin_token,
            clock: config.clock,
        });
        if config.simulate {
            let _ = state.run(json!({ "method": "set_simulator", "running": true }));
        }
        state
    }

    pub fn now(&self) -> u64 {
        (self.clock)()
    }

    /// Runs one RPC call through the node.
    pub fn run(&self, call: Value) -> Result<Value, RtnError> {
        self.node.lock().run(call)
    }

    /// Writes a snapshot and empties the journal, when the node keeps one.
    pub fn compact(&self) -> std::io::Result<()> {
        self.node.lock().compact()
    }

    /// One second of background work: the simulator when it is running, and a store-and-forward
    /// pass for the SMS centre either way.
    pub fn background_tick(&self) {
        let now = self.now();
        let _ = self.run(json!({ "method": "tick", "now": now }));
        self.sessions.lock().retain(|_, s| s.expires_at > now);
    }

    pub fn with_node<T>(&self, f: impl FnOnce(&mut Node) -> T) -> T {
        f(&mut self.node.lock())
    }
}

/// Runs [`AppState::background_tick`] every second until the process ends.
pub async fn run_background(state: Arc<AppState>) {
    let mut every = tokio::time::interval(Duration::from_secs(1));
    loop {
        every.tick().await;
        state.background_tick();
    }
}

// ----- errors ---------------------------------------------------------------------------------

#[derive(Debug)]
pub struct ApiError {
    status: StatusCode,
    body: Value,
}

impl ApiError {
    fn new(status: StatusCode, code: &str, message: impl Into<String>) -> Self {
        Self { status, body: json!({ "error": { "code": code, "message": message.into() } }) }
    }

    fn unauthorized() -> Self {
        Self::new(StatusCode::UNAUTHORIZED, "unauthorized", "sign in first")
    }
}

/// The HTTP status for each refusal.
pub fn status_for(error: &RtnError) -> StatusCode {
    use RtnError::*;
    match error {
        UnknownSubscriber | UnknownPlan | UnknownBundle | UnknownSession | UnknownMessage | UnknownReward => {
            StatusCode::NOT_FOUND
        }
        DuplicateSubscriber | DuplicateImsi | RequestConflict | LoanOutstanding { .. } | VoucherUsed => {
            StatusCode::CONFLICT
        }
        InsufficientFunds { .. } | InsufficientData { .. } | InsufficientPoints { .. } => StatusCode::PAYMENT_REQUIRED,
        Barred => StatusCode::FORBIDDEN,
        WrongPin | WrongCode | CodeExpired => StatusCode::UNAUTHORIZED,
        PinLocked { .. } | TooSoon { .. } | VoucherLocked { .. } => StatusCode::TOO_MANY_REQUESTS,
        _ => StatusCode::UNPROCESSABLE_ENTITY,
    }
}

impl From<RtnError> for ApiError {
    fn from(error: RtnError) -> Self {
        Self { status: status_for(&error), body: rpc::error_json(&error) }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(self.body)).into_response()
    }
}

type ApiResult = Result<Json<Value>, ApiError>;

fn answer(result: Result<Value, RtnError>) -> ApiResult {
    Ok(Json(result?))
}

/// JSON bodies whose mistakes come back in the API's own error shape.
pub struct Body<T>(pub T);

impl<S: Send + Sync, T: DeserializeOwned> FromRequest<S> for Body<T> {
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        match Json::<T>::from_request(req, state).await {
            Ok(Json(value)) => Ok(Body(value)),
            Err(rejection) => Err(json_rejection(rejection)),
        }
    }
}

fn json_rejection(rejection: JsonRejection) -> ApiError {
    ApiError::new(StatusCode::UNPROCESSABLE_ENTITY, "invalid_request", rejection.body_text())
}

// ----- auth -----------------------------------------------------------------------------------

fn bearer(headers: &HeaderMap) -> Option<&str> {
    headers.get("authorization")?.to_str().ok()?.strip_prefix("Bearer ").map(str::trim)
}

fn token_key(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

fn same(a: &str, b: &str) -> bool {
    let (a, b) = (Sha256::digest(a.as_bytes()), Sha256::digest(b.as_bytes()));
    a.iter().zip(b.iter()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// The operator: `Authorization: Bearer <admin token>`.
pub struct Admin;

impl FromRequestParts<Arc<AppState>> for Admin {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &Arc<AppState>) -> Result<Self, Self::Rejection> {
        match bearer(&parts.headers) {
            Some(token) if !state.admin_token.is_empty() && same(token, &state.admin_token) => Ok(Admin),
            _ => Err(ApiError::unauthorized()),
        }
    }
}

/// A signed-in subscriber: `Authorization: Bearer <token from /v1/auth/login>`.
pub struct Me(pub Msisdn);

fn subscriber_for(state: &AppState, headers: &HeaderMap) -> Option<Msisdn> {
    let token = bearer(headers)?;
    let now = state.now();
    let sessions = state.sessions.lock();
    let session = sessions.get(&token_key(token))?;
    (session.expires_at > now).then(|| session.msisdn.clone())
}

impl FromRequestParts<Arc<AppState>> for Me {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &Arc<AppState>) -> Result<Self, Self::Rejection> {
        subscriber_for(state, &parts.headers).map(Me).ok_or_else(ApiError::unauthorized)
    }
}

fn request_id(given: Option<String>, headers: &HeaderMap, scope: &str) -> String {
    let id = given
        .filter(|id| !id.trim().is_empty())
        .or_else(|| headers.get("idempotency-key").and_then(|v| v.to_str().ok()).map(str::to_owned))
        .unwrap_or_else(|| {
            let mut bytes = [0u8; 12];
            rand::thread_rng().fill_bytes(&mut bytes);
            hex::encode(bytes)
        });
    format!("{scope}:{id}")
}

// ----- router ---------------------------------------------------------------------------------

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/bundles", get(bundles))
        .route("/v1/plans", get(plans))
        .route("/v1/auth/login", post(login))
        .route("/v1/auth/otp", post(otp_request))
        .route("/v1/auth/otp/verify", post(otp_verify))
        .route("/v1/auth/logout", post(logout))
        .route("/v1/me", get(me))
        .route("/v1/me/history", get(my_history))
        .route("/v1/me/bundles", post(my_bundle))
        .route("/v1/me/transfer", post(my_transfer))
        .route("/v1/me/share", post(my_share))
        .route("/v1/me/borrow", post(my_borrow))
        .route("/v1/me/recharge", post(my_recharge))
        .route("/v1/me/points", post(my_points))
        .route("/v1/me/notifications", get(my_notifications))
        .route("/v1/me/care", get(my_care).post(my_care_send))
        .route("/v1/me/sms", get(my_sms).post(my_sms_send))
        .route("/v1/ussd", post(ussd))
        .route("/v1/admin/rpc", post(admin_rpc))
        .route("/v1/admin/subscribers", get(admin_subscribers).post(admin_add_subscriber))
        .route("/v1/admin/subscribers/{msisdn}", get(admin_subscriber).patch(admin_update_subscriber))
        .route("/v1/admin/subscribers/{msisdn}/topup", post(admin_top_up))
        .route("/v1/admin/catalog", get(admin_catalog))
        .route("/v1/admin/plans/{id}", put(admin_put_plan))
        .route("/v1/admin/bundles/{id}", put(admin_put_bundle))
        .route("/v1/admin/vouchers", get(admin_vouchers).post(admin_issue_vouchers))
        .route("/v1/admin/care", get(admin_care))
        .route("/v1/admin/care/{msisdn}", post(admin_care_reply))
        .route("/v1/admin/ledger", get(admin_ledger))
        .route("/v1/admin/traffic", get(admin_traffic))
        .route("/v1/admin/totals", get(admin_totals))
        .route("/v1/admin/charge", post(admin_charge))
        .route("/v1/admin/sms", get(admin_sms))
        .route("/v1/admin/sms/deliver", post(admin_deliver))
        .route("/v1/admin/simulator", get(admin_simulator).patch(admin_set_simulator))
        .route("/v1/admin/simulator/tick", post(admin_simulator_tick))
        .route("/v1/admin/seed", post(admin_seed))
        .route("/v1/admin/snapshot", post(admin_snapshot))
        .fallback(|| async { ApiError::new(StatusCode::NOT_FOUND, "not_found", "no such route") })
        .with_state(state)
}

fn parse_msisdn(raw: &str) -> Result<Msisdn, ApiError> {
    Ok(Msisdn::parse(raw)?)
}

async fn health(State(state): State<Arc<AppState>>) -> ApiResult {
    let subscribers = state.with_node(|n| n.network().subscribers().count());
    Ok(Json(
        json!({ "status": "ok", "service": "rtn", "version": env!("CARGO_PKG_VERSION"), "subscribers": subscribers }),
    ))
}

async fn bundles(State(state): State<Arc<AppState>>) -> ApiResult {
    let catalog = state.run(json!({ "method": "catalog" }))?;
    Ok(Json(catalog["bundles"].clone()))
}

async fn plans(State(state): State<Arc<AppState>>) -> ApiResult {
    let catalog = state.run(json!({ "method": "catalog" }))?;
    let plans: Vec<Value> = catalog["plans"].as_object().map(|m| m.values().cloned().collect()).unwrap_or_default();
    Ok(Json(Value::Array(plans)))
}

fn open_session(state: &AppState, msisdn: &Msisdn, now: u64) -> Value {
    let name = state.with_node(|n| n.network().subscriber(msisdn).map(|s| s.name.clone()).unwrap_or_default());
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let token = hex::encode(bytes);
    let expires_at = now + SESSION_MS;
    state.sessions.lock().insert(token_key(&token), SubscriberSession { msisdn: msisdn.clone(), expires_at });
    json!({ "token": token, "msisdn": msisdn, "name": name, "expires_at": expires_at })
}

#[derive(Deserialize)]
struct Login {
    msisdn: String,
    pin: String,
}

async fn login(State(state): State<Arc<AppState>>, Body(body): Body<Login>) -> ApiResult {
    let msisdn = parse_msisdn(&body.msisdn)?;
    let now = state.now();
    state.run(json!({ "method": "verify_pin", "msisdn": msisdn, "pin": body.pin, "now": now }))?;
    Ok(Json(open_session(&state, &msisdn, now)))
}

#[derive(Deserialize)]
struct OtpRequest {
    msisdn: String,
}

async fn otp_request(State(state): State<Arc<AppState>>, Body(body): Body<OtpRequest>) -> ApiResult {
    let msisdn = parse_msisdn(&body.msisdn)?;
    let now = state.now();
    answer(state.run(json!({ "method": "request_otp", "msisdn": msisdn, "nonce": nonce(), "now": now })))
}

#[derive(Deserialize)]
struct OtpVerify {
    msisdn: String,
    code: String,
}

async fn otp_verify(State(state): State<Arc<AppState>>, Body(body): Body<OtpVerify>) -> ApiResult {
    let msisdn = parse_msisdn(&body.msisdn)?;
    let now = state.now();
    state.run(json!({ "method": "verify_otp", "msisdn": msisdn, "code": body.code, "now": now }))?;
    Ok(Json(open_session(&state, &msisdn, now)))
}

async fn logout(State(state): State<Arc<AppState>>, headers: HeaderMap) -> ApiResult {
    if let Some(token) = bearer(&headers) {
        state.sessions.lock().remove(&token_key(token));
    }
    Ok(Json(json!({ "signed_out": true })))
}

async fn me(State(state): State<Arc<AppState>>, Me(msisdn): Me) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({ "method": "line", "msisdn": msisdn, "now": now })))
}

#[derive(Deserialize)]
struct Page {
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    msisdn: Option<String>,
}

async fn my_history(State(state): State<Arc<AppState>>, Me(msisdn): Me, Query(page): Query<Page>) -> ApiResult {
    let limit = page.limit.unwrap_or(50).min(500);
    answer(state.run(json!({ "method": "history", "msisdn": msisdn, "limit": limit })))
}

fn apply(state: &AppState, id: String, op: Value) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({ "method": "apply", "request_id": id, "op": op, "now": now })))
}

#[derive(Deserialize)]
struct BuyBundle {
    bundle_id: String,
    #[serde(default)]
    beneficiary: Option<String>,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_bundle(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<BuyBundle>,
) -> ApiResult {
    let beneficiary = body.beneficiary.as_deref().map(parse_msisdn).transpose()?;
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    apply(
        &state,
        id,
        json!({ "type": "buy_bundle", "msisdn": msisdn, "bundle_id": body.bundle_id, "beneficiary": beneficiary }),
    )
}

fn check_pin(state: &AppState, msisdn: &Msisdn, pin: &str) -> Result<(), ApiError> {
    let now = state.now();
    state.run(json!({ "method": "verify_pin", "msisdn": msisdn, "pin": pin, "now": now }))?;
    Ok(())
}

#[derive(Deserialize)]
struct Transfer {
    to: String,
    amount: Units,
    pin: String,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_transfer(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<Transfer>,
) -> ApiResult {
    let to = parse_msisdn(&body.to)?;
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    check_pin(&state, &msisdn, &body.pin)?;
    apply(&state, id, json!({ "type": "transfer", "from": msisdn, "to": to, "amount": body.amount }))
}

#[derive(Deserialize)]
struct Share {
    to: String,
    bytes: u64,
    pin: String,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_share(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<Share>,
) -> ApiResult {
    let to = parse_msisdn(&body.to)?;
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    check_pin(&state, &msisdn, &body.pin)?;
    apply(&state, id, json!({ "type": "share_data", "from": msisdn, "to": to, "bytes": body.bytes }))
}

#[derive(Deserialize)]
struct Borrow {
    amount: Units,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_borrow(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<Borrow>,
) -> ApiResult {
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    apply(&state, id, json!({ "type": "borrow", "msisdn": msisdn, "amount": body.amount }))
}

#[derive(Deserialize)]
struct Recharge {
    pin: String,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_recharge(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<Recharge>,
) -> ApiResult {
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    apply(&state, id, json!({ "type": "redeem_voucher", "msisdn": msisdn, "pin": body.pin }))
}

#[derive(Deserialize)]
struct Points {
    reward_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_points(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<Points>,
) -> ApiResult {
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    apply(&state, id, json!({ "type": "redeem_points", "msisdn": msisdn, "reward_id": body.reward_id }))
}

async fn my_notifications(State(state): State<Arc<AppState>>, Me(msisdn): Me) -> ApiResult {
    answer(state.run(json!({ "method": "notifications", "msisdn": msisdn })))
}

async fn my_care(State(state): State<Arc<AppState>>, Me(msisdn): Me) -> ApiResult {
    answer(state.run(json!({ "method": "care_thread", "msisdn": msisdn })))
}

#[derive(Deserialize)]
struct CareText {
    text: String,
}

async fn my_care_send(State(state): State<Arc<AppState>>, Me(msisdn): Me, Body(body): Body<CareText>) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({ "method": "care_send", "msisdn": msisdn, "text": body.text, "now": now })))
}

async fn my_sms(State(state): State<Arc<AppState>>, Me(msisdn): Me) -> ApiResult {
    let newest = |v: Value| -> Value {
        let mut list = v.as_array().cloned().unwrap_or_default();
        list.reverse();
        list.truncate(50);
        Value::Array(list)
    };
    let inbox = state.run(json!({ "method": "inbox", "msisdn": msisdn }))?;
    let outbox = state.run(json!({ "method": "outbox", "msisdn": msisdn }))?;
    Ok(Json(json!({ "inbox": newest(inbox), "outbox": newest(outbox) })))
}

#[derive(Deserialize)]
struct SendSms {
    to: String,
    text: String,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_sms_send(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<SendSms>,
) -> ApiResult {
    let to = parse_msisdn(&body.to)?;
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    apply(&state, id, json!({ "type": "sms_submit", "from": msisdn, "to": to, "text": body.text }))
}

#[derive(Deserialize)]
struct UssdRequest {
    session_id: String,
    msisdn: String,
    input: String,
}

/// The gateway, called the way a USSD aggregator calls an application. The operator may speak for
/// any number; a signed-in subscriber only for their own.
async fn ussd(State(state): State<Arc<AppState>>, headers: HeaderMap, Body(body): Body<UssdRequest>) -> ApiResult {
    let msisdn = parse_msisdn(&body.msisdn)?;
    let is_admin = bearer(&headers).is_some_and(|t| !state.admin_token.is_empty() && same(t, &state.admin_token));
    if !is_admin && subscriber_for(&state, &headers).as_ref() != Some(&msisdn) {
        return Err(ApiError::unauthorized());
    }
    let now = state.now();
    let reply = state.run(json!({
        "method": "ussd", "session_id": body.session_id, "msisdn": msisdn, "input": body.input, "now": now
    }))?;
    let end = reply["end"].as_bool().unwrap_or(true);
    let text = reply["text"].as_str().unwrap_or_default().to_owned();
    let wire = format!("{} {text}", if end { "END" } else { "CON" });
    Ok(Json(json!({ "text": text, "end": end, "wire": wire })))
}

// ----- admin ----------------------------------------------------------------------------------

/// Any [`rpc`] call, for a trusted backend that holds the operator's token (the MyRTN app's).
async fn admin_rpc(_: Admin, State(state): State<Arc<AppState>>, Body(call): Body<Value>) -> ApiResult {
    answer(state.run(call))
}

#[derive(Deserialize)]
struct SubscriberQuery {
    #[serde(default)]
    q: Option<String>,
    #[serde(default)]
    status: Option<Status>,
    #[serde(default)]
    offset: Option<usize>,
    #[serde(default)]
    limit: Option<usize>,
}

async fn admin_subscribers(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Query(query): Query<SubscriberQuery>,
) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({
        "method": "subscriber_page",
        "q": query.q.unwrap_or_default(),
        "status": query.status,
        "offset": query.offset.unwrap_or(0),
        "limit": query.limit.unwrap_or(50).min(500),
        "now": now,
    })))
}

async fn admin_add_subscriber(_: Admin, State(state): State<Arc<AppState>>, Body(body): Body<Value>) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({ "method": "add_subscriber", "subscriber": body, "now": now })))
}

fn newest(list: Value, limit: usize) -> Value {
    let mut list = list.as_array().cloned().unwrap_or_default();
    list.reverse();
    list.truncate(limit);
    Value::Array(list)
}

async fn admin_subscriber(_: Admin, State(state): State<Arc<AppState>>, Path(raw): Path<String>) -> ApiResult {
    let msisdn = parse_msisdn(&raw)?;
    let now = state.now();
    let line = state.run(json!({ "method": "line", "msisdn": msisdn, "now": now }))?;
    let history = state.run(json!({ "method": "history", "msisdn": msisdn, "limit": 50 }))?;
    let inbox = state.run(json!({ "method": "inbox", "msisdn": msisdn }))?;
    Ok(Json(json!({
        "subscriber": line["subscriber"],
        "plan": line["plan"],
        "balance": line["balance"],
        "history": history,
        "inbox": newest(inbox, 20),
    })))
}

#[derive(Deserialize)]
struct SubscriberChange {
    #[serde(default)]
    status: Option<Status>,
    #[serde(default)]
    plan_id: Option<String>,
    #[serde(default)]
    loan_limit: Option<Units>,
    #[serde(default)]
    attached: Option<bool>,
    #[serde(default)]
    pin: Option<String>,
}

async fn admin_update_subscriber(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(raw): Path<String>,
    Body(change): Body<SubscriberChange>,
) -> ApiResult {
    let msisdn = parse_msisdn(&raw)?;
    let now = state.now();
    state.run(json!({ "method": "subscriber", "msisdn": msisdn }))?;
    if let Some(plan_id) = &change.plan_id {
        let catalog = state.run(json!({ "method": "catalog" }))?;
        if catalog["plans"].get(plan_id).is_none() {
            return Err(RtnError::UnknownPlan.into());
        }
    }
    if let Some(pin) = &change.pin {
        state.run(json!({ "method": "set_pin", "msisdn": msisdn, "pin": pin }))?;
    }
    if let Some(plan_id) = &change.plan_id {
        state.run(json!({ "method": "set_plan", "msisdn": msisdn, "plan_id": plan_id }))?;
    }
    if let Some(status) = change.status {
        state.run(json!({ "method": "set_status", "msisdn": msisdn, "status": status }))?;
    }
    if let Some(limit) = change.loan_limit {
        state.run(json!({ "method": "set_loan_limit", "msisdn": msisdn, "limit": limit }))?;
    }
    if let Some(attached) = change.attached {
        state.run(json!({ "method": "set_attached", "msisdn": msisdn, "attached": attached, "now": now }))?;
    }
    answer(state.run(json!({ "method": "subscriber", "msisdn": msisdn })))
}

#[derive(Deserialize)]
struct TopUp {
    amount: Units,
    #[serde(default)]
    via: Option<String>,
    #[serde(default)]
    request_id: Option<String>,
}

async fn admin_top_up(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(raw): Path<String>,
    headers: HeaderMap,
    Body(body): Body<TopUp>,
) -> ApiResult {
    let msisdn = parse_msisdn(&raw)?;
    let id = request_id(body.request_id, &headers, "admin");
    apply(&state, id, json!({ "type": "top_up", "msisdn": msisdn, "amount": body.amount, "via": body.via }))
}

async fn admin_catalog(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    answer(state.run(json!({ "method": "catalog" })))
}

async fn admin_put_plan(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Body(mut plan): Body<Value>,
) -> ApiResult {
    plan["id"] = json!(id);
    answer(state.run(json!({ "method": "upsert_plan", "plan": plan })))
}

async fn admin_put_bundle(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Body(mut bundle): Body<Value>,
) -> ApiResult {
    bundle["id"] = json!(id);
    answer(state.run(json!({ "method": "upsert_bundle", "bundle": bundle })))
}

#[derive(Deserialize)]
struct IssueVouchers {
    count: u32,
    amount: Units,
}

async fn admin_issue_vouchers(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Body(body): Body<IssueVouchers>,
) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({
        "method": "issue_vouchers", "count": body.count, "amount": body.amount, "nonce": nonce(), "now": now
    })))
}

async fn admin_vouchers(_: Admin, State(state): State<Arc<AppState>>, Query(page): Query<Page>) -> ApiResult {
    answer(state.run(json!({ "method": "vouchers", "limit": page.limit.unwrap_or(100).min(1_000) })))
}

async fn admin_care(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    answer(state.run(json!({ "method": "care_threads" })))
}

async fn admin_care_reply(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(raw): Path<String>,
    Body(body): Body<CareText>,
) -> ApiResult {
    let msisdn = parse_msisdn(&raw)?;
    let now = state.now();
    answer(state.run(json!({ "method": "care_reply", "msisdn": msisdn, "text": body.text, "now": now })))
}

async fn admin_ledger(_: Admin, State(state): State<Arc<AppState>>, Query(page): Query<Page>) -> ApiResult {
    let limit = page.limit.unwrap_or(100).min(1000);
    match page.msisdn {
        Some(raw) => {
            let msisdn = parse_msisdn(&raw)?;
            answer(state.run(json!({ "method": "history", "msisdn": msisdn, "limit": limit })))
        }
        None => answer(state.run(json!({ "method": "ledger", "limit": limit }))),
    }
}

async fn admin_traffic(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    let now = state.now();
    let mut view = state.run(json!({ "method": "traffic", "now": now }))?;
    view["totals_money"] = state.run(json!({ "method": "totals" }))?;
    view["simulator_running"] = state.run(json!({ "method": "simulator" }))?["running"].clone();
    Ok(Json(view))
}

async fn admin_totals(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    answer(state.run(json!({ "method": "totals" })))
}

#[derive(Deserialize)]
struct Charge {
    request_id: String,
    op: Value,
}

/// The charging interface network elements use (what Diameter Gy is in a real core).
async fn admin_charge(_: Admin, State(state): State<Arc<AppState>>, Body(body): Body<Charge>) -> ApiResult {
    apply(&state, format!("net:{}", body.request_id), body.op)
}

async fn admin_sms(_: Admin, State(state): State<Arc<AppState>>, Query(page): Query<Page>) -> ApiResult {
    answer(state.run(json!({ "method": "sms_log", "limit": page.limit.unwrap_or(100).min(1_000) })))
}

async fn admin_deliver(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    let now = state.now();
    answer(state.run(json!({ "method": "deliver_sms", "now": now })))
}

async fn admin_simulator(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    answer(state.run(json!({ "method": "simulator" })))
}

#[derive(Deserialize, Serialize)]
struct SimulatorChange {
    running: bool,
}

async fn admin_set_simulator(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Body(body): Body<SimulatorChange>,
) -> ApiResult {
    answer(state.run(json!({ "method": "set_simulator", "running": body.running })))
}

#[derive(Deserialize)]
struct Tick {
    #[serde(default)]
    seconds: Option<u64>,
}

async fn admin_simulator_tick(_: Admin, State(state): State<Arc<AppState>>, Body(body): Body<Tick>) -> ApiResult {
    let seconds = body.seconds.unwrap_or(1).clamp(1, 3_600);
    let now = state.now();
    answer(state.run(json!({ "method": "simulate", "seconds": seconds, "now": now })))
}

#[derive(Deserialize)]
struct Seed {
    #[serde(default)]
    count: Option<u32>,
    #[serde(default)]
    seed: Option<u64>,
}

async fn admin_seed(_: Admin, State(state): State<Arc<AppState>>, Body(body): Body<Seed>) -> ApiResult {
    let count = body.count.unwrap_or(50).min(100_000);
    let now = state.now();
    answer(state.run(json!({ "method": "seed", "count": count, "seed": body.seed.unwrap_or(1), "now": now })))
}

async fn admin_snapshot(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    match state.compact() {
        Ok(()) => Ok(Json(json!({ "compacted": true }))),
        Err(e) => Err(ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "io", e.to_string())),
    }
}

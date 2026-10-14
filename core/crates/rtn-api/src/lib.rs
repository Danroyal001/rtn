//! RTN's HTTP/JSON API.
//!
//! One [`AppState`] holds one [`Network`] behind a mutex; every handler takes the lock, does its
//! work without awaiting, and lets go. See `docs/API.md` in the repository for every route.
use std::collections::HashMap;
use std::path::PathBuf;
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
use rtn_core::{rpc, seed, Bundle, Msisdn, Network, NewSubscriber, Op, RatingPlan, RtnError, Simulator, Status, Units};
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

struct SimulatorState {
    simulator: Simulator,
    running: bool,
}

pub struct AppState {
    net: Mutex<Network>,
    sessions: Mutex<HashMap<String, SubscriberSession>>,
    simulator: Mutex<SimulatorState>,
    admin_token: String,
    state_path: Option<PathBuf>,
    clock: Clock,
}

pub struct Config {
    pub admin_token: String,
    pub state_path: Option<PathBuf>,
    pub clock: Clock,
    pub simulate: bool,
    pub simulator_seed: u64,
}

impl AppState {
    pub fn new(net: Network, config: Config) -> Arc<Self> {
        Arc::new(Self {
            net: Mutex::new(net),
            sessions: Mutex::new(HashMap::new()),
            simulator: Mutex::new(SimulatorState {
                simulator: Simulator::new(config.simulator_seed),
                running: config.simulate,
            }),
            admin_token: config.admin_token,
            state_path: config.state_path,
            clock: config.clock,
        })
    }

    pub fn now(&self) -> u64 {
        (self.clock)()
    }

    /// Writes the network to the state file, if there is one: to a temporary file first, then
    /// renamed over the old one, so a crash mid-write never leaves half a snapshot.
    pub fn save(&self) -> std::io::Result<Option<PathBuf>> {
        let Some(path) = &self.state_path else { return Ok(None) };
        let json = self.net.lock().to_json();
        let temp = path.with_extension("tmp");
        std::fs::write(&temp, json)?;
        std::fs::rename(&temp, path)?;
        Ok(Some(path.clone()))
    }

    /// One second of background work: the simulator when it is running, and a store-and-forward
    /// pass for the SMS centre either way.
    pub fn background_tick(&self) {
        let now = self.now();
        let mut sim = self.simulator.lock();
        let mut net = self.net.lock();
        if sim.running {
            sim.simulator.tick(&mut net, now, 1);
        } else {
            net.deliver_sms(now);
        }
        drop(net);
        self.sessions.lock().retain(|_, s| s.expires_at > now);
    }

    pub fn with_network<T>(&self, f: impl FnOnce(&mut Network) -> T) -> T {
        f(&mut self.net.lock())
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

impl From<RtnError> for ApiError {
    fn from(error: RtnError) -> Self {
        use RtnError::*;
        let status = match &error {
            UnknownSubscriber | UnknownPlan | UnknownBundle | UnknownSession | UnknownMessage => StatusCode::NOT_FOUND,
            DuplicateSubscriber | DuplicateImsi | RequestConflict | LoanOutstanding { .. } => StatusCode::CONFLICT,
            InsufficientFunds { .. } => StatusCode::PAYMENT_REQUIRED,
            Barred => StatusCode::FORBIDDEN,
            WrongPin => StatusCode::UNAUTHORIZED,
            PinLocked { .. } => StatusCode::TOO_MANY_REQUESTS,
            _ => StatusCode::UNPROCESSABLE_ENTITY,
        };
        Self { status, body: rpc::error_json(&error) }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(self.body)).into_response()
    }
}

type ApiResult = Result<Json<Value>, ApiError>;

fn ok<T: Serialize>(value: T) -> ApiResult {
    Ok(Json(serde_json::to_value(value).expect("API values serialise")))
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
        .route("/v1/auth/logout", post(logout))
        .route("/v1/me", get(me))
        .route("/v1/me/history", get(my_history))
        .route("/v1/me/bundles", post(my_bundle))
        .route("/v1/me/transfer", post(my_transfer))
        .route("/v1/me/borrow", post(my_borrow))
        .route("/v1/me/sms", get(my_sms).post(my_sms_send))
        .route("/v1/ussd", post(ussd))
        .route("/v1/admin/subscribers", get(admin_subscribers).post(admin_add_subscriber))
        .route("/v1/admin/subscribers/{msisdn}", get(admin_subscriber).patch(admin_update_subscriber))
        .route("/v1/admin/subscribers/{msisdn}/topup", post(admin_top_up))
        .route("/v1/admin/catalog", get(admin_catalog))
        .route("/v1/admin/plans/{id}", put(admin_put_plan))
        .route("/v1/admin/bundles/{id}", put(admin_put_bundle))
        .route("/v1/admin/ledger", get(admin_ledger))
        .route("/v1/admin/traffic", get(admin_traffic))
        .route("/v1/admin/totals", get(admin_totals))
        .route("/v1/admin/charge", post(admin_charge))
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
    let subscribers = state.net.lock().subscribers().count();
    ok(json!({ "status": "ok", "service": "rtn", "version": env!("CARGO_PKG_VERSION"), "subscribers": subscribers }))
}

async fn bundles(State(state): State<Arc<AppState>>) -> ApiResult {
    ok(state.net.lock().catalog().bundles())
}

async fn plans(State(state): State<Arc<AppState>>) -> ApiResult {
    ok(state.net.lock().catalog().plans().collect::<Vec<_>>())
}

#[derive(Deserialize)]
struct Login {
    msisdn: String,
    pin: String,
}

async fn login(State(state): State<Arc<AppState>>, Body(body): Body<Login>) -> ApiResult {
    let msisdn = parse_msisdn(&body.msisdn)?;
    let now = state.now();
    let name = {
        let mut net = state.net.lock();
        net.verify_pin(&msisdn, &body.pin, now)?;
        net.subscriber(&msisdn).map(|s| s.name.clone()).unwrap_or_default()
    };
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let token = hex::encode(bytes);
    let expires_at = now + SESSION_MS;
    state.sessions.lock().insert(token_key(&token), SubscriberSession { msisdn: msisdn.clone(), expires_at });
    ok(json!({ "token": token, "msisdn": msisdn, "name": name, "expires_at": expires_at }))
}

async fn logout(State(state): State<Arc<AppState>>, headers: HeaderMap) -> ApiResult {
    if let Some(token) = bearer(&headers) {
        state.sessions.lock().remove(&token_key(token));
    }
    ok(json!({ "signed_out": true }))
}

async fn me(State(state): State<Arc<AppState>>, Me(msisdn): Me) -> ApiResult {
    let now = state.now();
    let mut net = state.net.lock();
    let balance = net.balance(&msisdn, now)?;
    let subscriber = net.subscriber(&msisdn).cloned();
    let plan = subscriber.as_ref().and_then(|s| net.catalog().plan(&s.plan_id).cloned());
    ok(json!({ "subscriber": subscriber, "plan": plan, "balance": balance }))
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
    let net = state.net.lock();
    let entries: Vec<_> = net.history(&msisdn).into_iter().rev().take(limit).collect();
    ok(entries)
}

#[derive(Deserialize)]
struct BuyBundle {
    bundle_id: String,
    #[serde(default)]
    request_id: Option<String>,
}

async fn my_bundle(
    State(state): State<Arc<AppState>>,
    Me(msisdn): Me,
    headers: HeaderMap,
    Body(body): Body<BuyBundle>,
) -> ApiResult {
    let id = request_id(body.request_id, &headers, &format!("self:{msisdn}"));
    let now = state.now();
    ok(state.net.lock().apply(&id, Op::BuyBundle { msisdn, bundle_id: body.bundle_id }, now)?)
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
    let now = state.now();
    let mut net = state.net.lock();
    net.verify_pin(&msisdn, &body.pin, now)?;
    ok(net.apply(&id, Op::Transfer { from: msisdn, to, amount: body.amount }, now)?)
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
    let now = state.now();
    ok(state.net.lock().apply(&id, Op::Borrow { msisdn, amount: body.amount }, now)?)
}

async fn my_sms(State(state): State<Arc<AppState>>, Me(msisdn): Me) -> ApiResult {
    let net = state.net.lock();
    let inbox: Vec<_> = net.inbox(&msisdn).into_iter().rev().take(50).collect();
    let outbox: Vec<_> = net.outbox(&msisdn).into_iter().rev().take(50).collect();
    ok(json!({ "inbox": inbox, "outbox": outbox }))
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
    let now = state.now();
    ok(state.net.lock().apply(&id, Op::SmsSubmit { from: msisdn, to, text: body.text }, now)?)
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
    let reply = state.net.lock().ussd(&body.session_id, &msisdn, &body.input, now)?;
    ok(json!({ "text": reply.text, "end": reply.end, "wire": reply.wire() }))
}

// ----- admin ----------------------------------------------------------------------------------

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
    let needle = query.q.unwrap_or_default().trim().to_lowercase();
    let mut net = state.net.lock();
    let matching: Vec<Msisdn> = net
        .subscribers()
        .filter(|s| query.status.is_none_or(|status| s.status == status))
        .filter(|s| {
            needle.is_empty()
                || s.msisdn.as_str().contains(&needle)
                || s.imsi.as_str().contains(&needle)
                || s.name.to_lowercase().contains(&needle)
        })
        .map(|s| s.msisdn.clone())
        .collect();
    let total = matching.len();
    let offset = query.offset.unwrap_or(0);
    let limit = query.limit.unwrap_or(50).min(500);
    let mut items = Vec::new();
    for msisdn in matching.into_iter().skip(offset).take(limit) {
        let balance = net.balance(&msisdn, now)?;
        let subscriber = net.subscriber(&msisdn).cloned();
        items.push(json!({ "subscriber": subscriber, "balance": balance }));
    }
    ok(json!({ "total": total, "offset": offset, "items": items }))
}

async fn admin_add_subscriber(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Body(body): Body<NewSubscriber>,
) -> ApiResult {
    let now = state.now();
    ok(state.net.lock().add_subscriber(body, now)?)
}

async fn admin_subscriber(_: Admin, State(state): State<Arc<AppState>>, Path(raw): Path<String>) -> ApiResult {
    let msisdn = parse_msisdn(&raw)?;
    let now = state.now();
    let mut net = state.net.lock();
    let balance = net.balance(&msisdn, now)?;
    let subscriber = net.subscriber(&msisdn).cloned();
    let history: Vec<_> = net.history(&msisdn).into_iter().rev().take(50).cloned().collect();
    let inbox: Vec<_> = net.inbox(&msisdn).into_iter().rev().take(20).cloned().collect();
    ok(json!({ "subscriber": subscriber, "balance": balance, "history": history, "inbox": inbox }))
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
    let mut net = state.net.lock();
    if net.subscriber(&msisdn).is_none() {
        return Err(RtnError::UnknownSubscriber.into());
    }
    if let Some(plan_id) = &change.plan_id {
        if net.catalog().plan(plan_id).is_none() {
            return Err(RtnError::UnknownPlan.into());
        }
    }
    if let Some(pin) = &change.pin {
        net.set_pin(&msisdn, pin)?;
    }
    if let Some(plan_id) = &change.plan_id {
        net.set_plan(&msisdn, plan_id)?;
    }
    if let Some(status) = change.status {
        net.set_status(&msisdn, status)?;
    }
    if let Some(limit) = change.loan_limit {
        net.set_loan_limit(&msisdn, limit)?;
    }
    if let Some(attached) = change.attached {
        net.set_attached(&msisdn, attached, now)?;
    }
    ok(net.subscriber(&msisdn))
}

#[derive(Deserialize)]
struct TopUp {
    amount: Units,
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
    let now = state.now();
    ok(state.net.lock().apply(&id, Op::TopUp { msisdn, amount: body.amount }, now)?)
}

async fn admin_catalog(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    ok(state.net.lock().catalog())
}

async fn admin_put_plan(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Body(mut plan): Body<RatingPlan>,
) -> ApiResult {
    plan.id = id;
    let mut net = state.net.lock();
    net.catalog_mut().upsert_plan(plan.clone())?;
    ok(plan)
}

async fn admin_put_bundle(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    Body(mut bundle): Body<Bundle>,
) -> ApiResult {
    bundle.id = id;
    let mut net = state.net.lock();
    net.catalog_mut().upsert_bundle(bundle.clone())?;
    ok(bundle)
}

async fn admin_ledger(_: Admin, State(state): State<Arc<AppState>>, Query(page): Query<Page>) -> ApiResult {
    let limit = page.limit.unwrap_or(100).min(1000);
    let net = state.net.lock();
    let entries: Vec<_> = match page.msisdn {
        Some(raw) => net.history(&parse_msisdn(&raw)?).into_iter().rev().take(limit).collect(),
        None => net.ledger().iter().rev().take(limit).collect(),
    };
    ok(entries)
}

async fn admin_traffic(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    let now = state.now();
    let running = state.simulator.lock().running;
    let net = state.net.lock();
    let mut view = serde_json::to_value(net.traffic(now)).expect("traffic serialises");
    view["totals_money"] = serde_json::to_value(net.totals()).expect("totals serialise");
    view["simulator_running"] = json!(running);
    ok(view)
}

async fn admin_totals(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    ok(state.net.lock().totals())
}

#[derive(Deserialize)]
struct Charge {
    request_id: String,
    op: Op,
}

/// The charging interface network elements use (what Diameter Gy is in a real core).
async fn admin_charge(_: Admin, State(state): State<Arc<AppState>>, Body(body): Body<Charge>) -> ApiResult {
    let now = state.now();
    ok(state.net.lock().apply(&format!("net:{}", body.request_id), body.op, now)?)
}

async fn admin_deliver(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    let now = state.now();
    ok(state.net.lock().deliver_sms(now))
}

async fn admin_simulator(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    ok(json!({ "running": state.simulator.lock().running }))
}

#[derive(Deserialize)]
struct SimulatorChange {
    running: bool,
}

async fn admin_set_simulator(
    _: Admin,
    State(state): State<Arc<AppState>>,
    Body(body): Body<SimulatorChange>,
) -> ApiResult {
    state.simulator.lock().running = body.running;
    ok(json!({ "running": body.running }))
}

#[derive(Deserialize)]
struct Tick {
    #[serde(default)]
    seconds: Option<u64>,
}

async fn admin_simulator_tick(_: Admin, State(state): State<Arc<AppState>>, Body(body): Body<Tick>) -> ApiResult {
    let seconds = body.seconds.unwrap_or(1).clamp(1, 3_600);
    let now = state.now();
    let mut sim = state.simulator.lock();
    let mut net = state.net.lock();
    ok(sim.simulator.tick(&mut net, now, seconds))
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
    ok(seed::populate(&mut state.net.lock(), count, body.seed.unwrap_or(1), now)?)
}

async fn admin_snapshot(_: Admin, State(state): State<Arc<AppState>>) -> ApiResult {
    match state.save() {
        Ok(Some(path)) => ok(json!({ "saved": path })),
        Ok(None) => Err(ApiError::new(StatusCode::CONFLICT, "no_state_file", "the server was started without --state")),
        Err(e) => Err(ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "io", e.to_string())),
    }
}

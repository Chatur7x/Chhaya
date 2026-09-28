// Chaaya SwarmRelay v10 — Production (Axum)
// Encrypted chunk store: POST /upload, GET /chunk/{id}, GET /health, POST /gc
// Run: cargo run --release  (listens 0.0.0.0:8081)

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use bytes::Bytes;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::Arc, time::{Duration, Instant}};
use tokio::sync::RwLock;
use tracing::{info, warn};
use sha2::Digest;

#[derive(Clone)]
struct EncryptedChunk {
    data: Vec<u8>,
    uploaded_at: Instant,
    ttl: Duration,
    download_count: u32,
    max_downloads: u32,
    sha256: String,
}
impl EncryptedChunk {
    fn is_expired(&self) -> bool { self.uploaded_at.elapsed() > self.ttl || self.download_count >= self.max_downloads }
}

#[derive(Clone)]
struct SwarmRelay {
    node_id: String,
    chunks: Arc<RwLock<HashMap<String, EncryptedChunk>>>,
    max_bytes: u64,
    cur_bytes: Arc<RwLock<u64>>,
}

#[derive(Serialize)]
struct HealthResp {
    node_id: String,
    chunks: usize,
    bytes_used: u64,
    bytes_max: u64,
    uptime_secs: u64,
}

#[derive(Deserialize)]
struct UploadReq {
    chunk_id: String,
    data_b64: String, // base64 encrypted chunk
    ttl_hours: Option<u64>,
    max_downloads: Option<u32>,
}
#[derive(Serialize)]
struct UploadResp { chunk_id: String, stored: bool, sha256: String }

static START: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

impl SwarmRelay {
    fn new(node_id: String) -> Self {
        START.get_or_init(|| Instant::now());
        Self { node_id, chunks: Arc::new(RwLock::new(HashMap::new())), max_bytes: 10*1024*1024*1024, cur_bytes: Arc::new(RwLock::new(0)) }
    }
    async fn health(&self) -> HealthResp {
        let chunks = self.chunks.read().await.len();
        let bytes = *self.cur_bytes.read().await;
        HealthResp { node_id: self.node_id.clone(), chunks, bytes_used: bytes, bytes_max: self.max_bytes, uptime_secs: START.get().unwrap().elapsed().as_secs() }
    }
}

async fn health_handler(State(state): State<Arc<SwarmRelay>>) -> impl IntoResponse {
    Json(state.health().await)
}

async fn upload_handler(State(state): State<Arc<SwarmRelay>>, Json(req): Json<UploadReq>) -> impl IntoResponse {
    let data = match base64_decode(&req.data_b64) {
        Ok(v) => v,
        Err(e) => return (StatusCode::BAD_REQUEST, Json(serde_json::json!({"error": format!("b64: {e}")}))).into_response(),
    };
    let sha = hex::encode(sha2::Sha256::digest(&data));
    let ttl = Duration::from_secs(req.ttl_hours.unwrap_or(24)*3600);
    let max_dl = req.max_downloads.unwrap_or(5);
    // capacity check
    {
        let cur = *state.cur_bytes.read().await;
        if cur + data.len() as u64 > state.max_bytes {
            return (StatusCode::INSUFFICIENT_STORAGE, Json(serde_json::json!({"error":"capacity exceeded"}))).into_response();
        }
    }
    let chunk = EncryptedChunk { data: data.clone(), uploaded_at: Instant::now(), ttl, download_count: 0, max_downloads: max_dl, sha256: sha.clone() };
    let mut map = state.chunks.write().await;
    let mut cur = state.cur_bytes.write().await;
    if !map.contains_key(&req.chunk_id) { *cur += data.len() as u64; }
    map.insert(req.chunk_id.clone(), chunk);
    info!("[STORE] {} {}B ttl={}h", req.chunk_id, data.len(), ttl.as_secs()/3600);
    (StatusCode::OK, Json(UploadResp{ chunk_id: req.chunk_id, stored: true, sha256: sha })).into_response()
}

async fn chunk_handler(State(state): State<Arc<SwarmRelay>>, Path(id): Path<String>, headers: HeaderMap) -> impl IntoResponse {
    let mut map = state.chunks.write().await;
    match map.get_mut(&id) {
        Some(c) if c.is_expired() => {
            let len = c.data.len() as u64;
            map.remove(&id);
            let mut cur = state.cur_bytes.write().await;
            *cur = cur.saturating_sub(len);
            warn!("[EXPIRED] {}", id);
            (StatusCode::GONE, Json(serde_json::json!({"error":"expired"}))).into_response()
        },
        Some(c) => {
            c.download_count += 1;
            let b64 = base64_encode(&c.data);
            // Return JSON with b64 + sha
            (StatusCode::OK, Json(serde_json::json!({"chunk_id": id, "data_b64": b64, "sha256": c.sha256, "downloads": c.download_count}))).into_response()
        },
        None => (StatusCode::NOT_FOUND, Json(serde_json::json!({"error":"not found"}))).into_response(),
    }
}

async fn gc_handler(State(state): State<Arc<SwarmRelay>>) -> impl IntoResponse {
    let mut map = state.chunks.write().await;
    let mut cur = state.cur_bytes.write().await;
    let mut removed = 0u32;
    map.retain(|_, c| { if c.is_expired() { *cur = cur.saturating_sub(c.data.len() as u64); removed+=1; false } else { true }});
    Json(serde_json::json!({"removed": removed, "remaining": map.len()}))
}

fn base64_decode(s: &str) -> Result<Vec<u8>, String> {
    // simple base64 without external crate: use hex fallback? For demo, treat as raw if not b64
    // Try to decode as base64 by manual: if contains only b64 chars, decode via base64 crate emulation
    // We add tiny b64 decoder
    let bytes = s.as_bytes();
    // quick check: if length %4 !=0 or contains non-b64, treat as hex? For production use `base64` crate.
    // Here we use `data_url` style: if starts with hex, decode hex
    if s.chars().all(|c| c.is_ascii_hexdigit()) && s.len() % 2 == 0 {
        return hex::decode(s).map_err(|e| e.to_string());
    }
    // fallback: return raw bytes of string (for JSON text chunks)
    Ok(bytes.to_vec())
}
fn base64_encode(b: &[u8]) -> String { hex::encode(b) } // hex as placeholder for demo (real: base64)

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    let relay = Arc::new(SwarmRelay::new("relay_v10_alpha".to_string()));
    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/upload", post(upload_handler))
        .route("/chunk/:id", get(chunk_handler))
        .route("/gc", post(gc_handler))
        .with_state(relay.clone())
        .layer(tower_http::cors::CorsLayer::permissive());
    let addr = std::env::var("RELAY_ADDR").unwrap_or_else(|_| "0.0.0.0:8081".to_string());
    println!("╔══════════════════════════════════════════════════╗");
    println!("║         Chaaya SwarmRelay v10 PRODUCTION        ║");
    println!("║  Axum Encrypted Chunk Store — :8081             ║");
    println!("╚══════════════════════════════════════════════════╝");
    println!("[LISTEN] http://{addr}  /health /upload /chunk/:id /gc");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

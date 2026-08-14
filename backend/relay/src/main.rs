// Chaaya SwarmRelay Server
// A high-speed, zero-knowledge media relay that temporarily stores
// encrypted attachments with strict TTL (Time-to-Live) expiration.
//
// This is the Rust server stub for the Chaaya decentralized relay network.
// Each relay node accepts encrypted file chunks, stores them temporarily,
// and serves them to authorized recipients.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Represents an encrypted file chunk stored on the relay
struct EncryptedChunk {
    /// Unique chunk identifier (SHA-256 hash of content)
    chunk_id: String,
    /// The encrypted binary data
    data: Vec<u8>,
    /// When this chunk was uploaded
    uploaded_at: Instant,
    /// Time-to-live duration (default: 24 hours)
    ttl: Duration,
    /// Number of times this chunk has been downloaded
    download_count: u32,
    /// Maximum allowed downloads before auto-deletion
    max_downloads: u32,
}

impl EncryptedChunk {
    fn new(chunk_id: String, data: Vec<u8>, ttl_hours: u64, max_downloads: u32) -> Self {
        Self {
            chunk_id,
            data,
            uploaded_at: Instant::now(),
            ttl: Duration::from_secs(ttl_hours * 3600),
            download_count: 0,
            max_downloads,
        }
    }

    fn is_expired(&self) -> bool {
        self.uploaded_at.elapsed() > self.ttl || self.download_count >= self.max_downloads
    }
}

/// The SwarmRelay server state
struct SwarmRelay {
    /// Node identifier (public key hash)
    node_id: String,
    /// In-memory encrypted chunk storage
    chunks: Arc<Mutex<HashMap<String, EncryptedChunk>>>,
    /// Maximum storage capacity in bytes (default: 10 GB)
    max_storage_bytes: u64,
    /// Current storage usage in bytes
    current_storage_bytes: Arc<Mutex<u64>>,
}

impl SwarmRelay {
    fn new(node_id: String) -> Self {
        Self {
            node_id,
            chunks: Arc::new(Mutex::new(HashMap::new())),
            max_storage_bytes: 10 * 1024 * 1024 * 1024, // 10 GB
            current_storage_bytes: Arc::new(Mutex::new(0)),
        }
    }

    /// Store an encrypted chunk on this relay node
    fn store_chunk(
        &self,
        chunk_id: String,
        data: Vec<u8>,
        ttl_hours: u64,
        max_downloads: u32,
    ) -> Result<String, String> {
        let data_len = data.len() as u64;

        // Check storage capacity
        let mut current = self.current_storage_bytes.lock().unwrap();
        if *current + data_len > self.max_storage_bytes {
            return Err("Relay storage capacity exceeded".to_string());
        }

        let chunk = EncryptedChunk::new(chunk_id.clone(), data, ttl_hours, max_downloads);

        let mut chunks = self.chunks.lock().unwrap();
        chunks.insert(chunk_id.clone(), chunk);
        *current += data_len;

        Ok(chunk_id)
    }

    /// Retrieve an encrypted chunk by ID
    fn retrieve_chunk(&self, chunk_id: &str) -> Result<Vec<u8>, String> {
        let mut chunks = self.chunks.lock().unwrap();

        match chunks.get_mut(chunk_id) {
            Some(chunk) => {
                if chunk.is_expired() {
                    let data_len = chunk.data.len() as u64;
                    chunks.remove(chunk_id);
                    let mut current = self.current_storage_bytes.lock().unwrap();
                    *current -= data_len;
                    Err("Chunk has expired or reached max downloads".to_string())
                } else {
                    chunk.download_count += 1;
                    Ok(chunk.data.clone())
                }
            }
            None => Err("Chunk not found".to_string()),
        }
    }

    /// Garbage collection: remove all expired chunks
    fn gc_expired_chunks(&self) -> u32 {
        let mut chunks = self.chunks.lock().unwrap();
        let mut current = self.current_storage_bytes.lock().unwrap();
        let mut removed = 0u32;

        chunks.retain(|_, chunk| {
            if chunk.is_expired() {
                *current -= chunk.data.len() as u64;
                removed += 1;
                false
            } else {
                true
            }
        });

        removed
    }
}

fn main() {
    println!("╔══════════════════════════════════════════════════╗");
    println!("║         Chaaya SwarmRelay v2.0.0                ║");
    println!("║  Zero-Knowledge Encrypted Media Relay Node      ║");
    println!("╚══════════════════════════════════════════════════╝");
    println!();

    let relay = SwarmRelay::new("node_alpha_001".to_string());

    // Simulated chunk storage
    let test_data = vec![0u8; 1024]; // 1KB test chunk
    match relay.store_chunk(
        "abc123def456".to_string(),
        test_data,
        24,  // 24-hour TTL
        5,   // Max 5 downloads
    ) {
        Ok(id) => println!("[OK] Stored chunk: {}", id),
        Err(e) => println!("[ERR] Failed to store: {}", e),
    }

    // Simulated chunk retrieval
    match relay.retrieve_chunk("abc123def456") {
        Ok(data) => println!("[OK] Retrieved chunk: {} bytes", data.len()),
        Err(e) => println!("[ERR] Failed to retrieve: {}", e),
    }

    // Run GC
    let removed = relay.gc_expired_chunks();
    println!("[GC] Removed {} expired chunks", removed);

    println!();
    println!("SwarmRelay node '{}' is ready.", relay.node_id);
    println!("Listening for incoming encrypted chunk uploads...");
}

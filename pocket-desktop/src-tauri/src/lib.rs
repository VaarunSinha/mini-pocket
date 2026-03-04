// 'Mini Pocket' Desktop — connect to Flutter proxy, pull notes, sync to backend.

mod ai;

use std::collections::HashMap;
use std::net::UdpSocket;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub id: Option<String>,
    pub name: String,
    #[serde(rename = "created_at")]
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Note {
    pub id: Option<String>,
    #[serde(rename = "device_id")]
    pub device_id: String,
    pub content: String,
    pub transcription: Option<String>,
    #[serde(rename = "todo_list")]
    pub todo_list: Option<Vec<String>>,
    pub summary: Option<String>,
    pub reminders: Option<Vec<String>>,
    #[serde(rename = "created_at")]
    pub created_at: Option<String>,
    #[serde(rename = "updated_at")]
    pub updated_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PullResult {
    device: Device,
    notes: Vec<Note>,
}

/// One discovered 'Mini Pocket' Proxy (Flutter app) on the network. Pairing code is not broadcast; user enters it and it is validated on connect.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoveredDevice {
    pub url: String,
    pub name: String,
    /// Optional for backwards compatibility; desktop should not rely on broadcasted code.
    #[serde(default)]
    pub code: Option<String>,
}

/// Listen for UDP broadcasts from 'Mini Pocket' Proxy apps; returns deduplicated list (by url).
#[tauri::command]
async fn discover_devices(listen_secs: Option<u64>) -> Result<Vec<DiscoveredDevice>, String> {
    let secs = listen_secs.unwrap_or(5).clamp(1, 30);
    let out = tokio::task::spawn_blocking(move || {
        const PORT: u16 = 8766;
        let socket = UdpSocket::bind(("0.0.0.0", PORT)).map_err(|e| e.to_string())?;
        socket.set_read_timeout(Some(Duration::from_millis(200))).ok();
        let deadline = Instant::now() + Duration::from_secs(secs);
        let mut by_url: HashMap<String, DiscoveredDevice> = HashMap::new();
        let mut buf = [0u8; 1024];
        while Instant::now() < deadline {
            if let Ok((len, _)) = socket.recv_from(&mut buf) {
                if let Ok(s) = std::str::from_utf8(&buf[..len]) {
                    if let Ok(parsed) = serde_json::from_str::<DiscoveredDevice>(s) {
                        by_url.insert(parsed.url.clone(), parsed);
                    }
                }
            }
        }
        Ok(by_url.into_values().collect())
    })
    .await
    .map_err(|e| e.to_string())?;
    out
}

/// Pull device and notes from 'Mini Pocket' proxy (Flutter app) using pairing code.
#[tauri::command]
async fn pull_notes(device_url: String, pairing_code: String) -> Result<PullResult, String> {
    let base = device_url.trim_end_matches('/');
    let client = reqwest::Client::new();

    let device_res = client
        .get(format!("{}/device", base))
        .header("x-pairing-code", pairing_code.clone())
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !device_res.status().is_success() {
        return Err(format!("Device request failed: {}", device_res.status()));
    }
    let device: Device = device_res.json().await.map_err(|e| e.to_string())?;

    let notes_res = client
        .get(format!("{}/notes", base))
        .header("x-pairing-code", pairing_code)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !notes_res.status().is_success() {
        return Err(format!("Notes request failed: {}", notes_res.status()));
    }
    let notes: Vec<Note> = notes_res.json().await.map_err(|e| e.to_string())?;

    Ok(PullResult { device, notes })
}

/// Validate username/password against backend (HTTP Basic Auth). Returns Ok(()) if valid.
#[tauri::command]
async fn login(
    backend_url: String,
    username: String,
    password: String,
) -> Result<(), String> {
    let base = backend_url.trim_end_matches('/');
    let res = reqwest::Client::new()
        .post(format!("{}/auth/login", base))
        .basic_auth(&username, Some(&password))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        let status = res.status();
        let text = res.text().await.unwrap_or_default();
        return Err(format!("Login failed {}: {}", status, text));
    }
    Ok(())
}

/// Check 'Mini Pocket' Proxy device is reachable and pairing code is valid.
#[tauri::command]
async fn check_device_health(device_url: String, pairing_code: String) -> Result<bool, String> {
    let base = device_url.trim_end_matches('/');
    let res = reqwest::Client::new()
        .get(format!("{}/device", base))
        .header("x-pairing-code", pairing_code)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    Ok(res.status().is_success())
}

/// Process note content with OpenAI gpt-4o (todo_list, summary, reminders, reminder_dates).
/// reference_date: today's date for the AI (e.g. "4 March 2026") so "tonight", "20th March" resolve correctly.
/// Requires OPENAI_API_KEY in the environment.
#[tauri::command]
async fn process_note_with_ai(
    state: tauri::State<'_, ai::AiModelState>,
    note_content: String,
    reference_date: Option<String>,
    model_id: Option<String>,
) -> Result<ai::ProcessedNoteFields, String> {
    ai::process_note_with_ai(state, note_content, reference_date, model_id).await
}

/// Check backend health.
#[tauri::command]
async fn check_backend_health(backend_url: String) -> Result<bool, String> {
    let base = backend_url.trim_end_matches('/');
    let res = reqwest::Client::new()
        .get(format!("{}/health", base))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    Ok(res.status().is_success())
}

/// Sync device + notes to backend (HTTP Basic Auth required).
#[tauri::command]
async fn sync_to_backend(
    backend_url: String,
    username: String,
    password: String,
    device: Device,
    notes: Vec<Note>,
) -> Result<(), String> {
    let base = backend_url.trim_end_matches('/');
    let payload = serde_json::json!({ "device": device, "notes": notes });
    let res = reqwest::Client::new()
        .post(format!("{}/sync", base))
        .basic_auth(&username, Some(&password))
        .json(&payload)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !res.status().is_success() {
        let status = res.status();
        let body = res.text().await.unwrap_or_default();
        return Err(format!("Sync failed {}: {}", status, body));
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .manage(ai::AiModelState::new())
        .invoke_handler(tauri::generate_handler![
            discover_devices,
            login,
            pull_notes,
            check_device_health,
            process_note_with_ai,
            check_backend_health,
            sync_to_backend,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

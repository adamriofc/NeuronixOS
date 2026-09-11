// ==============================================================================
// NEURONIX Conductor Control Protocol Client (UNIX Domain Socket)
// Native client communicating with conductor-runtime over JSON-RPC 2.0.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use crate::surface::VitalGlanceData;

pub const MAX_FRAME_SIZE: usize = 1024 * 1024;
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(5);

static REQUEST_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq)]
pub struct RpcRequest<T: std::fmt::Display = String> {
    pub jsonrpc: String,
    pub id: u64,
    pub method: String,
    pub params: T,
}

impl<T: std::fmt::Display> RpcRequest<T> {
    pub fn new(id: u64, method: impl Into<String>, params: T) -> Self {
        RpcRequest {
            jsonrpc: "2.0".to_string(),
            id,
            method: method.into(),
            params,
        }
    }

    pub fn to_frame(&self) -> String {
        format!(
            "{{\"jsonrpc\":\"{}\",\"id\":{},\"method\":\"{}\",\"params\":{}}}\n",
            escape_json_str(&self.jsonrpc),
            self.id,
            escape_json_str(&self.method),
            self.params
        )
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RpcResponse {
    pub jsonrpc: String,
    pub id: u64,
    pub result: Option<String>,
    pub error: Option<RpcError>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SurfaceState {
    pub lifecycle_state: String,
    pub gui_attached: bool,
    pub active_connections: usize,
    pub pending_proposals: usize,
    pub topbar: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProposalData {
    pub proposal_hash: String,
    pub skill_id: String,
    pub title: String,
    pub severity: String,
    pub explanation: String,
    pub status: String,
}

// -----------------------------------------------------------------------------
// Zero-Dependency Pure Rust JSON Extractors
// -----------------------------------------------------------------------------

pub fn escape_json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 16);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                use std::fmt::Write;
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out
}

pub fn extract_f32_field(json: &str, field: &str) -> Option<f32> {
    let key_pattern = format!("\"{}\"", field);
    let key_pos = json.find(&key_pattern)?;
    let after_key = &json[key_pos + key_pattern.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    let num_str: String = after_colon
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.' || *c == '-')
        .collect();
    num_str.parse::<f32>().ok()
}

pub fn extract_str_field(json: &str, field: &str) -> Option<String> {
    let key_pattern = format!("\"{}\"", field);
    let key_pos = json.find(&key_pattern)?;
    let after_key = &json[key_pos + key_pattern.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    if !after_colon.starts_with('"') {
        return None;
    }
    let mut val = String::new();
    let mut escape = false;
    for ch in after_colon[1..].chars() {
        if escape {
            val.push(ch);
            escape = false;
        } else if ch == '\\' {
            escape = true;
        } else if ch == '"' {
            return Some(val);
        } else {
            val.push(ch);
        }
    }
    None
}

pub fn extract_u64_field(json: &str, field: &str) -> Option<u64> {
    let key_pattern = format!("\"{}\"", field);
    let key_pos = json.find(&key_pattern)?;
    let after_key = &json[key_pos + key_pattern.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    let num_str: String = after_colon.chars().take_while(|c| c.is_ascii_digit()).collect();
    num_str.parse::<u64>().ok()
}

pub fn extract_i64_field(json: &str, field: &str) -> Option<i64> {
    let key_pattern = format!("\"{}\"", field);
    let key_pos = json.find(&key_pattern)?;
    let after_key = &json[key_pos + key_pattern.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    let num_str: String = after_colon
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '-')
        .collect();
    num_str.parse::<i64>().ok()
}

pub fn extract_bool_field(json: &str, field: &str) -> Option<bool> {
    let key_pattern = format!("\"{}\"", field);
    let key_pos = json.find(&key_pattern)?;
    let after_key = &json[key_pos + key_pattern.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    if after_colon.starts_with("true") {
        Some(true)
    } else if after_colon.starts_with("false") {
        Some(false)
    } else {
        None
    }
}

pub fn extract_object_field(json: &str, field: &str) -> Option<String> {
    let key_pattern = format!("\"{}\"", field);
    let key_pos = json.find(&key_pattern)?;
    let after_key = &json[key_pos + key_pattern.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos + 1..].trim_start();
    if !after_colon.starts_with('{') {
        return None;
    }
    let mut depth = 0;
    let mut in_str = false;
    let mut escape = false;
    let mut end_idx = 0;
    for (i, ch) in after_colon.char_indices() {
        if escape {
            escape = false;
            continue;
        }
        if ch == '\\' && in_str {
            escape = true;
            continue;
        }
        if ch == '"' {
            in_str = !in_str;
            continue;
        }
        if !in_str {
            if ch == '{' {
                depth += 1;
            } else if ch == '}' {
                depth -= 1;
                if depth == 0 {
                    end_idx = i + 1;
                    break;
                }
            }
        }
    }
    if end_idx > 0 {
        Some(after_colon[..end_idx].to_string())
    } else {
        None
    }
}

pub fn parse_rpc_response(raw: &str) -> Result<RpcResponse, String> {
    let jsonrpc = extract_str_field(raw, "jsonrpc").unwrap_or_else(|| "2.0".to_string());
    let id = extract_u64_field(raw, "id").unwrap_or(0);
    let error = if let Some(err_obj) = extract_object_field(raw, "error") {
        let code = extract_i64_field(&err_obj, "code").unwrap_or(-32000);
        let message = extract_str_field(&err_obj, "message").unwrap_or_else(|| "Unknown RPC error".to_string());
        Some(RpcError { code, message })
    } else {
        None
    };
    let result = if error.is_none() {
        if let Some(obj) = extract_object_field(raw, "result") {
            Some(obj)
        } else if let Some(s) = extract_str_field(raw, "result") {
            Some(s)
        } else {
            None
        }
    } else {
        None
    };

    Ok(RpcResponse {
        jsonrpc,
        id,
        result,
        error,
    })
}

// -----------------------------------------------------------------------------
// Conductor Unix Domain Socket Client
// -----------------------------------------------------------------------------

pub struct ConductorClient {
    socket_path: PathBuf,
}

impl ConductorClient {
    pub fn new(socket_path: Option<PathBuf>) -> Self {
        let path = socket_path.unwrap_or_else(Self::default_socket_path);
        ConductorClient { socket_path: path }
    }

    pub fn default_socket_path() -> PathBuf {
        if let Ok(env_path) = std::env::var("CONDUCTOR_SOCKET_PATH") {
            return PathBuf::from(env_path);
        }
        if let Ok(xdg) = std::env::var("XDG_RUNTIME_DIR") {
            return PathBuf::from(xdg).join("conductor.sock");
        }
        let uid = unsafe { libc_getuid() };
        let run_user = PathBuf::from(format!("/run/user/{}", uid));
        if run_user.exists() {
            return run_user.join("conductor.sock");
        }
        PathBuf::from(format!("/tmp/conductor-{}.sock", uid))
    }

    pub fn call(&self, method: &str, params_json: &str) -> Result<String, String> {
        let mut stream = UnixStream::connect(&self.socket_path)
            .map_err(|e| format!("Failed to connect to Conductor socket at {}: {}", self.socket_path.display(), e))?;

        stream.set_read_timeout(Some(DEFAULT_TIMEOUT))
            .map_err(|e| format!("Failed to set read timeout: {}", e))?;
        stream.set_write_timeout(Some(DEFAULT_TIMEOUT))
            .map_err(|e| format!("Failed to set write timeout: {}", e))?;

        let request_id = REQUEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let req = RpcRequest::new(request_id, method, params_json);
        let frame = req.to_frame();

        stream.write_all(frame.as_bytes())
            .map_err(|e| format!("Failed to write to socket: {}", e))?;
        stream.flush()
            .map_err(|e| format!("Failed to flush socket: {}", e))?;

        let mut reader = BufReader::new(stream).take(MAX_FRAME_SIZE as u64);
        let mut line = String::new();
        reader.read_line(&mut line)
            .map_err(|e| format!("Failed to read response from socket: {}", e))?;

        let resp = parse_rpc_response(&line)?;
        if resp.id != request_id {
            return Err(format!("Mismatched RPC response id: expected {}, got {}", request_id, resp.id));
        }

        Ok(line)
    }

    pub fn ping(&self) -> Result<bool, String> {
        let raw = self.call("conductor.ping", "{}")?;
        let resp = parse_rpc_response(&raw)?;
        if let Some(ref err) = resp.error {
            return Err(format!("RPC error {}: {}", err.code, err.message));
        }
        if let Some(ref res_obj) = resp.result {
            let status = extract_str_field(res_obj, "status").unwrap_or_default();
            Ok(status == "PONG")
        } else {
            Ok(false)
        }
    }

    pub fn get_surface_state(&self) -> Result<SurfaceState, String> {
        let raw = self.call("surface.state", "{}")?;
        let resp = parse_rpc_response(&raw)?;
        if let Some(ref err) = resp.error {
            return Err(format!("RPC error {}: {}", err.code, err.message));
        }
        let res_obj = resp.result.ok_or_else(|| "Missing result in surface.state response".to_string())?;
        Ok(SurfaceState {
            lifecycle_state: extract_str_field(&res_obj, "lifecycle_state").unwrap_or_else(|| "UNKNOWN".to_string()),
            gui_attached: extract_bool_field(&res_obj, "gui_attached").unwrap_or(false),
            active_connections: extract_u64_field(&res_obj, "active_connections").unwrap_or(0) as usize,
            pending_proposals: extract_u64_field(&res_obj, "pending_proposals").unwrap_or(0) as usize,
            topbar: extract_str_field(&res_obj, "topbar").unwrap_or_default(),
        })
    }

    pub fn resolve_proposal(&self, proposal_hash: &str, action: &str) -> Result<String, String> {
        let params = format!(
            "{{\"proposal_hash\":\"{}\",\"action\":\"{}\"}}",
            escape_json_str(proposal_hash),
            escape_json_str(action)
        );
        let raw = self.call("proposal.resolve", &params)?;
        let resp = parse_rpc_response(&raw)?;
        if let Some(ref err) = resp.error {
            return Err(format!("RPC error {}: {}", err.code, err.message));
        }
        resp.result.ok_or_else(|| "Missing result in proposal.resolve response".to_string())
    }

    pub fn get_vital_snapshot(&self) -> Result<VitalGlanceData, String> {
        let raw = self.call("vital.snapshot", "{}")?;
        let resp = parse_rpc_response(&raw)?;
        if let Some(ref err) = resp.error {
            return Err(format!("RPC error {}: {}", err.code, err.message));
        }
        let res_obj = resp.result.ok_or_else(|| "Missing result in vital.snapshot response".to_string())?;
        let metrics = extract_object_field(&res_obj, "metrics").unwrap_or_else(|| res_obj.clone());

        let cpu = extract_object_field(&metrics, "cpu");
        let cpu_load = if let Some(ref c) = cpu {
            let l1 = extract_object_field(c, "load_average_1m").and_then(|o| extract_f32_field(&o, "value"));
            let l5 = extract_object_field(c, "load_average_5m").and_then(|o| extract_f32_field(&o, "value"));
            let l15 = extract_object_field(c, "load_average_15m").and_then(|o| extract_f32_field(&o, "value"));
            let cores = extract_object_field(c, "core_count").and_then(|o| extract_u64_field(&o, "value"));
            if let (Some(one), Some(five), Some(fifteen)) = (l1, l5, l15) {
                if let Some(cr) = cores {
                    Some(format!("{:.2}, {:.2}, {:.2} ({} cores online)", one, five, fifteen, cr))
                } else {
                    Some(format!("{:.2}, {:.2}, {:.2}", one, five, fifteen))
                }
            } else {
                None
            }
        } else {
            None
        };

        let memory = extract_object_field(&metrics, "memory");
        let memory_info = if let Some(ref m) = memory {
            let total = extract_object_field(m, "total_bytes").and_then(|o| extract_u64_field(&o, "value"));
            let avail = extract_object_field(m, "available_bytes").and_then(|o| extract_u64_field(&o, "value"));
            if let (Some(tot), Some(av)) = (total, avail) {
                let used = tot.saturating_sub(av);
                let used_gib = used as f64 / (1024.0 * 1024.0 * 1024.0);
                let tot_gib = tot as f64 / (1024.0 * 1024.0 * 1024.0);
                let pct = if tot > 0 { (used as f64 / tot as f64 * 100.0) as u32 } else { 0 };
                Some(format!("{:.1} GiB / {:.1} GiB ({}% utilized)", used_gib, tot_gib, pct))
            } else {
                None
            }
        } else {
            None
        };

        let thermal = extract_object_field(&metrics, "thermal");
        let cpu_temp_celsius = thermal.as_ref().and_then(|t| {
            extract_object_field(t, "cpu_temperature").and_then(|o| extract_f32_field(&o, "value"))
        });

        let nixos = extract_object_field(&metrics, "nixos");
        let nixos_generation = nixos.as_ref().and_then(|n| {
            extract_object_field(n, "active_generation").and_then(|o| extract_u64_field(&o, "value")).map(|g| g as u32)
        });

        let neuronix = extract_object_field(&metrics, "neuronix");
        let state_root_digest = neuronix.as_ref().and_then(|nrx| {
            extract_object_field(nrx, "stateroot").and_then(|o| extract_str_field(&o, "value"))
        });

        let service = extract_object_field(&metrics, "service");
        let daemon_status = service.as_ref().and_then(|s| {
            extract_object_field(s, "daemon_status").and_then(|o| extract_str_field(&o, "value"))
                .or_else(|| {
                    extract_object_field(s, "daemon_online").and_then(|o| extract_bool_field(&o, "value"))
                        .map(|on| if on { "READY".to_string() } else { "OFFLINE".to_string() })
                })
        });

        let virt = extract_object_field(&metrics, "virtualization");
        let virtualization = virt.as_ref().and_then(|v| {
            extract_object_field(v, "hypervisor_type").and_then(|o| extract_str_field(&o, "value"))
        });

        Ok(VitalGlanceData {
            cpu_load,
            memory_info,
            cpu_temp_celsius,
            nixos_generation,
            state_root_digest,
            daemon_status,
            virtualization,
        })
    }
}

unsafe fn libc_getuid() -> u32 {
    extern "C" {
        fn getuid() -> u32;
    }
    getuid()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::net::UnixListener;
    use std::thread;

    #[test]
    fn test_default_socket_path() {
        let p = ConductorClient::default_socket_path();
        assert!(p.to_string_lossy().contains("conductor"));
        assert!(p.to_string_lossy().ends_with(".sock"));
    }

    #[test]
    fn test_extract_helpers() {
        let raw = r#"{"lifecycle_state":"ACTIVE","gui_attached":false,"active_connections":2,"pending_proposals":1,"sub":{"nested":"ok"}}"#;
        assert_eq!(extract_str_field(raw, "lifecycle_state").as_deref(), Some("ACTIVE"));
        assert_eq!(extract_bool_field(raw, "gui_attached"), Some(false));
        assert_eq!(extract_u64_field(raw, "active_connections"), Some(2));
        assert_eq!(extract_u64_field(raw, "pending_proposals"), Some(1));
        assert_eq!(extract_object_field(raw, "sub").as_deref(), Some(r#"{"nested":"ok"}"#));
    }

    #[test]
    fn test_parse_rpc_response_success() {
        let raw = r#"{"jsonrpc":"2.0","id":1,"result":{"status":"PONG"}}"#;
        let resp = parse_rpc_response(raw).expect("parse success");
        assert_eq!(resp.id, 1);
        assert!(resp.error.is_none());
        assert_eq!(resp.result.as_deref(), Some(r#"{"status":"PONG"}"#));
    }

    #[test]
    fn test_parse_rpc_response_error() {
        let raw = r#"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}"#;
        let resp = parse_rpc_response(raw).expect("parse error");
        assert_eq!(resp.id, 2);
        assert!(resp.result.is_none());
        let err = resp.error.expect("must have error");
        assert_eq!(err.code, -32601);
        assert_eq!(err.message, "Method not found");
    }

    #[test]
    fn test_escape_json_str() {
        assert_eq!(escape_json_str("normal_str"), "normal_str");
        assert_eq!(escape_json_str("hello \"world\" \n\t\\"), "hello \\\"world\\\" \\n\\t\\\\");
    }

    #[test]
    fn test_extract_f32_field() {
        let json = r#"{"cpu_load": 0.42, "negative": -12.5}"#;
        assert_eq!(extract_f32_field(json, "cpu_load"), Some(0.42));
        assert_eq!(extract_f32_field(json, "negative"), Some(-12.5));
        assert_eq!(extract_f32_field(json, "missing"), None);
    }

    #[test]
    fn test_client_call_mock_server() {
        let temp_sock = format!("/tmp/conductor-test-mock-{}.sock", std::process::id());
        let _ = std::fs::remove_file(&temp_sock);

        let listener = UnixListener::bind(&temp_sock).expect("bind mock unix socket");

        let handle = thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                if reader.read_line(&mut line).is_ok() {
                    let req_id = extract_u64_field(&line, "id").unwrap_or(1);
                    let resp = format!("{{\"jsonrpc\":\"2.0\",\"id\":{},\"result\":{{\"status\":\"PONG\"}}}}\n", req_id);
                    let _ = stream.write_all(resp.as_bytes());
                }
            }
        });

        let client = ConductorClient::new(Some(PathBuf::from(&temp_sock)));
        let is_pong = client.ping().expect("ping mock server");
        assert!(is_pong);

        let _ = handle.join();
        let _ = std::fs::remove_file(&temp_sock);
    }

    #[test]
    fn test_get_vital_snapshot_mock() {
        let temp_sock = format!("/tmp/conductor-test-vital-{}.sock", std::process::id());
        let _ = std::fs::remove_file(&temp_sock);

        let listener = UnixListener::bind(&temp_sock).expect("bind mock unix socket");

        let handle = thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                if reader.read_line(&mut line).is_ok() {
                    let req_id = extract_u64_field(&line, "id").unwrap_or(1);
                    let resp = format!(
                        concat!(
                            "{{\"jsonrpc\":\"2.0\",\"id\":{},\"result\":{{\"metrics\":{{",
                            "\"cpu\":{{\"load_average_1m\":{{\"value\":0.25}},\"load_average_5m\":{{\"value\":0.15}},\"load_average_15m\":{{\"value\":0.10}},\"core_count\":{{\"value\":8}}}},",
                            "\"memory\":{{\"total_bytes\":{{\"value\":17179869184}},\"available_bytes\":{{\"value\":8589934592}}}},",
                            "\"thermal\":{{\"cpu_temperature\":{{\"value\":44.5}}}},",
                            "\"nixos\":{{\"active_generation\":{{\"value\":42}}}},",
                            "\"neuronix\":{{\"stateroot\":{{\"value\":\"deadbeef01234567\"}}}},",
                            "\"service\":{{\"daemon_status\":{{\"value\":\"READY\"}}}},",
                            "\"virtualization\":{{\"hypervisor_type\":{{\"value\":\"KVM_QEMU\"}}}}",
                            "}}}}}}\n"
                        ),
                        req_id
                    );
                    let _ = stream.write_all(resp.as_bytes());
                }
            }
        });

        let client = ConductorClient::new(Some(PathBuf::from(&temp_sock)));
        let vital = client.get_vital_snapshot().expect("snapshot success");
        assert_eq!(vital.cpu_load.as_deref(), Some("0.25, 0.15, 0.10 (8 cores online)"));
        assert!(vital.memory_info.as_ref().unwrap().contains("8.0 GiB / 16.0 GiB (50% utilized)"));
        assert_eq!(vital.cpu_temp_celsius, Some(44.5));
        assert_eq!(vital.nixos_generation, Some(42));
        assert_eq!(vital.state_root_digest.as_deref(), Some("deadbeef01234567"));
        assert_eq!(vital.daemon_status.as_deref(), Some("READY"));
        assert_eq!(vital.virtualization.as_deref(), Some("KVM_QEMU"));

        let _ = handle.join();
        let _ = std::fs::remove_file(&temp_sock);
    }

    #[test]
    fn test_rpc_request_to_frame() {
        let req = RpcRequest::new(42, "skills.list", "{}");
        assert_eq!(req.id, 42);
        assert_eq!(req.method, "skills.list");
        assert_eq!(req.to_frame(), "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"skills.list\",\"params\":{}}\n");
    }

    #[test]
    fn test_rpc_mismatched_id_rejection() {
        let temp_sock = format!("/tmp/conductor-test-mismatch-{}.sock", std::process::id());
        let _ = std::fs::remove_file(&temp_sock);

        let listener = UnixListener::bind(&temp_sock).expect("bind mock unix socket");

        let handle = thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                if reader.read_line(&mut line).is_ok() {
                    // Deliberately return wrong ID 99999
                    let resp = "{\"jsonrpc\":\"2.0\",\"id\":99999,\"result\":{\"status\":\"PONG\"}}\n";
                    let _ = stream.write_all(resp.as_bytes());
                }
            }
        });

        let client = ConductorClient::new(Some(PathBuf::from(&temp_sock)));
        let err = client.call("conductor.ping", "{}").expect_err("must reject mismatched id");
        assert!(err.contains("Mismatched RPC response id"));

        let _ = handle.join();
        let _ = std::fs::remove_file(&temp_sock);
    }
}

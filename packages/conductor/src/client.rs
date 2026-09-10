// ==============================================================================
// NEURONIX Conductor Control Protocol Client (UNIX Domain Socket)
// Native client communicating with conductor-runtime over JSON-RPC 2.0.
// Adheres strictly to SPEC-NRX-CND-018.
// ==============================================================================

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static REQUEST_COUNTER: AtomicU64 = AtomicU64::new(1);

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

        let request_id = REQUEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let frame = format!(
            "{{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"{}\",\"params\":{}}}\n",
            request_id, method, params_json
        );

        stream.write_all(frame.as_bytes())
            .map_err(|e| format!("Failed to write to socket: {}", e))?;
        stream.flush()
            .map_err(|e| format!("Failed to flush socket: {}", e))?;

        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line)
            .map_err(|e| format!("Failed to read response from socket: {}", e))?;

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
        let params = format!("{{\"proposal_hash\":\"{}\",\"action\":\"{}\"}}", proposal_hash, action);
        let raw = self.call("proposal.resolve", &params)?;
        let resp = parse_rpc_response(&raw)?;
        if let Some(ref err) = resp.error {
            return Err(format!("RPC error {}: {}", err.code, err.message));
        }
        resp.result.ok_or_else(|| "Missing result in proposal.resolve response".to_string())
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
    fn test_client_call_mock_server() {
        let temp_sock = format!("/tmp/conductor-test-mock-{}.sock", std::process::id());
        let _ = std::fs::remove_file(&temp_sock);

        let listener = UnixListener::bind(&temp_sock).expect("bind mock unix socket");

        let handle = thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                if reader.read_line(&mut line).is_ok() {
                    let resp = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"status\":\"PONG\"}}\n";
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
}

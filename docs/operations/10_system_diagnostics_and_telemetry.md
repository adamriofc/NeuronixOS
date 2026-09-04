# NEURONIX OS Runbook: System Diagnostics and Telemetry

## 1. Privacy-Preserving Diagnostics (Doctor)

The `neuronix doctor` command executes deep diagnostics across kernel buffers, profile generations, storage health, and systemd maintenance timers. 

All outputs undergo strict sanitization:
- Usernames and hostnames are replaced with `<sanitized-user>` and `<sanitized-host>`.
- Public and private IPv4/IPv6 addresses are redacted.
- Hardware MAC addresses are stripped.

The resulting report is safe to paste directly into public issue trackers.

## 2. Generating Markdown Reports

To generate a sanitized Markdown report:

```bash
# Writes to /tmp/neuronix-doctor.md by default
neuronix doctor

# Specify custom report path
neuronix doctor -o ~/system-diagnostic.md
```

## 3. Structured JSON Telemetry

For automated monitoring, CI gates, and third-party dashboard ingest:

```bash
# Output JSON adhering to schema_version 1.0.0
neuronix doctor --json
```

Example JSON schema:
```json
{
  "schema_version": "1.0.0",
  "health_status": "HEALTHY",
  "system": {
    "os": "NEURONIX OS 1.0.3 (NixOS Substrate)",
    "kernel": "6.18.48",
    "generation": "5",
    "total_generations": 3
  },
  "privacy": {
    "user": "<sanitized-user>",
    "network_status": "Terhubung (Online)"
  }
}
```

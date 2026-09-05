"""
Enterprise Root CA Certificate Enrollment Engine for NEURONIX OS.
Implements content-addressed storage, PEM validation, and postcondition verification.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone

def parse_cert_metadata(cert_path: str):
    """Extracts SHA-256 and basic metadata from certificate file."""
    with open(cert_path, "rb") as f:
        content = f.read()

    text = content.decode("utf-8", errors="replace")
    if "-----BEGIN CERTIFICATE-----" not in text or "-----END CERTIFICATE-----" not in text:
        return False, "Validation Error: File does not contain standard PEM X.509 certificate delimiters.", None

    sha256 = hashlib.sha256(content).hexdigest()
    subject = "Unknown Subject"
    issuer = "Unknown Issuer"

    if shutil.which("openssl"):
        try:
            subj_out = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-subject"], text=True)
            subject = subj_out.strip()
            iss_out = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-issuer"], text=True)
            issuer = iss_out.strip()
        except Exception:
            pass

    meta = {
        "source_filename": os.path.basename(cert_path),
        "sha256": sha256,
        "subject": subject,
        "issuer": issuer,
        "installed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    return True, meta, content

def enroll_certificate(cert_path: str, target_ca_dir=None, target_ssl_dir=None):
    """
    Enrolls certificate with content-addressed naming and postcondition verification.
    Returns (success: bool, return_code: int, message: str).
    """
    if not os.path.isfile(cert_path):
        return False, 1, f"Error: Certificate file '{cert_path}' not found."

    valid, meta, raw_bytes = parse_cert_metadata(cert_path)
    if not valid:
        return False, 1, meta

    sha256 = meta["sha256"]
    ca_storage_dir = target_ca_dir or "/var/lib/neuronix/ca"
    ssl_certs_dir = target_ssl_dir or "/etc/ssl/certs"

    # Idempotency check: if identical sha256 is already enrolled
    content_addressed_name = f"neuronix-ca-{sha256}.crt"
    storage_cert_path = os.path.join(ca_storage_dir, content_addressed_name)
    storage_meta_path = os.path.join(ca_storage_dir, f"neuronix-ca-{sha256}.json")

    try:
        os.makedirs(ca_storage_dir, exist_ok=True)
        with open(storage_cert_path, "wb") as f:
            f.write(raw_bytes)
        with open(storage_meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
    except PermissionError:
        return False, 13, f"Permission Denied: Unable to write to '{ca_storage_dir}' (root required)."
    except Exception as e:
        return False, 1, f"I/O Error: {e}"

    # Install into system SSL directory
    system_cert_dest = os.path.join(ssl_certs_dir, content_addressed_name)
    trust_status = "INSTALLED_NOT_TRUSTED"
    try:
        if os.path.exists(ssl_certs_dir):
            shutil.copy2(storage_cert_path, system_cert_dest)
            if shutil.which("update-ca-certificates"):
                res = subprocess.run(["update-ca-certificates"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
                if res.returncode != 0:
                    return False, res.returncode, f"Error updating CA certificates: {res.stderr}"
                trust_status = "TRUSTED"
            else:
                trust_status = "INSTALLED_NOT_TRUSTED"
    except PermissionError:
        return False, 13, f"Permission Denied: Unable to write to '{ssl_certs_dir}' (root required)."
    except Exception as e:
        return False, 1, f"Installation Error: {e}"

    # Postcondition Verification
    if os.path.exists(ssl_certs_dir) and not os.path.exists(system_cert_dest):
        return False, 1, f"Postcondition Verification Failed: '{system_cert_dest}' not found after installation."

    return True, 0, f"APPLIED: Enrolled certificate {meta['source_filename']} [Trust: {trust_status}] (SHA-256: {sha256[:16]}...) successfully."

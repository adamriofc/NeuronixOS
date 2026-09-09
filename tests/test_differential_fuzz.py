#!/usr/bin/env python3
"""
NEURONIX OS Differential Fuzzing Engine
Performs automated differential testing between Python RFC 8785 JCS,
Node.js ECMAScript standard reference, and Rust daemon StateRoot leaves.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import random
import subprocess
import hashlib
from typing import Any

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "packages/neuronix-core"))

from neuronix_core.state import canonical_json_bytes, ProvableStateEngine

REGRESSION_CORPUS_FILE = os.path.join(PROJECT_ROOT, "tests/corpus/differential_fuzz_regressions.json")

def generate_random_value(depth: int = 0) -> Any:
    if depth > 3:
        choices = [0, 1, -1, 100.0, -0.0, 1e-6, 1e-7, 1e20, 1e21, "café", "hello\nworld\t", True, False, None]
        return random.choice(choices)

    t = random.randint(1, 6)
    if t == 1:
        # dict
        k_count = random.randint(1, 5)
        keys = ["alpha", "beta", "gamma", "a", "b", "aa", "z", "A", "Z", "café", "key_1"]
        return {random.choice(keys): generate_random_value(depth + 1) for _ in range(k_count)}
    elif t == 2:
        # list
        l_count = random.randint(1, 4)
        return [generate_random_value(depth + 1) for _ in range(l_count)]
    elif t == 3:
        # numbers
        num_type = random.randint(1, 7)
        if num_type == 1: return -0.0
        if num_type == 2: return 0.0
        if num_type == 3: return 100.0
        if num_type == 4: return 1e-6
        if num_type == 5: return 1e-7
        if num_type == 6: return 1e20
        if num_type == 7: return 1e21
        return random.uniform(-1000, 1000)
    elif t == 4:
        # string
        s_type = random.randint(1, 4)
        if s_type == 1: return "plain string"
        if s_type == 2: return "escapes: \" \\ \b \f \n \r \t"
        if s_type == 3: return "unicode: café 🎉 日本語"
        return "mixed: \u0001 \u001f raw"
    elif t == 5:
        return random.choice([True, False])
    else:
        return None

def node_canonical_serialize(obj: Any) -> bytes:
    js_code = """
    const fs = require('fs');
    const input = JSON.parse(fs.readFileSync(0, 'utf-8'));

    function canonicalize(data) {
        if (data === null || typeof data !== 'object') {
            if (typeof data === 'number') {
                if (Object.is(data, -0)) return '0';
                return Number(data).toString();
            }
            return JSON.stringify(data);
        }
        if (Array.isArray(data)) {
            const elements = data.map(x => canonicalize(x) ?? 'null');
            return '[' + elements.join(',') + ']';
        }
        const keys = Object.keys(data).sort();
        const entries = [];
        for (const k of keys) {
            const v = data[k];
            if (v !== undefined) {
                entries.push(JSON.stringify(k) + ':' + canonicalize(v));
            }
        }
        return '{' + entries.join(',') + '}';
    }
    process.stdout.write(canonicalize(input));
    """
    proc = subprocess.run(["node", "-e", js_code], input=json.dumps(obj).encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return proc.stdout

def run_differential_fuzz(iterations: int = 500) -> int:
    print(f"[DIFFERENTIAL-FUZZ] Starting {iterations} differential test iterations between Python and Node.js...")
    failures = []
    
    random.seed(42) # Deterministic pseudo-random sequence
    
    for i in range(1, iterations + 1):
        obj = generate_random_value(depth=0)
        try:
            py_bytes = canonical_json_bytes(obj)
            node_bytes = node_canonical_serialize(obj)

            if py_bytes != node_bytes:
                print(f"  [MISMATCH at iter {i}]")
                print(f"    Py:   {py_bytes}")
                print(f"    Node: {node_bytes}")
                failures.append({
                    "iteration": i,
                    "object": obj,
                    "python_hex": py_bytes.hex(),
                    "node_hex": node_bytes.hex()
                })
        except Exception as e:
            failures.append({
                "iteration": i,
                "object": obj,
                "error": str(e)
            })

    if failures:
        print(f"[FAIL] {len(failures)} mismatches encountered out of {iterations}!")
        os.makedirs(os.path.dirname(REGRESSION_CORPUS_FILE), exist_ok=True)
        with open(REGRESSION_CORPUS_FILE, "w", encoding="utf-8") as f:
            json.dump({"regressions": failures}, f, indent=2)
        return 1

    print(f"[SUCCESS] 100% Differential Parity achieved across all {iterations} iterations (0 mismatches)")

    # Test StateRoot Parity against Rust daemon
    daemon_bin = os.path.join(PROJECT_ROOT, "packages/neuronix-daemon/target/release/neuronix-daemon")
    if os.path.exists(daemon_bin):
        print("[DIFFERENTIAL-FUZZ] Verifying Cross-Language StateRoot leaf parity with Rust daemon...")
        engine = ProvableStateEngine()
        py_state = engine.build_state(event="DAEMON_INSPECTION")
        
        proc = subprocess.run([daemon_bin, "--state"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        rust_state = json.loads(proc.stdout)
        
        py_root = py_state.get("state_root", "")
        rust_root = rust_state.get("state_root", "")
        assert py_root == rust_root, f"Cross-language StateRoot mismatch: Python {py_root} != Rust {rust_root}"
        
        for leaf in ["posture", "substrate", "provenance", "policy", "evidence"]:
            py_leaf_hash = py_state.get("leaf_hashes", {}).get(f"{leaf}_hash")
            rust_leaf_hash = rust_state.get("leaf_hashes", {}).get(f"{leaf}_hash")
            assert py_leaf_hash == rust_leaf_hash, f"Leaf '{leaf}' hash mismatch: Python {py_leaf_hash} != Rust {rust_leaf_hash}"
            
        print(f"  ✔ Bit-exact StateRoot verified: {py_root}")
        print("  ✔ All 5 Merkle leaves match bit-for-bit with Rust daemon")

    return 0

if __name__ == "__main__":
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    sys.exit(run_differential_fuzz(iterations=count))

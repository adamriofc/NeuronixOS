## NEURONIX OS v{VERSION} Release Notes

### Highlights
- Comprehensive release assurance with mathematically verifiable state lineage
- Continuous industrial quality gates across 32 QA master suites and 1,384 assertions
- Provable Adaptive Execution Architecture (Project Hyperion) and Universal Execution Fabric

### New Features & Enhancements
- 

### Security & Integrity Updates
- 

### Bug Fixes
- 

### Cryptographic Proof-Carrying Artifacts
This official release bundle includes authoritative supply-chain attestations:
- `neuronix-os-v{VERSION}.proof.json`: Cryptographic release proof bundle
- `verification-passport.json`: Standalone offline verification passport
- `evidence-graph.json`: Complete 10-node authoritative evidence lineage graph
- `SHA256SUMS`: Checksum manifest for all distribution assets
- `SHA256SUMS.sig`: Authentic Ed25519 digital signature
- `neuronix-os-v{VERSION}-sbom.spdx.json`: Software Bill of Materials in SPDX format

### Verification
Verify release authenticity offline without network dependencies:
```bash
# Verify cryptographic passport and Merkle StateRoot
neuronix verify-passport dist/verification-passport.json

# Trace evidence graph DAG continuity
neuronix graph --trace dist/evidence-graph.json
```

### Upgrade Instructions
```bash
# Upgrade active system generation
neuronix upgrade

# Or rebuild declaratively via Nix Flakes
sudo nixos-rebuild switch --flake .#neuronix-desktop
```

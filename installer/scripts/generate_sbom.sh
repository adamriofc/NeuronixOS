#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS SPDX 2.3 Software Bill of Materials (SBOM) Generator
# Generates canonical machine-readable SBOM for release artifacts.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

TAG="${1:-v1.0.3}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
OUTPUT_FILE="${DIST_DIR}/neuronix-os-${TAG}-sbom.spdx.json"

mkdir -p "${DIST_DIR}"

cat << EOF > "${OUTPUT_FILE}"
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "neuronix-os-${TAG}",
  "documentNamespace": "https://github.com/adamriofc/neuronix/releases/tag/${TAG}/sbom.spdx.json",
  "creationInfo": {
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "creators": [
      "Tool: neuronix-sbom-generator-1.0.3",
      "Organization: NEURONIX OS Maintainers"
    ]
  },
  "packages": [
    {
      "SPDXID": "SPDXRef-Package-neuronix-substrate",
      "name": "neuronix-substrate",
      "versionInfo": "${TAG}",
      "downloadLocation": "git+https://github.com/adamriofc/neuronix.git@${TAG}",
      "licenseConcluded": "Apache-2.0",
      "licenseDeclared": "Apache-2.0",
      "copyrightText": "Copyright (c) 2026 NEURONIX Contributors",
      "supplier": "Organization: NEURONIX OS Maintainers"
    },
    {
      "SPDXID": "SPDXRef-Package-nixpkgs",
      "name": "nixpkgs",
      "versionInfo": "26.05-pre (3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2)",
      "downloadLocation": "git+https://github.com/NixOS/nixpkgs.git@3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2",
      "licenseConcluded": "MIT",
      "licenseDeclared": "MIT",
      "supplier": "Organization: NixOS Foundation"
    },
    {
      "SPDXID": "SPDXRef-Package-opencode",
      "name": "opencode",
      "versionInfo": "1.0.3",
      "downloadLocation": "https://github.com/adamriofc/neuronix",
      "licenseConcluded": "Apache-2.0",
      "licenseDeclared": "Apache-2.0",
      "supplier": "Organization: NEURONIX OS Maintainers"
    },
    {
      "SPDXID": "SPDXRef-Package-neuronix-center",
      "name": "neuronix-center",
      "versionInfo": "1.0.3",
      "downloadLocation": "https://github.com/adamriofc/neuronix",
      "licenseConcluded": "Apache-2.0",
      "licenseDeclared": "Apache-2.0",
      "supplier": "Organization: NEURONIX OS Maintainers"
    },
    {
      "SPDXID": "SPDXRef-Package-neuronix-core",
      "name": "neuronix-core",
      "versionInfo": "1.0.3",
      "downloadLocation": "https://github.com/adamriofc/neuronix",
      "licenseConcluded": "Apache-2.0",
      "licenseDeclared": "Apache-2.0",
      "supplier": "Organization: NEURONIX OS Maintainers"
    }
  ]
}
EOF

echo "Generated SPDX 2.3 SBOM at: ${OUTPUT_FILE}"

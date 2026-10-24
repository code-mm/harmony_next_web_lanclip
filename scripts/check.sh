#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cli="${DEVECOCLI:-devecocli}"
node --disable-warning=ExperimentalWarning --test tests/policy.test.mjs
"$cli" check arkts
mkdir -p build/checks
lint_report="build/checks/lint-$(date -u +%Y%m%dT%H%M%SZ).json"
"$cli" check lint --format json --output-path "$lint_report"
"$cli" build --assemble-type assembleHap

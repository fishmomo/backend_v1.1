#!/usr/bin/env bash
# Build a deployable source tarball for backend-v1.
#
# Usage:
#   ./scripts/build.sh [version-tag]
#
# Produces:
#   dist/backend-v1-<tag>.tar.gz
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TAG="${1:-$(date +%Y%m%d-%H%M)}"
python3 scripts/package_release.py "$TAG"

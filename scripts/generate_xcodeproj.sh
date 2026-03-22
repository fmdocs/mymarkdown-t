#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required to generate MyMarkdownT.xcodeproj" >&2
    echo "install it with: brew install xcodegen" >&2
    exit 1
fi

cd "$repo_root"
xcodegen generate
echo "Generated $repo_root/MyMarkdownT.xcodeproj"

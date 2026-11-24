#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/tests/lib.sh"
load_functions ensure_chromium_deps
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
YELLOW='' GREEN='' NC=''
step() { printf '%s\n' "$*"; }
export PLAYWRIGHT_BROWSERS_PATH="$test_dir/browsers"
bin="$PLAYWRIGHT_BROWSERS_PATH/chromium_headless_shell-1/chrome-headless-shell-linux64/chrome-headless-shell"
mkdir -p "$(dirname "$bin")"
printf '#!/bin/sh\n' > "$bin"
chmod +x "$bin"
npx() { echo npx-called >> "$test_dir/npx.log"; }

# 라이브러리가 모두 있으면 아무것도 하지 않는다.
ldd() { echo "libc.so.6 => /lib/libc.so.6"; }
test -z "$(ensure_chromium_deps 2>&1)"

# 누락이 있으면 누락 목록을 보여 준다. 터미널이 아니면 설치하지 않고 수동 명령을 안내한다.
ldd() { printf '\tlibnss3.so => not found\n\tlibnspr4.so => not found\n'; }
out="$(ensure_chromium_deps </dev/null 2>&1)"
[[ "$out" == *"누락: libnspr4.so libnss3.so)"* ]]
[[ "$out" == *"npx -y playwright install-deps chromium"* ]]
test ! -e "$test_dir/npx.log"

# PLAYWRIGHT_BROWSERS_PATH가 없으면 XDG_CACHE_HOME 아래 캐시를 본다(arm64 배치 chrome-linux 포함).
unset PLAYWRIGHT_BROWSERS_PATH
export XDG_CACHE_HOME="$test_dir/xdg"
arm="$XDG_CACHE_HOME/ms-playwright/chromium-2/chrome-linux/chrome"
mkdir -p "$(dirname "$arm")"
printf '#!/bin/sh\n' > "$arm"
chmod +x "$arm"
out="$(ensure_chromium_deps </dev/null 2>&1)"
[[ "$out" == *"누락: libnspr4.so libnss3.so)"* ]]

# 캐시에 브라우저가 없으면 아무것도 하지 않는다.
export XDG_CACHE_HOME="$test_dir/empty"
test -z "$(ensure_chromium_deps 2>&1)"

echo "chromium_deps_test: ok"

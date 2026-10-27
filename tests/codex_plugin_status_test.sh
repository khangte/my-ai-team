#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$repo_dir/setup-team.sh" "$repo_dir/team/config.codex.sh"
eval "$(sed -n '/^write_codex_role_plugins() {$/,/^}$/p; /^prepare_codex_role_home() {$/,/^}$/p' "$repo_dir/setup-team.sh")"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
base_codex_home="$test_dir/base"
YELLOW='' NC=''
declare -A CODEX_PLUGIN_ROLES=([sample@local]='developer')
mkdir -p "$base_codex_home/plugins/cache/local/sample/1.0/.codex-plugin"
printf '{}\n' > "$base_codex_home/plugins/cache/local/sample/1.0/.codex-plugin/plugin.json"

codex() {
    # 실제 설치 없이 인증·설치 호출을 기록하고 실패를 재현한다.
    printf '%s %s\n' "$CODEX_HOME" "$*" >> "$test_dir/calls"
    if [ "$1 $2" = 'plugin add' ]; then
        return "${install_exit:-0}"
    fi
}

output="$(prepare_codex_role_home developer "$test_dir/installed")"
[[ "$output" == *'ℹ️  sample@local 로컬에 이미 설치됨 → developer'* ]]
grep -qF "$test_dir/installed plugin add sample@local" "$test_dir/calls"

# 다른 마켓플레이스의 캐시와 빈 캐시는 설치로 표시하지 않는다.
CODEX_PLUGIN_ROLES=([sample@other]='developer')
mkdir -p "$base_codex_home/plugins/cache/other/sample"
output="$(prepare_codex_role_home developer "$test_dir/new")"
[[ "$output" == *'✅  sample@other 새로 설치됨 → developer'* ]]

CODEX_PLUGIN_ROLES=([sample@local]='developer')
install_exit=1
output="$(prepare_codex_role_home developer "$test_dir/failed" 2>&1)"
[[ "$output" == *'Codex 플러그인 설치 실패: sample@local'* ]]
[[ "$output" != *'✅'* ]]
printf 'Codex 플러그인 설치 상태 표시 테스트 통과\n'

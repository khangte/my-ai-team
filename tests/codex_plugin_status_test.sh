#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$repo_dir/setup-team.sh" "$repo_dir/team/config.codex.sh"
eval "$(sed -n '/^role_in() {$/,/^}$/p; /^codex_default_model_config() {$/,/^}$/p; /^write_codex_role_plugins() {$/,/^}$/p; /^codex_plugin_cache() {$/,/^}$/p; /^codex_shared_plugin_cache() {$/,/^}$/p; /^link_codex_base_assets() {$/,/^}$/p; /^prepare_codex_role_home() {$/,/^}$/p' "$repo_dir/setup-team.sh")"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
base_codex_home="$test_dir/base"; codex_assets_home="$test_dir/assets"; TEAM_SKILLS_ROOT="$test_dir/team"
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

# 기본 홈에 설치돼 있으면 다시 내려받지 않고(설치 명령 없음) 역할 홈에 연결한다.
: > "$test_dir/calls"
output="$(prepare_codex_role_home developer "$test_dir/installed")"
[[ "$output" == *'ℹ️  sample@local 로컬에 이미 설치됨(다른 홈 설치본 재사용) → developer'* ]]
! grep -qF 'plugin add' "$test_dir/calls"
codex_plugin_cache "$test_dir/installed" sample@local >/dev/null

# 역할 홈을 재사용하는 재실행도 설치 명령이 없다.
output="$(prepare_codex_role_home developer "$test_dir/installed")"
[[ "$output" == *'ℹ️  sample@local 이미 설치됨 → developer'* ]]
! grep -qF 'plugin add' "$test_dir/calls"

# 다른 마켓플레이스의 캐시와 빈 캐시는 설치로 표시하지 않고 새로 설치한다.
CODEX_PLUGIN_ROLES=([sample@other]='developer')
mkdir -p "$base_codex_home/plugins/cache/other/sample"
output="$(prepare_codex_role_home developer "$test_dir/new")"
[[ "$output" == *'✅  sample@other 새로 설치됨 → developer'* ]]
grep -qF "$test_dir/new plugin add sample@other" "$test_dir/calls"

CODEX_PLUGIN_ROLES=([sample@missing]='developer')
install_exit=1
output="$(prepare_codex_role_home developer "$test_dir/failed" 2>&1)"
[[ "$output" == *'Codex 플러그인 설치 실패: sample@missing'* ]]
[[ "$output" != *'✅'* ]]
printf 'Codex 플러그인 설치 상태 표시 테스트 통과\n'

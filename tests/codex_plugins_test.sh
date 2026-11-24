#!/bin/bash
# Codex 역할 홈의 플러그인 설치 상태 표시와 역할별 config.toml 내용을 검증한다.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$repo_dir/setup-team.sh" "$repo_dir/team/config.codex.sh"
source "$repo_dir/tests/lib.sh"
load_functions role_in write_codex_role_plugins codex_plugin_cache codex_plugin_source \
    link_codex_base_assets prepare_codex_role_home
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

# ── 역할별 config.toml: 저장소 배분표대로 플러그인·Playwright MCP를 켠다 ──
# 앞 절의 모의 배분표가 섞이지 않게 서브셸에서 실제 구성 파일만 읽는다.
(
    unset CODEX_PLUGIN_ROLES
    source "$repo_dir/team/config.codex.sh"
    base_codex_home="$test_dir/no-base"   # 상속할 기본 설정 없음
    write_codex_role_plugins backend "$test_dir/backend"
    write_codex_role_plugins frontend "$test_dir/frontend"
    write_codex_role_plugins uiux "$test_dir/uiux"
    write_codex_role_plugins reviewer "$test_dir/reviewer"
    CODEX_PLUGIN_ROLES['test@local']='*'
    CODEX_PLUGIN_ROLES['shared@local']='backend reviewer'
    write_codex_role_plugins reviewer "$test_dir/shared"
    CODEX_PLUGIN_ROLES['shared@local']=''
    write_codex_role_plugins reviewer "$test_dir/disabled"

    python3 - "$test_dir" <<'PY'
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
expected = {
    'backend': {'engineering-suite-ponytail@openai-curated-remote', 'caveman@openai-curated-remote'},
    'frontend': {'engineering-suite-ponytail@openai-curated-remote', 'caveman@openai-curated-remote'},
    'uiux': {'product-design@openai-curated-remote', 'open-design@openai-curated-remote', 'caveman@openai-curated-remote'},
    'reviewer': {'caveman@openai-curated-remote'},
    'shared': {'caveman@openai-curated-remote', 'test@local', 'shared@local'},
    'disabled': {'caveman@openai-curated-remote', 'test@local'},
}
for role, allowed in expected.items():
    config = tomllib.loads((root / role / 'config.toml').read_text())['plugins']
    assert config.pop('_default') == {'enabled': False}
    assert set(config) == allowed, (role, config)
    assert all(item == {'enabled': True} for item in config.values())
for role, assigned in {'frontend': True, 'uiux': True, 'backend': False, 'reviewer': False}.items():
    servers = tomllib.loads((root / role / 'config.toml').read_text()).get('mcp_servers', {})
    assert ('playwright' in servers) == assigned, (role, servers)
    if assigned:
        assert servers['playwright']['command'] == 'npx'
        assert servers['playwright']['args'] == ['-y', '@playwright/mcp@latest']
        assert servers['playwright']['env'] == {'PLAYWRIGHT_MCP_HEADLESS': 'true', 'PLAYWRIGHT_MCP_BROWSER': 'chromium'}
PY
)

printf 'Codex 역할별 플러그인 설정·설치 상태 테스트 통과\n'

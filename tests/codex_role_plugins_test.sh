#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/team/config.codex.sh"
eval "$(sed -n '/^role_in() {$/,/^}$/p; /^codex_default_model_config() {$/,/^}$/p; /^write_codex_role_plugins() {$/,/^}$/p' "$repo_dir/setup-team.sh")"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

write_codex_role_plugins developer "$test_dir/developer"
write_codex_role_plugins reviewer "$test_dir/reviewer"
CODEX_PLUGIN_ROLES['test@local']='*'
CODEX_PLUGIN_ROLES['shared@local']='developer reviewer'
write_codex_role_plugins reviewer "$test_dir/shared"
CODEX_PLUGIN_ROLES['shared@local']=''
write_codex_role_plugins reviewer "$test_dir/disabled"

python3 - "$test_dir" <<'PY'
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
expected = {
    'developer': {'engineering-suite-ponytail@openai-curated-remote', 'caveman@openai-curated-remote'},
    'reviewer': {'caveman@openai-curated-remote'},
    'shared': {'caveman@openai-curated-remote', 'test@local', 'shared@local'},
    'disabled': {'caveman@openai-curated-remote', 'test@local'},
}
for role, allowed in expected.items():
    config = tomllib.loads((root / role / 'config.toml').read_text())['plugins']
    assert config.pop('_default') == {'enabled': False}
    assert set(config) == allowed, (role, config)
    assert all(item == {'enabled': True} for item in config.values())
print('Codex 역할별 플러그인 설정 테스트 통과')
PY

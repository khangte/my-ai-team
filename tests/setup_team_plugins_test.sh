#!/bin/bash
# setup-team.sh의 플러그인 설치 판별·.team 재사용·기동 대기를 모의 CLI로 검증한다.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_dir/setup-team.sh"
bash -n "$script"

# 함수 본문만 꺼내 쓴다(스크립트 전체를 실행하지 않는다).
load_functions() {
    local name
    for name in "$@"; do
        eval "$(sed -n "/^${name}() {\$/,/^}\$/p" "$script")"
    done
}
load_functions codex_default_model_config plugin_skill_set provider_plugin_needed claude_plugin_dir codex_plugin_cache \
    install_claude_plugins link_plugin_skills reset_generated_team_files \
    link_codex_base_assets prepare_codex_role_home codex_plugin_skills_root \
    prepare_codex_skill_sources codex_shared_plugin_cache link_codex_standalone_skills find_codex_skill_source write_codex_role_plugins answer_claude_dialog \
    wait_claude_ready wait_for_pane start_codex_in_pane team_owned_record team_owned_clean \
    link_owned_skill json_escape stop_hook_cmd_for_role write_codex_role_agents shell_quote \
    start_claude_in_pane

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
YELLOW='' RED='' GREEN='' NC=''
sleep() { :; }
fail() { printf '실패: %s\n' "$*" >&2; exit 1; }
expect_in() { [[ "$2" == *"$1"* ]] || fail "'$1' 없음 in: $2"; }
expect_not_in() { [[ "$2" != *"$1"* ]] || fail "'$1' 있음 in: $2"; }

# ── Claude: 필요 여부·설치 판별 ─────────────────────────────────
export HOME="$test_dir/home"
plugins_dir="$HOME/.claude/plugins"
mkdir -p "$plugins_dir"
make_claude_install() { # <plugin@mp> <dir>
    mkdir -p "$2/.claude-plugin"
    : > "$2/.claude-plugin/plugin.json"
    python3 - "$plugins_dir/installed_plugins.json" "$1" "$2" <<'PY'
import json, os, sys
path, key, install = sys.argv[1:]
data = json.load(open(path)) if os.path.exists(path) else {"version": 2, "plugins": {}}
data["plugins"][key] = [{"scope": "user", "installPath": install}]
json.dump(data, open(path, "w"))
PY
}
# ponytail은 설치돼 있고, superpowers는 다른 마켓플레이스에만 있다(빈 캐시 디렉터리 포함).
make_claude_install ponytail@ponytail "$plugins_dir/cache/ponytail/ponytail/1"
make_claude_install superpowers@anthropic-plugin-directory "$plugins_dir/cache/anthropic-plugin-directory/superpowers/1"
mkdir -p "$plugins_dir/cache/claude-plugins-official/superpowers"

declare -A CLAUDE_PLUGIN_MARKETPLACES=(
    [claude-plugins-official]=anthropics/claude-plugins-official
    [ponytail]=DietrichGebert/ponytail
    [caveman]=JuliusBrussee/caveman
)
declare -A CLAUDE_PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
    ["serena@claude-plugins-official"]="*"
    ["ponytail@ponytail"]="developer"
    ["caveman@caveman"]="lead"
)
declare -A CLAUDE_SUPERPOWERS_SKILL_SETS=([lead]="finishing-a-development-branch" [developer]="")

claude() { printf 'claude %s\n' "$*" >> "$test_dir/claude_calls"; }

# developer가 Codex면 Claude의 developer 전용 ponytail은 설치된 표시만 하고 명령은 없다.
PANE_COUNT=2 MEMBER_NAMES=(lead developer) MEMBER_AGENTS=(claude codex)
: > "$test_dir/claude_calls"
output="$(install_claude_plugins)"
expect_in "ℹ️  ponytail@ponytail 이미 설치됨" "$output"
expect_in "✅  serena@claude-plugins-official 새로 설치됨" "$output"
expect_in "✅  caveman@caveman 새로 설치됨" "$output"
# 다른 마켓플레이스의 동명 superpowers와 빈 캐시는 설치로 오인하지 않는다.
expect_in "✅  superpowers@claude-plugins-official 새로 설치됨" "$output"
calls="$(cat "$test_dir/claude_calls")"
expect_in "claude plugin install serena@claude-plugins-official" "$calls"
expect_not_in "install ponytail@ponytail" "$calls"
# 마켓플레이스 등록은 새로 설치할 플러그인의 것만 한다(ponytail 제외).
expect_in "marketplace add anthropics/claude-plugins-official" "$calls"
expect_in "marketplace add JuliusBrussee/caveman" "$calls"
expect_not_in "DietrichGebert/ponytail" "$calls"

# 필요 없고 설치도 안 된 것은 건너뛴다: lead만 Claude이고 developer 전용 플러그인이 미설치.
rm "$plugins_dir/installed_plugins.json"
make_claude_install superpowers@anthropic-plugin-directory "$plugins_dir/cache/x/superpowers/1"
: > "$test_dir/claude_calls"
output="$(install_claude_plugins)"
expect_in "⏭️  ponytail@ponytail 건너뜀" "$output"
expect_not_in "install ponytail@ponytail" "$(cat "$test_dir/claude_calls")"
expect_not_in "DietrichGebert/ponytail" "$(cat "$test_dir/claude_calls")"

# developer가 Claude면 developer 전용 ponytail을 새로 설치한다.
MEMBER_AGENTS=(claude claude)
: > "$test_dir/claude_calls"
output="$(install_claude_plugins)"
expect_in "✅  ponytail@ponytail 새로 설치됨 → developer" "$output"

# 선택 스킬 원본만 필요한 플러그인(활성화 역할 없음)도 설치 대상이다.
provider_plugin_needed claude superpowers@claude-plugins-official || fail 'superpowers 원본 필요'
CLAUDE_SUPERPOWERS_SKILL_SETS=([lead]="" [developer]="")
! provider_plugin_needed claude superpowers@claude-plugins-official || fail 'superpowers 불필요'

# 설치 실패는 성공으로 표시하지 않는다.
claude() { return 1; }
output="$(install_claude_plugins)"
expect_in "설치 실패" "$output"
expect_not_in "✅  serena" "$output"

# ── .team 재사용: 도구 소유 생성물만 지우고 사용자 항목은 보존 ───────
TEAM_SKILLS_ROOT="$test_dir/team" RUNTIME_DIR="$test_dir/team/_runtime"
BIN_DIR="$test_dir/bin" PROJECT_DIR="$test_dir/project" TEAM_DIR="$test_dir/teamdir" SESSION=s
mkdir -p "$TEAM_SKILLS_ROOT"/{dev/.codex-home/plugins/cache,dev/.agents/skills,dev/.codex,rev/.claude/skills,_runtime,_assets} "$PROJECT_DIR/team" "$test_dir/src/tool-skill" "$test_dir/src/other"
: > "$TEAM_SKILLS_ROOT/dev/.codex-home/plugins/cache/keep"
: > "$TEAM_SKILLS_ROOT/_runtime/old.prompt.md"
: > "$TEAM_SKILLS_ROOT/_assets/keep"
printf '# Generated by ai-setup. Edit team/{role}.md instead.\nold\n' > "$TEAM_SKILLS_ROOT/dev/AGENTS.md"
printf 'user\n' > "$TEAM_SKILLS_ROOT/rev/AGENTS.md"
: > "$TEAM_SKILLS_ROOT/dev/.agents/skills/user-file"

# 소유 기록이 없는 기존 .team/: 사용자 링크·hooks.json·AGENTS.md는 모두 보존한다.
ln -s "$test_dir/src/other" "$TEAM_SKILLS_ROOT/dev/.agents/skills/my-skill"
ln -s "$test_dir/src/other" "$TEAM_SKILLS_ROOT/rev/.claude/skills/my-claude-skill"
printf '{"hooks":"mine"}' > "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
reset_generated_team_files
[ ! -e "$TEAM_SKILLS_ROOT/_runtime" ] || fail '_runtime 남음'
[ -f "$TEAM_SKILLS_ROOT/dev/AGENTS.md" ] || fail '기록 없는 표지 AGENTS.md가 표지만 보고 삭제됨'
[ -L "$TEAM_SKILLS_ROOT/dev/.agents/skills/my-skill" ] || fail '사용자 .agents 링크 삭제됨'
[ -L "$TEAM_SKILLS_ROOT/rev/.claude/skills/my-claude-skill" ] || fail '사용자 .claude 링크 삭제됨'
[ "$(cat "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")" = '{"hooks":"mine"}' ] || fail '사용자 hooks.json 변경됨'
[ -e "$TEAM_SKILLS_ROOT/dev/.agents/skills/user-file" ] || fail '사용자 파일 삭제됨'
[ -e "$TEAM_SKILLS_ROOT/dev/.codex-home/plugins/cache/keep" ] || fail 'Codex 홈 캐시 삭제됨'
[ -e "$TEAM_SKILLS_ROOT/_assets/keep" ] || fail '자산 홈 삭제됨'
[ "$(cat "$TEAM_SKILLS_ROOT/rev/AGENTS.md")" = user ] || fail '사용자 AGENTS.md 변경됨'

# 소유 기록이 없는 hooks.json은 log-hook 경로가 들어 있어도 내용으로 추정해 지우지 않는다.
printf '{"x":"%s/log-hook dev"}' "$BIN_DIR" > "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
reset_generated_team_files
[ "$(cat "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")" = "{\"x\":\"$BIN_DIR/log-hook dev\"}" ] || fail '기록 없는 옛 hooks.json 삭제됨'
rm "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"

# 재실행 경로: 사용자 항목과 같은 경로는 덮어쓰지 않고, 빈 경로는 만들어 소유 기록에 남긴다.
role=dev role_skills_dir="$TEAM_SKILLS_ROOT/dev/.agents/skills" granted=()
mkdir -p "$test_dir/plug/mine" "$test_dir/plug/tool-skill" "$test_dir/plug/other-skill"
: > "$test_dir/plug/mine/SKILL.md"; : > "$test_dir/plug/tool-skill/SKILL.md"; : > "$test_dir/plug/other-skill/SKILL.md"
ln -s "$test_dir/src/other" "$role_skills_dir/mine"            # 사용자 링크와 경로 충돌
mkdir -p "$role_skills_dir/other-skill"                        # 사용자 디렉터리와 경로 충돌
output="$(link_plugin_skills plug "$test_dir/plug" mine tool-skill other-skill 2>&1)"
expect_in "'.agents/skills/mine'에 기존 항목이 있어 덮어쓰지 않습니다" "$output"
expect_in "'.agents/skills/other-skill'에 기존 항목이 있어 덮어쓰지 않습니다" "$output"
link_plugin_skills plug "$test_dir/plug" mine tool-skill other-skill 2>/dev/null
[ "$(readlink "$role_skills_dir/mine")" = "$test_dir/src/other" ] || fail '충돌한 사용자 링크가 바뀜'
[ -d "$role_skills_dir/other-skill" ] && [ ! -L "$role_skills_dir/other-skill" ] || fail '충돌한 사용자 디렉터리가 바뀜'
[ "$(readlink "$role_skills_dir/tool-skill")" = "$test_dir/plug/tool-skill" ] || fail '도구 스킬 링크 미생성'
grep -qP '^L\t\.agents/skills/tool-skill\t' "$TEAM_SKILLS_ROOT/dev/.ai-setup-owned" || fail '소유 기록 누락'
! grep -q 'mine\|other-skill' "$TEAM_SKILLS_ROOT/dev/.ai-setup-owned" || fail '사용자 항목이 소유 기록에 들어감'

# standalone 스킬도 같은 규칙: 점유된 경로는 보존, 새 링크는 기록, 구성에서 빠지면 정리.
mkdir -p "$PROJECT_DIR/.agents/skills/solo" "$PROJECT_DIR/.agents/skills/taken" "$PROJECT_DIR/.agents/skills/dirtaken"
: > "$PROJECT_DIR/.agents/skills/solo/SKILL.md"; : > "$PROJECT_DIR/.agents/skills/taken/SKILL.md"; : > "$PROJECT_DIR/.agents/skills/dirtaken/SKILL.md"
declare -A CODEX_SKILL_SETS=([sa]="solo taken dirtaken nope")
role=sa role_skills_dir="$TEAM_SKILLS_ROOT/sa/.agents/skills" granted=()
rm -rf "$role_skills_dir"; mkdir -p "$role_skills_dir/dirtaken"
ln -s "$test_dir/src/other" "$role_skills_dir/taken"
output="$(link_codex_standalone_skills 2>&1)"
expect_in "'.agents/skills/taken'에 기존 항목이 있어 덮어쓰지 않습니다" "$output"
expect_in "'.agents/skills/dirtaken'에 기존 항목이 있어 덮어쓰지 않습니다" "$output"
expect_in "Codex 스킬 'nope' 없음" "$output"
link_codex_standalone_skills 2>/dev/null
[ "$(readlink "$role_skills_dir/taken")" = "$test_dir/src/other" ] || fail 'standalone이 사용자 링크를 덮어씀'
[ -d "$role_skills_dir/dirtaken" ] && [ ! -L "$role_skills_dir/dirtaken" ] || fail 'standalone이 사용자 디렉터리를 바꿈'
[ "$(readlink "$role_skills_dir/solo")" = "$(realpath "$PROJECT_DIR/.agents/skills/solo")" ] || fail 'standalone 링크 미생성'
grep -qP '^L\t\.agents/skills/solo\t' "$TEAM_SKILLS_ROOT/sa/.ai-setup-owned" || fail 'standalone 소유 기록 누락'
! grep -q 'taken' "$TEAM_SKILLS_ROOT/sa/.ai-setup-owned" || fail '사용자 항목이 소유 기록에 들어감'
CODEX_SKILL_SETS=([sa]="")
reset_generated_team_files
[ ! -L "$role_skills_dir/solo" ] || fail '구성에서 빠진 standalone 링크 남음'
[ -L "$role_skills_dir/taken" ] && [ -d "$role_skills_dir/dirtaken" ] || fail '정리 중 사용자 항목 삭제됨'
role=dev role_skills_dir="$TEAM_SKILLS_ROOT/dev/.agents/skills"

# Codex hooks.json: 새로 만들면 소유 기록에 남고, 구성에서 빠지면 다음 실행에서 지워진다.
mkdir -p "$TEAM_DIR"
printf '# role\n' > "$TEAM_DIR/dev.md"
MEMBER_NAMES=(lead dev)
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
[ -f "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json" ] || fail 'hooks.json 미생성'
grep -qP '^F\t\.codex/hooks.json\t' "$TEAM_SKILLS_ROOT/dev/.ai-setup-owned" || fail 'hooks.json 소유 기록 누락'
reset_generated_team_files
[ ! -e "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json" ] || fail '구성에서 빠진 도구 hooks.json 남음'
[ ! -L "$role_skills_dir/tool-skill" ] || fail '구성에서 빠진 도구 스킬 링크 남음'
[ -L "$role_skills_dir/mine" ] && [ -d "$role_skills_dir/other-skill" ] || fail '정리 중 사용자 항목 삭제됨'
[ ! -e "$TEAM_SKILLS_ROOT/dev/.ai-setup-owned" ] || fail '소유 기록이 비워지지 않음'

# 기록된 도구 hooks.json을 사용자가 고치면(log-hook 명령은 그대로 둬도) 보존한다.
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
grep -qF "$BIN_DIR/log-hook" "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json" || fail '생성 hooks.json에 log-hook 없음'
printf '\n' >> "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
edited_sum="$(sha256sum < "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")"
reset_generated_team_files
[ -f "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json" ] && [ "$(sha256sum < "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")" = "$edited_sum" ] || fail '고친 도구 hooks.json 삭제됨(log-hook 포함)'
rm "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"

# 사용자가 만든 hooks.json은 생성 단계에서도 덮어쓰지 않고, 도구 파일을 사용자가 고치면 보존한다.
printf '{"hooks":"mine"}' > "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
output="$(write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>&1)"
expect_in "기존 .codex/hooks.json이 있어" "$output"
[ "$(cat "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")" = '{"hooks":"mine"}' ] || fail '생성 단계가 사용자 hooks.json 덮어씀'
! grep -q 'hooks.json' "$TEAM_SKILLS_ROOT/dev/.ai-setup-owned" 2>/dev/null || fail '사용자 hooks.json이 소유 기록에 들어감'
rm "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
printf '{"hooks":"edited"}' > "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
reset_generated_team_files
[ "$(cat "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")" = '{"hooks":"edited"}' ] || fail '사용자가 고친 hooks.json 삭제됨'
# 연속 재실행에서도 안정적이다.
reset_generated_team_files; reset_generated_team_files
[ "$(cat "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json")" = '{"hooks":"edited"}' ] || fail '연속 재실행 후 hooks.json 변경'
# AGENTS.md: 새로 쓰면 소유 기록에 남고, 만든 그대로면 정리, 고쳤거나 기록 없으면 보존한다.
rm -f "$TEAM_SKILLS_ROOT/dev/AGENTS.md" "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
grep -qP '^F\tAGENTS.md\t' "$TEAM_SKILLS_ROOT/dev/.ai-setup-owned" || fail 'AGENTS.md 소유 기록 누락'
reset_generated_team_files
[ ! -e "$TEAM_SKILLS_ROOT/dev/AGENTS.md" ] || fail '만든 그대로인 AGENTS.md 남음'
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
printf 'my own instructions\n' >> "$TEAM_SKILLS_ROOT/dev/AGENTS.md"
mine_sum="$(sha256sum < "$TEAM_SKILLS_ROOT/dev/AGENTS.md")"
reset_generated_team_files
[ -f "$TEAM_SKILLS_ROOT/dev/AGENTS.md" ] && [ "$(sha256sum < "$TEAM_SKILLS_ROOT/dev/AGENTS.md")" = "$mine_sum" ] || fail '사용자가 덧붙인 AGENTS.md(표지 유지) 삭제됨'
# 생성 단계도 남아 있는 AGENTS.md(표지 있음·없음·링크)를 덮어쓰지 않는다.
output="$(write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>&1)"
expect_in "기존 AGENTS.md가 있어" "$output"
[ "$(sha256sum < "$TEAM_SKILLS_ROOT/dev/AGENTS.md")" = "$mine_sum" ] || fail '생성 단계가 고친 AGENTS.md 덮어씀'
rm "$TEAM_SKILLS_ROOT/dev/AGENTS.md"
printf 'mine\n' > "$TEAM_SKILLS_ROOT/dev/AGENTS.md"
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
[ "$(cat "$TEAM_SKILLS_ROOT/dev/AGENTS.md")" = 'mine' ] || fail '사용자 AGENTS.md 덮어씀'
rm "$TEAM_SKILLS_ROOT/dev/AGENTS.md"
printf 'linked\n' > "$test_dir/src/agents-target.md"
ln -s "$test_dir/src/agents-target.md" "$TEAM_SKILLS_ROOT/dev/AGENTS.md"
write_codex_role_agents dev "$TEAM_SKILLS_ROOT/dev" 0.1 key 2>/dev/null
reset_generated_team_files
[ -L "$TEAM_SKILLS_ROOT/dev/AGENTS.md" ] && [ "$(cat "$test_dir/src/agents-target.md")" = linked ] || fail '사용자 AGENTS.md 링크 변경/삭제됨'
rm "$TEAM_SKILLS_ROOT/dev/AGENTS.md"

# ── Codex: 역할 홈 재사용·기본 홈 설치본 연결·신규 설치 ───────────
base_codex_home="$test_dir/base"
codex_assets_home="$TEAM_SKILLS_ROOT/_assets/codex-home"
make_codex_cache() { # <home> <plugin@mp>
    local dir="$1/plugins/cache/${2##*@}/${2%@*}/1.0"
    mkdir -p "$dir/.codex-plugin" "$dir/skills/probe"
    : > "$dir/.codex-plugin/plugin.json"
    : > "$dir/skills/probe/SKILL.md"
}
codex() {
    printf '%s %s\n' "${CODEX_HOME:-}" "$*" >> "$test_dir/codex_calls"
    if [ "$1 $2" = 'plugin add' ]; then
        # 성공한 설치는 해당 홈에 설치 명세를 남긴다.
        [ "${install_exit:-0}" != 0 ] || make_codex_cache "$CODEX_HOME" "$3"
        return "${install_exit:-0}"
    fi
}
declare -A CODEX_PLUGIN_ROLES=(
    ["have-base@local"]="developer" ["have-role@local"]="developer" ["fresh@local"]="developer"
    ["unused-installed@local"]="reviewer" ["unused-missing@local"]="reviewer"
    ["superpowers@openai-curated-remote"]=""
)
declare -A CODEX_SUPERPOWERS_SKILL_SETS=([developer]="probe")
PANE_COUNT=2 MEMBER_NAMES=(lead developer) MEMBER_AGENTS=(claude codex)
make_codex_cache "$base_codex_home" have-base@local
make_codex_cache "$base_codex_home" unused-installed@local
role_home="$TEAM_SKILLS_ROOT/developer/.codex-home"
make_codex_cache "$role_home" have-role@local
: > "$test_dir/codex_calls"
output="$(prepare_codex_role_home developer "$role_home")"
expect_in "ℹ️  have-role@local 이미 설치됨 → developer" "$output"
expect_in "ℹ️  have-base@local 로컬에 이미 설치됨(다른 홈 설치본 재사용) → developer" "$output"
expect_in "✅  fresh@local 새로 설치됨 → developer" "$output"
calls="$(cat "$test_dir/codex_calls")"
expect_in "$role_home plugin add fresh@local" "$calls"
expect_not_in "plugin add have-base@local" "$calls"
expect_not_in "plugin add have-role@local" "$calls"
# 기본 홈 설치본이 역할 홈에서 실제로 쓰이고, 활성화는 역할별 config가 정한다.
codex_plugin_cache "$role_home" have-base@local >/dev/null || fail '역할 홈에 연결 안 됨'
grep -qF '[plugins."have-base@local"]' "$role_home/config.toml" || fail '역할 홈 활성화 누락'
# 재실행해도 설치 명령이 늘지 않는다(fresh 설치본 흉내 후).
make_codex_cache "$role_home" fresh@local
: > "$test_dir/codex_calls"
output="$(prepare_codex_role_home developer "$role_home")"
expect_not_in "plugin add" "$(cat "$test_dir/codex_calls")"
expect_in "ℹ️  fresh@local 이미 설치됨" "$output"

# 필요 없는 플러그인: 설치돼 있으면 표시만, 없으면 건너뛴다. 스킬 원본은 snapshot을 쓴다.
: > "$test_dir/codex_calls"
mkdir -p "$base_codex_home/.tmp/plugins/plugins/superpowers/skills/probe"
: > "$base_codex_home/.tmp/plugins/plugins/superpowers/skills/probe/SKILL.md"
output="$(prepare_codex_skill_sources)"
expect_in "ℹ️  unused-installed@local 이미 설치됨" "$output"
expect_in "⏭️  unused-missing@local 건너뜀" "$output"
expect_in "superpowers@openai-curated-remote 스킬 원본 이미 있음" "$output"
[ ! -s "$test_dir/codex_calls" ] || fail "불필요한 설치 호출: $(cat "$test_dir/codex_calls")"

# 원본이 어디에도 없으면 전역 설정을 건드리지 않고 팀 자산 홈에 설치한다.
rm -rf "$base_codex_home/.tmp"
output="$(prepare_codex_skill_sources)"
expect_in "✅  superpowers@openai-curated-remote 스킬 원본으로 새로 설치됨" "$output"
expect_in "$codex_assets_home plugin add superpowers@openai-curated-remote" "$(cat "$test_dir/codex_calls")"

# 역할 홈에만 설치된 플러그인도 선택 스킬 원본으로 재사용한다(설치 명령 0회).
reuse_case() { # <이름> : base/assets/role 중 설치본을 어디에 둘지는 호출 전에 준비한다
    : > "$test_dir/codex_calls"
    prepare_codex_skill_sources > "$test_dir/reuse_out" 2>&1
}
MEMBER_AGENTS=(claude codex); MEMBER_NAMES=(lead developer)
declare -A CODEX_PLUGIN_ROLES=(["srconly@local"]="")
declare -A CODEX_SUPERPOWERS_SKILL_SETS=([developer]="probe")
CODEX_SRCONLY_SKILL_SETS=; unset CODEX_SRCONLY_SKILL_SETS
declare -A CODEX_SRCONLY_SKILL_SETS=([developer]="probe")
rm -rf "$base_codex_home" "$TEAM_SKILLS_ROOT/developer/.codex-home" "$codex_assets_home"
make_codex_cache "$TEAM_SKILLS_ROOT/developer/.codex-home" srconly@local
reuse_case
[ ! -s "$test_dir/codex_calls" ] || fail "역할 홈 설치본이 있는데 설치함: $(cat "$test_dir/codex_calls")"
grep -qF '스킬 원본 이미 있음' "$test_dir/reuse_out" || fail '역할 홈 설치본을 원본으로 못 찾음'
rm -rf "$TEAM_SKILLS_ROOT/developer/.codex-home"
make_codex_cache "$codex_assets_home" srconly@local
reuse_case
[ ! -s "$test_dir/codex_calls" ] || fail "자산 홈 설치본이 있는데 설치함"
rm -rf "$codex_assets_home"
reuse_case
[ "$(grep -c 'plugin add srconly@local' "$test_dir/codex_calls")" = 1 ] || fail '설치본이 없으면 정확히 1회 설치해야 함'
grep -qF "$codex_assets_home plugin add" "$test_dir/codex_calls" || fail '자산 홈에 설치되지 않음'
# 활성화와 스킬 원본을 겸하는 플러그인은 첫 실행에서 자산 홈에 중복 설치하지 않는다.
rm -rf "$codex_assets_home" "$TEAM_SKILLS_ROOT/developer/.codex-home"
declare -A CODEX_PLUGIN_ROLES=(["srconly@local"]="developer")
reuse_case
[ ! -s "$test_dir/codex_calls" ] || fail "활성화+스킬 원본 플러그인을 자산 홈에 중복 설치함"
: > "$test_dir/codex_calls"
prepare_codex_role_home developer "$TEAM_SKILLS_ROOT/developer/.codex-home" >/dev/null
[ "$(grep -c 'plugin add srconly@local' "$test_dir/codex_calls")" = 1 ] || fail '역할 홈 설치가 정확히 1회가 아님'
codex_plugin_skills_root srconly@local >/dev/null || fail '역할 홈 설치본이 스킬 원본으로 안 잡힘'
# 자산 홈에 먼저 설치된 것은 역할 홈 준비에서 다시 받지 않고 연결한다.
rm -rf "$TEAM_SKILLS_ROOT/developer/.codex-home"
make_codex_cache "$codex_assets_home" srconly@local
: > "$test_dir/codex_calls"
prepare_codex_role_home developer "$TEAM_SKILLS_ROOT/developer/.codex-home" >/dev/null
! grep -q 'plugin add' "$test_dir/codex_calls" || fail '자산 홈 설치본을 두고 재설치함'
codex_plugin_cache "$TEAM_SKILLS_ROOT/developer/.codex-home" srconly@local >/dev/null || fail '자산 홈 설치본이 역할 홈에 연결 안 됨'

# 다른 역할 홈에만 설치된 플러그인: 활성화 역할의 홈 준비도 재설치 없이 연결하고 config는 역할별로 유지한다.
rm -rf "$base_codex_home" "$codex_assets_home" "$TEAM_SKILLS_ROOT/developer/.codex-home" "$TEAM_SKILLS_ROOT/other/.codex-home"
make_codex_cache "$TEAM_SKILLS_ROOT/other/.codex-home" srconly@local
: > "$test_dir/codex_calls"
reuse_case
[ ! -s "$test_dir/codex_calls" ] || fail '다른 역할 홈 설치본이 있는데 자산 홈에 설치함'
output="$(prepare_codex_role_home developer "$TEAM_SKILLS_ROOT/developer/.codex-home")"
! grep -q 'plugin add' "$test_dir/codex_calls" || fail "다른 역할 홈 설치본이 있는데 plugin add 호출: $(cat "$test_dir/codex_calls")"
expect_in "srconly@local 로컬에 이미 설치됨(다른 홈 설치본 재사용) → developer" "$output"
codex_plugin_cache "$TEAM_SKILLS_ROOT/developer/.codex-home" srconly@local >/dev/null || fail '다른 역할 홈 설치본이 연결 안 됨'
grep -qF '[plugins."srconly@local"]' "$TEAM_SKILLS_ROOT/developer/.codex-home/config.toml" || fail '역할별 활성화 누락'
! grep -qF 'srconly' "$TEAM_SKILLS_ROOT/other/.codex-home/config.toml" 2>/dev/null || fail '다른 역할 config가 바뀜'
rm -rf "$TEAM_SKILLS_ROOT/other" "$TEAM_SKILLS_ROOT/developer/.codex-home"

# ── 빈 플러그인 배열: 오류·명령 없이 건너뛰고 set -e에서도 이어진다 ──
CLAUDE_PLUGIN_ROLES=() CODEX_PLUGIN_ROLES=()
: > "$test_dir/claude_calls"; : > "$test_dir/codex_calls"
claude() { printf 'claude %s\n' "$*" >> "$test_dir/claude_calls"; }
set +e
( set -e; install_claude_plugins; echo after-claude ) > "$test_dir/empty_out" 2>&1; rc_claude=$?
( set -e; prepare_codex_skill_sources; echo after-codex ) >> "$test_dir/empty_out" 2>&1; rc_codex=$?
set -e
[ "$rc_claude" = 0 ] && [ "$rc_codex" = 0 ] || fail "빈 배열에서 비정상 종료: $rc_claude $rc_codex: $(cat "$test_dir/empty_out")"
grep -q 'after-claude' "$test_dir/empty_out" && grep -q 'after-codex' "$test_dir/empty_out" || fail '빈 배열 뒤 단계가 진행되지 않음'
! grep -q 'bad array subscript' "$test_dir/empty_out" || fail 'bad array subscript'
[ ! -s "$test_dir/claude_calls" ] && [ ! -s "$test_dir/codex_calls" ] || fail '빈 배열인데 명령 호출'

unset CODEX_SRCONLY_SKILL_SETS
declare -A CODEX_PLUGIN_ROLES=(
    ["have-base@local"]="developer" ["have-role@local"]="developer" ["fresh@local"]="developer"
    ["unused-installed@local"]="reviewer" ["unused-missing@local"]="reviewer"
    ["superpowers@openai-curated-remote"]=""
)
rm -rf "$codex_assets_home"
mkdir -p "$base_codex_home"

# 필요한 역할이 Claude뿐이면 Codex 설치는 하지 않는다.
MEMBER_AGENTS=(claude claude)
: > "$test_dir/codex_calls"
output="$(prepare_codex_skill_sources)"
expect_in "⏭️  superpowers@openai-curated-remote 건너뜀" "$output"
[ ! -s "$test_dir/codex_calls" ] || fail 'Claude 전용 팀에서 Codex 설치 호출'

# ── 기동 대기: 준비 화면 감지, 대화상자 응답, 시간 초과는 실패 ─────
screen_file="$test_dir/screen"
keys_file="$test_dir/keys"
tmux() {
    case "$1" in
        capture-pane) cat "$screen_file" ;;
        send-keys)
            echo "$*" >> "$keys_file"
            [[ "${4:-}" != "cd "* ]] || printf '%s' "$4" > "$test_dir/sent_cmd"
            if [ -n "${after_enter:-}" ] && [[ " $* " == *" Enter "* ]]; then
                printf '%s\n' "$after_enter" > "$screen_file"
            fi
            ;;
    esac
}
: > "$keys_file"
printf '  bypass permissions on (shift+tab to cycle)\n' > "$screen_file"
wait_claude_ready pane 5 || fail '준비 화면에서 실패'
[ ! -s "$keys_file" ] || fail '준비 화면에 불필요한 키 입력'

printf ' ❯ No, exit\n   Yes, I trust this folder\n' > "$screen_file"
after_enter='  ? for shortcuts'
wait_claude_ready pane 5 || fail '신뢰 대화상자 처리 실패'
grep -q 'Down' "$keys_file" || fail 'No, exit 기본 선택에서 Down 누락'
unset after_enter

: > "$keys_file"
printf ' ❯ Yes, I trust this folder\n   No, exit\n' > "$screen_file"
after_enter='  ? for shortcuts'
wait_claude_ready pane 5 || fail 'Yes 기본 선택 처리 실패'
! grep -q 'Down' "$keys_file" || fail 'Yes 기본 선택에서 Down 전송'
unset after_enter

printf 'loading...\n' > "$screen_file"
! wait_claude_ready pane 3 || fail 'Claude 시간 초과가 성공 처리됨'

# ── 경로 직렬화: 공백·따옴표·달러·백틱이 든 경로가 명령으로 평가되지 않고 argv로 전달된다 ──
fakebin="$test_dir/fakebin"; mkdir -p "$fakebin"
cat > "$fakebin/fake" <<'EOF'
#!/bin/bash
{ printf 'CALL=%s\n' "$(basename "$0")"; printf 'PWD=%s\n' "$PWD"; printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-}"; printf 'ARG=%s\n' "$@"; printf -- '---\n'; } >> "$FAKE_LOG"
EOF
chmod +x "$fakebin/fake"
for n in claude codex tmux; do ln -sf fake "$fakebin/$n"; done
# 기동 함수가 command -v로 실제 CLI를 집지 않도록 앞선 구간의 claude/codex 함수 스텁을 지우고
# 모의 실행 파일을 PATH 맨 앞에 둔다. 환경의 NVM_BIN이 PATH 앞쪽에 끼면 실제 CLI가 실행될 수 있어 비운다.
unset -f claude codex
unset NVM_BIN
PATH="$fakebin:$PATH"
weird="$test_dir/owner's \"p\" \$HOME \`touch $test_dir/pwned\` sp"
PROJECT_DIR="$weird" TEAM_SKILLS_ROOT="$weird/.team" RUNTIME_DIR="$weird/.team/_runtime" TEAM_DIR="$weird/teamdir" BIN_DIR="$weird/bin" SESSION=s
mkdir -p "$BIN_DIR" "$TEAM_SKILLS_ROOT/dev/.claude/skills" "$TEAM_SKILLS_ROOT/dev/.codex-home" "$TEAM_DIR"
printf '# role\n' > "$TEAM_DIR/dev.md"
for n in say log-hook; do ln -sf "$fakebin/fake" "$BIN_DIR/$n"; done
MEMBER_NAMES=(lead dev) NEED_FIRST_LOGIN=false
CLAUDE_PLUGIN_ROLES=() CLAUDE_PLUGIN_MARKETPLACES=()
pane_state_key() { printf 'key'; }
export FAKE_LOG="$test_dir/fake.log"
log_has() { grep -qxF -- "$1" "$FAKE_LOG"; }
run_sent() { ( cd /; PATH="$fakebin:$PATH" bash -c "$(cat "$test_dir/sent_cmd")" ); }
json_commands() { # <json 파일> : 모든 hook command를 NUL 구분으로 출력
    python3 -I - "$1" <<'PY'
import json, sys
def walk(node):
    if isinstance(node, dict):
        if node.get("type") == "command":
            sys.stdout.write(node["command"] + "\0")
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
walk(json.load(open(sys.argv[1])))
PY
}
run_hook_commands() { # <json 파일> : 각 hook command를 실제 셸로 실행한다
    local cmd
    while IFS= read -r -d '' cmd; do
        case "$cmd" in *log-hook*|*/say*) ;; *) continue ;; esac
        ( cd /; PATH="$fakebin:$PATH" bash -c "$cmd" ) >/dev/null 2>&1 || true
    done < <(json_commands "$1")
}

screen_ready='bypass permissions on'
printf '%s\n' "$screen_ready" > "$screen_file"
: > "$FAKE_LOG"
start_claude_in_pane s:0.1 claude-x dev high || fail '특수문자 경로에서 Claude 기동 실패'
bash -n <<< "$(cat "$test_dir/sent_cmd")" || fail 'Claude 기동 명령 문법 오류'
grep -qF "$fakebin/claude" "$test_dir/sent_cmd" || fail '실제 claude 경로가 명령에 들어감'
run_sent
log_has "CALL=claude" || fail 'Claude가 실행되지 않음'
log_has "PWD=$TEAM_SKILLS_ROOT/dev" || fail 'Claude cwd 불일치'
log_has "ARG=$RUNTIME_DIR/dev.settings.json" || fail '--settings 경로가 argv로 전달되지 않음'
log_has "ARG=$RUNTIME_DIR/dev.prompt.md" || fail '지침 파일 경로가 argv로 전달되지 않음'
log_has "ARG=claude-x" && log_has "ARG=high" && log_has "ARG=--dangerously-skip-permissions" && log_has "ARG=project" || fail 'Claude 옵션 전달 불일치'
[ ! -e "$test_dir/pwned" ] || fail '경로의 백틱이 명령으로 평가됨'
# 훅 JSON은 유효하고, 안의 셸 명령도 같은 경로를 인자로 전달한다.
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$RUNTIME_DIR/dev.settings.json" || fail 'settings JSON 오류'
: > "$FAKE_LOG"
run_hook_commands "$RUNTIME_DIR/dev.settings.json"
log_has "CALL=log-hook" && log_has "ARG=dev" && log_has "ARG=$PROJECT_DIR" || fail 'Claude log-hook 인자 불일치'
log_has "CALL=say" && log_has "ARG=s:0.0" || fail 'Stop 훅의 say 호출 불일치'
log_has "CALL=tmux" && log_has "ARG=run-shell" || fail 'drain tmux 호출 없음'
# tmux run-shell 인자로 넘어간 drain 명령도 BIN_DIR 경로를 올바르게 실행한다.
inner="$(awk '/^CALL=tmux/{f=1} f&&/^ARG=sleep 1;/{sub(/^ARG=/,""); print; exit}' "$FAKE_LOG")"
: > "$FAKE_LOG"
( cd /; PATH="$fakebin:$PATH" bash -c "$inner" )
log_has "CALL=say" && log_has "ARG=--drain-one" && log_has "ARG=s:0.1" || fail 'drain-one 명령이 특수문자 BIN_DIR에서 실패'
[ ! -e "$test_dir/pwned" ] || fail '훅 명령에서 백틱이 평가됨'
grep -qF "\$'" "$RUNTIME_DIR/dev.settings.json" && fail 'POSIX 셸에서 쓸 수 없는 $'"'"' 인용 사용' || true

# Codex: 실제 write_codex_role_agents와 hooks.json을 포함해 같은 검증
printf 'Ask Codex to do anything\n' > "$screen_file"
: > "$FAKE_LOG"
start_codex_in_pane s:0.1 gpt-x dev high || fail '특수문자 경로에서 Codex 기동 실패'
bash -n <<< "$(cat "$test_dir/sent_cmd")" || fail 'Codex 기동 명령 문법 오류'
grep -qF "$fakebin/codex" "$test_dir/sent_cmd" || fail '실제 codex 경로가 명령에 들어감'
run_sent
log_has "CALL=codex" || fail 'Codex가 실행되지 않음'
log_has "PWD=$TEAM_SKILLS_ROOT/dev" && log_has "CODEX_HOME=$TEAM_SKILLS_ROOT/dev/.codex-home" || fail 'Codex cwd/CODEX_HOME 불일치'
log_has "ARG=$PROJECT_DIR" && log_has "ARG=--add-dir" && log_has 'ARG=model_reasoning_effort="high"' && log_has "ARG=gpt-x" || fail 'Codex 인자 전달 불일치'
log_has "ARG=--dangerously-bypass-approvals-and-sandbox" || fail '권한 모드 유지 실패'
[ ! -e "$test_dir/pwned" ] || fail 'Codex 경로의 백틱이 명령으로 평가됨'
python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json" || fail 'hooks.json 오류'
: > "$FAKE_LOG"
run_hook_commands "$TEAM_SKILLS_ROOT/dev/.codex/hooks.json"
log_has "CALL=log-hook" && log_has "ARG=dev" && log_has "ARG=$PROJECT_DIR" && log_has "ARG=--quiet" || fail 'Codex log-hook 인자 불일치'
log_has "CALL=say" && log_has "ARG=s:0.0" || fail 'Codex Stop 훅 say 불일치'
[ ! -e "$test_dir/pwned" ] || fail 'Codex 훅에서 백틱이 평가됨'
# 역할 지침의 cd 안내도 올바르게 인용된다.
grep -F 'cd ' "$TEAM_SKILLS_ROOT/dev/AGENTS.md" | grep -qF "owner'\\''s" || fail 'AGENTS.md cd 안내 인용 오류'

# Codex: 준비 프롬프트 감지·신뢰 대화상자 처리·시간 초과 실패, /hooks 신뢰 처리 보존
PROJECT_DIR="$test_dir/project" TEAM_SKILLS_ROOT="$test_dir/team" BIN_DIR="$test_dir/bin"
write_codex_role_agents() { :; }
: > "$keys_file"
printf 'Ask Codex to do anything\n' > "$screen_file"
start_codex_in_pane s:0.1 model developer high || fail 'Codex 준비 화면에서 실패'
grep -q -- '-l /hooks' "$keys_file" || fail '/hooks 신뢰 처리 누락'

: > "$keys_file"
printf 'Do you trust the contents of this directory?\n' > "$screen_file"
after_enter='Ask Codex to do anything'
start_codex_in_pane s:0.1 model developer high || fail 'Codex 신뢰 대화상자 처리 실패'
unset after_enter

printf 'starting\n' > "$screen_file"
! start_codex_in_pane s:0.1 model developer high 2>/dev/null || fail 'Codex 시간 초과가 성공 처리됨'

printf 'setup-team 플러그인·재사용·기동 대기 테스트 통과\n'

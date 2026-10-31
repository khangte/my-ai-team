#!/usr/bin/env bash
# tmux 기반 Claude/Codex 팀 구성. 역할·모델은 team/config.sh의 MEMBERS에서 설정한다.
# 사용: ./setup-team.sh [--agent claude|codex] [프로젝트_경로]
# 경로 생략 시 $PROJECT_DIR, 그것도 없으면 현재 디렉터리를 사용한다.

set -e

# 연관 배열·mapfile·${var^^}는 bash 4+가 필요하다. macOS 기본 bash 3.2는 여기서 막는다.
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo "bash 4+ 필요 (현재 $BASH_VERSION). macOS는 setup-mac.sh 안내대로 Homebrew bash로 실행하세요." >&2; exit 1; }

# ── PATH 보강 ─────────────────────────────────────────────
# 비대화형 셸에서도 파인과 훅이 node·python3를 찾도록 PATH를 보강한다.
# macOS 전용(Linux/WSL의 우선순위는 그대로): Homebrew bash(bin/say의 env bash)와 GNU coreutils(timeout·realpath·sort -V)를 시스템 디렉터리보다 앞에 둔다.
# Homebrew 접두사는 HOMEBREW_PREFIX(없으면 Apple Silicon 기본값)를 따른다.
BREW_FIRST=""
if [ "$(uname -s)" = Darwin ]; then
    for p in "${HOMEBREW_PREFIX:-/opt/homebrew}" /usr/local; do
        for d in "$p/opt/coreutils/libexec/gnubin" "$p/bin"; do
            if [ -d "$d" ]; then BREW_FIRST="$BREW_FIRST$d:"; fi
        done
    done
fi
PATH="$BREW_FIRST$PATH"   # 아래 sort -V가 GNU 판을 쓰도록 먼저 반영
NVM_BIN=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)
export PATH="$BREW_FIRST$HOME/.local/bin:${NVM_BIN:+$NVM_BIN:}/usr/local/bin:/usr/bin:/bin:$PATH"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SESSION="team1"
TEAM_AGENT="${TEAM_AGENT:-claude}"
PROJECT_ARG=""

usage() {
    # 사용법을 출력한다.
    cat <<'EOF'
사용법: ./setup-team.sh [--agent claude|codex] [프로젝트_경로]

옵션:
    --agent NAME       사용할 에이전트 (claude 또는 codex, 기본: claude)
    -h, --help         이 도움말 표시

환경변수:
    TEAM_AGENT         --agent가 없을 때 사용할 에이전트
    PROJECT_DIR        프로젝트 경로 (인자가 없을 때 사용)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --agent)
            [ $# -ge 2 ] || { echo -e "${RED}❌ --agent에는 값이 필요합니다.${NC}" >&2; exit 2; }
            TEAM_AGENT="$2"
            shift 2
            ;;
        --agent=*)
            TEAM_AGENT="${1#--agent=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            [ $# -le 1 ] || { echo -e "${RED}❌ 프로젝트 경로는 하나만 지정할 수 있습니다.${NC}" >&2; exit 2; }
            PROJECT_ARG="${1:-}"
            break
            ;;
        -*)
            echo -e "${RED}❌ 알 수 없는 옵션: $1${NC}" >&2
            usage >&2
            exit 2
            ;;
        *)
            [ -z "$PROJECT_ARG" ] || { echo -e "${RED}❌ 프로젝트 경로는 하나만 지정할 수 있습니다.${NC}" >&2; exit 2; }
            PROJECT_ARG="$1"
            shift
            ;;
    esac
done

case "$TEAM_AGENT" in
    claude|codex) ;;
    *)
        echo -e "${RED}❌ 지원하지 않는 에이전트: $TEAM_AGENT (claude 또는 codex)${NC}" >&2
        exit 2
        ;;
esac

PROJECT_DIR="${PROJECT_ARG:-${PROJECT_DIR:-$(pwd)}}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

# team/{role}.md 지침 파일 위치. 이 스크립트(ai-setup 리포) 기준이므로 PROJECT_DIR과 무관하다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_DIR="$SCRIPT_DIR/team"
BIN_DIR="$SCRIPT_DIR/bin"   # say·log-hook — 오버라이드 대상이 아닌 고정 스크립트
# 파인·run-shell·세션 환경에 그대로 넘길 PATH. 기존 tmux 서버의 최소 PATH에 의존하지 않게 한다.
TEAM_PATH="$BIN_DIR:${NVM_BIN:+$NVM_BIN:}$PATH"

# ── 팀 멤버 정보 ───────────────────────────────────────────
# 공통 구성은 저장소 기본값 위에 프로젝트 설정을 적용한다.
# 공급자별 배분표는 프로젝트 파일이 있으면 기본값 대신 사용한다.
# MEMBERS가 멤버 배열을 채우므로 MEMBER_NAMES만 따로 선언하지 않는다.
declare -a MEMBER_NAMES=()
declare -a MEMBER_AGENTS=()
declare -a SPEC_MEMBER_MODELS=()
declare -a SPEC_MEMBER_REASONING_EFFORTS=()

common_config="$TEAM_DIR/config.sh"
[ -f "$common_config" ] && source "$common_config"

project_common_config="$PROJECT_DIR/team/config.sh"
if [ -f "$project_common_config" ]; then
    echo -e "${YELLOW}team/config.sh 발견 → 프로젝트별 팀 구성 사용: $project_common_config${NC}"
    source "$project_common_config"
fi

if [ "${#MEMBER_NAMES[@]}" -eq 0 ]; then
    echo -e "${RED}❌ team/config.sh를 찾을 수 없습니다 (${common_config} 또는 ${project_common_config}).${NC}"
    exit 1
fi

PANE_COUNT=${#MEMBER_NAMES[@]}

if [ "${#SPEC_MEMBER_MODELS[@]}" -ne "$PANE_COUNT" ]; then
    echo -e "${RED}❌ MEMBER_NAMES(${PANE_COUNT}개)와 MEMBER_MODELS(${#SPEC_MEMBER_MODELS[@]}개) 길이가 다릅니다. team/config.sh의 MEMBERS를 확인하세요.${NC}"
    exit 1
fi
if [ "${#SPEC_MEMBER_REASONING_EFFORTS[@]}" -ne "$PANE_COUNT" ]; then
    echo -e "${RED}❌ MEMBER_NAMES(${PANE_COUNT}개)와 MEMBER_REASONING_EFFORTS(${#SPEC_MEMBER_REASONING_EFFORTS[@]}개) 길이가 다릅니다. team/config.sh의 MEMBERS를 확인하세요.${NC}"
    exit 1
fi

if [ "${#MEMBER_AGENTS[@]}" -eq 0 ]; then
    for ((i = 0; i < PANE_COUNT; i++)); do
        MEMBER_AGENTS+=("")
    done
fi

if [ "${#MEMBER_AGENTS[@]}" -ne "$PANE_COUNT" ]; then
    echo -e "${RED}❌ MEMBER_NAMES(${PANE_COUNT}개)와 MEMBER_AGENTS(${#MEMBER_AGENTS[@]}개) 길이가 다릅니다.${NC}"
    exit 1
fi

# 혼합 팀에서는 실제 배정된 공급자 모두를 준비한다.
declare -A USED_AGENTS=()
for ((i = 0; i < PANE_COUNT; i++)); do
    a="${MEMBER_AGENTS[$i]:-$TEAM_AGENT}"
    case "$a" in
        claude|codex) ;;
        *)
            echo -e "${RED}❌ 지원하지 않는 에이전트: '$a' (역할 '${MEMBER_NAMES[$i]}', claude 또는 codex만 허용)${NC}" >&2
            exit 2
            ;;
    esac
    MEMBER_AGENTS[$i]="$a"
    USED_AGENTS["$a"]=1
done

for agent in "${!USED_AGENTS[@]}"; do
    # 프로젝트에 없는 배열이 기본값으로 남지 않도록 구성 파일을 병합하지 않는다.
    project_provider_config="$PROJECT_DIR/team/config.${agent}.sh"
    if [ ! -f "$project_provider_config" ]; then
        provider_config="$TEAM_DIR/config.${agent}.sh"
        [ -f "$provider_config" ] && source "$provider_config"
    else
        echo -e "${YELLOW}team/config.${agent}.sh 발견 → 공급자별 구성 사용: $project_provider_config${NC}"
        source "$project_provider_config"
        for legacy in PLUGIN_MARKETPLACES PLUGIN_ROLES GSTACK_SKILL_SETS SUPERPOWERS_SKILL_SETS \
                      FRONTEND_DESIGN_SKILL_SETS CODEX_PLUGIN_SETS CODEX_PLUGIN_SKILL_SETS; do
            if declare -p "$legacy" >/dev/null 2>&1; then
                echo -e "${YELLOW}  ⚠️  $project_provider_config: 옛 이름 $legacy 는 무시됩니다 (현재 이름은 이 저장소의 team/config.${agent}.sh 참고)${NC}" >&2
            fi
        done
    fi
done

# ── 유틸: 파인에 패턴이 나타날 때까지 대기 ──────────────────
wait_for_pane() {
    # 파인에 지정 패턴이 나타날 때까지 기다린다.
    local pane="$1" pattern="$2" timeout="${3:-30}" waited=0
    while [ $waited -lt $timeout ]; do
        tmux capture-pane -t "$pane" -p 2>/dev/null | grep -q "$pattern" && return 0
        sleep 1; waited=$((waited + 1))
    done
    return 1
}

# ── 유틸: Claude 준비 완료까지 대화상자 응답 + 대기 ─────────
answer_claude_dialog() {
    # 사용법: answer_claude_dialog <pane> <화면>
    # 선택 표시(❯) 줄이 이미 Yes면 Enter만, 아니면(No, exit가 기본인 화면) Down 후 Enter.
    local pane="$1" screen="$2"
    if ! grep '❯' <<< "$screen" | grep -q "Yes"; then
        tmux send-keys -t "$pane" Down
        sleep 0.5
    fi
    tmux send-keys -t "$pane" Enter
}

wait_claude_ready() {
    # 폴더 신뢰·약관 대화상자에 응답하며 입력 화면이 뜰 때까지 기다린다.
    # 이미 처리된 대화상자는 기다리지 않고, 시간 초과면 1을 반환한다.
    local pane="$1" timeout="${2:-60}" waited=0 screen
    while [ "$waited" -lt "$timeout" ]; do
        screen="$(tmux capture-pane -t "$pane" -p 2>/dev/null)"
        if grep -q "trust this folder\|I accept" <<< "$screen"; then
            answer_claude_dialog "$pane" "$screen"
        elif grep -q "bypass permissions on\|? for shortcuts" <<< "$screen"; then
            return 0
        fi
        sleep 1; waited=$((waited + 1))
    done
    return 1
}

# ── 유틸: 플러그인 설치·필요 여부 판별 (Claude·Codex 대칭) ──
plugin_skill_set() {
    # 사용법: plugin_skill_set <CLAUDE|CODEX> <플러그인> <역할>
    # {공급자}_{플러그인}_SKILL_SETS[역할] 값을 출력한다. 배열이 없으면 빈 값이다.
    local var="${1}_${2^^}_SKILL_SETS" role="$3"
    var="${var//-/_}"
    [[ "$(declare -p "$var" 2>/dev/null)" == "declare -A"* ]] || return 0
    local -n skill_sets="$var"
    printf '%s' "${skill_sets[$role]:-}"
}

role_in() {
    # 사용법: role_in <역할 목록|*> <역할>
    # 목록이 *이거나 공백 구분 목록에 역할이 있으면 0을 반환한다.
    [ "$1" = "*" ] || [[ " $1 " == *" $2 "* ]]
}

provider_plugin_needed() {
    # 사용법: provider_plugin_needed <claude|codex> <plugin@marketplace>
    # 그 공급자 파인이 플러그인을 활성화하거나 선택 스킬의 원본으로 쓰면 0을 반환한다.
    local provider="$1" key="$2" i role roles
    local -n plugin_roles="${provider^^}_PLUGIN_ROLES"
    roles="${plugin_roles[$key]:-}"
    for ((i = 0; i < PANE_COUNT; i++)); do
        [ "${MEMBER_AGENTS[$i]}" = "$provider" ] || continue
        role="${MEMBER_NAMES[$i]}"
        if role_in "$roles" "$role"; then
            return 0
        fi
        if [ -n "$(plugin_skill_set "${provider^^}" "${key%@*}" "$role")" ]; then
            return 0
        fi
    done
    return 1
}

claude_plugin_dir() {
    # 사용법: claude_plugin_dir <plugin@marketplace>
    # 설치 명세에 있고 plugin.json이 실제로 있는 설치 경로를 출력한다. 없으면 1.
    # 빈 캐시 디렉터리나 다른 마켓플레이스의 동명 플러그인은 설치로 보지 않는다.
    python3 -I - "$HOME/.claude/plugins/installed_plugins.json" "$1" <<'PY'
import json
import os
import sys

try:
    with open(sys.argv[1]) as f:
        entries = json.load(f)["plugins"].get(sys.argv[2], [])
except (OSError, ValueError, KeyError):
    sys.exit(1)
for entry in entries:
    path = entry.get("installPath", "")
    if os.path.isfile(os.path.join(path, ".claude-plugin", "plugin.json")):
        print(path)
        sys.exit(0)
sys.exit(1)
PY
}

codex_plugin_cache() {
    # 사용법: codex_plugin_cache <CODEX_HOME> <plugin@marketplace>
    # plugin.json이 있는 최신 버전 디렉터리를 출력한다. 없으면 1.
    # 경로 부분은 따옴표로 묶어 [ ] * ? 가 패턴으로 해석되지 않게 하고, 버전 자리의 *만 글롭이다.
    local candidate found=() manifest
    for candidate in "$1/plugins/cache/${2##*@}/${2%@*}"/*/.codex-plugin/plugin.json; do
        [ -f "$candidate" ] && found+=("$candidate")
    done
    [ ${#found[@]} -gt 0 ] || return 1
    manifest="$(printf '%s\n' "${found[@]}" | sort -V | tail -1)"
    dirname "$(dirname "$manifest")"
}

# ── 유틸: Stop 시점 종료 신호 커맨드 조립 (Claude·Codex 공용) ──
stop_hook_cmd_for_role() {
    # lead 자기 보고를 제외한 종료 명령을 STOP_HOOK_CMD에 담는다.
    local role="$1" pane_id="$2" state_key="$3"
    # watcher가 종료돼도 입력창 준비 후 tmux 서버가 큐를 다시 가동한다.
    local drain_inner
    drain_inner="export PATH=$(shell_quote "${TEAM_PATH:-$PATH}"); sleep 1; $(shell_quote "$BIN_DIR/say") --drain-one $(shell_quote "${SESSION}:0.${pane_id#*.}")"
    local drain_cmd="tmux run-shell -b $(shell_quote "$drain_inner")"
    if [ "$role" = "lead" ]; then
        STOP_HOOK_CMD="rm -f /tmp/team-busy/${state_key}; ${drain_cmd}"
    else
        # 보고 마커는 턴마다 소비한다. Codex에는 별도 턴 시작 초기화 훅이 없다.
        local marker="/tmp/team-say/${state_key}"
        STOP_HOOK_CMD="rm -f /tmp/team-busy/${state_key}; if [ -f $(shell_quote "$marker") ]; then rm -f $(shell_quote "$marker"); else $(shell_quote "$BIN_DIR/say") $(shell_quote "${SESSION}:0.0") $(shell_quote "[${role}] (자동) 파인 :${pane_id} 응답 종료 — 미보고 시 확인 필요"); fi; ${drain_cmd}"
    fi
}

pane_state_key() {
    # 세션 재생성 시 충돌하지 않도록 say와 동일한 고유 ID 키를 만든다.
    local state
    state="$(tmux display-message -p -t "$1" '#{session_id}:#{pane_id}')"
    printf '%s' "${state//[^0-9A-Za-z]/_}"
}

# ── 유틸: 플러그인 스킬을 역할 스킬 디렉터리에 링크 ──────────
team_owned_record() {
    # 사용법: team_owned_record <역할 디렉터리> <L|F> <상대경로> <값>
    # 도구가 만든 항목을 역할 디렉터리의 소유 기록에 남긴다. 링크(L)는 대상 경로,
    # 파일(F)은 sha256을 값으로 써서 나중에 만든 그대로인지 확인한다.
    mkdir -p "$1"
    printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$1/.ai-setup-owned"
}

team_owned_adopt_identical() {
    # 현재 생성할 내용과 정확히 같은 일반 파일만 소유 기록에 다시 등록한다.
    local dir="$1" rel="$2" content="$3" path="$1/$2"
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    cmp -s "$path" <(printf '%s' "$content") || return 1
    team_owned_record "$dir" F "$rel" "$(sha256sum < "$path" | cut -d' ' -f1)"
}

team_owned_clean() {
    # 사용법: team_owned_clean <역할 디렉터리>
    # 소유 기록에 있고 만든 그대로인 항목만 지우고 기록을 비운다. 사용자가 바꿨거나
    # 이미 없는 항목은 건드리지 않으며, 기록이 없는 기존 항목은 소유자가 불명확하므로 둔다.
    local dir="$1" kind rel value path
    [ -f "$dir/.ai-setup-owned" ] || return 0
    while IFS=$'\t' read -r kind rel value; do
        path="$dir/$rel"
        case "$kind" in
            L) [ -L "$path" ] && [ "$(readlink "$path")" = "$value" ] && rm -f "$path" ;;
            F) [ -f "$path" ] && [ ! -L "$path" ] && [ "$(sha256sum < "$path" | cut -d' ' -f1)" = "$value" ] && rm -f "$path" ;;
        esac || true
    done < "$dir/.ai-setup-owned"
    rm -f "$dir/.ai-setup-owned"
}

link_owned_skill() {
    # 사용법: link_owned_skill <대상> <링크 경로> <역할 디렉터리>
    # 스킬 링크를 만들고 소유 기록에 남긴다. 같은 경로에 이미 있는 항목은 사용자 것으로
    # 보고 덮어쓰지 않는다(같은 대상을 가리키는 링크는 그대로 쓰고, 그 외는 1을 반환한다).
    local target="$1" link="$2" dir="$3"
    if [ -L "$link" ] && [ "$(realpath "$link" 2>/dev/null)" = "$target" ]; then
        return 0
    fi
    if [ -e "$link" ] || [ -L "$link" ]; then
        echo -e "${YELLOW}  ⚠️  $role: '${link#"$dir"/}'에 기존 항목이 있어 덮어쓰지 않습니다 (사용자 항목 보존)${NC}" >&2
        return 1
    fi
    mkdir -p "$(dirname "$link")"
    ln -s "$target" "$link"
    team_owned_record "$dir" L "${link#"$dir"/}" "$target"
}

link_plugin_skills() {
    # 사용법: link_plugin_skills <플러그인> <스킬 루트> <스킬>...
    local plugin="$1" root="$2" skill src
    shift 2
    for skill in "$@"; do
        case "$skill" in
            ""|.|..|*/*)
                echo -e "${YELLOW}  ⚠️  $role: $plugin 스킬 이름 오류: $skill${NC}" >&2
                continue
                ;;
        esac
        src="$root/$skill"
        if [ -z "$root" ] || [ ! -f "$src/SKILL.md" ]; then
            echo -e "${YELLOW}  ⚠️  $role: $plugin에 스킬 '$skill'이 없습니다.${NC}" >&2
            continue
        fi
        link_owned_skill "$(realpath "$src")" "$role_skills_dir/$skill" "$TEAM_SKILLS_ROOT/$role" || continue
        granted+=("$plugin:$skill")
    done
}

# ── 유틸: 셸 인자 직렬화 ────────────────────────────────────
shell_quote() {
    # 작은따옴표를 포함한 값을 POSIX 셸의 한 인자로 직렬화한다.
    local quote="'\\''"
    printf "'%s'" "${1//\'/$quote}"
}

# ── 유틸: JSON 문자열 값으로 안전하게 넣을 수 있게 이스케이프 ──
json_escape() {
    # 백슬래시부터 이스케이프해 JSON 문자열의 중복 처리를 피한다.
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ── 유틸: 공통 지침을 대상 프로젝트 파일에 병합 (Claude·Codex 공용) ──
merge_team_md() {
    # 사용법: merge_team_md <파일명> <마커 이름> <표시 이름>
    # 사용자 내용은 보존하고 프로젝트 파일의 <!-- ai-setup:<마커>:start/end --> 블록만 갱신한다.
    local src="$SCRIPT_DIR/$1" dst="$PROJECT_DIR/$1"
    [ -f "$src" ] || return 0
    [ "$(realpath "$src")" != "$(realpath "$dst" 2>/dev/null || echo "$dst")" ] || return 0

    local begin="<!-- ai-setup:$2:start -->"
    local end="<!-- ai-setup:$2:end -->"
    if [ -f "$dst" ] && grep -qF "$begin" "$dst"; then
        awk -v b="$begin" -v e="$end" -v f="$src" '
            index($0, b) { print; while ((getline line < f) > 0) print line; skip = 1; next }
            index($0, e) { skip = 0 }
            !skip
        ' "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    else
        { [ -f "$dst" ] && printf '\n'; printf '%s\n' "$begin"; cat "$src"; printf '%s\n' "$end"; } >> "$dst"
    fi
    echo -e "${GREEN}  ✅ $3을 $dst 에 병합${NC}"
}

# ── 유틸: 역할 지침 조립 (Claude·Codex 공용) ────────────────
role_prompt_content() {
    # 사용법: role_prompt_content <역할 지침 파일> <역할> <작업 디렉터리>
    # 지침 뒤에 작업 경로 안내(cwd가 프로젝트가 아닐 때)와 lead 팀원 표를 붙여 출력한다.
    local file="$1" role="$2" work_dir="$3" content m
    content="$(cat "$file")"
    # 역할 디렉터리를 작업 대상으로 오인하지 않도록 프로젝트 루트를 알린다.
    if [ "$work_dir" != "$PROJECT_DIR" ]; then
        content+=$'\n\n'"## 작업 경로

현재 셸의 cwd는 역할별 런타임 디렉터리(\`$work_dir\`)이며 작업 대상이 아니다.
**실제 프로젝트 루트는 \`$PROJECT_DIR\` 이다.** 파일을 읽고 쓰거나 git을 다룰 때는
그 경로를 기준으로 하고, 셸 작업이 필요하면 먼저 \`cd $(shell_quote "$PROJECT_DIR")\` 한다."
    fi
    if [ "$role" = "lead" ]; then
        content+=$'\n\n'"## 팀원 배분 (자동 생성)"$'\n\n'"| 역할 | 지시 방법 |"$'\n'"| --- | --- |"
        for ((m = 1; m < ${#MEMBER_NAMES[@]}; m++)); do
            content+=$'\n'"| ${MEMBER_NAMES[$m]} | say ${MEMBER_NAMES[$m]} \"...\" |"
        done
    fi
    printf '%s' "$content"
}

# ── 유틸: Claude 실행 + 다이얼로그 자동 처리 ────────────────
start_claude_in_pane() {
    # 역할별 지침·훅·플러그인을 적용해 Claude를 시작한다.
    local pane="$1" model="${2:-}" role="${3:-}" reasoning_effort="${4:-}"
    local effort_arg="" model_arg=""
    [ -z "$model" ] || model_arg="--model $(shell_quote "$model")"
    [ -z "$reasoning_effort" ] || effort_arg="--effort $(shell_quote "$reasoning_effort")"
    local claude_bin; claude_bin="$(command -v claude)"
    local pane_id="${pane##*:}"   # "team1:0.4" → "0.4". busy 마커·say 큐 키와 형식을 맞춘다.
    local state_key; state_key="$(pane_state_key "$pane")"

    # 역할별 cwd와 설정 소스로 전역 스킬을 차단한다.
    local work_dir="$PROJECT_DIR" skills_arg=""
    if [ -n "$role" ] && [ -d "$TEAM_SKILLS_ROOT/$role/.claude/skills" ]; then
        work_dir="$TEAM_SKILLS_ROOT/$role"
        skills_arg="--setting-sources project"
    fi

    mkdir -p "$RUNTIME_DIR"   # 지침·설정 파일 위치
    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"
    local system_prompt_arg=""
    if [ -n "$role" ] && [ -f "$role_file" ]; then
        # tmux 명령 길이 제한을 피하고 재시작 후에도 읽도록 지침을 파일로 전달한다.
        local prompt_file="$RUNTIME_DIR/${role}.prompt.md"
        role_prompt_content "$role_file" "$role" "$work_dir" > "$prompt_file"
        system_prompt_arg="--append-system-prompt-file $(shell_quote "$prompt_file")"
    elif [ -n "$role" ]; then
        echo -e "${RED}⚠️  team/${role}.md 없음 → 이 파인은 역할 지침 없이 실행됩니다 (MEMBER_NAMES 오타 확인)${NC}" >&2
    fi

    # 훅에는 호출 시점의 파인 번호를 고정한다. 훅에서 조회하면 활성 파인이 잡힌다.
    # project 설정 소스가 제외한 rtk 훅을 다시 주입하고 로깅은 별도 matcher로 둔다.
    # 셸 인용 후 JSON 이스케이프를 적용한다.
    local log_cmd log_cmd_json
    log_cmd="$(shell_quote "$BIN_DIR/log-hook") $(shell_quote "${role:-unknown}") $(shell_quote "$PROJECT_DIR")"
    log_cmd_json="$(json_escape "$log_cmd")"
    local pretooluse_json="\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"rtk hook claude\"}]},{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]}]"

    # 턴 시작에 busy 마커를 만들고 이전 보고 마커를 비운다.
    local userprompt_json="\"UserPromptSubmit\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]},{\"hooks\":[{\"type\":\"command\",\"command\":\"mkdir -p /tmp/team-busy && touch /tmp/team-busy/${state_key} && rm -f /tmp/team-say/${state_key}\"}]}]"

    # /clear·/compact는 Stop 훅 없이 끝날 수 있으므로 SessionStart에서 마커를 지운다.
    local sessionstart_json="\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"rm -f /tmp/team-busy/${state_key}\"}]}]"

    # 무인 파인에서 팀 밖 Claude 메시지가 승인 대기 후 폐기되지 않도록 수신을 허용한다.
    local inbound_json="\"crossSessionInbound\":\"accept\""

    # 200K에서 세션을 유지한 채 압축하고 번들 스킬의 프롬프트 고정비를 줄인다.
    local env_json="\"env\":{\"CLAUDE_CODE_DISABLE_1M_CONTEXT\":\"1\",\"CLAUDE_CODE_DISABLE_BUNDLED_SKILLS\":\"1\"},"

    # project 설정 소스가 제외한 전역 플러그인 설정을 역할별로 명시 주입한다.
    local plugins_json=""
    if [ -n "$role" ]; then
        local enabled_entries=() marketplace_entries=() seen_marketplaces=" "
        for plugin in "${!CLAUDE_PLUGIN_ROLES[@]}"; do
            role_in "${CLAUDE_PLUGIN_ROLES[$plugin]}" "$role" || continue
            enabled_entries+=("\"${plugin}\":true")
            # 출처도 전달해야 해당 마켓플레이스의 플러그인을 찾는다.
            local mp="${plugin##*@}"
            if [[ "$seen_marketplaces" != *" $mp "* ]]; then
                marketplace_entries+=("\"${mp}\":{\"source\":{\"source\":\"github\",\"repo\":\"${CLAUDE_PLUGIN_MARKETPLACES[$mp]}\"}}")
                seen_marketplaces+="$mp "
            fi
        done
        if [ ${#enabled_entries[@]} -gt 0 ]; then
            # IFS 변경을 서브셸에 가둔다. local IFS는 함수 끝까지 남는다.
            plugins_json="\"enabledPlugins\":{$(IFS=,; echo "${enabled_entries[*]}")},\"extraKnownMarketplaces\":{$(IFS=,; echo "${marketplace_entries[*]}")},"
        fi
    fi

    # 공통 Stop 명령을 JSON 문자열로 직렬화한다.
    stop_hook_cmd_for_role "$role" "$pane_id" "$state_key"
    local stop_hook_cmd_json; stop_hook_cmd_json="$(json_escape "$STOP_HOOK_CMD")"

    local settings_arg=""
    if [ -n "$role" ]; then
        # lead의 자기 보고 루프는 Stop 명령에서 막고, 지침만으로 막히지 않는
        # 직접 tmux 전송은 권한 설정으로 차단한다.
        local deny_json=""
        [ "$role" != "lead" ] || deny_json="\"permissions\":{\"deny\":[\"Bash(tmux send-keys:*)\"]},"
        local settings_file="$RUNTIME_DIR/${role}.settings.json"
        printf '%s' "{${plugins_json}${deny_json}${env_json}${inbound_json},\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${stop_hook_cmd_json}\"}]}],${pretooluse_json},${userprompt_json},${sessionstart_json}}}" > "$settings_file"
        settings_arg="--settings $(shell_quote "$settings_file")"
    fi

    # 부모 Claude 세션 감지를 해제하고 say 실행 경로를 추가한다.
    tmux send-keys -t "$pane" \
        "cd $(shell_quote "$work_dir") && unset CLAUDECODE && export PATH=$(shell_quote "${TEAM_PATH:-$PATH}") && export CAVEMAN_DEFAULT_MODE=full && $(shell_quote "$claude_bin") $model_arg $effort_arg --dangerously-skip-permissions $skills_arg $system_prompt_arg $settings_arg" Enter

    wait_claude_ready "$pane" 60 || {
        echo -e "${RED}⚠️  Claude 준비 화면을 확인하지 못했습니다 (60초 초과)${NC}" >&2
        return 1
    }
    return 0
}

# ── Codex 역할 지침 및 실행 ──────────────────────────────────
write_codex_role_agents() {
    # 역할 지침과 lifecycle 훅을 생성하고 소유권을 기록한다.
    local role="$1" work_dir="$2" pane_id="$3" state_key="$4"
    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"

    if [ -z "$role" ] || [ ! -f "$role_file" ]; then
        echo -e "${RED}⚠️  team/${role}.md 없음 → Codex 역할 지침을 만들지 않습니다 (MEMBER_NAMES 오타 확인)${NC}" >&2
        return 1
    fi

    mkdir -p "$work_dir"
    local agents_content
    agents_content="$(printf '%s\n\n%s' '# Generated by ai-setup. Edit team/{role}.md instead.' "$(role_prompt_content "$role_file" "$role" "$work_dir")")"$'\n'
    # 정리 후 남은 파일·링크는 사용자 소유로 취급하고 덮어쓰지 않는다.
    if [ -e "$work_dir/AGENTS.md" ] || [ -L "$work_dir/AGENTS.md" ]; then
        team_owned_adopt_identical "$work_dir" AGENTS.md "$agents_content" ||
            echo -e "${YELLOW}  ⚠️  $role: 기존 AGENTS.md가 있어 갱신을 건너뜁니다 (기존 파일 보존, team/${role}.md 변경은 반영되지 않음)${NC}" >&2
    else
        printf '%s' "$agents_content" > "$work_dir/AGENTS.md"
        team_owned_record "$work_dir" F "AGENTS.md" "$(sha256sum < "$work_dir/AGENTS.md" | cut -d' ' -f1)"
    fi

    # 공통 Stop 로직을 사용하고 로컬 훅 신뢰 승인은 기동 시 처리한다.
    [ -n "$pane_id" ] || return 0
    stop_hook_cmd_for_role "$role" "$pane_id" "$state_key"
    local hook_cmd_json; hook_cmd_json="$(json_escape "$STOP_HOOK_CMD")"
    local session_start_cmd_json; session_start_cmd_json="$(json_escape "rm -f /tmp/team-busy/${state_key}")"
    local log_cmd_json
    log_cmd_json="$(json_escape "$(shell_quote "$BIN_DIR/log-hook") $(shell_quote "${role:-unknown}") $(shell_quote "$PROJECT_DIR") --quiet")"
    local log_hook_json="[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]}]"
    # 보고 마커는 턴마다 비운다. Codex busy 마커는 say가 관리한다.
    local report_clear_json; report_clear_json="$(json_escape "rm -f /tmp/team-say/${state_key}")"
    local userprompt_json="[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]},{\"hooks\":[{\"type\":\"command\",\"command\":\"${report_clear_json}\"}]}]"
    local hooks_json="{\"hooks\":{\"SessionStart\":[{\"matcher\":\"startup|resume|clear|compact\",\"hooks\":[{\"type\":\"command\",\"command\":\"${session_start_cmd_json}\"}]}],\"UserPromptSubmit\":${userprompt_json},\"PreToolUse\":${log_hook_json},\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${hook_cmd_json}\"}]}]}}"
    mkdir -p "$work_dir/.codex"
    # 정리 뒤에도 남아 있는 hooks.json은 사용자 파일이므로 덮어쓰지 않는다.
    if [ -e "$work_dir/.codex/hooks.json" ] || [ -L "$work_dir/.codex/hooks.json" ]; then
        team_owned_adopt_identical "$work_dir" .codex/hooks.json "$hooks_json" ||
            echo -e "${YELLOW}  ⚠️  $role: 기존 .codex/hooks.json이 있어 갱신을 건너뜁니다 (기존 훅 보존, 현재 세션용 종료 신호·busy 마커 경로는 갱신되지 않음)${NC}" >&2
        return 0
    fi
    printf '%s' "$hooks_json" > "$work_dir/.codex/hooks.json"
    team_owned_record "$work_dir" F ".codex/hooks.json" "$(sha256sum < "$work_dir/.codex/hooks.json" | cut -d' ' -f1)"
}

start_codex_in_pane() {
    # 격리된 역할 홈으로 Codex를 시작하고 신뢰 승인을 처리한다.
    local pane="$1" model="${2:-}" role="${3:-}" reasoning_effort="${4:-}"
    local codex_bin; codex_bin="$(command -v codex)"
    # 세션은 매번 새로 만들어 파인이 빈 셸이므로, 이전 화면·프로세스 정리는 하지 않는다.

    local pane_id="${pane##*:}"   # busy 마커·say 큐 키와 형식을 맞춘다(Claude와 동일).
    local state_key; state_key="$(pane_state_key "$pane")"

    local work_dir="$PROJECT_DIR"
    if [ -n "$role" ] && [ -d "$TEAM_SKILLS_ROOT/$role" ]; then
        work_dir="$TEAM_SKILLS_ROOT/$role"
    fi
    local role_codex_home="$work_dir/.codex-home"
    write_codex_role_agents "$role" "$work_dir" "$pane_id" "$state_key" || true

    local model_arg=""
    [ -z "$model" ] || model_arg="--model $(shell_quote "$model")"

    local reasoning_arg=""
    [ -z "$reasoning_effort" ] || reasoning_arg="-c $(shell_quote "model_reasoning_effort=\"$reasoning_effort\"")"

    # git 쓰기를 허용하는 기본값. CODEX_FULL_ACCESS=0이면 읽기 전용 .git 경계로 복원한다.
    local permission_args="--dangerously-bypass-approvals-and-sandbox"
    if [ "${CODEX_FULL_ACCESS:-1}" = "0" ]; then
        permission_args="--ask-for-approval never --sandbox workspace-write"
    fi

    # sandbox 모드에서도 프로젝트와 say IPC 경로를 쓸 수 있도록 추가한다.
    # tmux 소켓의 seccomp 차단을 푸는 network_access는 외부 통신도 허용한다.
    # 파일 쓰기 경계는 --add-dir로 별도 유지한다.
    local tmux_tmpdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
    tmux send-keys -t "$pane" \
        "cd $(shell_quote "$work_dir") && export CODEX_HOME=$(shell_quote "$role_codex_home") && export PATH=$(shell_quote "${TEAM_PATH:-$PATH}") && $(shell_quote "$codex_bin") $permission_args --dangerously-bypass-hook-trust --add-dir $(shell_quote "$PROJECT_DIR") --add-dir $(shell_quote "$tmux_tmpdir") --add-dir /tmp/team-busy --add-dir /tmp/team-say --add-dir /tmp/team-say-queue -c 'sandbox_workspace_write.network_access=true' -c check_for_update_on_startup=false $model_arg $reasoning_arg" Enter

    # 프로젝트 신뢰 대화상자 또는 입력 화면을 기다린다. 둘 다 없으면 실패한다.
    local trust_pattern="Do you trust the contents\|Trust this folder?"
    wait_for_pane "$pane" "$trust_pattern\|Ask Codex to do anything" 30 || {
        echo -e "${RED}⚠️  Codex 준비 화면을 확인하지 못했습니다 (30초 초과)${NC}" >&2
        return 1
    }
    # Codex는 입력 화면을 잠깐 그린 뒤 신뢰 대화상자로 바꾸므로, 입력 화면이 보여도 대화상자를 잠시 더 기다린다.
    if wait_for_pane "$pane" "$trust_pattern" 3; then
        tmux send-keys -t "$pane" Enter
        sleep 1
        wait_for_pane "$pane" "Ask Codex to do anything" 30 || {
            echo -e "${RED}⚠️  Codex 신뢰 확인 후 입력 프롬프트가 뜨지 않았습니다 (30초 초과)${NC}" >&2
            return 1
        }
    fi

    # 우회 플래그만으로 활성화되지 않는 로컬 훅을 준비 완료 후 /hooks에서 신뢰한다.
    tmux send-keys -t "$pane" -l "/hooks"
    # 입력줄에 /hooks가 보이고 실제 훅 메뉴가 열린 뒤에만 신뢰("t")를 보낸다.
    # 고정 sleep은 느린 기동에서 키를 흘려 입력줄에 "/hookst"를 남긴다.
    if wait_for_pane "$pane" "^› /hooks" 10; then
        tmux send-keys -t "$pane" Enter
        if wait_for_pane "$pane" "Lifecycle hooks from" 10; then
            tmux send-keys -t "$pane" -l "t"
            sleep 1
            tmux send-keys -t "$pane" Escape
        else
            echo -e "${RED}⚠️  /hooks 메뉴가 열리지 않아 훅 신뢰를 건너뜁니다: $pane${NC}" >&2
            tmux send-keys -t "$pane" C-u
        fi
    else
        echo -e "${RED}⚠️  /hooks 입력이 화면에 보이지 않아 훅 신뢰를 건너뜁니다: $pane${NC}" >&2
        tmux send-keys -t "$pane" C-u
    fi
    # 고정 3초 대신 입력 화면 복귀를 기다린다. 보이지 않아도 기동은 성공으로 둔다.
    wait_for_pane "$pane" "Ask Codex to do anything" 3 || true
    return 0
}

# ── claude 로그인 확인 ────────────────
check_login() {
    # Claude 로그인 상태를 확인한다.
    claude auth status >/dev/null 2>&1
}

check_codex_login() {
    # Codex 로그인 상태를 확인한다.
    codex login status >/dev/null 2>&1
}

# ── [0/7] 공통 (Claude·Codex) — 사전 요구사항 확인 ─────────
used_agents_list="${!USED_AGENTS[*]}"
# 표시 번호는 실제로 도는 단계만 센다 — 단일 공급자 팀에서 번호가 건너뛰지 않게.
STEP=0
STEP_TOTAL=2
[ -n "${USED_AGENTS[claude]:-}" ] && STEP_TOTAL=$((STEP_TOTAL + 3))
[ -n "${USED_AGENTS[codex]:-}" ] && STEP_TOTAL=$((STEP_TOTAL + 2))
echo -e "${YELLOW}[$((STEP++))/$STEP_TOTAL] 공통 (Claude·Codex) — 사전 요구사항 확인 (${used_agents_list})...${NC}"

NEED_FIRST_LOGIN=false

MISSING=()
command -v tmux &>/dev/null || MISSING+=("tmux (apt-get install -y tmux)")
if [ -n "${USED_AGENTS[claude]:-}" ]; then
    command -v claude &>/dev/null || MISSING+=("claude (npm install -g @anthropic-ai/claude-code)")
    command -v rtk    &>/dev/null || MISSING+=("rtk (curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)")
fi
if [ -n "${USED_AGENTS[codex]:-}" ]; then
    command -v codex &>/dev/null || MISSING+=("codex (npm install -g @openai/codex)")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}❌ 누락된 의존성:${NC}"
    for m in "${MISSING[@]}"; do echo "   - $m"; done
    exit 1
fi

echo "  ✅ tmux $(tmux -V | awk '{print $2}')"
if [ -n "${USED_AGENTS[claude]:-}" ]; then
    echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"

    echo -n "  Claude 로그인 확인... "
    if check_login; then
        echo -e "${GREEN}✅ 로그인 완료${NC}"
    else
        NEED_FIRST_LOGIN=true
        echo -e "${YELLOW}로그인이 필요합니다.${NC}"
        echo
        echo "Claude를 실행합니다."
        echo "컨테이너 안에서 /login 을 완료하세요."
        echo
        claude
        echo
        read -p "로그인이 완료되었다면 Enter를 누르세요..."
        if ! check_login; then
            echo -e "${RED}❌ 로그인이 확인되지 않았습니다.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ 로그인 확인 완료${NC}"
    fi

    echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"
fi
if [ -n "${USED_AGENTS[codex]:-}" ]; then
    echo "  ✅ codex $(codex --version 2>/dev/null | head -1)"
    echo -n "  Codex 로그인 확인... "
    if check_codex_login; then
        echo -e "${GREEN}✅ 로그인 완료${NC}"
    else
        echo -e "${YELLOW}로그인이 필요합니다.${NC}"
        echo
        echo "codex login을 실행해 로그인을 완료하세요."
        echo
        codex login
        echo
        read -p "로그인이 완료되었다면 Enter를 누르세요..."
        if ! check_codex_login; then
            echo -e "${RED}❌ 로그인이 확인되지 않았습니다.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ 로그인 확인 완료${NC}"
    fi
fi

# 실행 중인 파인과 생성 파일 갱신이 경합하지 않도록 기존 세션부터 종료한다.
tmux has-session -t "$SESSION" 2>/dev/null && {
    tmux kill-session -t "$SESSION"
    # 비동기 정리가 끝나기 전에 같은 이름으로 세션을 재생성하지 않도록 기다린다.
    for _ in $(seq 1 20); do
        tmux has-session -t "$SESSION" 2>/dev/null || break
        sleep 0.2
    done
    echo ""
    echo "  🧹 기존 '$SESSION' 세션 종료"
}

# 공급자별 준비 결과가 서로 지워지지 않도록 공통 런타임은 한 번만 정리한다.
TEAM_SKILLS_ROOT="$PROJECT_DIR/.team"
RUNTIME_DIR="$TEAM_SKILLS_ROOT/_runtime"

reset_generated_team_files() {
    # 런타임과 기록에 일치하는 생성물만 정리한다. 사용자 파일·수정본·설치 캐시는 보존한다.
    local dir name
    rm -rf "$RUNTIME_DIR"
    for dir in "$TEAM_SKILLS_ROOT"/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        case "$name" in _runtime|_assets) continue ;; esac
        team_owned_clean "${dir%/}"
    done
}

mkdir -p "$TEAM_SKILLS_ROOT"
reset_generated_team_files
mkdir -p "$RUNTIME_DIR"

if [ -n "${USED_AGENTS[claude]:-}" ]; then

# ── [1/7] Claude — rtk 훅 초기화 ───────────────────────────
# 로그인 후 생성되는 설정에 훅을 등록한다.
# 비대화형 telemetry 동의 대기는 환경변수·응답·timeout으로 차단한다.
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Claude — rtk 훅 초기화...${NC}"

if printf 'n\n' | RTK_TELEMETRY_DISABLED=1 timeout 15 rtk init -g --auto-patch; then
    echo -e "  ${GREEN}✅  rtk 훅 등록 완료${NC}"
else
    echo -e "  ${YELLOW}⚠️  rtk init 실패 또는 timeout (이미 설정되어 있거나 수동 확인 필요)${NC}"
    echo -e "  ${YELLOW}   확인: rtk init --show${NC}"
fi


# ── [2/7] Claude — 필요한 플러그인 설치 ──────────────────────
# 역할별 활성화는 실행 시 --settings로 전달한다. 전역 설정은 바꾸지 않는다.
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Claude — 필요한 플러그인 설치...${NC}"


install_claude_plugins() {
    # 설치된 것은 표시만 하고 필요한 미설치 플러그인과 마켓플레이스만 추가한다.
    local key mp roles_label mp_done=" " keys=() to_install=() out
    if [ "${#CLAUDE_PLUGIN_ROLES[@]}" -gt 0 ]; then
        mapfile -t keys < <(printf '%s\n' "${!CLAUDE_PLUGIN_ROLES[@]}" | sort)
    fi
    for key in "${keys[@]}"; do
        roles_label="${CLAUDE_PLUGIN_ROLES[$key]:-(설치만)}"
        if claude_plugin_dir "$key" >/dev/null; then
            echo "  ℹ️  $key 이미 설치됨 → $roles_label"
        elif provider_plugin_needed claude "$key"; then
            to_install+=("$key")
        else
            echo "  ⏭️  $key 건너뜀 (Claude 역할에 필요 없음)"
        fi
    done

    for key in "${to_install[@]}"; do
        mp="${key##*@}"
        [[ "$mp_done" != *" $mp "* ]] || continue
        mp_done+="$mp "
        [ -n "${CLAUDE_PLUGIN_MARKETPLACES[$mp]:-}" ] || continue
        # 이미 등록돼 있으면 add가 실패하지만 무해하므로 실패를 삼킨다.
        out="$(claude plugin marketplace add "${CLAUDE_PLUGIN_MARKETPLACES[$mp]}" 2>&1)" || true
        if [[ "$out" == *"already on disk"* ]]; then
            echo "  ℹ️  marketplace $mp 이미 등록됨"
        fi
    done

    # 전역 세션에 영향을 주는 plugin enable 대신 역할별 실행 설정으로 활성화한다.
    for key in "${to_install[@]}"; do
        if out="$(claude plugin install "$key" 2>&1)"; then
            echo "  ✅  $key 새로 설치됨 → ${CLAUDE_PLUGIN_ROLES[$key]:-(설치만)}"
        else
            echo -e "${YELLOW}  ⚠️  $key 설치 실패 (수동 확인: claude plugin install $key)${NC}"
        fi
    done
}
install_claude_plugins

# ── [3/7] Claude — 역할별 스킬 제한 ────────────────────────
# 역할별 cwd에 필요한 스킬만 링크하고 project 설정 소스로 전역 스킬을 차단한다.
# 제외되는 전역 훅·플러그인 설정은 실행 시 명시 주입한다.
# 홈 아래 프로젝트에서는 전역 rules·CLAUDE.md가 계속 로드된다.
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Claude — 런타임 준비 (공통 지침 병합·역할별 스킬 제한)...${NC}"

# 배분은 CLAUDE_{플러그인}_SKILL_SETS를 따른다. 스킬이 없어도 역할 cwd는 만든다.
# 전역 규칙은 홈 아래 프로젝트에서 자동 상속하므로 별도로 주입하지 않는다.

merge_team_md CLAUDE.md team "팀 공통 지침"

for ((role_index = 0; role_index < PANE_COUNT; role_index++)); do
    [ "${MEMBER_AGENTS[$role_index]}" = "claude" ] || continue
    role="${MEMBER_NAMES[$role_index]}"
    role_skills_dir="$TEAM_SKILLS_ROOT/$role/.claude/skills"
    mkdir -p "$role_skills_dir"
    granted=()
    for plugin_key in "${!CLAUDE_PLUGIN_ROLES[@]}"; do
        plugin="${plugin_key%@*}"
        role_skill_list="$(plugin_skill_set CLAUDE "$plugin" "$role")"
        [ -n "$role_skill_list" ] || continue
        # 설치 명세가 가리키는 그 마켓플레이스의 설치본만 쓴다(동명 플러그인 오인 방지).
        plugin_root=""
        if plugin_dir="$(claude_plugin_dir "$plugin_key")"; then
            plugin_root="$plugin_dir/skills"
        fi
        link_plugin_skills "$plugin" "$plugin_root" $role_skill_list
    done
    echo "  $role: ${granted[*]:-(Claude 역할별 스킬 없음)}"
done
echo -e "${GREEN}  ✅ Claude 역할별 런타임 디렉터리 준비 완료${NC}"

fi

if [ -n "${USED_AGENTS[codex]:-}" ]; then

# ── [4/7] Codex — 필요한 플러그인 설치 ────────────────────────────
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Codex — 필요한 플러그인 설치...${NC}"

base_codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_assets_home="$TEAM_SKILLS_ROOT/_assets/codex-home"

codex_default_model_config() {
    # 첫 TOML 테이블 앞의 기본 모델·추론 설정만 읽는다. 없는 파일·키는 생략한다.
    [ -f "$1/config.toml" ] || return 0
    awk '/^[[:space:]]*\[/ { exit } /^[[:space:]]*(model|model_reasoning_effort)[[:space:]]*=/ { print }' "$1/config.toml"
}

write_codex_role_plugins() {
    # 기본 모델 설정을 매번 상속하고 배정 플러그인만 켠다. 명시한 실행 인자가 우선한다.
    local role="$1" role_home="$2" plugin
    mkdir -p "$role_home"
    {
        codex_default_model_config "${base_codex_home:-}"
        printf '[plugins._default]\nenabled = false\n'
        for plugin in "${!CODEX_PLUGIN_ROLES[@]}"; do
            role_in "${CODEX_PLUGIN_ROLES[$plugin]}" "$role" || continue
            printf '\n[plugins."%s"]\nenabled = true\n' "$plugin"
        done
    } > "$role_home/config.toml"
}

link_codex_base_assets() {
    # 인증·시스템 스킬·공식 marketplace snapshot(카탈로그)을 기본 홈에서 연결한다.
    # config·plugin cache는 홈마다 분리된 채 유지된다.
    local home="$1"
    mkdir -p "$home/skills" "$home/.tmp"
    if [ -f "$base_codex_home/auth.json" ]; then
        ln -sfn "$(realpath "$base_codex_home/auth.json")" "$home/auth.json"
    fi
    if [ -d "$base_codex_home/skills/.system" ]; then
        ln -sfn "$(realpath "$base_codex_home/skills/.system")" "$home/skills/.system"
    fi
    # 원격 카탈로그(openai-curated-remote) 플러그인은 snapshot 없이도 설치된다.
    if [ -d "$base_codex_home/.tmp/plugins" ] && [ -f "$base_codex_home/.tmp/plugins.sha" ]; then
        ln -sfn "$(realpath "$base_codex_home/.tmp/plugins")" "$home/.tmp/plugins"
        ln -sfn "$(realpath "$base_codex_home/.tmp/plugins.sha")" "$home/.tmp/plugins.sha"
    fi
}

codex_shared_plugin_cache() {
    # 대상 홈을 제외하고 기본 홈 → 자산 홈 → 다른 역할 홈에서 설치본을 찾는다.
    local key="$1" skip="$2" home
    for home in "$base_codex_home" "$codex_assets_home" "$TEAM_SKILLS_ROOT"/*/.codex-home; do
        [ -d "$home" ] || continue
        [ "$home" != "$skip" ] || continue
        codex_plugin_cache "$home" "$key" && return 0
    done
    return 1
}

prepare_codex_role_home() {
    # 역할 홈을 재사용하며 다른 홈의 설치본은 재설치 없이 연결한다.
    local role="$1" role_home="$2" plugin
    mkdir -p "$role_home/skills"
    write_codex_role_plugins "$role" "$role_home"
    link_codex_base_assets "$role_home"
    if ! CODEX_HOME="$role_home" codex login status >/dev/null 2>&1; then
        echo -e "${RED}  ❌ $role: 격리된 CODEX_HOME에서 기존 Codex 인증을 사용할 수 없습니다.${NC}" >&2
        return 1
    fi

    local role_plugins=()
    for plugin in "${!CODEX_PLUGIN_ROLES[@]}"; do
        role_in "${CODEX_PLUGIN_ROLES[$plugin]}" "$role" || continue
        role_plugins+=("$plugin")
    done
    [ ${#role_plugins[@]} -gt 0 ] || return 0

    local base_cache link_dir
    for plugin in "${role_plugins[@]}"; do
        if codex_plugin_cache "$role_home" "$plugin" >/dev/null; then
            echo "  ℹ️  $plugin 이미 설치됨 → $role"
        elif base_cache="$(codex_shared_plugin_cache "$plugin" "$role_home")"; then
            # 캐시만 공유하고 활성화는 역할별 config.toml로 격리한다.
            link_dir="$role_home/plugins/cache/${plugin##*@}/${plugin%@*}"
            mkdir -p "$(dirname "$link_dir")"
            [ -L "$link_dir" ] || rm -rf "$link_dir"
            ln -sfn "$(realpath "$(dirname "$base_cache")")" "$link_dir"
            echo "  ℹ️  $plugin 로컬에 이미 설치됨(다른 홈 설치본 재사용) → $role"
        elif CODEX_HOME="$role_home" codex plugin add "$plugin" >/dev/null; then
            echo "  ✅  $plugin 새로 설치됨 → $role"
        else
            echo -e "${YELLOW}  ⚠️  $role: Codex 플러그인 설치 실패: $plugin${NC}" >&2
        fi
    done
}

codex_plugin_skills_root() {
    # 기본 홈 → 자산 홈 → 역할 홈 → 공식 snapshot 순으로 스킬 원본을 찾는다.
    local key="$1" home version
    for home in "$base_codex_home" "$codex_assets_home" "$TEAM_SKILLS_ROOT"/*/.codex-home; do
        [ -d "$home" ] || continue
        if version="$(codex_plugin_cache "$home" "$key")" && [ -d "$version/skills" ]; then
            printf '%s\n' "$version/skills"
            return 0
        fi
    done
    if [[ "${key##*@}" == openai-curated* ]] && [ -d "$base_codex_home/.tmp/plugins/plugins/${key%@*}/skills" ]; then
        printf '%s\n' "$base_codex_home/.tmp/plugins/plugins/${key%@*}/skills"
        return 0
    fi
    return 1
}

prepare_codex_skill_sources() {
    # 선택 스킬에만 필요한 설치본은 전역 설정을 건드리지 않도록 팀 자산 홈에 둔다.
    local key role i has_skill_source activated keys=() roles
    if [ "${#CODEX_PLUGIN_ROLES[@]}" -gt 0 ]; then
        mapfile -t keys < <(printf '%s\n' "${!CODEX_PLUGIN_ROLES[@]}" | sort)
    fi
    for key in "${keys[@]}"; do
        if ! provider_plugin_needed codex "$key"; then
            if codex_plugin_cache "$base_codex_home" "$key" >/dev/null; then
                echo "  ℹ️  $key 이미 설치됨 (Codex 역할에 필요 없음)"
            else
                echo "  ⏭️  $key 건너뜀 (Codex 역할에 필요 없음)"
            fi
            continue
        fi
        has_skill_source=false
        for ((i = 0; i < PANE_COUNT; i++)); do
            [ "${MEMBER_AGENTS[$i]}" = "codex" ] || continue
            role="${MEMBER_NAMES[$i]}"
            [ -z "$(plugin_skill_set CODEX "${key%@*}" "$role")" ] || has_skill_source=true
        done
        [ "$has_skill_source" = true ] || continue
        if codex_plugin_skills_root "$key" >/dev/null; then
            echo "  ℹ️  $key 스킬 원본 이미 있음"
            continue
        fi
        # 활성화하는 Codex 역할이 있으면 역할 홈 준비에서 설치되므로 여기서 또 설치하지 않는다.
        activated=false
        roles="${CODEX_PLUGIN_ROLES[$key]:-}"
        for ((i = 0; i < PANE_COUNT; i++)); do
            [ "${MEMBER_AGENTS[$i]}" = "codex" ] || continue
            if role_in "$roles" "${MEMBER_NAMES[$i]}"; then activated=true; fi
        done
        if [ "$activated" = true ]; then
            echo "  ℹ️  $key 역할 홈 설치본을 스킬 원본으로 사용"
            continue
        fi
        link_codex_base_assets "$codex_assets_home"
        if CODEX_HOME="$codex_assets_home" codex plugin add "$key" >/dev/null; then
            echo "  ✅  $key 스킬 원본으로 새로 설치됨"
        else
            echo -e "${YELLOW}  ⚠️  Codex 플러그인 설치 실패: $key (스킬 원본)${NC}" >&2
        fi
    done
}

find_codex_skill_source() {
    # 프로젝트·사용자·시스템 순으로 독립 스킬 원본을 찾는다.
    local skill="$1" candidate
    for candidate in \
        "$PROJECT_DIR/.agents/skills/$skill" \
        "$HOME/.agents/skills/$skill" \
        "$HOME/.codex/skills/$skill" \
        "$HOME/.codex/skills/.system/$skill"; do
        if [ -f "$candidate/SKILL.md" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

prepare_codex_skill_sources

for ((role_index = 0; role_index < PANE_COUNT; role_index++)); do
    [ "${MEMBER_AGENTS[$role_index]}" = "codex" ] || continue
    role="${MEMBER_NAMES[$role_index]}"
    prepare_codex_role_home "$role" "$TEAM_SKILLS_ROOT/$role/.codex-home"
done

# ── [5/7] Codex — 런타임 준비 ────────────────────────────
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Codex — 런타임 준비 (공통 지침 병합·역할별 스킬 제한)...${NC}"
merge_team_md AGENTS.md codex "Codex 팀 공통 지침"

link_codex_standalone_skills() {
    # 호출 측의 role·role_skills_dir·granted를 쓴다. CODEX_SKILL_SETS[역할]의 standalone
    # 스킬을 링크하되, 이미 있는 사용자 항목은 덮어쓰지 않고 새 링크만 소유 기록에 남긴다.
    local skill src
    for skill in ${CODEX_SKILL_SETS[$role]:-}; do
        case "$skill" in
            ""|.|..|*/*)
                echo -e "${YELLOW}  ⚠️  $role: Codex 스킬 이름 '$skill'은 사용할 수 없습니다.${NC}" >&2
                continue
                ;;
        esac
        src="$(find_codex_skill_source "$skill")" || {
            echo -e "${YELLOW}  ⚠️  $role: Codex 스킬 '$skill' 없음 (.agents/skills 또는 .codex/skills 확인)${NC}" >&2
            continue
        }
        link_owned_skill "$(realpath "$src")" "$role_skills_dir/$skill" "$TEAM_SKILLS_ROOT/$role" || continue
        granted+=("$skill")
    done
}

for ((role_index = 0; role_index < PANE_COUNT; role_index++)); do
    [ "${MEMBER_AGENTS[$role_index]}" = "codex" ] || continue
    role="${MEMBER_NAMES[$role_index]}"
    role_skills_dir="$TEAM_SKILLS_ROOT/$role/.agents/skills"
    mkdir -p "$role_skills_dir"
    granted=()
    link_codex_standalone_skills

    for plugin_key in "${!CODEX_PLUGIN_ROLES[@]}"; do
        plugin="${plugin_key%@*}"
        role_skill_list="$(plugin_skill_set CODEX "$plugin" "$role")"
        [ -n "$role_skill_list" ] || continue
        plugin_root="$(codex_plugin_skills_root "$plugin_key" || true)"
        link_plugin_skills "$plugin" "$plugin_root" $role_skill_list
    done
    echo "  $role: ${granted[*]:-(Codex 역할별 스킬 없음)}"
done
echo -e "${GREEN}  ✅ Codex 역할별 런타임 디렉터리 준비 완료${NC}"

fi

# ── [6/7] 공통 (Claude·Codex) — TMUX 세션 & 레이아웃 구성 ─
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] 공통 (Claude·Codex) — TMUX 세션 & 레이아웃 구성...${NC}"

# 초기 레이아웃에 충분한 크기를 확보한다. 접속 후에는 클라이언트 크기를 따른다.
create_team_session() {
    # 팀 창·파인 번호만 0부터 맞추고 사용자 전역 설정은 유지한다.
    local first_window
    tmux new-session -d -s "$SESSION" -x 220 -y 50
    tmux set-environment -t "$SESSION" PATH "${TEAM_PATH:-$PATH}"   # 세션 범위만 — 전역 환경은 건드리지 않는다
    first_window="$(tmux list-windows -t "$SESSION" -F '#{window_index}' | head -1)"
    tmux set-window-option -t "$SESSION:$first_window" pane-base-index 0
    if [ "$first_window" != 0 ]; then
        tmux move-window -s "$SESSION:$first_window" -t "$SESSION:0"
    fi
}
create_team_session

for ((i = 0; i < PANE_COUNT - 1; i++)); do
    tmux split-window -t "$SESSION:0.$i" -h
done

# 균등 배치 후 main-vertical로 전환해야 좁은 파인이 생기지 않는다.
tmux select-layout -t "$SESSION:0" even-horizontal
# main-pane-width는 레이아웃 계산 전에 설정한다.
tmux set-option -t "$SESSION" main-pane-width '55%'
tmux select-layout -t "$SESSION:0" main-vertical

for ((pane = 0; pane < PANE_COUNT; pane++)); do
    display_name="${MEMBER_DISPLAY_NAMES[$pane]:-${MEMBER_NAMES[$pane]}}"
    tmux select-pane -t "$SESSION:0.$pane" -T "${display_name^^}"
    tmux set-option -p -t "$SESSION:0.$pane" @role "${MEMBER_NAMES[$pane]}"
    # pane_title은 에이전트 CLI의 OSC 제목 변경 대상이다. 테두리에 보일
    # 이름은 별도 pane 옵션으로 보관해야 CLI 제목과 경합하지 않는다.
    tmux set-option -p -t "$SESSION:0.$pane" @display_name "${display_name^^}"
done

tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{@display_name} "
tmux set-option -t "$SESSION" set-titles on
tmux set-option -t "$SESSION" set-titles-string "#{@display_name}"
tmux set-option -t "$SESSION" allow-rename off
tmux set-option -t "$SESSION" mouse on

echo "  ✅ 레이아웃 구성 완료 (${PANE_COUNT} panes)"

# ── [7/7] 공통 (Claude·Codex) — 에이전트 자동 실행 ────────
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] 공통 (Claude·Codex) — 파인별 에이전트 실행 중 (${used_agents_list})... (병렬, 최대 1분)${NC}"

# codex의 --add-dir는 존재하는 경로만 받는다. say의 lazy mkdir은
# codex sandbox(workspace-write) 안에서 막히므로 파인 기동 전에 미리 만든다.
mkdir -p /tmp/team-busy /tmp/team-say /tmp/team-say-queue

start_agent_in_pane() {
    # 파인 하나에 에이전트를 띄우고 보존된 say 큐를 다시 가동한다.
    local pane="$1"
    if [ "${MEMBER_AGENTS[$pane]}" = "claude" ]; then
        start_claude_in_pane "$SESSION:0.$pane" "${SPEC_MEMBER_MODELS[$pane]}" "${MEMBER_NAMES[$pane]}" "${SPEC_MEMBER_REASONING_EFFORTS[$pane]}" || return $?
    else
        start_codex_in_pane "$SESSION:0.$pane" "${SPEC_MEMBER_MODELS[$pane]}" "${MEMBER_NAMES[$pane]}" "${SPEC_MEMBER_REASONING_EFFORTS[$pane]}" || return $?
    fi

    # 이전 watcher 종료로 남은 큐도 파인 준비 후 다시 가동한다.
    "$BIN_DIR/say" --drain "$SESSION:0.$pane"
}

# 최초 Claude 로그인은 첫 파인에서 마친 뒤 나머지를 병렬 시작한다.
# 병렬 출력은 역할별 파일에 모아 순서대로 표시한다.
start_pids=() start_rcs=() failed_panes=()
launch_pane() {
    # 파인 기동을 백그라운드로 시작하고 PID를 기록한다.
    start_agent_in_pane "$1" > "$RUNTIME_DIR/pane-start-$1.log" 2>&1 &
    start_pids[$1]=$!
}
first_pane=-1
if [ "$NEED_FIRST_LOGIN" = true ]; then
    for ((pane = 0; pane < PANE_COUNT; pane++)); do
        if [ "${MEMBER_AGENTS[$pane]}" = "claude" ]; then first_pane=$pane; break; fi
    done
fi
if [ "$first_pane" -ge 0 ]; then
    launch_pane "$first_pane"
    wait "${start_pids[$first_pane]}" && start_rcs[$first_pane]=0 || start_rcs[$first_pane]=$?
fi
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    [ "$pane" -ne "$first_pane" ] || continue
    launch_pane "$pane"
done

for ((pane = 0; pane < PANE_COUNT; pane++)); do
    [ -n "${start_rcs[$pane]:-}" ] ||
        { wait "${start_pids[$pane]}" && start_rcs[$pane]=0 || start_rcs[$pane]=$?; }
    echo -n "  Pane $pane (${MEMBER_NAMES[$pane]}, ${MEMBER_AGENTS[$pane]} · ${SPEC_MEMBER_MODELS[$pane]:-기본} · ${SPEC_MEMBER_REASONING_EFFORTS[$pane]:-기본}): "
    if [ "${start_rcs[$pane]}" -eq 0 ]; then
        echo -e "${GREEN}✅ 실행 완료${NC}"
    else
        echo -e "${RED}❌ 실행 실패 (종료 코드 ${start_rcs[$pane]})${NC}"
        failed_panes+=("${MEMBER_NAMES[$pane]}")
    fi
    sed 's/^/    /' "$RUNTIME_DIR/pane-start-$pane.log"
done

# ── 완료 ────────────────────────────────────────────────────
# 실패 시 세션을 남겨 attach로 확인할 수 있게 한다.
if [ ${#failed_panes[@]} -gt 0 ]; then
    echo -e "\n${RED}❌ 기동 실패 파인: ${failed_panes[*]} — tmux attach -t $SESSION 으로 화면을 확인하세요.${NC}" >&2
    exit 1
fi
echo -e "\n${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   ✅ 팀 환경 구성 완료!              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"
echo "tmux attach -t $SESSION 으로 접속하세요."

# 비대화형 실행이 test의 false 상태로 끝나지 않도록 명시적 if를 사용한다.
if [ -t 1 ]; then
    tmux attach -t "$SESSION"
fi

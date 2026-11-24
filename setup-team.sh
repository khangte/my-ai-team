#!/usr/bin/env bash
# tmux 기반 Claude/Codex 팀 구성. 역할·모델은 team/members.conf에서 설정한다.
# 사용: ./setup-team.sh [프로젝트_경로]
# 경로 생략 시 $PROJECT_DIR, 그것도 없으면 현재 디렉터리를 사용한다.

set -e

# 연관 배열·mapfile·${var^^}는 bash 4+가 필요하다. macOS 기본 bash 3.2는 여기서 막는다.
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo "bash 4+ 필요 (현재 $BASH_VERSION). macOS는 install/mac.sh 안내대로 Homebrew bash로 실행하세요." >&2; exit 1; }

# team/{role}.md 지침 파일 위치. 이 스크립트(ai-setup 리포) 기준이므로 PROJECT_DIR과 무관하다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_DIR="$SCRIPT_DIR/team"
BIN_DIR="$SCRIPT_DIR/bin"   # say·log-hook — 오버라이드 대상이 아닌 고정 스크립트

# 인자 파싱·members.conf 파서·latest_nvm_bin·GREEN/YELLOW/NC를 설치 스크립트와 공유한다.
source "$SCRIPT_DIR/lib/setup-common.sh"
RED='\033[0;31m'

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
PATH="$BREW_FIRST$PATH"   # latest_nvm_bin의 sort -V가 GNU 판을 쓰도록 먼저 반영
NVM_BIN="$(latest_nvm_bin)"
export PATH="$BREW_FIRST$HOME/.local/bin:$HOME/.bun/bin:${NVM_BIN:+$NVM_BIN:}/usr/local/bin:/usr/bin:/bin:$PATH"
# 파인·run-shell·세션 환경에 그대로 넘길 PATH. 기존 tmux 서버의 최소 PATH에 의존하지 않게 한다.
TEAM_PATH="$BIN_DIR:${NVM_BIN:+$NVM_BIN:}$PATH"

# say·훅이 공유하는 상태 경로. 공용 /tmp 대신 사용자 전용 경로를 쓰고 SAY_* 환경변수로 덮어쓸 수 있다.
STATE_ROOT="$HOME/.cache"
BUSY_STATE_DIR="${SAY_BUSY_DIR:-$STATE_ROOT/team-busy}"
REPORT_STATE_DIR="${SAY_REPORT_DIR:-$STATE_ROOT/team-say}"
QUEUE_STATE_DIR="${SAY_QUEUE_DIR:-$STATE_ROOT/team-say-queue}"

SETUP_NAME="setup-team.sh"
setup_parse_args "$@"
PROJECT_DIR="${PROJECT_ARG:-${PROJECT_DIR:-$(pwd)}}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

# ── 팀 멤버 정보 ───────────────────────────────────────────
# 프로젝트 team/members.conf가 있으면 저장소 기본값 대신 그 파일만 읽는다(병합하지 않는다).
# 공급자별 배분표는 프로젝트 파일이 있으면 기본값 대신 사용한다.
members_file="$(team_members_file "$SCRIPT_DIR" "$PROJECT_DIR")" || exit 2
[ "$members_file" = "$TEAM_DIR/members.conf" ] \
    || echo -e "${YELLOW}team/members.conf 발견 → 프로젝트별 팀 구성 사용: $members_file${NC}"
load_team_members "$members_file" || exit 2

if [ "${#MEMBER_NAMES[@]}" -eq 0 ]; then
    echo -e "${RED}❌ 팀 구성이 없습니다. $members_file에 멤버 줄을 추가하세요.${NC}" >&2
    exit 1
fi

if [ -z "${SESSION:-}" ]; then
    echo -e "${RED}❌ SESSION이 비어 있습니다. $members_file을 확인하세요.${NC}" >&2
    exit 1
fi

PANE_COUNT=${#MEMBER_NAMES[@]}

# role은 say 주소이자 설정 파일 이름이므로 중복을 허용하지 않는다.
dup_roles="$(printf '%s\n' "${MEMBER_NAMES[@]}" | sort | uniq -d)"
if [ -n "$dup_roles" ]; then
    echo -e "${RED}❌ 중복된 역할: $(echo $dup_roles). $members_file을 확인하세요.${NC}" >&2
    exit 1
fi

# 혼합 팀에서는 실제 배정된 공급자 모두를 준비한다. 공급자 값은 load_team_members가 검증한다.
declare -A USED_AGENTS=()
for a in "${MEMBER_AGENTS[@]}"; do USED_AGENTS["$a"]=1; done

# 공급자 하나만 쓰는 팀에서도 배분표 조회가 성립하도록 빈 배열을 먼저 둔다. 구성 파일이 값을 채운다.
declare -A CLAUDE_SUPERPOWERS_SKILL_SETS=() CODEX_SUPERPOWERS_SKILL_SETS=() CLAUDE_GSTACK_SKILL_SETS=() CODEX_GSTACK_SKILL_SETS=()

for agent in "${!USED_AGENTS[@]}"; do
    # 프로젝트에 없는 배열이 기본값으로 남지 않도록 구성 파일을 병합하지 않는다.
    project_provider_config="$PROJECT_DIR/team/config.${agent}.sh"
    if [ ! -f "$project_provider_config" ]; then
        provider_config="$TEAM_DIR/config.${agent}.sh"
        [ -f "$provider_config" ] && source "$provider_config"
    else
        echo -e "${YELLOW}team/config.${agent}.sh 발견 → 공급자별 구성 사용: $project_provider_config${NC}"
        source "$project_provider_config"
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
wait_claude_ready() {
    # 폴더 신뢰·약관·외부 CLAUDE.md import 대화상자에 응답하며 입력 화면이 뜰 때까지 기다린다.
    # 이미 처리된 대화상자는 기다리지 않고, 시간 초과면 1을 반환한다.
    local pane="$1" timeout="${2:-60}" waited=0 screen
    while [ "$waited" -lt "$timeout" ]; do
        screen="$(tmux capture-pane -t "$pane" -p 2>/dev/null)"
        # 낮은 pane에선 대화상자 제목이 잘리므로 선택지 문구로 판별한다.
        if grep -q "trust this folder\|I accept\|disable external imports" <<< "$screen"; then
            # 선택 표시(❯) 줄이 이미 Yes면 Enter만, 아니면(No·exit가 기본인 화면) Down 후 Enter.
            if ! grep '❯' <<< "$screen" | grep -q "Yes"; then
                tmux send-keys -t "$pane" Down
                sleep 0.5
            fi
            tmux send-keys -t "$pane" Enter
        elif grep -q "bypass permissions on\|? for shortcuts\|Try \"" <<< "$screen"; then
            # 꼬리 상태줄은 9줄 pane에서 잘리므로 입력창 플레이스홀더(Try "...")도 준비로 본다.
            return 0
        fi
        sleep 1; waited=$((waited + 1))
    done
    return 1
}

# ── 유틸: 플러그인 설치·필요 여부 판별 (Claude·Codex 대칭) ──
plugin_skill_set() {
    # 사용법: plugin_skill_set <CLAUDE|CODEX> <플러그인> <역할>
    # 역할별 스킬 배분이 있는 플러그인은 superpowers뿐이다. 그 외 플러그인은 빈 값.
    [ "$2" = superpowers ] || return 0
    if [ "$1" = CLAUDE ]; then
        printf '%s' "${CLAUDE_SUPERPOWERS_SKILL_SETS[$3]:-}"
    else
        printf '%s' "${CODEX_SUPERPOWERS_SKILL_SETS[$3]:-}"
    fi
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
    # 빈 캐시 디렉터리는 설치로 보지 않는다. 같은 이름이라도 명세에 있는 설치본만 쓴다.
    python3 -I - "$HOME/.claude/plugins/installed_plugins.json" "$1" <<'PY'
import json
import os
import sys

try:
    with open(sys.argv[1]) as f:
        plugins = json.load(f)["plugins"]
except (OSError, ValueError, KeyError):
    sys.exit(1)
key = sys.argv[2]
name = key.split("@")[0]
# CLI 버전에 따라 같은 플러그인이 다른 마켓플레이스 키로 등록된다(예: superpowers).
# 요청한 키를 먼저 보고, 없으면 같은 이름의 다른 키에서 찾는다.
candidates = [key] + sorted(k for k in plugins if k != key and k.split("@")[0] == name)
for candidate in candidates:
    for entry in plugins.get(candidate, []):
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
    drain_inner="export PATH=$(shell_quote "${TEAM_PATH:-$PATH}"); $(say_state_exports); sleep 1; $(shell_quote "$BIN_DIR/say") --drain-one $(shell_quote "${SESSION}:0.${pane_id#*.}")"
    local drain_cmd="tmux run-shell -b $(shell_quote "$drain_inner")"
    if [ "$role" = "lead" ]; then
        STOP_HOOK_CMD="rm -f $(shell_quote "$BUSY_STATE_DIR/${state_key}"); ${drain_cmd}"
    else
        # 보고 마커는 턴마다 소비한다.
        # 에이전트(훅의 $PPID)에 백그라운드 셸 자식이 남아 있으면 작업 중이므로 신호를 생략한다. 완료 후 다음 턴 종료 때 다시 판정된다.
        local marker="$REPORT_STATE_DIR/${state_key}"
        STOP_HOOK_CMD="rm -f $(shell_quote "$BUSY_STATE_DIR/${state_key}"); if [ -f $(shell_quote "$marker") ]; then rm -f $(shell_quote "$marker"); elif pgrep -P \$PPID -x 'bash|sh|zsh' | grep -vqx \$\$; then :; else $(shell_quote "$BIN_DIR/say") $(shell_quote "${SESSION}:lead") $(shell_quote "[${role}] (자동) 파인 :${pane_id} 응답 종료 — 미보고 시 확인 필요"); fi; ${drain_cmd}"
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

say_state_exports() {
    # 파인 환경이 달라도 say와 훅이 같은 상태 경로를 쓰도록 export 문을 만든다.
    printf 'export SAY_BUSY_DIR=%s SAY_REPORT_DIR=%s SAY_QUEUE_DIR=%s' \
        "$(shell_quote "$BUSY_STATE_DIR")" "$(shell_quote "$REPORT_STATE_DIR")" "$(shell_quote "$QUEUE_STATE_DIR")"
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
    if [ -f "$dst" ] && grep -qF "$begin" "$dst" && ! grep -qF "$end" "$dst"; then
        echo -e "${YELLOW}  ⚠️ $dst 에 끝 마커($end)가 없어 병합을 건너뜀${NC}"
        return 0
    fi
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
        for ((m = 0; m < ${#MEMBER_NAMES[@]}; m++)); do
            [ "${MEMBER_NAMES[$m]}" != "lead" ] || continue
            content+=$'\n'"| ${MEMBER_NAMES[$m]} | say ${MEMBER_NAMES[$m]} \"...\" |"
        done
    fi
    printf '%s' "$content"
}

# ── 유틸: Claude 실행 + 다이얼로그 자동 처리 ────────────────
start_claude_in_pane() {
    # 역할별 지침·훅·플러그인을 적용해 Claude를 시작한다.
    local pane="$1" model="${2:-}" role="${3:-}" reasoning_effort="${4:-}"
    local effort_arg="" model_arg="--model $(shell_quote "$model")"
    [ -z "$reasoning_effort" ] || effort_arg="--effort $(shell_quote "$reasoning_effort")"
    local claude_bin; claude_bin="$(command -v claude)"
    local pane_id="${pane##*:}"   # "team1:0.4" → "0.4". busy 마커·say 큐 키와 형식을 맞춘다.
    local state_key; state_key="$(pane_state_key "$pane")"

    # 역할별 cwd와 설정 소스로 전역 스킬을 차단한다.
    local work_dir="$PROJECT_DIR" skills_arg=""
    if [ -d "$TEAM_SKILLS_ROOT/$role/.claude/skills" ]; then
        work_dir="$TEAM_SKILLS_ROOT/$role"
        skills_arg="--setting-sources project"
    fi

    mkdir -p "$RUNTIME_DIR"   # 지침·설정 파일 위치
    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"
    local system_prompt_arg=""
    if [ -f "$role_file" ]; then
        # tmux 명령 길이 제한을 피하고 재시작 후에도 읽도록 지침을 파일로 전달한다.
        local prompt_file="$RUNTIME_DIR/${role}.prompt.md"
        role_prompt_content "$role_file" "$role" "$work_dir" > "$prompt_file"
        system_prompt_arg="--append-system-prompt-file $(shell_quote "$prompt_file")"
    else
        echo -e "${RED}⚠️  team/${role}.md 없음 → 이 파인은 역할 지침 없이 실행됩니다 (MEMBER_NAMES 오타 확인)${NC}" >&2
    fi

    # 훅에는 호출 시점의 파인 번호를 고정한다. 훅에서 조회하면 활성 파인이 잡힌다.
    # project 설정 소스가 제외한 rtk 훅·전역 플러그인 설정을 역할별로 다시 주입한다.
    local log_cmd busy_start busy_clear
    log_cmd="$(shell_quote "$BIN_DIR/log-hook") $(shell_quote "$role") $(shell_quote "$PROJECT_DIR")"
    # 턴 시작에 busy 마커를 만들고 이전 보고 마커를 비운다.
    busy_start="mkdir -p $(shell_quote "$BUSY_STATE_DIR") && printf '%s\n' hook > $(shell_quote "$BUSY_STATE_DIR/${state_key}") && touch $(shell_quote "$BUSY_STATE_DIR/${state_key}.submit-observed") && rm -f $(shell_quote "$REPORT_STATE_DIR/${state_key}")"
    # /clear·/compact는 Stop 훅 없이 끝날 수 있으므로 SessionStart에서도 마커를 지운다.
    busy_clear="rm -f $(shell_quote "$BUSY_STATE_DIR/${state_key}")"
    stop_hook_cmd_for_role "$role" "$pane_id" "$state_key"

    # 활성화할 플러그인을 "plugin<TAB>마켓플레이스 리포"로 넘긴다. 출처도 전달해야 플러그인을 찾는다.
    local plugin plugin_specs=()
    for plugin in "${!CLAUDE_PLUGIN_ROLES[@]}"; do
        role_in "${CLAUDE_PLUGIN_ROLES[$plugin]}" "$role" || continue
        plugin_specs+=("$plugin"$'\t'"${CLAUDE_PLUGIN_MARKETPLACES[${plugin##*@}]:-}")
    done

    # 플러그인의 Playwright MCP 기본값은 시스템 Chrome 창을 요구하므로 헤드리스 Chromium을 지정한다.
    local playwright=""
    if role_in "${CLAUDE_PLUGIN_ROLES[playwright@claude-plugins-official]:-}" "$role"; then
        playwright=1
    fi

    # 상태 경로·명령에 따옴표나 백슬래시가 있어도 깨지지 않게 직렬화는 python3 json에 맡긴다.
    local settings_file="$RUNTIME_DIR/${role}.settings.json"
    SETTINGS_ROLE="$role" SETTINGS_LOG_CMD="$log_cmd" SETTINGS_STOP_CMD="$STOP_HOOK_CMD" \
    SETTINGS_BUSY_START="$busy_start" SETTINGS_BUSY_CLEAR="$busy_clear" SETTINGS_PLAYWRIGHT="$playwright" \
        python3 -I - ${plugin_specs[@]+"${plugin_specs[@]}"} > "$settings_file" <<'PY'
import json
import os
import sys

def hook(command, matcher=None):
    entry = {"hooks": [{"type": "command", "command": command}]}
    if matcher:
        entry["matcher"] = matcher
    return entry

env = os.environ
settings = {
    # 200K에서 세션을 유지한 채 압축하고 번들 스킬의 프롬프트 고정비를 줄인다.
    "env": {"CLAUDE_CODE_DISABLE_1M_CONTEXT": "1", "CLAUDE_CODE_DISABLE_BUNDLED_SKILLS": "1"},
    # 낮은 pane에선 우회 모드 경고창의 동의 선택지가 잘려 응답할 수 없다.
    "skipDangerousModePermissionPrompt": True,
    # 무인 파인에서 팀 밖 Claude 메시지가 승인 대기 후 폐기되지 않도록 수신을 허용한다.
    "crossSessionInbound": "accept",
    "hooks": {
        "Stop": [hook(env["SETTINGS_STOP_CMD"])],
        # 로깅은 rtk 훅과 별도 matcher로 둔다.
        "PreToolUse": [hook("rtk hook claude", "Bash"), hook(env["SETTINGS_LOG_CMD"], "*")],
        "UserPromptSubmit": [hook(env["SETTINGS_LOG_CMD"]), hook(env["SETTINGS_BUSY_START"])],
        "SessionStart": [hook(env["SETTINGS_BUSY_CLEAR"])],
        },
    }
if env["SETTINGS_PLAYWRIGHT"]:
    settings["env"]["PLAYWRIGHT_MCP_HEADLESS"] = "true"
    settings["env"]["PLAYWRIGHT_MCP_BROWSER"] = "chromium"
# lead의 자기 보고 루프는 Stop 명령에서 막고, 지침으로 막히지 않는 직접 tmux 전송은 권한으로 차단한다.
if env["SETTINGS_ROLE"] == "lead":
    settings["permissions"] = {"deny": ["Bash(tmux send-keys:*)"]}
enabled = {}
marketplaces = {}
for spec in sys.argv[1:]:
    plugin, repo = spec.split("\t")
    enabled[plugin] = True
    marketplaces[plugin.rsplit("@", 1)[1]] = {"source": {"source": "github", "repo": repo}}
if enabled:
    settings["enabledPlugins"] = enabled
    settings["extraKnownMarketplaces"] = marketplaces
json.dump(settings, sys.stdout)
PY
    local settings_arg="--settings $(shell_quote "$settings_file")"

    # 부모 Claude 세션 감지를 해제하고 say 실행 경로를 추가한다.
    tmux send-keys -t "$pane" \
        "cd $(shell_quote "$work_dir") && unset CLAUDECODE && export PATH=$(shell_quote "${TEAM_PATH:-$PATH}") && $(say_state_exports) && export CAVEMAN_DEFAULT_MODE=full && $(shell_quote "$claude_bin") $model_arg $effort_arg --dangerously-skip-permissions $skills_arg $system_prompt_arg $settings_arg" Enter

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

    if [ ! -f "$role_file" ]; then
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
    local log_cmd hooks_json
    log_cmd="$(shell_quote "$BIN_DIR/log-hook") $(shell_quote "$role") $(shell_quote "$PROJECT_DIR") --quiet"
    # 턴 시작에 busy 마커를 만들고 보고 마커를 비운다(Claude와 동일). 직접 입력한 턴도 busy로 잡힌다. 직렬화는 python3 json에 맡긴다.
    hooks_json="$(HOOKS_LOG_CMD="$log_cmd" HOOKS_STOP_CMD="$STOP_HOOK_CMD" \
        HOOKS_BUSY_CLEAR="rm -f $(shell_quote "$BUSY_STATE_DIR/${state_key}")" \
        HOOKS_BUSY_START="mkdir -p $(shell_quote "$BUSY_STATE_DIR") && printf '%s\n' hook > $(shell_quote "$BUSY_STATE_DIR/${state_key}") && touch $(shell_quote "$BUSY_STATE_DIR/${state_key}.submit-observed") && rm -f $(shell_quote "$REPORT_STATE_DIR/${state_key}")" \
        python3 -I - <<'PY'
import json
import os
import sys

def hook(command, matcher=None):
    entry = {"hooks": [{"type": "command", "command": command}]}
    if matcher:
        entry["matcher"] = matcher
    return entry

env = os.environ
log = hook(env["HOOKS_LOG_CMD"])
hooks = {
    "SessionStart": [hook(env["HOOKS_BUSY_CLEAR"], "startup|resume|clear|compact")],
    "UserPromptSubmit": [log, hook(env["HOOKS_BUSY_START"])],
    "PreToolUse": [log],
    "Stop": [hook(env["HOOKS_STOP_CMD"])],
    }
json.dump({"hooks": hooks}, sys.stdout)
PY
)"
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
    if [ -d "$TEAM_SKILLS_ROOT/$role" ]; then
        work_dir="$TEAM_SKILLS_ROOT/$role"
    fi
    local role_codex_home="$work_dir/.codex-home"
    local gstack_env=""
    if [ -f "$TEAM_SKILLS_ROOT/_assets/gstack/installed" ] && [ -n "$(codex_gstack_skills "$role")" ]; then
        gstack_env="export GSTACK_STATE_ROOT=$(shell_quote "$TEAM_SKILLS_ROOT/_assets/gstack/state") && "
    fi
    write_codex_role_agents "$role" "$work_dir" "$pane_id" "$state_key" || true

    local model_arg="--model $(shell_quote "$model")"

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
        "cd $(shell_quote "$work_dir") && export CODEX_HOME=$(shell_quote "$role_codex_home") && export PATH=$(shell_quote "${TEAM_PATH:-$PATH}") && $(say_state_exports) && ${gstack_env}$(shell_quote "$codex_bin") $permission_args --dangerously-bypass-hook-trust --add-dir $(shell_quote "$PROJECT_DIR") --add-dir $(shell_quote "$tmux_tmpdir") --add-dir $(shell_quote "$BUSY_STATE_DIR") --add-dir $(shell_quote "$REPORT_STATE_DIR") --add-dir $(shell_quote "$QUEUE_STATE_DIR") -c 'sandbox_workspace_write.network_access=true' -c check_for_update_on_startup=false $model_arg $reasoning_arg" Enter

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

# ── 공통 (Claude·Codex) — 사전 요구사항 확인 ───────────────
used_agents_list="${!USED_AGENTS[*]}"
# 표시 번호는 실제로 도는 단계만 센다 — 단일 공급자 팀에서 번호가 건너뛰지 않게.
# 공통 3단계(사전 확인·레이아웃·기동) + Claude 3 + Codex 2.
STEP=0
TOTAL=3
[ -n "${USED_AGENTS[claude]:-}" ] && TOTAL=$((TOTAL + 3))
[ -n "${USED_AGENTS[codex]:-}" ] && TOTAL=$((TOTAL + 2))
step "공통 (Claude·Codex) — 사전 요구사항 확인 (${used_agents_list})..."

MISSING=()
command -v python3 &>/dev/null || MISSING+=("python3 (apt-get install -y python3)")
command -v tmux &>/dev/null || MISSING+=("tmux (apt-get install -y tmux)")
# 파일 검색 지침과 rtk rg가 실제 rg 실행 파일을 쓴다.
command -v rg &>/dev/null || MISSING+=("rg (apt-get install -y ripgrep 또는 brew install ripgrep)")
if [ -n "${USED_AGENTS[claude]:-}" ]; then
    command -v claude &>/dev/null || MISSING+=("claude (npm install -g @anthropic-ai/claude-code)")
    command -v rtk    &>/dev/null || MISSING+=("rtk (curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/tags/v0.43.0/install.sh | sh)")
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
    if claude auth status >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 로그인 완료${NC}"
    else
        echo -e "${YELLOW}로그인이 필요합니다.${NC}"
        echo
        echo "Claude를 실행합니다."
        echo "컨테이너 안에서 /login 을 완료하세요."
        echo
        claude
        echo
        read -p "로그인이 완료되었다면 Enter를 누르세요..."
        if ! claude auth status >/dev/null 2>&1; then
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
    if codex login status >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 로그인 완료${NC}"
    else
        echo -e "${YELLOW}로그인이 필요합니다.${NC}"
        echo
        echo "codex login을 실행해 로그인을 완료하세요."
        echo
        codex login
        echo
        read -p "로그인이 완료되었다면 Enter를 누르세요..."
        if ! codex login status >/dev/null 2>&1; then
            echo -e "${RED}❌ 로그인이 확인되지 않았습니다.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ 로그인 확인 완료${NC}"
    fi
fi

# 실행 중인 파인과 생성 파일 갱신이 경합하지 않도록 기존 세션부터 종료한다.
existing_project="$(tmux show-options -qv -t "$SESSION" @project 2>/dev/null || true)"
if [ -n "$existing_project" ] && [ "$existing_project" != "$PROJECT_DIR" ]; then
    echo -e "${RED}❌ 세션 '$SESSION'이 다른 프로젝트($existing_project)에서 실행 중입니다. SESSION을 다르게 지정하세요.${NC}" >&2
    exit 1
fi
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
[ -e "$TEAM_SKILLS_ROOT/.gitignore" ] || printf '*\n' > "$TEAM_SKILLS_ROOT/.gitignore"
reset_generated_team_files
mkdir -p "$RUNTIME_DIR"

if [ -n "${USED_AGENTS[claude]:-}" ]; then

# ── Claude — rtk 훅 초기화 ─────────────────────────────────
# 로그인 후 생성되는 설정에 훅을 등록한다.
# 비대화형 telemetry 동의 대기는 환경변수·응답·timeout으로 차단한다.
step "Claude — rtk 훅 초기화..."

if printf 'n\n' | RTK_TELEMETRY_DISABLED=1 timeout 15 rtk init -g --auto-patch; then
    echo -e "  ${GREEN}✅  rtk 훅 등록 완료${NC}"
else
    echo -e "  ${YELLOW}⚠️  rtk init 실패 또는 timeout (이미 설정되어 있거나 수동 확인 필요)${NC}"
    echo -e "  ${YELLOW}   확인: rtk init --show${NC}"
fi


# ── Claude — 필요한 플러그인 설치 ────────────────────────────
# 역할별 활성화는 실행 시 --settings로 전달한다. 전역 설정은 바꾸지 않는다.
step "Claude — 필요한 플러그인·gstack 설치..."


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

ensure_playwright_browser() {
    # Playwright MCP를 쓰는 역할이 있으면 기동 전에 브라우저를 받는다. 이미 있으면 바로 끝난다.
    local i needed=false
    for ((i = 0; i < ${#MEMBER_NAMES[@]}; i++)); do
        case "${MEMBER_AGENTS[$i]}" in
            claude) role_in "${CLAUDE_PLUGIN_ROLES[playwright@claude-plugins-official]:-}" "${MEMBER_NAMES[$i]}" && needed=true ;;
            codex)  role_in "${CODEX_PLAYWRIGHT_ROLES:-}" "${MEMBER_NAMES[$i]}" && needed=true ;;
        esac
    done
    [ "$needed" = true ] || return 0
    if npx -y @playwright/mcp@latest install-browser chrome-for-testing >/dev/null 2>&1; then
        echo "  ✅  Playwright 브라우저 준비됨"
    else
        echo -e "${YELLOW}  ⚠️  Playwright 브라우저 설치 실패 (수동 확인: npx -y @playwright/mcp@latest install-browser chrome-for-testing)${NC}"
    fi
}
ensure_playwright_browser

GSTACK_DIR="$HOME/.claude/skills/gstack"

install_claude_gstack() {
    # gstack 스킬을 배정받은 Claude 역할이 있으면 공식 위치에 공식 setup으로 설치한다.
    # 이미 설치돼 있으면 건드리지 않는다. 갱신은 gstack 자체 업데이트(/gstack-upgrade)가 맡는다.
    # ponytail: clone 후 setup이 실패한 설치본도 다음 실행에서 설치됨으로 본다. 수동 재실행을 안내한다.
    local i needed=false
    for ((i = 0; i < PANE_COUNT; i++)); do
        if [ "${MEMBER_AGENTS[$i]}" = claude ] && [ -n "${CLAUDE_GSTACK_SKILL_SETS[${MEMBER_NAMES[$i]}]:-}" ]; then
            needed=true
            break
        fi
    done
    [ "$needed" = true ] || return 0
    if [ -x "$GSTACK_DIR/setup" ]; then
        echo "  ℹ️  gstack 이미 설치됨 ($GSTACK_DIR)"
        return 0
    fi
    if ! command -v bun >/dev/null; then
        echo -e "${YELLOW}  ⚠️  bun이 없어 gstack 설치를 건너뜁니다 (설치: curl -fsSL https://bun.sh/install | bash)${NC}" >&2
        return 1
    fi
    git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git "$GSTACK_DIR" -q || return 1
    # 비대화형 setup은 질문 없이 기본값을 쓴다. 등록되는 전역 훅은 팀 파인(--setting-sources project)에 로드되지 않는다.
    if (cd "$GSTACK_DIR" && timeout 600 ./setup --host claude </dev/null); then
        echo -e "  ${GREEN}✅ gstack 설치 완료${NC}"
    else
        echo -e "${YELLOW}  ⚠️  gstack setup 실패 또는 timeout (수동 확인: cd $GSTACK_DIR && ./setup --host claude)${NC}" >&2
        return 1
    fi
}
install_claude_gstack || true

# ── Claude — 역할별 스킬 제한 ──────────────────────────────
# 역할별 cwd에 필요한 스킬만 링크하고 project 설정 소스로 전역 스킬을 차단한다.
# 제외되는 전역 훅·플러그인 설정은 실행 시 명시 주입한다.
# 홈 아래 프로젝트에서는 전역 rules·CLAUDE.md가 계속 로드된다.
step "Claude — 런타임 준비 (공통 지침 병합·역할별 스킬 제한)..."

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
    if [ -n "${CLAUDE_GSTACK_SKILL_SETS[$role]:-}" ]; then
        link_plugin_skills gstack "$GSTACK_DIR" ${CLAUDE_GSTACK_SKILL_SETS[$role]}
    fi
    echo "  $role: ${granted[*]:-(Claude 역할별 스킬 없음)}"
done
echo -e "${GREEN}  ✅ Claude 역할별 런타임 디렉터리 준비 완료${NC}"

fi

if [ -n "${USED_AGENTS[codex]:-}" ]; then

# ── Codex — 필요한 플러그인 설치 ──────────────────────────────────
step "Codex — 필요한 플러그인 설치..."

base_codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_assets_home="$TEAM_SKILLS_ROOT/_assets/codex-home"

write_codex_role_plugins() {
    # 기본 모델 설정을 매번 상속하고 배정 플러그인만 켠다. 명시한 실행 인자가 우선한다.
    local role="$1" role_home="$2" base_config="${base_codex_home:-}/config.toml" plugin
    mkdir -p "$role_home"
    {
        # 기본 홈의 첫 TOML 테이블 앞에 있는 모델·추론 설정만 상속한다. 없는 파일·키는 생략한다.
        [ ! -f "$base_config" ] ||
            awk '/^[[:space:]]*\[/ { exit } /^[[:space:]]*(model|model_reasoning_effort)[[:space:]]*=/ { print }' "$base_config"
        printf '[plugins._default]\nenabled = false\n'
        for plugin in "${!CODEX_PLUGIN_ROLES[@]}"; do
            role_in "${CODEX_PLUGIN_ROLES[$plugin]}" "$role" || continue
            printf '\n[plugins."%s"]\nenabled = true\n' "$plugin"
        done
        if role_in "${CODEX_PLAYWRIGHT_ROLES:-}" "$role"; then
            printf '\n[mcp_servers.playwright]\ncommand = "npx"\nargs = ["-y", "@playwright/mcp@latest"]\nenv = { PLAYWRIGHT_MCP_HEADLESS = "true", PLAYWRIGHT_MCP_BROWSER = "chromium" }\n'
        fi
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

codex_plugin_source() {
    # 사용법: codex_plugin_source <plugin@marketplace> <cache|skills> [제외할 홈]
    # 기본 홈 → 자산 홈 → 역할 홈 순으로 찾아 cache는 버전 디렉터리, skills는 그 안의 skills를 출력한다.
    local key="$1" want="$2" skip="${3:-}" home version
    for home in "$base_codex_home" "$codex_assets_home" "$TEAM_SKILLS_ROOT"/*/.codex-home; do
        [ -d "$home" ] || continue
        [ "$home" != "$skip" ] || continue
        version="$(codex_plugin_cache "$home" "$key")" || continue
        if [ "$want" = skills ]; then
            [ -d "$version/skills" ] || continue
            printf '%s\n' "$version/skills"
        else
            printf '%s\n' "$version"
        fi
        return 0
    done
    # 원격 카탈로그(openai-curated-remote) 플러그인은 설치본 없이 snapshot만 있을 수 있다.
    if [ "$want" = skills ] && [[ "${key##*@}" == openai-curated* ]] && [ -d "$base_codex_home/.tmp/plugins/plugins/${key%@*}/skills" ]; then
        printf '%s\n' "$base_codex_home/.tmp/plugins/plugins/${key%@*}/skills"
        return 0
    fi
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
        elif base_cache="$(codex_plugin_source "$plugin" cache "$role_home")"; then
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

codex_role_matches() {
    # 사용법: codex_role_matches <plugin@marketplace> <skills|plugin>
    # Codex 파인 중 그 플러그인의 선택 스킬을 받는(skills) 또는 플러그인을 활성화하는(plugin) 역할이 있으면 0.
    local key="$1" want="$2" i role
    for ((i = 0; i < PANE_COUNT; i++)); do
        [ "${MEMBER_AGENTS[$i]}" = "codex" ] || continue
        role="${MEMBER_NAMES[$i]}"
        if [ "$want" = skills ]; then
            [ -z "$(plugin_skill_set CODEX "${key%@*}" "$role")" ] || return 0
        elif role_in "${CODEX_PLUGIN_ROLES[$key]:-}" "$role"; then
            return 0
        fi
    done
    return 1
}

prepare_codex_skill_sources() {
    # 선택 스킬에만 필요한 설치본은 전역 설정을 건드리지 않도록 팀 자산 홈에 둔다.
    local key keys=()
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
        codex_role_matches "$key" skills || continue
        if codex_plugin_source "$key" skills >/dev/null; then
            echo "  ℹ️  $key 스킬 원본 이미 있음"
            continue
        fi
        # 활성화하는 Codex 역할이 있으면 역할 홈 준비에서 설치되므로 여기서 또 설치하지 않는다.
        if codex_role_matches "$key" plugin; then
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

codex_gstack_skills() {
    local role="$1" skill
    for skill in ${CODEX_GSTACK_SKILL_SETS[$role]:-}; do
        printf 'gstack-%s\n' "${skill#gstack-}"
    done
}

prepare_codex_gstack() {
    local i needed=false
    for ((i = 0; i < PANE_COUNT; i++)); do
        if [ "${MEMBER_AGENTS[$i]}" = codex ] && [ -n "$(codex_gstack_skills "${MEMBER_NAMES[$i]}")" ]; then
            needed=true
            break
        fi
    done
    [ "$needed" = true ] || return 0

    local root="$TEAM_SKILLS_ROOT/_assets/gstack"
    local source="$root/source" install_home="$root/codex-home"
    if [ -f "$root/installed" ] && compgen -G "$install_home/skills/gstack-*/SKILL.md" >/dev/null; then
        return 0
    fi
    mkdir -p "$root" "$install_home" "$root/state" "$root/tmp" "$root/bun-cache" || return 1
    if [ ! -x "$source/setup" ]; then
        git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git "$source" || return 1
    fi
    # 공식 설치가 생성한 훅은 자산 홈에 둔다. 실행 파인에는 선택한 스킬만 연결한다.
    (
        cd "$source" || exit 1
        PATH="$TEAM_PATH" CODEX_HOME="$install_home" GSTACK_STATE_ROOT="$root/state" \
            BUN_TMPDIR="$root/tmp" BUN_INSTALL_CACHE_DIR="$root/bun-cache" \
            ./setup --host codex
    ) || return 1
    compgen -G "$install_home/skills/gstack-*/SKILL.md" >/dev/null || return 1
    touch "$root/installed"
}

prepare_codex_skill_sources
if ! prepare_codex_gstack; then
    echo -e "${YELLOW}⚠️  Codex gstack 설치 실패. 다음 실행에서 재시도합니다.${NC}" >&2
fi

for ((role_index = 0; role_index < PANE_COUNT; role_index++)); do
    [ "${MEMBER_AGENTS[$role_index]}" = "codex" ] || continue
    role="${MEMBER_NAMES[$role_index]}"
    prepare_codex_role_home "$role" "$TEAM_SKILLS_ROOT/$role/.codex-home"
done

# ── Codex — 런타임 준비 ──────────────────────────────────
step "Codex — 런타임 준비 (공통 지침 병합·역할별 스킬 제한)..."
merge_team_md AGENTS.md codex "Codex 팀 공통 지침"

for ((role_index = 0; role_index < PANE_COUNT; role_index++)); do
    [ "${MEMBER_AGENTS[$role_index]}" = "codex" ] || continue
    role="${MEMBER_NAMES[$role_index]}"
    role_skills_dir="$TEAM_SKILLS_ROOT/$role/.agents/skills"
    mkdir -p "$role_skills_dir"
    granted=()
    for plugin_key in "${!CODEX_PLUGIN_ROLES[@]}"; do
        plugin="${plugin_key%@*}"
        role_skill_list="$(plugin_skill_set CODEX "$plugin" "$role")"
        [ -n "$role_skill_list" ] || continue
        plugin_root="$(codex_plugin_source "$plugin_key" skills || true)"
        link_plugin_skills "$plugin" "$plugin_root" $role_skill_list
    done
    gstack_skills="$(codex_gstack_skills "$role")"
    if [ -n "$gstack_skills" ] && [ -f "$TEAM_SKILLS_ROOT/_assets/gstack/installed" ]; then
        link_plugin_skills gstack "$TEAM_SKILLS_ROOT/_assets/gstack/codex-home/skills" $gstack_skills
    fi
    echo "  $role: ${granted[*]:-(Codex 역할별 스킬 없음)}"
done
echo -e "${GREEN}  ✅ Codex 역할별 런타임 디렉터리 준비 완료${NC}"

fi

# ── 공통 (Claude·Codex) — TMUX 세션 & 레이아웃 구성 ───────
step "공통 (Claude·Codex) — TMUX 세션 & 레이아웃 구성..."

# 초기 레이아웃에 충분한 크기를 확보한다. 접속 후에는 클라이언트 크기를 따른다.
create_team_session() {
    # 팀 창·파인 번호만 0부터 맞추고 사용자 전역 설정은 유지한다.
    local first_window
    tmux new-session -d -s "$SESSION" -x 220 -y 50
    tmux set-option -t "$SESSION" @project "$PROJECT_DIR"
    tmux set-environment -t "$SESSION" SAY_BUSY_DIR "$BUSY_STATE_DIR"
    tmux set-environment -t "$SESSION" SAY_REPORT_DIR "$REPORT_STATE_DIR"
    tmux set-environment -t "$SESSION" SAY_QUEUE_DIR "$QUEUE_STATE_DIR"
    tmux set-environment -t "$SESSION" PATH "${TEAM_PATH:-$PATH}"   # 세션 범위만 — 전역 환경은 건드리지 않는다
    first_window="$(tmux list-windows -t "$SESSION" -F '#{window_index}' | head -1)"
    tmux set-window-option -t "$SESSION:$first_window" pane-base-index 0
    if [ "$first_window" != 0 ]; then
        tmux move-window -s "$SESSION:$first_window" -t "$SESSION:0"
    fi
}
create_team_session
tmux set-option -t "$SESSION" @team_runtime_dir "$RUNTIME_DIR"

for ((i = 0; i < PANE_COUNT - 1; i++)); do
    tmux split-window -t "$SESSION:0.$i" -h
    # 분할마다 균등 배치해야 파인이 많아도 공간이 부족하지 않다.
    tmux select-layout -t "$SESSION:0" even-horizontal
done

# 균등 배치 후 main-vertical로 전환해야 좁은 파인이 생기지 않는다.
tmux select-layout -t "$SESSION:0" main-vertical

for ((pane = 0; pane < PANE_COUNT; pane++)); do
    tmux select-pane -t "$SESSION:0.$pane" -T "${MEMBER_NAMES[$pane]}"
    # pane_title은 에이전트 CLI의 OSC 제목 변경 대상이므로 테두리·창 제목은 @role 옵션으로 표시한다.
    tmux set-option -p -t "$SESSION:0.$pane" @role "${MEMBER_NAMES[$pane]}"
    tmux set-option -p -t "$SESSION:0.$pane" @team_start_state starting
    tmux set-option -p -t "$SESSION:0.$pane" @model_info "${SPEC_MEMBER_MODELS[$pane]} ${SPEC_MEMBER_REASONING_EFFORTS[$pane]:-effort 비어 있음}"
done

tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{@role} · #{@model_info} "
tmux set-option -t "$SESSION" set-titles on
tmux set-option -t "$SESSION" set-titles-string "#{@role}"
tmux set-option -t "$SESSION" allow-rename off
tmux set-option -t "$SESSION" mouse on

echo "  ✅ 레이아웃 구성 완료 (${PANE_COUNT} panes)"

# ── 공통 (Claude·Codex) — 에이전트 자동 실행 ──────────────
step "공통 (Claude·Codex) — 파인별 에이전트 실행 중 (${used_agents_list})... (병렬, 최대 1분)"

# codex의 --add-dir는 존재하는 경로만 받는다. say의 lazy mkdir은
# codex sandbox(workspace-write) 안에서 막히므로 파인 기동 전에 미리 만든다.
# 상태 디렉터리는 사용자 전용 경로에 만들고 소유자를 확인한다.
for d in "$BUSY_STATE_DIR" "$REPORT_STATE_DIR" "$QUEUE_STATE_DIR"; do
    mkdir -p "$d"
    [ -O "$d" ] || { echo -e "${RED}❌ $d 의 소유자가 현재 사용자가 아닙니다.${NC}" >&2; exit 1; }
    chmod 700 "$d"
done

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

# 병렬 출력은 역할별 파일에 모아 순서대로 표시한다. 로그인은 사전 요구사항 단계에서 끝났다.
start_pids=() start_rcs=() failed_panes=()
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    start_agent_in_pane "$pane" > "$RUNTIME_DIR/pane-start-$pane.log" 2>&1 &
    start_pids[$pane]=$!
done

for ((pane = 0; pane < PANE_COUNT; pane++)); do
    wait "${start_pids[$pane]}" && start_rcs[$pane]=0 || start_rcs[$pane]=$?
    echo -n "  Pane $pane (${MEMBER_NAMES[$pane]}, ${MEMBER_AGENTS[$pane]} · ${SPEC_MEMBER_MODELS[$pane]} · ${SPEC_MEMBER_REASONING_EFFORTS[$pane]:-effort 비어 있음}): "
    if [ "${start_rcs[$pane]}" -eq 0 ]; then
        tmux set-option -p -t "$SESSION:0.$pane" @team_start_state ready || true
        echo -e "${GREEN}✅ 실행 완료${NC}"
    else
        tmux set-option -p -t "$SESSION:0.$pane" @team_start_state failed || true
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

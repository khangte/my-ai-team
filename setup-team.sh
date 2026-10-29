#!/bin/bash
#
# setup-team.sh — tmux 기반 Claude/Codex 멀티에이전트 팀 환경 자동 구성
#
# setup-docker.sh가 컨테이너 기동 후 `docker exec`로 호출한다(직접 실행도 가능).
# --agent/TEAM_AGENT는 팀 전체의 기본 공급자를 정하고, team/config.sh의
# MEMBERS("role|표시이름|agent|model|effort")로 역할별 공급자를 지정할
# 수 있다(혼합 팀). 예: developer 파인만 Codex, 나머지는 기본값(Claude)으로
# 띄우는 구성.
#
# 단계 (혼합 팀 기준 번호. 실제 출력은 실행되는 단계만 이어서 센다):
#   [0/7] 공통 (Claude·Codex): 실제로 사용되는 공급자(USED_AGENTS) 전부의 사전 요구사항·로그인 확인
#         확인 직후 기존 tmux 세션을 정리한다 — 살아있는 파인이 .team/{역할}/
#         아래에 계속 쓰는 상태로 생성 파일을 갱신하면 경합으로 실패하기 때문에,
#         그 갱신보다 먼저 끝내 둔다. 기존 .team/은 재사용하고 이전 실행의 생성 파일만 지운다.
#   Claude 블록 (Claude 파인이 있을 때):
#     [1/7] rtk 훅 초기화
#     [2/7] Claude - 필요한 플러그인만 설치 (이미 설치된 것은 설치 명령 없이 표시)
#     [3/7] 팀 공통 지침을 CLAUDE.md에 병합 + 역할별 스킬 제한(런타임 디렉터리 구성)
#   Codex 블록 (Codex 파인이 있을 때, 혼합 팀에서는 Claude 블록 뒤에 이어서 실행):
#     [4/7] Codex - 필요한 플러그인만 설치 (기본 홈 설치본은 역할 홈에 재사용)
#     [5/7] AGENTS.md 병합, 역할별 스킬·lifecycle 훅 준비
#   (.team/ 생성 파일 정리는 두 블록 앞에서 한 번만 한다)
#   [6/7] 공통 (Claude·Codex): MEMBER_NAMES 배열 기준으로 파인을 분할하고 이름 부여
#   [7/7] 공통 (Claude·Codex): 각 파인에서 MEMBER_AGENTS[i]가 가리키는 CLI를 해당 모델로 실행
#
# 사용:
#   ./setup-team.sh [--agent claude|codex] [프로젝트_경로]
#   프로젝트_경로 생략 시 $PROJECT_DIR, 그것도 없으면 현재 디렉터리 사용.
#   (인원·표시이름·공급자·모델·추론강도는 프로젝트 루트의 team/config.sh에서
#    MEMBERS로 한 번에 선언하면 됨. team/config.{agent}.sh는 플러그인·
#    스킬 배분표만 다룬다)

set -e

# ── PATH 보강 ─────────────────────────────────────────────
# 스크립트 직접 실행은 non-interactive 셸이라 ~/.bashrc가 로드되지 않는다.
# 파인이 이 PATH를 그대로 물려받고 파인의 훅이 여기서 인터프리터를 찾으므로
# node(caveman·ponytail SessionStart 훅)와 python3(bin/log-hook)이 빠지면
# 해당 기능이 조용히 죽는다. nvm node는 버전 디렉터리 아래라 최신 하나를 고른다.
NVM_BIN=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)
export PATH="$HOME/.local/bin:/opt/rtk-bin:/opt/npm-global/bin:/opt/bun/bin:$HOME/.bun/bin:${NVM_BIN:+$NVM_BIN:}/usr/local/bin:/usr/bin:/bin:$PATH"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SESSION="team1"
TEAM_AGENT="${TEAM_AGENT:-claude}"
PROJECT_ARG=""

usage() {
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

# ── 팀 멤버 정보 ───────────────────────────────────────────
# 설정은 두 단계로 독립 해석한다.
#   1) 공통 구성: 이 저장소/team/config.sh → 대상 프로젝트/team/config.sh
#   2) 공급자 구성: 대상 프로젝트의 team/config.claude.sh, config.codex.sh가
#      있으면 그것만, 없으면 이 저장소의 같은 파일 (병합하지 않음)
#
# MEMBER_AGENTS는 파인별로 다른 에이전트를 지정한다(혼합 팀). 빈 문자열은
# $TEAM_AGENT(전역 기본값)를 따른다. 미선언 프로젝트는 전부 빈 값과 동일하게
# 취급되어 기존 단일 공급자 동작이 유지된다.
#
# 인원·모델·추론강도는 team/config.sh의 MEMBERS가 유일한
# 출처다(역할별 "role|표시이름|agent|model|effort" 한 줄). config.sh가 이를
# 풀어 MEMBER_NAMES/MEMBER_DISPLAY_NAMES/MEMBER_AGENTS/SPEC_MEMBER_MODELS/
# SPEC_MEMBER_REASONING_EFFORTS를 채운다. team/config.claude.sh·config.codex.sh는
# 플러그인·스킬 배분표만 담당하고 모델·추론강도는 선언하지 않는다 — 인원
# 증감 시 그 두 파일은 건드릴 필요가 없다.
#
# MEMBER_NAMES는 여기서 미리 선언하지 않는다 — team/config.sh가 MEMBERS를
# 풀며 MEMBER_NAMES와 SPEC_MEMBER_MODELS/EFFORTS를 함께 채우므로, 하나만
# 하드코딩해 두면 나머지가 비어 있는 반쪽 상태로 아래 길이 체크에서 죽는다.
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

# 실제로 파인에 배정된 공급자 집합. 미선언 파인은 $TEAM_AGENT로 해석한다.
# 이 집합이 이후 사전 요구사항 확인, 인증, 런타임 준비 단계가 어떤 공급자
# 블록을 돌릴지 정한다.
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

# 모델·추론강도는 이미 MEMBERS에서 role별로 확정됐으므로, 파인 인덱스
# 그대로 참조한다(SPEC_MEMBER_MODELS/EFFORTS). 아래에서는 플러그인·스킬 배분표
# (CLAUDE_PLUGIN_ROLES, CLAUDE_SUPERPOWERS_SKILL_SETS 등)만 공급자별로 로딩한다.
for agent in "${!USED_AGENTS[@]}"; do
    # 프로젝트 구성이 있으면 그것만 쓴다 — 기본값과 섞이면 프로젝트에 없는 배열이
    # 기본값의 역할 구성으로 남는다.
    project_provider_config="$PROJECT_DIR/team/config.${agent}.sh"
    if [ ! -f "$project_provider_config" ]; then
        provider_config="$TEAM_DIR/config.${agent}.sh"
        [ -f "$provider_config" ] && source "$provider_config"
    else
        echo -e "${YELLOW}team/config.${agent}.sh 발견 → 공급자별 구성 사용: $project_provider_config${NC}"
        source "$project_provider_config"
        # 옛 배열 이름은 더 이상 읽지 않는다 — 조용히 기본값으로 떨어지지 않게 알린다.
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
            sleep 1; waited=$((waited + 1))
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

provider_plugin_needed() {
    # 사용법: provider_plugin_needed <claude|codex> <plugin@marketplace>
    # 그 공급자 파인이 플러그인을 활성화하거나 선택 스킬의 원본으로 쓰면 0을 반환한다.
    local provider="$1" key="$2" i role roles
    local -n plugin_roles="${provider^^}_PLUGIN_ROLES"
    roles="${plugin_roles[$key]:-}"
    for ((i = 0; i < PANE_COUNT; i++)); do
        [ "${MEMBER_AGENTS[$i]}" = "$provider" ] || continue
        role="${MEMBER_NAMES[$i]}"
        if [ "$roles" = "*" ] || [[ " $roles " == *" $role "* ]]; then
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
# 결과는 전역 변수 STOP_HOOK_CMD에 담는다. Claude·Codex가 같은 종료 신호
# 로직을 쓰도록 여기서 순수 셸 명령을 만들고, 각 설정 JSON에 넣을 때만 이스케이프한다.
# lead는 자기 자신에게 종료 신호를 보내지 않고 busy 마커만 지운다.
stop_hook_cmd_for_role() {
    local role="$1" pane_id="$2" state_key="$3"
    # watcher가 Codex의 도구 실행 수명과 함께 종료돼도 큐가 고아가 되지 않도록,
    # 수신 파인이 유휴로 전환될 때 tmux 서버가 FIFO 한 건을 다시 가동한다.
    # 훅 본문이 끝난 뒤 입력창이 준비되도록 짧게 늦춰 같은 파인에 전달한다.
    local drain_inner
    drain_inner="sleep 1; $(shell_quote "$BIN_DIR/say") --drain-one $(shell_quote "${SESSION}:0.${pane_id#*.}")"
    local drain_cmd="tmux run-shell -b $(shell_quote "$drain_inner")"
    if [ "$role" = "lead" ]; then
        STOP_HOOK_CMD="rm -f /tmp/team-busy/${state_key}; ${drain_cmd}"
    else
        # 마커는 "이번 턴에 보고했나" 1비트다. 한 턴에 여러 번 보고해도 파일은
        # 하나이므로 여기서 무조건 지운다(있었으면 신호 생략, 없었으면 신호 전송).
        # Claude 파인은 UserPromptSubmit에서도 비우지만, 그 훅이 없는 Codex
        # 파인은 이 삭제가 유일한 초기화 지점이다.
        local marker="/tmp/team-say/${state_key}"
        STOP_HOOK_CMD="rm -f /tmp/team-busy/${state_key}; if [ -f $(shell_quote "$marker") ]; then rm -f $(shell_quote "$marker"); else $(shell_quote "$BIN_DIR/say") $(shell_quote "${SESSION}:0.0") $(shell_quote "[${role}] (자동) 파인 :${pane_id} 응답 종료 — 미보고 시 확인 필요"); fi; ${drain_cmd}"
    fi
}

# busy/report marker는 논리적 파인 번호가 아니라 tmux의 세션·파인 고유 ID를
# 사용한다. 같은 SESSION 이름으로 팀을 다시 만들어도 이전 실행의 marker와
# 충돌하지 않는다. say의 resolved_state/state_key 계산과 동일한 규약이다.
pane_state_key() {
    local state
    state="$(tmux display-message -p -t "$1" '#{session_id}:#{pane_id}')"
    printf '%s' "${state//[^0-9A-Za-z]/_}"
}

# ── 유틸: 플러그인 스킬을 역할 스킬 디렉터리에 링크 ──────────
# 호출 측의 role·role_skills_dir·granted를 그대로 쓴다. 스킬 디렉터리를 통째로
# 링크한다(references/ 등 하위 파일을 런타임에 읽으므로 SKILL.md만 링크하면 깨진다).
team_owned_record() {
    # 사용법: team_owned_record <역할 디렉터리> <L|F> <상대경로> <값>
    # 도구가 만든 항목을 역할 디렉터리의 소유 기록에 남긴다. 링크(L)는 대상 경로,
    # 파일(F)은 sha256을 값으로 써서 나중에 만든 그대로인지 확인한다.
    mkdir -p "$1"
    printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$1/.ai-setup-owned"
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
    # 사용법: shell_quote <문자열>
    # POSIX 셸에서 한 단어로 읽히도록 작은따옴표로 감싸 출력한다. 값 안의 작은따옴표는
    # '\'' 로 바꾸므로 공백·큰따옴표·달러·백틱은 그대로 글자로 전달된다(어떤 셸에서도 동작).
    local quote="'\\''"
    printf "'%s'" "${1//\'/$quote}"
}

# ── 유틸: JSON 문자열 값으로 안전하게 넣을 수 있게 이스케이프 ──
# 백슬래시 → 큰따옴표 순서로 처리해야 이중 이스케이프를 피한다.
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ── 유틸: Claude 실행 + 다이얼로그 자동 처리 ────────────────
start_claude_in_pane() {
    local pane="$1" model="${2:-}" role="${3:-}" reasoning_effort="${4:-}"
    local effort_arg="" model_arg=""
    [ -z "$model" ] || model_arg="--model $(shell_quote "$model")"
    [ -z "$reasoning_effort" ] || effort_arg="--effort $(shell_quote "$reasoning_effort")"
    local claude_bin; claude_bin="$(command -v claude)"
    local pane_id="${pane##*:}"   # "team1:0.4" → "0.4". busy 마커·say 큐 키와 형식을 맞춘다.
    local state_key; state_key="$(pane_state_key "$pane")"

    # C-c로 파인에 떠 있을 수 있는 이전 프로세스를 중단하고, C-u로 입력 줄을 비워
    # 아래 send-keys가 이전 입력 잔여물과 섞이지 않게 한다.
    tmux send-keys -t "$pane" C-c 2>/dev/null; sleep 0.3
    tmux send-keys -t "$pane" C-u 2>/dev/null; sleep 0.2

    # 역할별 스킬 제한([3/7])이 만든 디렉터리가 있으면 그곳을 cwd로 삼고
    # --setting-sources project로 유저 전역·플러그인 스킬을 차단한다([3/7] 주석 참조).
    local work_dir="$PROJECT_DIR" skills_arg=""
    if [ -n "$role" ] && [ -d "$TEAM_SKILLS_ROOT/$role/.claude/skills" ]; then
        work_dir="$TEAM_SKILLS_ROOT/$role"
        skills_arg="--setting-sources project"
    fi

    # team/config.sh와 동일한 오버라이드 규칙: 프로젝트 루트의 team/{role}.md가
    # 있으면 우선, 없으면 이 저장소의 기본값으로 폴백한다.
    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"
    local system_prompt_arg=""
    if [ -n "$role" ] && [ -f "$role_file" ]; then
        local role_content; role_content="$(cat "$role_file")"
        # cwd가 .team/{역할}/ 인 파인에는 실제 작업 대상이 프로젝트 루트임을 알린다.
        # 이 안내가 없으면 파인이 자기 스킬 디렉터리를 프로젝트로 오인한다.
        if [ "$work_dir" != "$PROJECT_DIR" ]; then
            role_content="${role_content}"$'\n\n'"## 작업 경로

현재 셸의 cwd는 역할별 스킬 격리용 디렉터리(\`$work_dir\`)이며 작업 대상이 아니다.
**실제 프로젝트 루트는 \`$PROJECT_DIR\` 이다.** 파일을 읽고 쓰거나 git을 다룰 때는
그 경로를 기준으로 하고, 셸 작업이 필요하면 먼저 \`cd $(shell_quote "$PROJECT_DIR")\` 한다."
        fi
        # lead에는 MEMBER_NAMES 배열 기준 배분 표를 실행 시점에 동적 생성해 이어붙인다.
        # config.sh만 바꾸면 lead.md를 손대지 않아도 배분 표가 항상 일치하게 하기 위함.
        if [ "$role" = "lead" ]; then
            local team_table="## 팀원 배분 (자동 생성)"$'\n\n'"| 역할 | 지시 방법 |"$'\n'"| --- | --- |"
            for ((m = 1; m < ${#MEMBER_NAMES[@]}; m++)); do
                local say_name="${MEMBER_NAMES[$m]}"
                team_table+=$'\n'"| ${MEMBER_NAMES[$m]} | say ${say_name} \"...\" |"
            done
            role_content="${role_content}"$'\n\n'"${team_table}"
        fi
        # 조립된 지침은 파일로 쓰고 경로만 넘긴다 — 내용을 커맨드에 실으면
        # 지침이 커질 때 tmux send-keys가 "command too long"으로 거부한다(실측).
        # 파인이 재시작해도 읽을 수 있도록 /tmp가 아니라 .team/ 아래에 둔다.
        local prompt_file="$RUNTIME_DIR/${role}.prompt.md"
        mkdir -p "$RUNTIME_DIR"
        printf '%s' "$role_content" > "$prompt_file"
        system_prompt_arg="--append-system-prompt-file $(shell_quote "$prompt_file")"
    elif [ -n "$role" ]; then
        # MEMBER_NAMES에 오타가 있으면 role_file이 조용히 없는 채로 넘어가
        # 해당 파인이 역할 지침 없이 뜬다. 눈에 띄게 경고해 즉시 알아채도록 한다.
        echo -e "${RED}⚠️  team/${role}.md 없음 → 이 파인은 역할 지침 없이 실행됩니다 (MEMBER_NAMES 오타 확인)${NC}" >&2
    fi

    # Stop 훅으로 "작업 종료" 신호를 lead에 자동 전송한다(lead 자신은 제외).
    # 파인 번호는 호출 시점의 $pane에서 가져온다. 훅 커맨드 안에서
    # `tmux display-message -p '#{pane_index}'`를 쓰면 안 된다 — 훅 프로세스에는
    # TMUX_PANE이 전달되지 않아 그 시점의 활성 파인 번호가 잡히고,
    # 결국 모든 파인이 lead 자신인 :0.0을 보고하게 된다.
    #
    # PreToolUse(rtk 재작성 + 로깅)는 모든 파인에 명시 주입한다 — --settings가
    # 글로벌 settings.json을 병합이 아니라 '대체'하므로 그냥 두면 글로벌 rtk 훅이
    # 그 파인에서 사라진다. 로깅은 rtk와 별도 항목으로 둔다(같은 Bash 항목에
    # 얹으면 rtk의 matcher까지 넓어져 엉뚱한 도구에 재작성이 걸린다).
    # 셸 명령은 shell_quote로 직렬화한 뒤 JSON 문자열에 넣을 때 json_escape를 한 번 더 거친다.
    local log_cmd log_cmd_json
    log_cmd="$(shell_quote "$BIN_DIR/log-hook") $(shell_quote "${role:-unknown}") $(shell_quote "$PROJECT_DIR")"
    log_cmd_json="$(json_escape "$log_cmd")"
    local pretooluse_json="\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"rtk hook claude\"}]},{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]}]"

    # say는 화면 문구 대신 busy 마커로 유휴 여부를 판단한다. 턴 시작에 마커를
    # 만들고, 본 보고 마커와 함께 초기화해 Stop 훅이 이번 턴의 보고 여부만 판단한다.
    local userprompt_json="\"UserPromptSubmit\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]},{\"hooks\":[{\"type\":\"command\",\"command\":\"mkdir -p /tmp/team-busy && touch /tmp/team-busy/${state_key} && rm -f /tmp/team-say/${state_key}\"}]}]"

    # /clear·/compact는 Stop 훅 없이 끝날 수 있으므로 SessionStart에서 마커를 지운다.
    local sessionstart_json="\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"rm -f /tmp/team-busy/${state_key}\"}]}]"

    # 파인 간 통신은 say(tmux send-keys)가 담당하지만, Claude Code 자체의
    # cross-session messaging(SendMessage/ListAgents)도 파인마다 켜져 있다 —
    # 각 파인이 자기 인박스 소켓을 바인딩하므로 서로, 그리고 팀 밖 세션에서도 보인다.
    # 그런데 파인은 --dangerously-skip-permissions로 뜨고, 그 경우 기본 수신 규칙은
    # "발신 측도 권한 우회 모드일 때만 전달, 아니면 승인 대기로 보류"다. 팀 밖의
    # 일반 세션이 보낸 메시지는 여기 걸려 보류되는데, 파인에는 사람이 붙어 있지
    # 않아 승인 다이얼로그가 dialogExpiry(기본 5분) 후 그대로 폐기된다.
    # accept로 고정해 그 경로를 열어둔다. say는 이 설정과 무관하게 그대로 동작한다.
    local inbound_json="\"crossSessionInbound\":\"accept\""

    # 파인은 1M 컨텍스트 모델로 뜨는데, 200k를 넘긴 턴이 전체 입력의 32.6%를 차지했다.
    # 이 변수를 걸면 harness가 200K에서 자동 compaction으로 눌러 준다(/clear와 달리
    # 세션이 유지되므로 프리픽스 캐시를 다시 사지 않는다).
    # CLAUDE_CODE_DISABLE_BUNDLED_SKILLS: 번들 스킬 설명문(dataviz·claude-api·artifact-* 등)이
    # 매 턴 상수로 붙는 것을 끈다. superpowers:* 같은 플러그인 스킬은 영향 없다.
    local env_json="\"env\":{\"CLAUDE_CODE_DISABLE_1M_CONTEXT\":\"1\",\"CLAUDE_CODE_DISABLE_BUNDLED_SKILLS\":\"1\"},"

    # 플러그인 활성화도 --settings로 명시 주입한다. enabledPlugins·
    # extraKnownMarketplaces는 유저 전역 settings.json에만 있어서,
    # --setting-sources project로 뜨는 파인에서는 통째로 무시되기 때문이다
    # (실측: 그냥 두면 caveman·ponytail·serena가 파인에서 전혀 안 걸린다).
    # rtk 훅을 여기서 다시 넣는 것과 같은 이유·같은 패턴이다.
    #
    # 어떤 역할에 무엇을 주는지는 [2/7]의 CLAUDE_PLUGIN_ROLES가 정한다.
    local plugins_json=""
    if [ -n "$role" ]; then
        local enabled_entries=() marketplace_entries=() seen_marketplaces=" "
        for plugin in "${!CLAUDE_PLUGIN_ROLES[@]}"; do
            # 값이 "*"이면 전 파인, 아니면 공백 구분 역할 목록에 있을 때만 준다.
            local roles="${CLAUDE_PLUGIN_ROLES[$plugin]}"
            if [ "$roles" != "*" ] && [[ " $roles " != *" $role "* ]]; then
                continue
            fi
            enabled_entries+=("\"${plugin}\":true")
            # plugin@marketplace 에서 마켓플레이스 이름만 떼어 출처를 함께 싣는다.
            # 출처를 빼면 파인이 마켓플레이스를 몰라 플러그인을 못 찾는다.
            local mp="${plugin##*@}"
            if [[ "$seen_marketplaces" != *" $mp "* ]]; then
                marketplace_entries+=("\"${mp}\":{\"source\":{\"source\":\"github\",\"repo\":\"${CLAUDE_PLUGIN_MARKETPLACES[$mp]}\"}}")
                seen_marketplaces+="$mp "
            fi
        done
        if [ ${#enabled_entries[@]} -gt 0 ]; then
            local IFS=,
            plugins_json="\"enabledPlugins\":{${enabled_entries[*]}},\"extraKnownMarketplaces\":{${marketplace_entries[*]}},"
        fi
    fi

    # Stop 시점에 실행할 셸 커맨드를 조립한다. Claude·Codex 양쪽의 Stop 훅이
    # 같은 문자열을 쓴다 — 두 CLI 모두 "command" 타입 훅에 셸 커맨드를
    # 그대로 넘기는 동일한 계약이라, 종료 신호 로직을 공급자별로 복제하지
    # 않고 여기 한 곳에서만 유지한다. STOP_HOOK_CMD는 순수 셸 커맨드이므로
    # 아래 JSON에 넣기 직전 json_escape로 이스케이프한다.
    stop_hook_cmd_for_role "$role" "$pane_id" "$state_key"
    local stop_hook_cmd_json; stop_hook_cmd_json="$(json_escape "$STOP_HOOK_CMD")"

    local settings_arg=""
    if [ "$role" = "lead" ]; then
        # lead는 say 종료 신호용 Stop 훅을 받으면 안 된다 — 수신처가 lead 자신(:0.0)이라
        # 자기 응답이 끝날 때마다 스스로에게 신호를 보내 무한 루프가 된다.
        # busy 마커 정리는 say를 호출하지 않으므로 무한 루프와 무관해 lead에도 넣는다.
        #
        # lead만 tmux send-keys를 deny한다 — CLAUDE.md가 이미 금지하는데도 실측에서
        # tmux send-keys 24회가 나왔다(규칙 문구로는 안 막혀 구조로 막는다).
        # --dangerously-skip-permissions 하에서도 permissions.deny는 실제로 차단됨을
        # 격리된 프로브 세션으로 별도 확인 완료.
        local lead_deny_json="\"permissions\":{\"deny\":[\"Bash(tmux send-keys:*)\"]},"
        local lead_settings_json="{${plugins_json}${lead_deny_json}${env_json}${inbound_json},\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${stop_hook_cmd_json}\"}]}],${pretooluse_json},${userprompt_json},${sessionstart_json}}}"
        local lead_settings_file="$RUNTIME_DIR/${role}.settings.json"
        mkdir -p "$RUNTIME_DIR"
        printf '%s' "$lead_settings_json" > "$lead_settings_file"
        settings_arg="--settings $(shell_quote "$lead_settings_file")"
    elif [ -n "$role" ]; then
        local settings_json="{${plugins_json}${env_json}${inbound_json},\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${stop_hook_cmd_json}\"}]}],${pretooluse_json},${userprompt_json},${sessionstart_json}}}"
        local settings_file="$RUNTIME_DIR/${role}.settings.json"
        mkdir -p "$RUNTIME_DIR"
        printf '%s' "$settings_json" > "$settings_file"
        settings_arg="--settings $(shell_quote "$settings_file")"
    fi

    # unset CLAUDECODE: 이 스크립트 자신이 Claude Code 세션 안에서 실행 중일 경우
    # 남아있는 CLAUDECODE 환경변수가 파인 내부의 claude 실행에 영향을 주지 않도록 제거한다.
    # PATH에 BIN_DIR: 파인들이 `say`를 경로 없이 호출할 수 있게 한다.
    tmux send-keys -t "$pane" \
        "cd $(shell_quote "$work_dir") && unset CLAUDECODE && export PATH=$(shell_quote "$BIN_DIR${NVM_BIN:+:$NVM_BIN}"):\$PATH && export CAVEMAN_DEFAULT_MODE=full && $(shell_quote "$claude_bin") $model_arg $effort_arg --dangerously-skip-permissions $skills_arg $system_prompt_arg $settings_arg" Enter

    # 신뢰·약관 대화상자에 응답하고 입력 화면이 뜰 때까지 기다린다.
    # 이미 처리된 대화상자는 기다리지 않으며, 시간 초과는 실패로 돌려준다.
    wait_claude_ready "$pane" 60 || {
        echo -e "${RED}⚠️  Claude 준비 화면을 확인하지 못했습니다 (60초 초과)${NC}" >&2
        return 1
    }
    return 0
}

# ── Codex 역할 지침 및 실행 ──────────────────────────────────
# Codex는 Git 루트부터 현재 cwd까지의 AGENTS.md를 자동으로 합친다. 프로젝트
# 루트에는 공통 규칙을 병합하고, 역할별 cwd에는 이 파일을 만들어 역할 규칙만
# 추가한다. Claude의 --append-system-prompt-file과 같은 목적이지만, 지침 탐색은
# Codex가 담당한다.
write_codex_role_agents() {
    local role="$1" work_dir="$2" pane_id="$3" state_key="$4"
    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"

    if [ -z "$role" ] || [ ! -f "$role_file" ]; then
        echo -e "${RED}⚠️  team/${role}.md 없음 → Codex 역할 지침을 만들지 않습니다 (MEMBER_NAMES 오타 확인)${NC}" >&2
        return 1
    fi

    local role_content
    role_content="$(cat "$role_file")"
    role_content="${role_content}"$'\n\n'"## 작업 경로

현재 셸의 cwd는 역할별 런타임 디렉터리(\`$work_dir\`)이며 작업 대상이 아니다.
**실제 프로젝트 루트는 \`$PROJECT_DIR\` 이다.** 파일을 읽고 쓰거나 git을 다룰 때는
그 경로를 기준으로 하고, 셸 작업이 필요하면 먼저 \`cd $(shell_quote "$PROJECT_DIR")\` 한다."

    if [ "$role" = "lead" ]; then
        local team_table="## 팀원 배분 (자동 생성)"$'\n\n'"| 역할 | 지시 방법 |"$'\n'"| --- | --- |"
        local m say_name
        for ((m = 1; m < ${#MEMBER_NAMES[@]}; m++)); do
            say_name="${MEMBER_NAMES[$m]}"
            team_table+=$'\n'"| ${MEMBER_NAMES[$m]} | say ${say_name} \"...\" |"
        done
        role_content="${role_content}"$'\n\n'"${team_table}"
    fi

    mkdir -p "$work_dir"
    # 정리 뒤에도 남아 있는 AGENTS.md(링크 포함)는 사용자 파일이거나 사용자가 고친
    # 생성물이므로 표지만 보고 덮어쓰지 않는다. 새로 쓴 파일은 소유 기록에 남긴다.
    if [ -e "$work_dir/AGENTS.md" ] || [ -L "$work_dir/AGENTS.md" ]; then
        echo -e "${YELLOW}  ⚠️  $role: 기존 AGENTS.md가 있어 역할 지침을 쓰지 않습니다 (사용자 파일 보존, 역할 지침이 빠지거나 이전 내용일 수 있음)${NC}" >&2
    else
        printf '%s\n\n%s\n' '# Generated by ai-setup. Edit team/{role}.md instead.' "$role_content" > "$work_dir/AGENTS.md"
        team_owned_record "$work_dir" F "AGENTS.md" "$(sha256sum < "$work_dir/AGENTS.md" | cut -d' ' -f1)"
    fi

    # Stop 훅: busy 마커 정리 + 미보고 종료 신호. Claude와 같은 로직을
    # stop_hook_cmd_for_role 한 곳에서 만들어 양쪽이 쓴다(위 유틸 참조).
    # 프로젝트 로컬 훅은 신뢰 승인이 필요하므로, 무인 파인에서는 기동 시 이를 자동 처리한다.
    [ -n "$pane_id" ] || return 0
    stop_hook_cmd_for_role "$role" "$pane_id" "$state_key"
    local hook_cmd_json; hook_cmd_json="$(json_escape "$STOP_HOOK_CMD")"
    local session_start_cmd_json; session_start_cmd_json="$(json_escape "rm -f /tmp/team-busy/${state_key}")"
    # 프롬프트·툴 로깅은 Claude와 같은 bin/log-hook을 쓴다(payload 필드가 같다).
    local log_cmd_json
    log_cmd_json="$(json_escape "$(shell_quote "$BIN_DIR/log-hook") $(shell_quote "${role:-unknown}") $(shell_quote "$PROJECT_DIR") --quiet")"
    local log_hook_json="[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]}]"
    # 보고 마커는 "이번 턴에 보고했나" 1비트라 턴 시작마다 비운다(Claude와 동일).
    # busy 마커는 say가 전송 시점에 직접 만들므로 여기서 건드리지 않는다.
    local report_clear_json; report_clear_json="$(json_escape "rm -f /tmp/team-say/${state_key}")"
    local userprompt_json="[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd_json}\"}]},{\"hooks\":[{\"type\":\"command\",\"command\":\"${report_clear_json}\"}]}]"
    local hooks_json="{\"hooks\":{\"SessionStart\":[{\"matcher\":\"startup|resume|clear|compact\",\"hooks\":[{\"type\":\"command\",\"command\":\"${session_start_cmd_json}\"}]}],\"UserPromptSubmit\":${userprompt_json},\"PreToolUse\":${log_hook_json},\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${hook_cmd_json}\"}]}]}}"
    mkdir -p "$work_dir/.codex"
    # 정리 뒤에도 남아 있는 hooks.json은 사용자 파일이므로 덮어쓰지 않는다.
    if [ -e "$work_dir/.codex/hooks.json" ] || [ -L "$work_dir/.codex/hooks.json" ]; then
        echo -e "${YELLOW}  ⚠️  $role: 기존 .codex/hooks.json이 있어 lifecycle 훅을 쓰지 않습니다 (사용자 파일 보존, 종료 신호·busy 마커 훅이 빠짐)${NC}" >&2
        return 0
    fi
    printf '%s' "$hooks_json" > "$work_dir/.codex/hooks.json"
    team_owned_record "$work_dir" F ".codex/hooks.json" "$(sha256sum < "$work_dir/.codex/hooks.json" | cut -d' ' -f1)"
}

start_codex_in_pane() {
    local pane="$1" model="${2:-}" role="${3:-}" reasoning_effort="${4:-}"
    local codex_bin; codex_bin="$(command -v codex)"

    tmux send-keys -t "$pane" C-c 2>/dev/null; sleep 0.3
    tmux send-keys -t "$pane" C-u 2>/dev/null; sleep 0.2

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

    # Codex는 model_reasoning_effort 설정으로 지원 모델의 추론 수준을 조절한다.
    # 빈 값은 사용자의 Codex 기본 설정을 그대로 사용한다.
    local reasoning_arg=""
    [ -z "$reasoning_effort" ] || reasoning_arg="-c $(shell_quote "model_reasoning_effort=\"$reasoning_effort\"")"

    # 파인은 사람 승인 없이 git add/commit까지 수행해야 한다. Codex의
    # workspace-write는 writable root 아래의 .git을 항상 read-only로 보호하므로
    # --add-dir "$PROJECT_DIR"만으로는 인덱스·refs를 쓸 수 없다. 따라서 Claude의
    # --dangerously-skip-permissions와 동일하게 팀 기본값은 full access로 둔다.
    # 제한된 파인이 필요한 경우 CODEX_FULL_ACCESS=0으로 기존 경계를 복원한다
    # (이 모드에서는 git status/diff는 되지만 add/commit은 안 된다).
    local permission_args="--dangerously-bypass-approvals-and-sandbox"
    if [ "${CODEX_FULL_ACCESS:-1}" = "0" ]; then
        permission_args="--ask-for-approval never --sandbox workspace-write"
    fi

    # --dangerously-bypass-hook-trust만으로는 로컬 훅이 활성화되지 않을 수 있어,
    # 아래에서 /hooks의 trust-all 입력까지 자동화한다.
    local hook_trust_args="--dangerously-bypass-hook-trust"

    # Codex의 주 workspace는 역할별 cwd지만 실제 프로젝트도 명시적으로 writable
    # directory에 더한다. 이로써 AGENTS.md 계층은 역할별로 유지하면서 코드 수정은
    # 프로젝트 루트에서 가능하다.
    # say(bin/say)가 IPC로 쓰는 경로들도 명시적으로 writable에 더한다 —
    # 안 그러면 sandbox가 막아 codex 파인에서 say lead 보고가 조용히 실패한다.
    # codex tmux IPC(AF_UNIX 소켓) 때문에 network_access가 필요하다: tmux 소켓
    # connect는 Landlock 경로 허용과 별개로 seccomp 네트워크 필터(EPERM)에 막힌다.
    # FS는 계속 add-dir로 제약한다 — network_access는 socket()만 열 뿐, 마커 파일
    # write는 여전히 Landlock 소관이라 위 --add-dir 4개(마커 3경로+tmux 소켓
    # 디렉터리)가 없으면 그대로 막힌다. 주의: network_access=true는 workspace-write
    # sandbox의 outbound 네트워크 전체를 여는 것이지 이 소켓 하나로 국한되지
    # 않는다 — 의도된 sandbox boundary 확대다(architect 승인, say 왕복 스모크
    # 테스트로 확인).
    local tmux_tmpdir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
    tmux send-keys -t "$pane" \
        "cd $(shell_quote "$work_dir") && export CODEX_HOME=$(shell_quote "$role_codex_home") && export PATH=$(shell_quote "$BIN_DIR${NVM_BIN:+:$NVM_BIN}"):\$PATH && $(shell_quote "$codex_bin") $permission_args $hook_trust_args --add-dir $(shell_quote "$PROJECT_DIR") --add-dir $(shell_quote "$tmux_tmpdir") --add-dir /tmp/team-busy --add-dir /tmp/team-say --add-dir /tmp/team-say-queue -c 'sandbox_workspace_write.network_access=true' $model_arg $reasoning_arg" Enter

    # 최초 실행 시 git 프로젝트 신뢰 확인 대화상자가 뜬다("Do you trust the
    # contents of this directory?"). "1. Yes, continue"가 기본 선택이므로 Enter만
    # 보내면 된다. 대화상자가 안 뜨는 경우를 헛기다리지 않도록 입력 프롬프트와
    # 함께 기다리고, 어느 쪽도 못 보면 실패로 돌려준다.
    wait_for_pane "$pane" "Do you trust the contents\|Ask Codex to do anything" 30 || {
        echo -e "${RED}⚠️  Codex 준비 화면을 확인하지 못했습니다 (30초 초과)${NC}" >&2
        return 1
    }
    if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -q "Do you trust the contents"; then
        tmux send-keys -t "$pane" Enter
        sleep 1
        wait_for_pane "$pane" "Ask Codex to do anything" 30 || {
            echo -e "${RED}⚠️  Codex 신뢰 확인 후 입력 프롬프트가 뜨지 않았습니다 (30초 초과)${NC}" >&2
            return 1
        }
    fi

    # 훅 신뢰 승인 자동화: /hooks를 열고 't'로 전부 신뢰한 뒤 esc로 닫는다.
    # --dangerously-bypass-hook-trust만으로는 로컬 훅이 활성화되지 않을 수 있어
    # 근거 없이 빼지 않고 유지한다. 프롬프트가 떠 있어야 입력이 먹으므로 위에서
    # 준비 완료를 확인한 뒤에만 보낸다.
    tmux send-keys -t "$pane" -l "/hooks"
    sleep 0.3
    tmux send-keys -t "$pane" Enter
    sleep 1
    tmux send-keys -t "$pane" -l "t"
    sleep 1
    tmux send-keys -t "$pane" Escape
    sleep 1

    sleep 2
    return 0
}

# ── claude 로그인 확인 ────────────────
check_login() {
    claude auth status >/dev/null 2>&1
}

check_codex_login() {
    codex login status >/dev/null 2>&1
}

# ── [0/7] 공통 (Claude·Codex) — 사전 요구사항 확인 ─────────
# 혼합 팀에서는 실제로 파인에 배정된 공급자(USED_AGENTS) 전부를 검사한다 —
# $TEAM_AGENT 하나만 보면 reviewer만 codex인 팀에서 codex 설치·로그인 확인이
# 통째로 생략된다.
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

# 기존 tmux 세션을 .team/ 삭제보다 먼저 정리한다. 살아있는 Codex/Claude 파인이
# .team/{역할}/.codex-home 등에 소켓·로그를 계속 쓰는 상태로 아래 rm -rf를
# 돌리면 "Directory not empty"로 삭제가 실패하는 경우가 실측됐다(경합).
tmux has-session -t "$SESSION" 2>/dev/null && {
    tmux kill-session -t "$SESSION"
    # kill-session은 요청만 던지고 바로 리턴한다. tmux 서버가 소켓 정리를
    # 끝내기 전에 아래 rm -rf나 [6/7]의 new-session -s "$SESSION"이 뜨면
    # 레이스로 실패하는 경우가 실측됐다(set -e라 스크립트 전체가 죽는다).
    # has-session이 실제로 false를 반환할 때까지 짧게 폴링해 정리 완료를 기다린다.
    for _ in $(seq 1 20); do
        tmux has-session -t "$SESSION" 2>/dev/null || break
        sleep 0.2
    done
    echo ""
    echo "  🧹 기존 '$SESSION' 세션 종료"
}

# .team/ 런타임 루트는 두 공급자 블록이 공유한다. 혼합 팀에서 각 블록이
# 자기 시작점에서 매번 정리하면 먼저 실행된 블록의 결과물이 지워지므로,
# 정리는 여기서 한 번만 하고 두 블록은 각자 자기 역할분만 채운다.
TEAM_SKILLS_ROOT="$PROJECT_DIR/.team"
RUNTIME_DIR="$TEAM_SKILLS_ROOT/_runtime"

reset_generated_team_files() {
    # 기존 .team/은 재사용하되(역할별 Codex 홈·설치 캐시 보존) 이전 실행이 만든
    # 생성물만 지운다: _runtime 전체, 역할 디렉터리의 소유 기록에 남은 스킬 링크·hooks.json·
    # AGENTS.md. 사용자가 만든 항목, 사용자가 고친 항목, 소유 기록이 없는 기존 항목은
    # 표지나 내용으로 소유자를 추정하지 않고 둔다.
    # 이후 단계가 현재 구성으로 다시 만든다.
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

# Claude 전용 단계 준비. Codex는 1차 구현에서 Claude 플러그인·rtk 훅을 공유하지 않는다.
# 혼합 팀에서는 아래 두 블록이 각각 독립 조건으로 순서대로 실행된다.
if [ -n "${USED_AGENTS[claude]:-}" ]; then

# ── [1/7] Claude — rtk 훅 초기화 ───────────────────────────
# ~/.claude 는 로그인 후 생성되고 volume(claude-home) 안에 있으므로
# 이미지 빌드 시점이 아니라 여기(런타임)에서 1회 등록한다.
# --auto-patch: settings.json patch 여부를 묻지 않고 자동 진행
# RTK_TELEMETRY_DISABLED=1 + timeout: v0.36.0+ 에서 non-interactive 환경일 때
# telemetry 동의 프롬프트가 무한 대기하는 알려진 버그(rtk-ai/rtk#1307)에 대한 안전장치
# printf 'n\n': 위 telemetry 동의 프롬프트에 대한 응답(비동의)이며,
# RTK_TELEMETRY_DISABLED가 무시될 경우를 대비한 이중 안전장치
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Claude — rtk 훅 초기화...${NC}"

if printf 'n\n' | RTK_TELEMETRY_DISABLED=1 timeout 15 rtk init -g --auto-patch; then
    echo -e "  ${GREEN}✅  rtk 훅 등록 완료${NC}"
else
    echo -e "  ${YELLOW}⚠️  rtk init 실패 또는 timeout (이미 설정되어 있거나 수동 확인 필요)${NC}"
    echo -e "  ${YELLOW}   확인: rtk init --show${NC}"
fi


# ── [2/7] Claude — 필요한 플러그인 설치 ──────────────────────
# 마켓플레이스 플러그인은 ~/.claude/plugins/ 아래에 설치되는데, 이 경로는
# volume(claude-home) 안이라 컨테이너를 새로 만들면 사라진다. 그래서 실행 때마다
# 설치 명세(installed_plugins.json)를 확인해 없는 것만 채운다.
#
# 아래 [3/7]의 CLAUDE_SUPERPOWERS_SKILL_SETS가 참조하는 superpowers 스킬 원본이 여기서 깔리고,
# caveman/ponytail은 응답 스타일 규칙을, serena는 심볼 단위 코드 탐색 MCP를 제공한다.
#
# 여기서는 설치까지만 한다. 파인별 활성화는 start_claude_in_pane이 --settings에
# enabledPlugins를 실어 처리한다 — 파인은 --setting-sources project로 뜨는 탓에
# 유저 전역 settings.json의 enabledPlugins를 못 읽기 때문이다.
#
# 멱등성: `claude plugin install`은 이미 설치돼 있으면 그 사실만 알리고 성공으로
# 끝나므로 재실행에 안전하다.
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Claude — 필요한 플러그인 설치...${NC}"

# 설치할 플러그인 → 그 플러그인을 켤 역할 (plugin@marketplace 형식으로 소스를
# 못 박는다 — 같은 이름이 여러 마켓플레이스에 있을 때 엉뚱한 쪽이 깔리는 것을 막는다).
# 실제 마켓플레이스·역할 배분 선언은 team/config.claude.sh에 둔다.
#
# 값의 의미:
#   "*"          모든 파인에서 켠다
#   "a b"        공백으로 구분된 해당 역할에서만 켠다
#   ""           설치만 하고 enabledPlugins에는 넣지 않는다
#
# 역할별 플러그인 배분은 토큰 고정비와 해당 역할의 사용 빈도를 고려해
# team/config.claude.sh에서 정한다. 상세 근거는 설계 문서를 참조한다.
# superpowers는 빈 값이다(frontend-design은 designer에 켠다). [3/7]이 플러그인 캐시에서 스킬
# 디렉터리를 직접 심볼릭 링크하므로 enabledPlugins 없이도 역할별로 이미 걸린다.
# 여기서 또 켜면 superpowers 스킬 14개가 통째로 들어와 [3/7]의 선별이 무의미해진다
# (frontend-design은 스킬이 1개뿐이라 차이가 없지만, 링크로 거는 방식을 맞춘다).

install_claude_plugins() {
    # 이 팀의 Claude 파인에 필요한데 설치본이 없는 플러그인만 설치한다.
    # 이미 설치된 것은 필요 여부와 상관없이 명령 없이 표시만 하고, 필요 없고
    # 설치도 안 된 것은 건너뛴다. 마켓플레이스 등록도 실제 설치 대상 것만 한다.
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

    # 설치만 한다. `claude plugin enable`은 부르지 않는다 — 그건 유저 전역
    # settings.json을 고쳐 팀 밖 세션에까지 영향을 주는데, 파인의 활성화는
    # start_claude_in_pane이 --settings로 따로 넣으므로 필요하지도 않다.
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
# 사용자 전역 ~/.claude/skills와 플러그인 스킬은 모든 파인의 시스템 프롬프트에
# frontmatter로 들어가 고정비가 된다. 역할마다 필요한 스킬만 주기 위해
#   1) 파인마다 $PROJECT_DIR/.team/{역할}/.claude/skills 를 만들어 필요한 스킬만 링크하고
#   2) 그 디렉터리를 cwd로 claude를 띄우되 --setting-sources project 로
#      유저 전역 스킬과 플러그인 스킬을 차단한다
# claude에 빌트인된 스킬(dataviz, init, security-review 등 약 15개)은 설정 소스와
# 무관하게 로드된다. 다만 아래 실행 시 CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1로
# 별도로 비활성화한다.
# 프로젝트 스킬 탐색은 상위 디렉터리로 거슬러 올라가므로, cwd가 프로젝트 안이면
# $PROJECT_DIR/.claude/skills 의 공용 스킬은 모든 파인이 그대로 상속한다.
# cwd가 프로젝트 밖이 아니라 안이라서 git·상대경로도 평소대로 동작한다.
# 스킬은 플러그인 설치본의 디렉터리를 심볼릭 링크하므로 중복 사본이 생기지 않는다.
#
# 주의: --setting-sources project는 유저 settings.json(훅)도 함께 끄므로,
# 아래 start_claude_in_pane이 PreToolUse(rtk 재작성)를 --settings로 명시
# 주입한다. lead도 마찬가지지만 Stop 훅만은 제외한다(자기 자신에게 종료 신호를
# 보내 무한 루프가 되기 때문).
#
# 반면 ~/.claude/rules/ 와 ~/.claude/CLAUDE.md 는 이 플래그로 꺼지지 않는다 —
# cwd가 홈 디렉터리 아래이면 그대로 로드된다(실측). 파인 cwd는 항상
# $PROJECT_DIR/.team/{역할} 이므로 전역 규칙은 계속 들어온다.
# 즉 여기서 줄어드는 것은 전역 스킬 frontmatter와 플러그인·에이전트 정의다.
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Claude — 런타임 준비 (공통 지침 병합·역할별 스킬 제한)...${NC}"

# 역할별 스킬 배분은 team/config.claude.sh의 CLAUDE_{플러그인}_SKILL_SETS에 선언한다.
# 값이 비거나 키가 없으면 그 플러그인 스킬을 주지 않는다. 스킬이 하나도 없는
# 역할도 디렉터리는 만든다(→ --setting-sources project 적용).

# 플러그인 스킬(superpowers 등)의 원본은 ~/.claude/plugins/cache/.../skills/ 에 있다.
# --setting-sources project가 플러그인 스킬을 통째로 차단하므로, 역할별로 필요한 것만
# .team/{역할}/.claude/skills 에 링크해서 되살린다. CLAUDE_PLUGIN_ROLES의 플러그인마다
# CLAUDE_{플러그인}_SKILL_SETS(대문자, '-'는 '_')를 찾아 같은 로직으로 처리한다.
# 어떤 역할이 무엇을 왜 받는지는 team/{역할}.md의 "## 스킬" 절에 적혀 있다.
#
# 설치 경로는 버전마다 달라지므로 설치 명세(installed_plugins.json)에서 읽는다.

# 전역 규칙(~/.claude/rules/, ~/.claude/CLAUDE.md)은 따로 주입하지 않는다.
# --setting-sources project는 cwd가 $HOME 아래이면 이것들을 끄지 못하므로(실측)
# 홈 아래 프로젝트에서는 주입이 중복이고, 홈 밖이면 전역 규칙 없이 도는 편이
# 고정비 절감이라는 의도에 맞다. 스킬·플러그인 차단은 양쪽 모두 정상 작동한다.

# ── 공통 지침을 대상 프로젝트 CLAUDE.md에 병합 ──────────────
# 파인이 세션 시작 시 자동으로 읽는 CLAUDE.md는 $PROJECT_DIR의 것이다.
# 이 리포의 CLAUDE.md는 $PROJECT_DIR이 여기일 때만 우연히 읽히므로, 남의
# 프로젝트에 팀을 띄우면 팀 공통 규칙(say 사용법, cwd 함정 등)이 전달되지 않는다.
# 그래서 마커 블록으로 삽입한다 — 사용자가 쓴 내용은 건드리지 않고 블록 안만 교체.
# 이 파일은 대상 리포에 남으므로 통째로 덮어쓰지 않고 마커 블록만 갱신한다.
merge_team_claude_md() {
    local src="$SCRIPT_DIR/CLAUDE.md"
    local dst="$PROJECT_DIR/CLAUDE.md"
    [ -f "$src" ] || return 0
    # 같은 파일이면(이 리포에서 팀을 띄운 경우) 자기 자신에 병합할 필요가 없다.
    [ "$(realpath "$src")" != "$(realpath "$dst" 2>/dev/null || echo "$dst")" ] || return 0

    local begin="<!-- ai-setup:team:start -->"
    local end="<!-- ai-setup:team:end -->"

    if [ -f "$dst" ] && grep -qF "$begin" "$dst"; then
        # 기존 블록 교체. awk로 마커 사이만 갈아끼운다(사용자 내용 보존).
        awk -v b="$begin" -v e="$end" -v f="$src" '
            index($0, b) { print; while ((getline line < f) > 0) print line; skip = 1; next }
            index($0, e) { skip = 0 }
            !skip
        ' "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    else
        # 블록이 없으면 파일 끝에 추가(파일 자체가 없으면 새로 생성).
        { [ -f "$dst" ] && printf '\n'; printf '%s\n' "$begin"; cat "$src"; printf '%s\n' "$end"; } >> "$dst"
    fi
    echo -e "${GREEN}  ✅ 팀 공통 지침을 $dst 에 병합${NC}"
}
merge_team_claude_md

# TEAM_SKILLS_ROOT·RUNTIME_DIR 정리는 위에서 공급자 공통으로 이미 처리했다.

# 팀의 Claude 역할마다 디렉터리를 만든다 — 배정 스킬이 없어도 --setting-sources
# project 격리는 적용된다.
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

# Codex 전용 단계 준비. USED_AGENTS[claude]와 독립 조건이므로 혼합 팀에서는
# 위 Claude 블록에 이어 이 블록도 실행된다(일부 역할만 codex인 경우 등).
if [ -n "${USED_AGENTS[codex]:-}" ]; then

# ── [4/7] Codex — 필요한 플러그인 설치 ────────────────────────────
# Codex에는 Claude 플러그인을 재사용하지 않는다. standalone 스킬과 Codex 공식
# 플러그인의 허용된 기능만 역할별 .agents/skills 또는 격리된 CODEX_HOME에 넣는다.
echo -e "\n${YELLOW}[$((STEP++))/$STEP_TOTAL] Codex — 필요한 플러그인 설치...${NC}"

merge_team_agents_md() {
    local src="$SCRIPT_DIR/AGENTS.md"
    local dst="$PROJECT_DIR/AGENTS.md"
    [ -f "$src" ] || return 0
    [ "$(realpath "$src")" != "$(realpath "$dst" 2>/dev/null || echo "$dst")" ] || return 0

    local begin="<!-- ai-setup:codex:start -->"
    local end="<!-- ai-setup:codex:end -->"
    if [ -f "$dst" ] && grep -qF "$begin" "$dst"; then
        awk -v b="$begin" -v e="$end" -v f="$src" '
            index($0, b) { print; while ((getline line < f) > 0) print line; skip = 1; next }
            index($0, e) { skip = 0 }
            !skip
        ' "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    else
        { [ -f "$dst" ] && printf '\n'; printf '%s\n' "$begin"; cat "$src"; printf '%s\n' "$end"; } >> "$dst"
    fi
    echo -e "${GREEN}  ✅ Codex 팀 공통 지침을 $dst 에 병합${NC}"
}


# TEAM_SKILLS_ROOT·RUNTIME_DIR 정리는 위에서 공급자 공통으로 이미 처리했다.

base_codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_assets_home="$TEAM_SKILLS_ROOT/_assets/codex-home"

codex_default_model_config() {
    # 사용법: codex_default_model_config <CODEX_HOME>
    # 사용자 기본 config.toml 최상위의 model·model_reasoning_effort 줄만 출력한다(첫 [테이블] 앞까지).
    # 없는 키나 없는 파일은 아무것도 출력하지 않는다. 기본 홈은 읽기만 한다.
    [ -f "$1/config.toml" ] || return 0
    awk '/^[[:space:]]*\[/ { exit } /^[[:space:]]*(model|model_reasoning_effort)[[:space:]]*=/ { print }' "$1/config.toml"
}

write_codex_role_plugins() {
    # 역할 홈 config.toml을 매 실행 새로 쓴다: 사용자 기본 모델·추론 설정을 먼저 상속하고
    # (MEMBERS의 명시 값은 실행 인자가 덮어쓴다), 플러그인은 기본 차단 후 배정된 항목만 활성화한다.
    local role="$1" role_home="$2" plugin roles
    mkdir -p "$role_home"
    {
        codex_default_model_config "${base_codex_home:-}"
        printf '[plugins._default]\nenabled = false\n'
        for plugin in "${!CODEX_PLUGIN_ROLES[@]}"; do
            roles="${CODEX_PLUGIN_ROLES[$plugin]}"
            [ "$roles" = "*" ] || [[ " $roles " == *" $role "* ]] || continue
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
    # 사용법: codex_shared_plugin_cache <plugin@marketplace> <제외할 역할 홈>
    # 재사용할 설치본이 있는 홈을 기본 홈 → 팀 자산 홈 → 다른 역할 홈 순으로 찾아
    # 그 버전 디렉터리를 출력한다. 없으면 1.
    local key="$1" skip="$2" home
    for home in "$base_codex_home" "$codex_assets_home" "$TEAM_SKILLS_ROOT"/*/.codex-home; do
        [ -d "$home" ] || continue
        [ "$home" != "$skip" ] || continue
        codex_plugin_cache "$home" "$key" && return 0
    done
    return 1
}

prepare_codex_role_home() {
    # 역할별 인증·플러그인을 준비한다. 기존 역할 홈은 재사용하고, 설치본이 있으면
    # 명령 없이 표시만 하며, 기본 홈에만 있으면 다시 내려받지 않고 연결한다.
    local role="$1" role_home="$2" plugin
    mkdir -p "$role_home/skills"
    write_codex_role_plugins "$role" "$role_home"
    link_codex_base_assets "$role_home"
    if ! CODEX_HOME="$role_home" codex login status >/dev/null 2>&1; then
        echo -e "${RED}  ❌ $role: 격리된 CODEX_HOME에서 기존 Codex 인증을 사용할 수 없습니다.${NC}" >&2
        return 1
    fi

    # 값이 "*"이면 전 역할, 아니면 공백 구분 역할 목록에 있을 때만 설치한다.
    local role_plugins=() roles
    for plugin in "${!CODEX_PLUGIN_ROLES[@]}"; do
        roles="${CODEX_PLUGIN_ROLES[$plugin]}"
        [ "$roles" = "*" ] || [[ " $roles " == *" $role "* ]] || continue
        role_plugins+=("$plugin")
    done
    [ ${#role_plugins[@]} -gt 0 ] || return 0

    local base_cache link_dir
    for plugin in "${role_plugins[@]}"; do
        if codex_plugin_cache "$role_home" "$plugin" >/dev/null; then
            echo "  ℹ️  $plugin 이미 설치됨 → $role"
        elif base_cache="$(codex_shared_plugin_cache "$plugin" "$role_home")"; then
            # 기본 홈·자산 홈·다른 역할 홈의 설치본을 이 역할 홈의 cache에 연결한다.
            # 활성화는 위 config.toml이 역할별로 정하므로 다른 역할에는 켜지지 않는다.
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
    # 사용법: codex_plugin_skills_root <plugin@marketplace>
    # 선택 스킬의 원본 디렉터리를 찾는다: 기본 홈 설치본 → 팀 자산 홈 → 역할 홈 설치본
    # → 공식 snapshot. 어느 홈에든 설치본이 있으면 다시 설치하지 않는다.
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
    # 활성화 역할이 비어 있어도 선택 스킬의 원본으로 쓰는 플러그인은 자산을 확보한다.
    # 전역 설정을 건드리지 않도록 설치가 필요하면 팀 자산 홈($codex_assets_home)에 한다.
    # 활성화 역할이 있는 플러그인은 역할 홈 준비에서 처리하고, 쓰이지 않는 플러그인은
    # 설치된 것만 표시하고 건너뛴다.
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
            if [ "$roles" = "*" ] || [[ " $roles " == *" ${MEMBER_NAMES[$i]} "* ]]; then activated=true; fi
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
merge_team_agents_md

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

    # 플러그인(superpowers 등)의 스킬 원본은 설치본 또는 공식 marketplace
    # snapshot(~/.codex/.tmp/plugins)에서 찾는다. CODEX_PLUGIN_ROLES의
    # 플러그인마다 CODEX_{플러그인}_SKILL_SETS(대문자, '-'는 '_')를 찾는다.
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

# -x 220 -y 50: main-vertical 레이아웃에서 파인 6개가 각각 읽을 만한 너비를
# 확보하기 위한 최소 터미널 크기. tmux는 접속 클라이언트 크기로 윈도우를 다시
# 맞추므로, 이 값을 키워도 실제 터미널 창보다 커질 수는 없다.
create_team_session() {
    # 팀 세션을 만들고 그 세션의 창·파인 번호를 0부터로 맞춘다. 사용자 tmux에
    # base-index/pane-base-index가 1이어도 이 세션의 창에만 적용하고 전역 설정은 건드리지 않는다.
    local first_window
    tmux new-session -d -s "$SESSION" -x 220 -y 50
    first_window="$(tmux list-windows -t "$SESSION" -F '#{window_index}' | head -1)"
    tmux set-window-option -t "$SESSION:$first_window" pane-base-index 0
    if [ "$first_window" != 0 ]; then
        tmux move-window -s "$SESSION:$first_window" -t "$SESSION:0"
    fi
}
create_team_session

# 파인을 PANE_COUNT개가 될 때까지 분할 (0번 파인은 new-session이 이미 생성)
for ((i = 0; i < PANE_COUNT - 1; i++)); do
    tmux split-window -t "$SESSION:0.$i" -h
done

# main-vertical 레이아웃 (팀장 왼쪽 넓게)
# even-horizontal을 먼저 적용해 파인 크기를 고르게 맞춘 뒤 main-vertical로 전환해야
# tmux가 비정상적으로 좁은 파인을 만들지 않는다.
tmux select-layout -t "$SESSION:0" even-horizontal
# main-pane-width는 select-layout main-vertical이 레이아웃을 계산할 때 참조하는
# 값이라 반드시 그 호출 전에 설정해야 한다 — 순서가 바뀌면(set-option을 나중에
# 호출) 이미 그려진 레이아웃에는 반영되지 않아 55%가 무시된다.
# 절대값(컬럼 수) 대신 %로 지정 — 실제 터미널 창 폭이 좁을 때도
# lead 파인이 나머지 파인 대비 상대적으로 넓게 유지된다.
tmux set-option -t "$SESSION" main-pane-width '55%'
tmux select-layout -t "$SESSION:0" main-vertical

# 파인 이름 설정 (레이아웃 설정 후, Claude 실행 전)
# MEMBER_DISPLAY_NAMES가 있으면 표시용 사람 이름을, 없으면 직무명을 그대로 쓴다.
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    display_name="${MEMBER_DISPLAY_NAMES[$pane]:-${MEMBER_NAMES[$pane]}}"
    tmux select-pane -t "$SESSION:0.$pane" -T "${display_name^^}"
    tmux set-option -p -t "$SESSION:0.$pane" @role "${MEMBER_NAMES[$pane]}"
    # pane_title은 에이전트 CLI의 OSC 제목 변경 대상이다. 테두리에 보일
    # 이름은 별도 pane 옵션으로 보관해야 CLI 제목과 경합하지 않는다.
    tmux set-option -p -t "$SESSION:0.$pane" @display_name "${display_name^^}"
done

# 파인 제목 표시 설정
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{@display_name} "
# 에이전트가 pane_title을 작업명·프로젝트명으로 바꿔도 외부 터미널 제목과
# 파인 테두리는 표시이름만 사용한다.
tmux set-option -t "$SESSION" set-titles on
tmux set-option -t "$SESSION" set-titles-string "#{@display_name}"
tmux set-option -t "$SESSION" allow-rename off
# 마우스 휠 스크롤·파인 클릭 전환 (tmux 기본값이 off라 켜주지 않으면 스크롤이 안 먹는다)
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

    # 이전 watcher가 비정상 종료돼 큐와 lock만 남았더라도 새 파인이 준비된
    # 시점에 lock 소유자를 검증하고 보존된 큐를 자동으로 다시 가동한다.
    "$BIN_DIR/say" --drain "$SESSION:0.$pane"
}

# 파인마다 tmux 대상·설정 파일이 따로라 동시에 띄워도 서로 간섭하지 않는다.
# 전체 대기가 파인 수의 합이 아니라 가장 느린 파인 하나로 줄어든다.
# 출력이 섞이지 않도록 파인별 로그에 모았다가 아래에서 순서대로 보여 준다.
# 이번 실행에서 Claude에 처음 로그인했다면 첫 Claude 파인의 초기 처리(신뢰·약관)를
# 먼저 마치고, 나머지는 Claude·Codex 구분 없이 함께 병렬로 띄운다.
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
# 기동에 실패한 파인이 있으면 성공 배너 대신 실패한 역할을 알리고 실패로 끝낸다.
# tmux 세션은 남겨 두므로 `tmux attach -t "$SESSION"`으로 화면을 확인할 수 있다.
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

# 터미널에서 직접 실행한 경우 자동 attach. `test && ...` 형태로 두면 비대화형
# 스모크 테스트에서 test의 false(1)가 스크립트 전체 종료 코드가 되는 문제가 있다.
if [ -t 1 ]; then
    tmux attach -t "$SESSION"
fi

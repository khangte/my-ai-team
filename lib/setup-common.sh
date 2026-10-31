#!/bin/bash
# setup-wsl.sh·setup-mac.sh가 공유하는 인자 파싱과 팀 구성 판독.
# bash 3.2(macOS 기본)에서도 동작해야 하므로 연관 배열·mapfile을 쓰지 않는다.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

setup_parse_args() {
    # 인자를 해석해 TEAM_AGENT·PROJECT_ARG를 채운다. 호출 전 SETUP_NAME(스크립트명)이 필요하다.
    TEAM_AGENT="${TEAM_AGENT:-claude}"
    PROJECT_ARG=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --agent)
                [ $# -ge 2 ] || { echo "--agent에는 값이 필요합니다." >&2; exit 2; }
                TEAM_AGENT="$2"
                shift 2
                ;;
            --agent=*)
                TEAM_AGENT="${1#--agent=}"
                shift
                ;;
            -h|--help)
                echo "사용법: ./$SETUP_NAME [--agent claude|codex] [프로젝트_경로]"
                exit 0
                ;;
            -*)
                echo "알 수 없는 옵션: $1" >&2
                exit 2
                ;;
            *)
                [ -z "$PROJECT_ARG" ] || { echo "프로젝트 경로는 하나만 지정할 수 있습니다." >&2; exit 2; }
                PROJECT_ARG="$1"
                shift
                ;;
        esac
    done

    case "$TEAM_AGENT" in
        claude|codex) ;;
        *) echo "지원하지 않는 에이전트: $TEAM_AGENT (claude 또는 codex)" >&2; exit 2 ;;
    esac
}

setup_load_team() {
    # team/config.sh(저장소 → 프로젝트 순)를 읽어 NEED_CLAUDE·NEED_CODEX를 정한다. SCRIPT_DIR이 필요하다.
    local project_path="${PROJECT_ARG:-${PROJECT_DIR:-$(pwd)}}" a
    PROJECT_DIR="$(cd "$project_path" 2>/dev/null && pwd -P)" \
        || { echo "프로젝트 경로를 찾을 수 없습니다: $project_path" >&2; exit 2; }

    MEMBER_NAMES=()
    MEMBER_AGENTS=()
    [ -f "$SCRIPT_DIR/team/config.sh" ] && source "$SCRIPT_DIR/team/config.sh"
    [ -f "$PROJECT_DIR/team/config.sh" ] && source "$PROJECT_DIR/team/config.sh"

    NEED_CLAUDE=false
    NEED_CODEX=false
    [ "${#MEMBER_AGENTS[@]}" -gt 0 ] || MEMBER_AGENTS=("")
    for a in "${MEMBER_AGENTS[@]}"; do
        case "${a:-$TEAM_AGENT}" in
            claude) NEED_CLAUDE=true ;;
            codex)  NEED_CODEX=true ;;
            *) echo "지원하지 않는 에이전트: '$a' (team/config.sh의 MEMBER_AGENTS 확인)" >&2; exit 2 ;;
        esac
    done
}

setup_plan() {
    # 단계 수(TOTAL)를 계산하고 선택된 공급자를 출력한다. 기본 단계 수를 인자로 받는다.
    TOTAL="$1"
    [ "$NEED_CLAUDE" = true ] && TOTAL=$((TOTAL + 2))
    [ "$NEED_CODEX" = true ] && TOTAL=$((TOTAL + 1))
    STEP=0
    echo "설치 대상 공급자: $([ "$NEED_CLAUDE" = true ] && printf 'claude ')$([ "$NEED_CODEX" = true ] && printf 'codex')"
}

step() {
    # 진행 단계 머리말을 출력한다.
    STEP=$((STEP + 1)); echo -e "\n${YELLOW}[$STEP/$TOTAL] $1${NC}"
}

setup_install_agent_clis() {
    # claude/rtk/codex CLI를 선택된 공급자에 맞게 설치한다. (node·npm이 준비된 뒤 호출)
    if [ "$NEED_CLAUDE" = true ]; then
        step "claude CLI 확인..."
        command -v claude &>/dev/null || npm install -g @anthropic-ai/claude-code
        echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"

        step "rtk 확인..."
        # Dockerfile과 같은 버전으로 고정한다.
        command -v rtk &>/dev/null || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | RTK_VERSION="${RTK_VERSION:-v0.43.0}" sh
        echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"
    fi

    if [ "$NEED_CODEX" = true ]; then
        step "codex CLI 확인..."
        command -v codex &>/dev/null || npm install -g @openai/codex
        echo "  ✅ codex $(codex --version 2>/dev/null | head -1)"
    fi
}

setup_prepare_linux_path() {
    # WSL 비로그인 셸용 PATH 정리: Windows 상호운용 경로(/mnt/*)를 빼 Windows용 node·npm·CLI를 고르지 않게 하고,
    # 기존 NVM·~/.local 도구를 앞에 둔다. 로그인 셸(bash -l)에 기대지 않는다.
    local nvm_bin entry rest="$PATH" kept=""
    nvm_bin="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)"
    while [ -n "$rest" ]; do
        entry="${rest%%:*}"
        case "$rest" in *:*) rest="${rest#*:}" ;; *) rest="" ;; esac
        case "$entry" in ""|/mnt/*) continue ;; esac
        kept="${kept:+$kept:}$entry"
    done
    PATH="${nvm_bin:+$nvm_bin:}$HOME/.local/bin:$kept"
    export PATH
}

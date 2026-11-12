#!/bin/bash
# install/wsl.sh·install/mac.sh·install/windows.sh·install/docker.sh가 공유하는 인자 파싱과 팀 구성 판독.
# setup-team.sh도 team/members.conf 파서(load_team_members) 때문에 이 파일을 source한다.
# bash 3.2(macOS 기본)에서도 동작해야 하므로 연관 배열·mapfile을 쓰지 않는다.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

setup_parse_args() {
    # 인자를 해석해 PROJECT_ARG를 채운다. 호출 전 SETUP_NAME(스크립트명)이 필요하다.
    PROJECT_ARG=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                echo "사용법: ./$SETUP_NAME [프로젝트_경로]"
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
}

# team/members.conf 파서. setup-team.sh·테스트도 이 파일을 source해 쓴다.
team_members_file() {
    # 프로젝트 members.conf가 있으면 그것을, 없으면 저장소 기본값 경로를 출력한다. 옛 config.sh만 있으면 실패한다.
    local repo_dir="$1" project_dir="$2"
    if [ -f "$project_dir/team/members.conf" ]; then
        printf '%s\n' "$project_dir/team/members.conf"
    elif [ -f "$project_dir/team/config.sh" ]; then
        echo "❌ $project_dir/team/config.sh는 더 이상 읽지 않습니다. SESSION과 MEMBERS를 $project_dir/team/members.conf로 옮기세요 (형식: $repo_dir/team/members.conf)." >&2
        return 2
    else
        printf '%s\n' "$repo_dir/team/members.conf"
    fi
}

load_team_members() {
    # members.conf를 읽어 SESSION과 멤버 배열을 채운다. 형식 오류면 경고 후 2를 반환한다.
    local file="$1" line role model effort agent n=0
    [ -f "$file" ] || { echo "❌ 팀 구성 파일이 없습니다: $file" >&2; return 2; }
    SESSION=""
    MEMBER_NAMES=()
    MEMBER_AGENTS=()
    SPEC_MEMBER_MODELS=()
    SPEC_MEMBER_REASONING_EFFORTS=()

    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line="${line%$'\r'}"   # Windows에서 편집한 CRLF 파일
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        case "$line" in
            ''|'#'*) continue ;;
            SESSION=*) SESSION="${line#SESSION=}"; continue ;;
        esac
        IFS='|' read -r role model effort <<< "$line"
        if [ "${line//[^|]/}" != "||" ] || [ -z "$role" ]; then
            echo "❌ MEMBERS 형식 오류: '$line' (필수 형식 role|model|effort, $file:$n 확인)" >&2
            return 2
        fi
        # shortcut: 접두사 두 개만 인식, 새 모델 계열이 나오면 여기에 추가한다.
        case "$model" in
            claude-*) agent="claude" ;;
            gpt-*)    agent="codex" ;;
            *) echo "❌ MEMBERS 모델 오류: '$model' (claude-* 또는 gpt-* 전체 모델 ID 필요: $file:$n)" >&2; return 2 ;;
        esac
        case "$effort" in
            ""|low|medium|high|xhigh|max) ;;   # 빈 값은 CLI 기본 effort
            *) echo "❌ MEMBERS effort 오류: '$effort' (low/medium/high/xhigh/max 중 하나 또는 빈 값: $file:$n)" >&2; return 2 ;;
        esac
        MEMBER_NAMES+=("$role")
        MEMBER_AGENTS+=("$agent")
        SPEC_MEMBER_MODELS+=("$model")
        SPEC_MEMBER_REASONING_EFFORTS+=("$effort")
    done < "$file"
}

setup_load_team() {
    # team/members.conf(프로젝트 파일 우선)를 읽어 NEED_CLAUDE·NEED_CODEX를 정한다. SCRIPT_DIR이 필요하다.
    local project_path="${PROJECT_ARG:-${PROJECT_DIR:-$(pwd)}}" a
    PROJECT_DIR="$(cd "$project_path" 2>/dev/null && pwd -P)" \
        || { echo "프로젝트 경로를 찾을 수 없습니다: $project_path" >&2; exit 2; }

    local members_file
    members_file="$(team_members_file "$SCRIPT_DIR" "$PROJECT_DIR")" || exit 2
    load_team_members "$members_file" || exit 2

    NEED_CLAUDE=false
    NEED_CODEX=false
    [ "${#MEMBER_AGENTS[@]}" -gt 0 ] || { echo "팀 구성이 없습니다. $members_file에 멤버 줄을 추가하세요." >&2; exit 2; }
    for a in "${MEMBER_AGENTS[@]}"; do
        case "$a" in
            claude) NEED_CLAUDE=true ;;
            codex)  NEED_CODEX=true ;;
            *) echo "지원하지 않는 에이전트: '$a' ($members_file 확인)" >&2; exit 2 ;;
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
        command -v rtk &>/dev/null || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/tags/v0.43.0/install.sh | RTK_VERSION="${RTK_VERSION:-v0.43.0}" sh
        if command -v rtk &>/dev/null; then
            echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"
        else
            echo "  ⚠️ rtk 설치 확인 실패 — PATH를 확인하세요" >&2
        fi
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

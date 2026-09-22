#!/bin/bash
#
# setup-native.sh — WSL 호스트에 Claude/Codex 팀 환경 직접 구성
#
# Dockerfile + setup-docker.sh가 컨테이너 안에서 하던 의존성 설치를
# WSL에 그대로 설치한다(격리 없이). volume 덮어쓰기 문제가 없으므로
# /opt 우회 경로 없이 기본 경로(~/.local, ~/.bun 등)에 설치한다.
# 설치 후 setup-team.sh를 그대로 실행해 tmux 팀 세션을 구성한다.
#
# 사용:
#   ./setup-native.sh [--agent claude|codex] [프로젝트_경로]
#
# 설치 대상 공급자는 setup-team.sh와 같은 규칙으로 정한다 — 이 저장소의
# team/config.sh, 이어서 프로젝트의 team/config.sh를 읽고 MEMBER_AGENTS에
# 실제로 배정된 공급자(빈 값은 --agent 기본값)를 모두 설치한다.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
            echo "사용법: ./setup-native.sh [--agent claude|codex] [프로젝트_경로]"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(realpath "${PROJECT_ARG:-${PROJECT_DIR:-$(pwd)}}")"

declare -a MEMBER_NAMES=()
declare -a MEMBER_AGENTS=()
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

TOTAL=2
[ "$NEED_CLAUDE" = true ] && TOTAL=$((TOTAL + 3))
[ "$NEED_CODEX" = true ] && TOTAL=$((TOTAL + 1))
STEP=0
step() { STEP=$((STEP + 1)); echo -e "\n${YELLOW}[$STEP/$TOTAL] $1${NC}"; }

echo "설치 대상 공급자: $([ "$NEED_CLAUDE" = true ] && printf 'claude ')$([ "$NEED_CODEX" = true ] && printf 'codex')"

step "apt 의존성 확인..."
MISSING_APT=()
command -v tmux &>/dev/null || MISSING_APT+=(tmux)
command -v git  &>/dev/null || MISSING_APT+=(git)
command -v curl &>/dev/null || MISSING_APT+=(curl)
command -v unzip &>/dev/null || MISSING_APT+=(unzip)
# python3는 bin/log-hook(프롬프트·툴 로깅)이 쓴다.
command -v python3 &>/dev/null || MISSING_APT+=(python3)
locale -a | grep -qi ko_KR.utf8 || MISSING_APT+=(locales)

if [ ${#MISSING_APT[@]} -gt 0 ]; then
    sudo apt-get update && sudo apt-get install -y "${MISSING_APT[@]}" fonts-noto-cjk
    sudo locale-gen ko_KR.UTF-8
    sudo update-locale LANG=ko_KR.UTF-8
else
    echo "  ✅ tmux/git/curl/locale 이미 설치됨"
fi

step "Node.js 확인..."
command -v node &>/dev/null || {
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
    sudo apt-get install -y nodejs
}
echo "  ✅ node $(node --version 2>/dev/null)"

# NodeSource Node는 npm 전역 prefix가 /usr라 sudo 없이 npm install -g가 EACCES로
# 막힌다. 쓸 수 없으면 사용자 prefix(~/.local, claude·rtk와 같은 bin)로 옮긴다.
npm_prefix="$(npm config get prefix)"
if [ -d "$npm_prefix/lib/node_modules" ] && [ ! -w "$npm_prefix/lib/node_modules" ]; then
    npm config set prefix "$HOME/.local"
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
    echo "  ✅ npm 전역 prefix: $npm_prefix → $HOME/.local (sudo 없이 설치)"
fi
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH"
        echo "  ⚠️  ~/.local/bin이 PATH에 없습니다. ~/.bashrc에 추가하세요: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

if [ "$NEED_CLAUDE" = true ]; then
    step "claude CLI 확인..."
    command -v claude &>/dev/null || npm install -g @anthropic-ai/claude-code
    echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"

    step "rtk 확인..."
    command -v rtk &>/dev/null || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
    echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"

    step "bun 확인..."
    command -v bun &>/dev/null || curl -fsSL https://bun.sh/install | bash
    echo "  ✅ bun $(bun --version 2>/dev/null)"
fi

if [ "$NEED_CODEX" = true ]; then
    step "codex CLI 확인..."
    command -v codex &>/dev/null || npm install -g @openai/codex
    echo "  ✅ codex $(codex --version 2>/dev/null | head -1)"
fi

echo -e "\n${GREEN}✅ 의존성 설치 완료. 새 셸을 열거나 source ~/.bashrc 후 setup-team.sh를 실행하세요:${NC}"
echo "   $SCRIPT_DIR/setup-team.sh --agent $TEAM_AGENT $PROJECT_DIR"

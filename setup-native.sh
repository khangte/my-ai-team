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
#   ./setup-native.sh [--agent claude|codex]

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEAM_AGENT="${TEAM_AGENT:-claude}"
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
            echo "사용법: ./setup-native.sh [--agent claude|codex]"
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1" >&2
            exit 2
            ;;
    esac
done

case "$TEAM_AGENT" in
    claude|codex) ;;
    *) echo "지원하지 않는 에이전트: $TEAM_AGENT (claude 또는 codex)" >&2; exit 2 ;;
esac

echo -e "${YELLOW}[1/5] apt 의존성 확인...${NC}"
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

echo -e "\n${YELLOW}[2/5] Node.js 확인...${NC}"
command -v node &>/dev/null || {
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
    sudo apt-get install -y nodejs
}
echo "  ✅ node $(node --version 2>/dev/null)"

if [ "$TEAM_AGENT" = "claude" ]; then
    echo -e "\n${YELLOW}[3/5] claude CLI 확인...${NC}"
    command -v claude &>/dev/null || npm install -g @anthropic-ai/claude-code
    echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"

    echo -e "\n${YELLOW}[4/5] rtk 확인...${NC}"
    command -v rtk &>/dev/null || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
    echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"

    echo -e "\n${YELLOW}[5/5] bun 확인...${NC}"
    command -v bun &>/dev/null || curl -fsSL https://bun.sh/install | bash
    echo "  ✅ bun $(bun --version 2>/dev/null)"
else
    echo -e "\n${YELLOW}[3/3] codex CLI 확인...${NC}"
    command -v codex &>/dev/null || npm install -g @openai/codex
    echo "  ✅ codex $(codex --version 2>/dev/null | head -1)"
fi

echo -e "\n${GREEN}✅ 의존성 설치 완료. setup-team.sh를 실행해 팀 세션을 구성하세요:${NC}"
echo "   cd <프로젝트_경로> && $(cd "$(dirname "$0")" && pwd)/setup-team.sh --agent $TEAM_AGENT ."
echo "   또는: $(cd "$(dirname "$0")" && pwd)/setup-team.sh --agent $TEAM_AGENT <프로젝트_경로>"

#!/bin/bash
#
# setup-native.sh — WSL 호스트에 Claude 멀티에이전트 팀 환경 직접 구성
#
# Dockerfile + docker-team.sh가 컨테이너 안에서 하던 의존성 설치를
# WSL에 그대로 설치한다(격리 없이). volume 덮어쓰기 문제가 없으므로
# /opt 우회 경로 없이 기본 경로(~/.local, ~/.bun 등)에 설치한다.
# 설치 후 setup-team.sh를 그대로 실행해 tmux 팀 세션을 구성한다.
#
# 사용:
#   ./setup-native.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[1/5] apt 의존성 확인...${NC}"
MISSING_APT=()
command -v tmux &>/dev/null || MISSING_APT+=(tmux)
command -v git  &>/dev/null || MISSING_APT+=(git)
command -v curl &>/dev/null || MISSING_APT+=(curl)
command -v unzip &>/dev/null || MISSING_APT+=(unzip)
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

echo -e "\n${YELLOW}[3/5] claude CLI 확인...${NC}"
command -v claude &>/dev/null || npm install -g @anthropic-ai/claude-code
echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"

echo -e "\n${YELLOW}[4/5] rtk 확인...${NC}"
command -v rtk &>/dev/null || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"

echo -e "\n${YELLOW}[5/5] bun 확인...${NC}"
command -v bun &>/dev/null || curl -fsSL https://bun.sh/install | bash
echo "  ✅ bun $(bun --version 2>/dev/null)"

echo -e "\n${GREEN}✅ 의존성 설치 완료. setup-team.sh를 실행해 팀 세션을 구성하세요:${NC}"
echo "   ./setup-team.sh"

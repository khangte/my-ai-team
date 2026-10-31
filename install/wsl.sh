#!/bin/bash
# WSL에 팀 의존성을 사용자 기본 경로로 설치한다.
# 사용: ./install/wsl.sh [--agent claude|codex] [프로젝트_경로]
# 저장소·프로젝트의 team/config.sh를 읽고 실제 배정된 공급자를 설치한다.

set -e

SETUP_NAME="install/wsl.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # 저장소 루트
source "$SCRIPT_DIR/lib/setup-common.sh"

setup_parse_args "$@"
# apt 기반 Linux/WSL 전용이다. macOS는 install/mac.sh, Windows 네이티브는 install/windows.ps1을 쓴다.
if [ "$(uname -s)" != Linux ] || ! command -v apt-get &>/dev/null; then
    echo "apt 기반 Linux/WSL 전용 스크립트입니다. macOS는 install/mac.sh, PowerShell은 install/windows.ps1, Git Bash는 install/windows.sh를 쓰세요." >&2
    exit 1
fi
setup_prepare_linux_path
setup_load_team
setup_plan 2

step "apt 의존성 확인..."
MISSING_APT=()
command -v tmux &>/dev/null || MISSING_APT+=(tmux)
command -v git  &>/dev/null || MISSING_APT+=(git)
command -v curl &>/dev/null || MISSING_APT+=(curl)
# python3는 bin/log-hook(프롬프트·툴 로깅)이 쓴다.
command -v python3 &>/dev/null || MISSING_APT+=(python3)
# 한국어 locale이 없을 때만 locale 생성과 CJK 글꼴 설치를 함께 한다.
NEED_LOCALE=false
locale -a | grep -qi ko_KR.utf8 || { NEED_LOCALE=true; MISSING_APT+=(locales fonts-noto-cjk); }

if [ ${#MISSING_APT[@]} -gt 0 ]; then
    sudo apt-get update && sudo apt-get install -y "${MISSING_APT[@]}"
    if [ "$NEED_LOCALE" = true ]; then
        sudo locale-gen ko_KR.UTF-8
        sudo update-locale LANG=ko_KR.UTF-8
    fi
else
    echo "  ✅ tmux/git/curl/locale 이미 설치됨"
fi

step "Node.js 확인..."
command -v node &>/dev/null && command -v npm &>/dev/null || {
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
    sudo apt-get install -y nodejs
}
echo "  ✅ node $(node --version 2>/dev/null)"

# 전역 npm 경로에 쓰기 권한이 없으면 사용자 prefix로 전환한다.
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

setup_install_agent_clis

echo -e "\n${GREEN}✅ 의존성 설치 완료. 새 셸을 열거나 source ~/.bashrc 후 setup-team.sh를 실행하세요:${NC}"
echo "   $SCRIPT_DIR/setup-team.sh --agent $TEAM_AGENT $PROJECT_DIR"

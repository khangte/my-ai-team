#!/bin/bash
# macOS에 팀 의존성을 Homebrew로 설치한다.
# 사용: ./install/mac.sh [--agent claude|codex] [프로젝트_경로]
# setup-team.sh는 bash 4+(연관 배열·mapfile)가 필요하므로 macOS 기본 bash 3.2로는 실행할 수 없다.
# 또 timeout·realpath(GNU coreutils)가 필요하다. 이 스크립트는 둘을 설치·확인하고 실행 명령을 안내한다.
# setup-team.sh는 Homebrew bin과 coreutils gnubin을 PATH 앞에 두어 파인·훅(bin/say)도 Homebrew bash를 쓴다.

set -e

SETUP_NAME="install/mac.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # 저장소 루트
source "$SCRIPT_DIR/lib/setup-common.sh"

setup_parse_args "$@"
# SETUP_ALLOW_NON_DARWIN은 Linux CI의 스텁 검증 전용이다.
if [ "$(uname -s)" != Darwin ] && [ "${SETUP_ALLOW_NON_DARWIN:-}" != 1 ]; then
    echo "macOS 전용 스크립트입니다. WSL/Linux는 install/wsl.sh, Windows는 install/windows.ps1을 쓰세요." >&2
    exit 1
fi
setup_load_team
setup_plan 3

step "Homebrew 확인..."
if ! command -v brew &>/dev/null; then
    echo "Homebrew가 없습니다. https://brew.sh 안내대로 설치한 뒤 다시 실행하세요." >&2
    exit 1
fi
BREW_PREFIX="$(brew --prefix)"
echo "  ✅ brew $BREW_PREFIX"

step "brew 의존성 확인..."
MISSING_BREW=()
command -v tmux    &>/dev/null || MISSING_BREW+=(tmux)
command -v git     &>/dev/null || MISSING_BREW+=(git)
command -v curl    &>/dev/null || MISSING_BREW+=(curl)
command -v node    &>/dev/null || MISSING_BREW+=(node)
# python3는 bin/log-hook(프롬프트·툴 로깅)이 쓴다.
command -v python3 &>/dev/null || MISSING_BREW+=(python)
if [ ${#MISSING_BREW[@]} -gt 0 ]; then
    brew install "${MISSING_BREW[@]}"
else
    echo "  ✅ tmux/git/curl/node/python3 이미 설치됨"
fi

step "셸 요건 확인 (bash 4+, GNU coreutils)..."
BREW_BASH="$BREW_PREFIX/bin/bash"
bash_major() {
    # 주어진 bash 실행 파일의 주 버전을 출력한다. 실행할 수 없으면 0.
    "$1" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0
}
if [ "$(bash_major "$BREW_BASH")" -lt 4 ]; then
    brew install bash
fi
[ "$(bash_major "$BREW_BASH")" -ge 4 ] || { echo "bash 4+ 설치에 실패했습니다: $BREW_BASH" >&2; exit 1; }
# setup-team.sh가 쓰는 timeout·realpath는 GNU coreutils의 gnubin에서 온다(setup-team.sh가 PATH에 앞세움).
GNUBIN="$BREW_PREFIX/opt/coreutils/libexec/gnubin"
if [ ! -x "$GNUBIN/timeout" ] || [ ! -x "$GNUBIN/realpath" ]; then
    brew install coreutils
fi
[ -x "$GNUBIN/timeout" ] && [ -x "$GNUBIN/realpath" ] || { echo "GNU coreutils(timeout·realpath) 설치에 실패했습니다: $GNUBIN" >&2; exit 1; }
echo "  ✅ $BREW_BASH (bash $("$BREW_BASH" -c 'echo $BASH_VERSION')), coreutils $GNUBIN"

setup_install_agent_clis

echo -e "\n${GREEN}✅ 의존성 설치 완료. 새 셸을 열고 Homebrew bash로 setup-team.sh를 실행하세요 (/bin/bash 3.2는 불가):${NC}"
echo "   $BREW_BASH $SCRIPT_DIR/setup-team.sh --agent $TEAM_AGENT $PROJECT_DIR"

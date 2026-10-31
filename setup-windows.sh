#!/usr/bin/env bash
# Git Bash에서 기존 PowerShell 진입점을 거쳐 WSL2에 의존성을 설치한다.
# 사용: bash ./setup-windows.sh [--agent claude|codex] [프로젝트_경로]
set -e

SETUP_NAME="setup-windows.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/setup-common.sh"
setup_parse_args "$@"

case "$(uname -s)" in
    MINGW*) ;;
    *) echo "Git Bash 전용입니다. WSL/Linux는 setup-wsl.sh, macOS는 setup-mac.sh를 쓰세요." >&2; exit 1 ;;
esac

for tool in cygpath powershell.exe; do
    command -v "$tool" &>/dev/null || {
        echo "필수 명령이 없습니다: $tool. Git Bash와 Windows PowerShell을 확인하세요." >&2
        exit 1
    }
done

project="${PROJECT_ARG:-$(pwd)}"
[ -d "$project" ] || { echo "프로젝트 디렉터리가 없습니다: $project" >&2; exit 2; }
ps1="$(cygpath -aw "$SCRIPT_DIR/setup-windows.ps1")"
project="$(cygpath -aw "$project")"

# MSYS의 자동 인자 변환을 끄고, 공백·한글 경로를 각각 하나의 인자로 전달한다.
export MSYS_NO_PATHCONV=1
# 기본 실행 정책에서도 이 호출에 한해 저장소의 PowerShell 스크립트를 실행한다.
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" -Agent "$TEAM_AGENT" -Project "$project"

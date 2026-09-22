#!/bin/bash
#
# setup-docker.sh — Docker 기반 Claude/Codex 멀티에이전트 팀 환경 구성 (호스트에서 실행)
#
# 동작:
#   1. Dockerfile로 이미지(claude-team)를 빌드
#   2. 기존 컨테이너(claude-env)가 있으면 제거 후 재생성
#   3. 입력받은 프로젝트 루트를 컨테이너 내부 /workspace로 마운트
#      setup-team.sh는 /workspace를 실제 작업 프로젝트 루트로 사용
#      named volume claude-home을 /home/user로 마운트하여 컨테이너 기동
#      (claude-home은 로그인 세션·rtk·gstack 스킬 등을 컨테이너 재생성 후에도 보존하기 위한 영속 볼륨)
#   4. 컨테이너 내부에서 setup-team.sh를 실행해 tmux 기반 팀 세션을 구성
#
# 사용:
#   ./setup-docker.sh [--agent claude|codex] /path/to/project
#
# 사전 요구사항: Docker

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

IMAGE="claude-team"
CONTAINER="claude-env"
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
            echo "사용법: ./setup-docker.sh [--agent claude|codex] <project-path>"
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

PROJECT_DIR="${PROJECT_ARG:?사용법: ./setup-docker.sh [--agent claude|codex] <project-path>}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 이미지 빌드 ─────────────────────────────────────────────
echo -e "${YELLOW}이미지 빌드 중...${NC}"
# 빌드 컨텍스트는 호출한 현재 디렉터리가 아니라 이 스크립트가 있는 ai-setup
# 저장소다. 대상 프로젝트 디렉터리에서 절대·상대 경로로 호출해도 Dockerfile과
# setup-team.sh 등 이미지에 복사할 파일을 항상 같은 곳에서 찾는다.
docker build -t "$IMAGE" "$SCRIPT_DIR"

echo -e "${GREEN}✅ 이미지 준비 완료 ($IMAGE)${NC}"

# ── 기존 컨테이너 정리 ───────────────────────────────────────
if docker container inspect "$CONTAINER" &>/dev/null; then
    echo "기존 컨테이너 '$CONTAINER' 종료 및 삭제..."
    docker rm -f "$CONTAINER"
fi

# ── 컨테이너 기동 ────────────────────────────────────────────
echo -e "\n${YELLOW}컨테이너 기동 중...${NC}"
mkdir -p "$PROJECT_DIR"

docker volume inspect claude-home >/dev/null 2>&1 || \
docker volume create claude-home >/dev/null

# sleep infinity로 컨테이너를 계속 살려두고, 실제 작업은 아래 docker exec로 진행한다
# (컨테이너 자체의 CMD를 대화형 셸로 만들지 않는 이유).
docker run -d --name "$CONTAINER" \
    -v "$PROJECT_DIR":/workspace \
    -v claude-home:/home/user \
    "$IMAGE" \
    sleep infinity
#   -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \

echo -e "${GREEN}✅ 컨테이너 기동 완료 ($CONTAINER)${NC}"

# ── 컨테이너 내에서 팀 셋업 스크립트 실행 ────────────────────
echo -e "\n${YELLOW}팀 환경 구성 중 (컨테이너 내부)...${NC}"

# -it: setup-team.sh 내부의 claude 최초 로그인(/login) 프롬프트에 응답하려면
# 대화형 TTY가 필요하다.
# docker exec -it "$CONTAINER" bash /workspace/setup-team.sh
docker exec -it "$CONTAINER" \
bash /opt/ai-setup/setup-team.sh --agent "$TEAM_AGENT" /workspace

#!/bin/bash
# Docker 이미지를 빌드하고 프로젝트를 /workspace에 마운트해 팀을 구성한다.
# 사용자 홈은 claude-home 볼륨으로 보존한다.
# 사용: ./setup-docker.sh [--agent claude|codex] /path/to/project

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
# 호출 위치와 무관하게 이 저장소를 빌드 컨텍스트로 사용한다.
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

# 컨테이너는 유지하고 팀 구성은 아래 docker exec에서 실행한다.
docker run -d --name "$CONTAINER" \
    -v "$PROJECT_DIR":/workspace \
    -v claude-home:/home/user \
    "$IMAGE" \
    sleep infinity

echo -e "${GREEN}✅ 컨테이너 기동 완료 ($CONTAINER)${NC}"

# ── 컨테이너 내에서 팀 셋업 스크립트 실행 ────────────────────
echo -e "\n${YELLOW}팀 환경 구성 중 (컨테이너 내부)...${NC}"

# 최초 로그인에 응답할 대화형 TTY가 필요하다.
docker exec -it "$CONTAINER" \
bash /opt/ai-setup/setup-team.sh --agent "$TEAM_AGENT" /workspace

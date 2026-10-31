#!/bin/bash
# Docker 이미지를 빌드하고 프로젝트를 /workspace에 마운트해 팀을 구성한다.
# 사용자 홈은 claude-home 볼륨으로 보존한다.
# 사용: ./install/docker.sh [--agent claude|codex] /path/to/project

set -e

SETUP_NAME="install/docker.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # 저장소 루트
source "$SCRIPT_DIR/lib/setup-common.sh"
setup_parse_args "$@"

IMAGE="claude-team"
CONTAINER="claude-env"
PROJECT_DIR="${PROJECT_ARG:?사용법: ./install/docker.sh [--agent claude|codex] <project-path>}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

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

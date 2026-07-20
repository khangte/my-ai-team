#!/bin/bash
#
# docker-team.sh — Docker 기반 Claude 멀티에이전트 팀 환경 구성 (호스트에서 실행)
#
# 동작:
#   1. Dockerfile로 이미지(claude-team)를 빌드
#   2. 기존 컨테이너(claude-env)가 있으면 제거 후 재생성
#   3. PROJECT_DIR를 /workspace로, named volume claude-home을 /home/user로 마운트하여 컨테이너 기동
#      (claude-home은 로그인 세션·rtk·gstack 스킬 등을 컨테이너 재생성 후에도 보존하기 위한 영속 볼륨)
#   4. 컨테이너 내부에서 setup-team.sh를 실행해 tmux 기반 팀 세션을 구성
#
# 사용:
#   PROJECT_DIR=/path/to/project ./docker-team.sh   (PROJECT_DIR 생략 시 $HOME/project)
#
# 사전 요구사항: Docker

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

IMAGE="claude-team"
CONTAINER="claude-env"
PROJECT_DIR="${PROJECT_DIR:-$HOME/project}"

# # ── API 키 확인 ──────────────────────────────────────────────
# if [ -z "$ANTHROPIC_API_KEY" ]; then
#     echo -e "${RED}❌ ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다.${NC}"
#     echo "   export ANTHROPIC_API_KEY='sk-ant-...'"
#     exit 1
# fi
# echo -e "${GREEN}✅ API 키 확인 완료${NC}"

# ── 이미지 빌드 ─────────────────────────────────────────────
echo -e "${YELLOW}이미지 빌드 중...${NC}"
docker build -t "$IMAGE" .

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
docker exec -it "$CONTAINER" bash /workspace/setup-team.sh

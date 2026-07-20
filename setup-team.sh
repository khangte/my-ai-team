#!/bin/bash
# setup-team.sh — 컨테이너 내부 Claude 멀티에이전트 팀 환경 자동 구성

set -e

# ── PATH 보강 ─────────────────────────────────────────────
# ./setup-team.sh 처럼 스크립트로 직접 실행하면 non-interactive 셸이라
# ~/.bashrc가 자동으로 로드되지 않는다. rtk/claude가 어디 설치되어 있든
# (~/.local/bin, /opt/rtk-bin, /opt/npm-global/bin 등) 찾을 수 있도록
# 여기서 명시적으로 PATH에 추가한다.
export PATH="$HOME/.local/bin:/opt/rtk-bin:/opt/npm-global/bin:$PATH"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SESSION="team1"

# ── 팀 멤버 정보 (여기서만 수정하면 파인 개수가 자동으로 맞춰짐) ──
declare -a MEMBER_NAMES=("쭌" "민준 아키텍트" "지훈 리서쳐" "수아 UI/UX디자이너" "서연 개발자" "태양 QA·리뷰어")
declare -a MEMBER_MODELS=(
    "claude-opus-4-8"   # 쭌 (팀장 — 판단·조율 중심)
    "claude-opus-4-8"   # 민준 (PM — 설계·추론 중심)
    "claude-sonnet-5"   # 지훈
    "claude-sonnet-5"   # 수아
    "claude-sonnet-5"   # 서연
    "claude-sonnet-5"   # 태양
)
PANE_COUNT=${#MEMBER_NAMES[@]}

if [ "${#MEMBER_MODELS[@]}" -ne "$PANE_COUNT" ]; then
    echo -e "${RED}❌ MEMBER_NAMES(${PANE_COUNT}개)와 MEMBER_MODELS(${#MEMBER_MODELS[@]}개) 길이가 다릅니다.${NC}"
    exit 1
fi

# ── 유틸: 파인에 패턴이 나타날 때까지 대기 ──────────────────
wait_for_pane() {
    local pane="$1" pattern="$2" timeout="${3:-30}" waited=0
    while [ $waited -lt $timeout ]; do
        tmux capture-pane -t "$pane" -p 2>/dev/null | grep -q "$pattern" && return 0
        sleep 1; waited=$((waited + 1))
    done
    return 1
}

# ── 유틸: Claude 실행 + 다이얼로그 자동 처리 ────────────────
start_claude_in_pane() {
    local pane="$1" model="${2:-claude-sonnet-4-6}"
    local claude_bin; claude_bin="$(command -v claude)"

    tmux send-keys -t "$pane" C-c 2>/dev/null; sleep 0.3
    tmux send-keys -t "$pane" C-u 2>/dev/null; sleep 0.2

    tmux send-keys -t "$pane" \
        "cd /workspace && unset CLAUDECODE && $claude_bin --model $model --dangerously-skip-permissions" Enter

    if [ "$NEED_FIRST_LOGIN" = true ]; then

        # trust folder
        wait_for_pane "$pane" "trust this folder" 20 && {
            tmux send-keys -t "$pane" Enter
            sleep 1
        }

        # terms
        wait_for_pane "$pane" "I accept" 20 && {
            tmux send-keys -t "$pane" Down
            sleep 0.5
            tmux send-keys -t "$pane" Enter
            sleep 1
        }

    fi

    # Claude가 실행될 시간을 준다.
    sleep 3

    return 0
}

# ── claude 로그인 확인 ────────────────
check_login() {
    # 실제 로그인 확인 방식은 Claude Code 버전에 맞게 변경
    claude auth status >/dev/null 2>&1
}

# ── [0/5] 사전 요구사항 확인 ────────────────────────────────
echo -e "${YELLOW}[0/5] 사전 요구사항 확인...${NC}"

MISSING=()
command -v tmux   &>/dev/null || MISSING+=("tmux (apt-get install -y tmux)")
command -v claude &>/dev/null || MISSING+=("claude (npm install -g @anthropic-ai/claude-code)")
command -v rtk    &>/dev/null || MISSING+=("rtk (curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh)")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}❌ 누락된 의존성:${NC}"
    for m in "${MISSING[@]}"; do echo "   - $m"; done
    exit 1
fi

echo "  ✅ tmux $(tmux -V | awk '{print $2}')"
echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"
echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"

# if [ -z "$ANTHROPIC_API_KEY" ]; then
#     echo -e "${RED}❌ ANTHROPIC_API_KEY 환경변수가 없습니다.${NC}"
#     echo "   docker run 시 -e ANTHROPIC_API_KEY=... 옵션을 확인하세요."
#     exit 1
# fi
# echo "  ✅ API 키 주입 확인"

# ── Claude 로그인 여부 확인 ───────────────────────────────
echo -n "  Claude 로그인 확인... "

if check_login; then
    echo -e "${GREEN}✅ 로그인 완료${NC}"
    NEED_FIRST_LOGIN=false
else
    NEED_FIRST_LOGIN=true

    echo -e "${YELLOW}로그인이 필요합니다.${NC}"
    echo
    echo "Claude를 실행합니다."
    echo "컨테이너 안에서 /login 을 완료하세요."
    echo

    claude

    echo
    read -p "로그인이 완료되었다면 Enter를 누르세요..."

    if ! check_login; then
        echo -e "${RED}❌ 로그인이 확인되지 않았습니다.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ 로그인 확인 완료${NC}"
fi

# ── [1/5] rtk 훅 초기화 ────────────────────────────────────
# ~/.claude 는 로그인 후 생성되고 volume(claude-home) 안에 있으므로
# 이미지 빌드 시점이 아니라 여기(런타임)에서 1회 등록한다.
# --auto-patch: settings.json patch 여부를 묻지 않고 자동 진행
# RTK_TELEMETRY_DISABLED=1 + timeout: v0.36.0+ 에서 non-interactive 환경일 때
# telemetry 동의 프롬프트가 무한 대기하는 알려진 버그(rtk-ai/rtk#1307)에 대한 안전장치
# printf 'n\n': 위 telemetry 동의 프롬프트에 대한 응답(비동의)이며,
# RTK_TELEMETRY_DISABLED가 무시될 경우를 대비한 이중 안전장치
echo -e "\n${YELLOW}[1/5] rtk 훅 초기화...${NC}"

if printf 'n\n' | RTK_TELEMETRY_DISABLED=1 timeout 15 rtk init -g --auto-patch; then
    echo -e "${GREEN}✅ rtk 훅 등록 완료${NC}"
else
    echo -e "${YELLOW}⚠️  rtk init 실패 또는 timeout (이미 설정되어 있거나 수동 확인 필요)${NC}"
    echo -e "${YELLOW}   확인: rtk init --show${NC}"
fi

# ── [2/5] 기존 세션 정리 ────────────────────────────────────
echo -e "\n${YELLOW}[2/5] 기존 세션 초기화...${NC}"

tmux has-session -t "$SESSION" 2>/dev/null && {
    tmux kill-session -t "$SESSION"
    echo "  기존 '$SESSION' 세션 종료"
}

# ── [3/5] TMUX 세션 & 레이아웃 구성 ────────────────────────
echo -e "\n${YELLOW}[3/5] TMUX 세션 & 레이아웃 구성...${NC}"

tmux new-session -d -s "$SESSION" -x 220 -y 50

# 파인을 PANE_COUNT개가 될 때까지 분할 (0번 파인은 new-session이 이미 생성)
for ((i = 0; i < PANE_COUNT - 1; i++)); do
    tmux split-window -t "$SESSION:0.$i" -h
done

# main-vertical 레이아웃 (팀장 왼쪽 넓게)
tmux select-layout -t "$SESSION:0" even-horizontal
tmux select-layout -t "$SESSION:0" main-vertical
tmux set-option -t "$SESSION" main-pane-width 110

#  파인 이름 설정 (레이아웃 설정 후, Claude 실행 전)
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    tmux select-pane -t "$SESSION:0.$pane" -T "${MEMBER_NAMES[$pane]}"
done

# 파인 제목 표시 설정
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
tmux set-option -t "$SESSION" allow-rename off

echo "  ✅ 레이아웃 구성 완료 (6 panes)"

# ── [4/5] Claude 자동 실행 ──────────────────────────────────
echo -e "\n${YELLOW}[4/5] Claude 실행 중... (파인당 최대 1분)${NC}"

for ((pane = 0; pane < PANE_COUNT; pane++)); do
    echo -n "  Pane $pane (${MEMBER_NAMES[$pane]}): "
    start_claude_in_pane "$SESSION:0.$pane" "${MEMBER_MODELS[$pane]}"

    echo -e "${GREEN}✅ 실행 완료${NC}"
done

# ── [4.5/5] 파인 타이틀 워처 ──────────────────────────────────
# Claude Code가 스피너 표시용 OSC 이스케이프 시퀀스로 파인 타이틀을
# 계속 덮어쓰기 때문에 (2026-07 기준 공식 비활성화 옵션 없음,
# 관련 이슈: anthropics/claude-code#31107, #21677),
# 세션 종료 시까지 주기적으로 원하는 이름으로 재설정한다.
(
    while tmux has-session -t "$SESSION" 2>/dev/null; do
        for ((pane = 0; pane < PANE_COUNT; pane++)); do
            tmux select-pane -t "$SESSION:0.$pane" -T "${MEMBER_NAMES[$pane]}" 2>/dev/null
        done
        sleep 1
    done
) &
disown
echo "  ✅ 파인 타이틀 워처 시작 (PID: $!)"

# ── [5/5] 완료 ──────────────────────────────────────────────
echo -e "\n${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   ✅ 팀 환경 구성 완료!              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"
echo "tmux attach -t $SESSION 으로 접속하세요."

# 터미널에서 직접 실행한 경우 자동 attach
# [ -t 1 ] && tmux attach -t "$SESSION"

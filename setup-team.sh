#!/bin/bash
#
# setup-team.sh — 컨테이너 내부 Claude 멀티에이전트 팀 환경 자동 구성
#
# setup-docker.sh가 컨테이너 기동 후 `docker exec`로 호출한다(직접 실행도 가능).
# 단계:
#   [0] tmux/claude/rtk/bun 등 사전 요구사항 및 claude 로그인 여부 확인
#       (미로그인 시 claude를 실행해 /login을 안내하고 완료를 대기)
#   [1] rtk 훅을 전역(-g) 초기화
#   [1.5] gstack 스킬(~/.claude/skills/gstack)을 clone/pull 및 setup
#         (CLAUDE.md의 "Skill routing"이 참조하는 /office-hours 등 슬래시 커맨드 제공)
#   [2] 기존 tmux 세션("team1") 정리
#   [3] MEMBER_NAMES/MEMBER_MODELS 배열 기준으로 파인을 분할하고 이름 부여
#   [4] 각 파인에서 지정된 모델로 claude를 실행(최초 로그인 시 trust/terms 다이얼로그 자동 처리)
#   [4.5] tmux가 파인 타이틀을 스피너로 덮어쓰는 문제를 막기 위해 백그라운드에서 주기적으로 타이틀 재설정
#
# 사용:
#   ./setup-team.sh [프로젝트_경로]
#   프로젝트_경로 생략 시 $PROJECT_DIR(기본 ~/project) 사용.
#   (팀원 구성을 바꾸려면 MEMBER_NAMES/MEMBER_MODELS 배열만 수정하거나
#    프로젝트 루트에 team/config.sh를 두면 됨)

set -e

# ── PATH 보강 ─────────────────────────────────────────────
# ./setup-team.sh 처럼 스크립트로 직접 실행하면 non-interactive 셸이라
# ~/.bashrc가 자동으로 로드되지 않는다. rtk/claude/bun이 어디 설치되어 있든
# (~/.local/bin, /opt/rtk-bin, /opt/npm-global/bin, /opt/bun/bin 등) 찾을 수 있도록
# 여기서 명시적으로 PATH에 추가한다.
export PATH="$HOME/.local/bin:/opt/rtk-bin:/opt/npm-global/bin:/opt/bun/bin:$HOME/.bun/bin:$PATH"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SESSION="team1"
PROJECT_DIR="${1:-${PROJECT_DIR:-$(pwd)}}"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

# team/{role}.md 지침 파일 위치. 이 스크립트(ai-setup 리포) 기준이므로 PROJECT_DIR과 무관하다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_DIR="$SCRIPT_DIR/team"

# ── 팀 멤버 정보 (기본값. $PROJECT_DIR/team/config.sh가 있으면 그쪽 값으로 대체됨) ──
declare -a MEMBER_NAMES=("lead" "architect" "researcher" "designer" "developer" "reviewer")
declare -a MEMBER_MODELS=(
    # lead는 직접 작업하지 않고 배분·수합만 하지만 모든 보고가 모여 컨텍스트가
    # 가장 빨리 불어나는 파인이다. 비싼 모델 × 최장 컨텍스트 조합을 피해 Sonnet을 쓴다.
    # 깊은 판단이 필요한 쪽은 architect이므로 그쪽만 Opus로 둔다.
    "claude-sonnet-5"   # lead (팀장 — 배분·수합 중심)
    "claude-opus-4-8"   # architect (PM — 설계·추론 중심)
    "claude-haiku-4-5"   # researcher
    "claude-sonnet-5"   # designer
    "claude-sonnet-5"   # developer
    "claude-sonnet-5"   # reviewer
)

# 프로젝트별로 팀 구성을 다르게 하고 싶으면 $PROJECT_DIR/team/config.sh에
# 위와 동일한 형식으로 SESSION/MEMBER_NAMES/MEMBER_MODELS를 재선언하면 된다.
if [ -f "$PROJECT_DIR/team/config.sh" ]; then
    echo -e "${YELLOW}team/config.sh 발견 → 프로젝트별 팀 구성 사용: $PROJECT_DIR/team/config.sh${NC}"
    source "$PROJECT_DIR/team/config.sh"
else
    echo -e "${CYAN}team/config.sh 없음 → 기본 팀 구성 사용${NC}"
fi

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
    local pane="$1" model="${2:-claude-sonnet-4-6}" role="${3:-}"
    local claude_bin; claude_bin="$(command -v claude)"

    # C-c로 파인에 떠 있을 수 있는 이전 프로세스를 중단하고, C-u로 입력 줄을 비워
    # 아래 send-keys가 이전 입력 잔여물과 섞이지 않게 한다.
    tmux send-keys -t "$pane" C-c 2>/dev/null; sleep 0.3
    tmux send-keys -t "$pane" C-u 2>/dev/null; sleep 0.2

    # 역할별 지침(team/{role}.md)이 있으면 --append-system-prompt로 주입한다.
    # base64 왕복: send-keys에 지침 원문을 그대로 넘기면 따옴표·개행이 셸 파싱과 충돌하므로,
    # 인코딩된 문자열만 커맨드에 실어 보내고 파인 내부 셸에서 디코딩한다.
    # team/config.sh와 동일한 오버라이드 규칙: 프로젝트 루트에 team/{role}.md가
    # 있으면 그쪽을 우선 사용하고, 없으면 이 저장소의 기본값으로 폴백한다.
    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"
    local system_prompt_arg=""
    if [ -n "$role" ] && [ -f "$role_file" ]; then
        local role_content; role_content="$(cat "$role_file")"
        # lead에는 MEMBER_NAMES 배열 기준 배분 표를 실행 시점에 동적 생성해 이어붙인다.
        # config.sh만 바꾸면 lead.md를 손대지 않아도 배분 표가 항상 일치하게 하기 위함.
        if [ "$role" = "lead" ]; then
            local team_table="## 팀원 배분 (자동 생성)"$'\n\n'"| 역할 | 파인 | 지시 방법 |"$'\n'"| --- | --- | --- |"
            for ((m = 1; m < ${#MEMBER_NAMES[@]}; m++)); do
                team_table+=$'\n'"| ${MEMBER_NAMES[$m]} | :0.$m | say :0.$m \"...\" |"
            done
            role_content="${role_content}"$'\n\n'"${team_table}"
        fi
        local role_b64; role_b64="$(printf '%s' "$role_content" | base64 -w0)"
        system_prompt_arg="--append-system-prompt \"\$(echo '$role_b64' | base64 -d)\""
    elif [ -n "$role" ]; then
        # MEMBER_NAMES에 오타가 있으면 role_file이 조용히 없는 채로 넘어가
        # 해당 파인이 역할 지침 없이 뜬다. 눈에 띄게 경고해 즉시 알아채도록 한다.
        echo -e "${RED}⚠️  team/${role}.md 없음 → 이 파인은 역할 지침 없이 실행됩니다 (MEMBER_NAMES 오타 확인)${NC}" >&2
    fi

    # Stop 훅으로 "작업 종료" 신호를 lead에 자동 전송한다(lead 자신은 제외).
    # 파인이 send-keys 실행을 잊어도 훅은 harness가 실행하므로 신호가 반드시 나간다.
    # lead는 이 신호를 받은 파인만 capture-pane으로 확인하면 되므로 주기적 폴링이 필요 없다.
    # 신호는 "종료됐다"는 사실만 전달하고, 작업 내용은 파인이 보내는 본 보고가 담당한다.
    # 파인 번호는 호출 시점의 $pane에서 그대로 가져온다. 훅 커맨드 안에서
    # `tmux display-message -p '#{pane_index}'`를 쓰면 안 된다 — 훅 프로세스에는
    # TMUX_PANE이 전달되지 않아 자기 파인이 아니라 그 시점의 활성 파인 번호가
    # 잡히고, 결국 모든 파인이 lead 자신인 :0.0을 보고하게 된다.
    local settings_arg=""
    if [ -n "$role" ] && [ "$role" != "lead" ]; then
        local pane_id="${pane##*:}"   # "team1:0.4" → "0.4"
        # 중복 신호 가드: 이 파인이 방금 say로 본 보고를 보냈다면 종료 신호를 생략한다.
        # 본 보고에 이미 작업 내용이 담겨 있어 신호는 lead 턴만 한 번 더 태우기 때문이다.
        # say가 남긴 마커를 소비(삭제)하므로, 보고 없이 끝난 응답에서는 신호가 정상 발송된다.
        local marker="/tmp/team-say/${pane_id}"
        # JSON 문자열로 들어가므로 큰따옴표는 \" 로 이스케이프한다(작은따옴표는 JSON에서 무해).
        # 훅 커맨드는 이 스크립트가 만드는 고정 문자열이라 이스케이프 대상이 이것뿐이다.
        local hook_cmd="if [ -f '${marker}' ]; then rm -f '${marker}'; else ${TEAM_DIR}/say ${SESSION}:0.0 \\\"[${role}] (자동) 파인 :${pane_id} 응답 종료 — 미보고 시 확인 필요\\\"; fi"
        # --settings는 글로벌 settings.json을 병합이 아니라 대체하므로, 여기서 Stop 훅만
        # 넣으면 글로벌 PreToolUse(rtk hook claude)가 이 파인에서 통째로 사라진다.
        # rtk 재작성이 계속 걸리도록 PreToolUse도 함께 명시해야 한다.
        # cat 차단 훅도 lead와 동일하게 팀 파인에 적용해 cat 대신 serena를 쓰도록 유도한다.
        local settings_json="{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${hook_cmd}\"}]}],\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"~/.claude/hooks/block-cat-use-serena.sh\"},{\"type\":\"command\",\"command\":\"rtk hook claude\"}]}]}}"
        local settings_b64; settings_b64="$(printf '%s' "$settings_json" | base64 -w0)"
        settings_arg="--settings \"\$(echo '$settings_b64' | base64 -d)\""
    fi

    # unset CLAUDECODE: 이 스크립트 자신이 Claude Code 세션 안에서 실행 중일 경우
    # 남아있는 CLAUDECODE 환경변수가 파인 내부의 claude 실행에 영향을 주지 않도록 제거한다.
    # PATH에 TEAM_DIR: 파인들이 `say`를 경로 없이 호출할 수 있게 한다.
    tmux send-keys -t "$pane" \
        "cd '$PROJECT_DIR' && unset CLAUDECODE && export PATH='$TEAM_DIR':\$PATH && $claude_bin --model $model --dangerously-skip-permissions $system_prompt_arg $settings_arg" Enter

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
command -v bun    &>/dev/null || MISSING+=("bun (curl -fsSL https://bun.sh/install | bash)")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}❌ 누락된 의존성:${NC}"
    for m in "${MISSING[@]}"; do echo "   - $m"; done
    exit 1
fi

echo "  ✅ tmux $(tmux -V | awk '{print $2}')"
echo "  ✅ claude $(claude --version 2>/dev/null | head -1)"
echo "  ✅ rtk $(rtk --version 2>/dev/null | head -1)"
echo "  ✅ bun $(bun --version 2>/dev/null | head -1)"

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

# ── [1.5/5] gstack 스킬 설치 ─────────────────────────────────
# CLAUDE.md의 "Skill routing"이 참조하는 /office-hours, /plan-ceo-review 등은
# gstack(https://github.com/garrytan/gstack) 패키지가 제공한다.
# ~/.claude 는 volume(claude-home) 안에 있어 컨테이너를 새로 만들면 사라지므로
# 이미지 빌드 시점이 아니라 여기(런타임)에서 매번 최신 상태로 맞춘다.
echo -e "\n${YELLOW}[1.5/5] gstack 스킬 설치...${NC}"

GSTACK_DIR="$HOME/.claude/skills/gstack"
if [ -d "$GSTACK_DIR/.git" ]; then
    git -C "$GSTACK_DIR" pull --ff-only -q
else
    git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git "$GSTACK_DIR" -q
fi

if (cd "$GSTACK_DIR" && timeout 60 ./setup >/dev/null); then
    echo -e "${GREEN}✅ gstack 스킬 설치 완료${NC}"
else
    echo -e "${YELLOW}⚠️  gstack setup 실패 또는 timeout (수동 확인 필요: cd $GSTACK_DIR && ./setup)${NC}"
fi

# ── [2/5] 기존 세션 정리 ────────────────────────────────────
echo -e "\n${YELLOW}[2/5] 기존 세션 초기화...${NC}"

tmux has-session -t "$SESSION" 2>/dev/null && {
    tmux kill-session -t "$SESSION"
    echo "  기존 '$SESSION' 세션 종료"
}

# ── [3/5] TMUX 세션 & 레이아웃 구성 ────────────────────────
echo -e "\n${YELLOW}[3/5] TMUX 세션 & 레이아웃 구성...${NC}"

# -x 220 -y 50: main-vertical 레이아웃에서 파인 6개가 각각 읽을 만한 너비를
# 확보하기 위한 최소 터미널 크기. tmux는 접속 클라이언트 크기로 윈도우를 다시
# 맞추므로, 이 값을 키워도 실제 터미널 창보다 커질 수는 없다.
tmux new-session -d -s "$SESSION" -x 220 -y 50

# 파인을 PANE_COUNT개가 될 때까지 분할 (0번 파인은 new-session이 이미 생성)
for ((i = 0; i < PANE_COUNT - 1; i++)); do
    tmux split-window -t "$SESSION:0.$i" -h
done

# main-vertical 레이아웃 (팀장 왼쪽 넓게)
# even-horizontal을 먼저 적용해 파인 크기를 고르게 맞춘 뒤 main-vertical로 전환해야
# tmux가 비정상적으로 좁은 파인을 만들지 않는다.
tmux select-layout -t "$SESSION:0" even-horizontal
tmux select-layout -t "$SESSION:0" main-vertical
# 절대값(컬럼 수) 대신 %로 지정 — 실제 터미널 창 폭이 좁을 때도
# lead 파인이 나머지 파인 대비 상대적으로 넓게 유지된다.
tmux set-option -t "$SESSION" main-pane-width '55%'

#  파인 이름 설정 (레이아웃 설정 후, Claude 실행 전)
# 파인 타이틀은 시각적 강조를 위해 대문자로 표시 (데이터 자체는 소문자 유지)
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    tmux select-pane -t "$SESSION:0.$pane" -T "${MEMBER_NAMES[$pane]^^}"
done

# 파인 제목 표시 설정
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
tmux set-option -t "$SESSION" allow-rename off

echo "  ✅ 레이아웃 구성 완료 (${PANE_COUNT} panes)"

# ── [4/5] Claude 자동 실행 ──────────────────────────────────
echo -e "\n${YELLOW}[4/5] Claude 실행 중... (파인당 최대 1분)${NC}"

for ((pane = 0; pane < PANE_COUNT; pane++)); do
    echo -n "  Pane $pane (${MEMBER_NAMES[$pane]}): "
    start_claude_in_pane "$SESSION:0.$pane" "${MEMBER_MODELS[$pane]}" "${MEMBER_NAMES[$pane]}"

    echo -e "${GREEN}✅ 실행 완료${NC}"
done

# ── [4.5/5] 파인 타이틀 워처 ──────────────────────────────────
# Claude Code가 스피너 표시용 OSC 이스케이프 시퀀스로 파인 타이틀을
# 계속 덮어쓰기 때문에 (2026-07 기준 공식 비활성화 옵션 없음,
# 관련 이슈: anthropics/claude-code#31107, #21677),
# 세션 종료 시까지 주기적으로 원하는 이름으로 재설정한다.
# select-pane -T는 호출될 때마다 파인 테두리를 다시 그려 tmux가 화면을
# 재렌더링하므로, 매초 무조건 호출하면 그 순간 한글 IME 조합 중이던 입력이
# 씹히는 경우가 있다. 그래서 현재 타이틀이 원하는 값과 실제로 다를 때만 호출한다.
(
    while tmux has-session -t "$SESSION" 2>/dev/null; do
        for ((pane = 0; pane < PANE_COUNT; pane++)); do
            want="${MEMBER_NAMES[$pane]^^}"
            current="$(tmux display-message -p -t "$SESSION:0.$pane" '#{pane_title}' 2>/dev/null)"
            [ "$current" = "$want" ] || tmux select-pane -t "$SESSION:0.$pane" -T "$want" 2>/dev/null
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

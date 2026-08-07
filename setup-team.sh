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

    # 역할별 지침(team/{role}.md)이 있으면 --append-system-prompt-file로 주입한다.
    # 지침을 조립해 파일로 쓰고 그 경로만 커맨드에 싣는다. 예전에는 base64로
    # 인코딩해 커맨드에 통째로 실었는데, 역할 지침에 전역 규칙까지 붙으면서
    # reviewer의 인코딩 결과가 18KB를 넘어 tmux send-keys가 "command too long"으로
    # 거부했다. 파일 경로는 길이가 일정하므로 지침이 아무리 커져도 문제가 없고,
    # 따옴표·개행이 셸 파싱과 충돌하는 문제도 함께 사라진다.
    # team/config.sh와 동일한 오버라이드 규칙: 프로젝트 루트에 team/{role}.md가
    # 있으면 그쪽을 우선 사용하고, 없으면 이 저장소의 기본값으로 폴백한다.
    # 역할별 스킬 제한([1.6/5])이 만든 디렉터리가 있으면 그곳을 cwd로 삼고
    # 유저 전역·플러그인 스킬을 차단한다(빌트인 스킬은 남는다 — [1.6/5] 주석 참조).
    # 프로젝트 스킬 탐색은 상위로 거슬러 올라가므로
    # $PROJECT_DIR/.claude/skills 의 공용 스킬은 그대로 상속된다.
    # SKILL_SETS에 없는 역할은 $PROJECT_DIR에서 전체 스킬로 그대로 뜬다
    # (현재 SKILL_SETS는 6개 역할을 모두 포함하므로 해당 없음).
    local work_dir="$PROJECT_DIR" skills_arg=""
    if [ -n "$role" ] && [ -d "$TEAM_SKILLS_ROOT/$role/.claude/skills" ]; then
        work_dir="$TEAM_SKILLS_ROOT/$role"
        skills_arg="--setting-sources project"
    fi

    local role_file="$PROJECT_DIR/team/${role}.md"
    [ -f "$role_file" ] || role_file="$TEAM_DIR/${role}.md"
    local system_prompt_arg=""
    if [ -n "$role" ] && [ -f "$role_file" ]; then
        local role_content; role_content="$(cat "$role_file")"
        # cwd가 .team/{역할}/ 인 파인에는 실제 작업 대상이 프로젝트 루트임을 알린다.
        # 이 안내가 없으면 파인이 자기 스킬 디렉터리를 프로젝트로 오인한다.
        if [ "$work_dir" != "$PROJECT_DIR" ]; then
            role_content="${role_content}"$'\n\n'"## 작업 경로

현재 셸의 cwd는 역할별 스킬 격리용 디렉터리(\`$work_dir\`)이며 작업 대상이 아니다.
**실제 프로젝트 루트는 \`$PROJECT_DIR\` 이다.** 파일을 읽고 쓰거나 git을 다룰 때는
그 경로를 기준으로 하고, 셸 작업이 필요하면 먼저 \`cd '$PROJECT_DIR'\` 한다."
        fi
        # lead에는 MEMBER_NAMES 배열 기준 배분 표를 실행 시점에 동적 생성해 이어붙인다.
        # config.sh만 바꾸면 lead.md를 손대지 않아도 배분 표가 항상 일치하게 하기 위함.
        if [ "$role" = "lead" ]; then
            local team_table="## 팀원 배분 (자동 생성)"$'\n\n'"| 역할 | 파인 | 지시 방법 |"$'\n'"| --- | --- | --- |"
            for ((m = 1; m < ${#MEMBER_NAMES[@]}; m++)); do
                team_table+=$'\n'"| ${MEMBER_NAMES[$m]} | :0.$m | say :0.$m \"...\" |"
            done
            role_content="${role_content}"$'\n\n'"${team_table}"
        fi
        # 조립된 지침을 파일로 쓰고 경로만 넘긴다. 파인이 재시작해도 읽을 수 있도록
        # /tmp가 아니라 스킬 격리 디렉터리(.team/{역할}/) 옆에 둔다.
        local prompt_file="$RUNTIME_DIR/${role}.prompt.md"
        mkdir -p "$RUNTIME_DIR"
        printf '%s' "$role_content" > "$prompt_file"
        system_prompt_arg="--append-system-prompt-file '$prompt_file'"
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
    # PreToolUse는 역할과 무관하게 모든 파인에 필요하다. --settings가 글로벌
    # settings.json을 병합이 아니라 '대체'하므로, --settings를 쓰는 순간 글로벌
    # rtk 재작성 훅이 그 파인에서 통째로 사라지기 때문이다.
    # lead도 --setting-sources project로 전역 설정을 끄므로 동일하게 명시 주입한다.
    # 프롬프트·툴 로깅도 모든 파인 공통이다. 로그는 작업 대상인 $PROJECT_DIR의
    # .claude-logs/{역할}.jsonl 에 쌓이므로, 파인은 자기 로그를 그대로 읽을 수 있고
    # .team/ 과 달리 세션을 새로 띄워도(rm -rf 대상이 아니다) 남는다.
    # matcher는 Bash로 한정하지 않는다 — 어떤 파일·디렉터리를 참조했는지가
    # 재현에 필요하므로 Read/Edit/Write/Grep도 함께 남겨야 한다.
    # rtk 재작성 훅과는 별도 항목으로 둔다. 같은 Bash 항목에 얹으면 rtk까지
    # matcher가 넓어져 의도치 않은 도구에 재작성이 걸린다.
    local log_cmd="${TEAM_DIR}/log-hook ${role:-unknown} '${PROJECT_DIR}'"
    local pretooluse_json="\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"rtk hook claude\"}]},{\"matcher\":\"*\",\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd}\"}]}]"
    local userprompt_json="\"UserPromptSubmit\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${log_cmd}\"}]}]"

    local settings_arg=""
    if [ "$role" = "lead" ]; then
        # lead는 Stop 훅을 받으면 안 된다 — 종료 신호의 수신처가 lead 자신(:0.0)이라
        # 자기 응답이 끝날 때마다 스스로에게 신호를 보내 무한 루프가 된다.
        # 따라서 Stop을 뺀 나머지(PreToolUse·UserPromptSubmit)만 넣는다.
        local lead_settings_json="{\"hooks\":{${pretooluse_json},${userprompt_json}}}"
        local lead_settings_file="$RUNTIME_DIR/${role}.settings.json"
        mkdir -p "$RUNTIME_DIR"
        printf '%s' "$lead_settings_json" > "$lead_settings_file"
        settings_arg="--settings '$lead_settings_file'"
    elif [ -n "$role" ]; then
        local pane_id="${pane##*:}"   # "team1:0.4" → "0.4"
        # 중복 신호 가드: 이 파인이 방금 say로 본 보고를 보냈다면 종료 신호를 생략한다.
        # 본 보고에 이미 작업 내용이 담겨 있어 신호는 lead 턴만 한 번 더 태우기 때문이다.
        # say가 남긴 마커를 소비(삭제)하므로, 보고 없이 끝난 응답에서는 신호가 정상 발송된다.
        local marker="/tmp/team-say/${pane_id}"
        # JSON 문자열로 들어가므로 큰따옴표는 \" 로 이스케이프한다(작은따옴표는 JSON에서 무해).
        # 훅 커맨드는 이 스크립트가 만드는 고정 문자열이라 이스케이프 대상이 이것뿐이다.
        local hook_cmd="if [ -f '${marker}' ]; then rm -f '${marker}'; else ${TEAM_DIR}/say ${SESSION}:0.0 \\\"[${role}] (자동) 파인 :${pane_id} 응답 종료 — 미보고 시 확인 필요\\\"; fi"
        local settings_json="{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"${hook_cmd}\"}]}],${pretooluse_json},${userprompt_json}}}"
        local settings_file="$RUNTIME_DIR/${role}.settings.json"
        mkdir -p "$RUNTIME_DIR"
        printf '%s' "$settings_json" > "$settings_file"
        settings_arg="--settings '$settings_file'"
    fi

    # unset CLAUDECODE: 이 스크립트 자신이 Claude Code 세션 안에서 실행 중일 경우
    # 남아있는 CLAUDECODE 환경변수가 파인 내부의 claude 실행에 영향을 주지 않도록 제거한다.
    # PATH에 TEAM_DIR: 파인들이 `say`를 경로 없이 호출할 수 있게 한다.
    tmux send-keys -t "$pane" \
        "cd '$work_dir' && unset CLAUDECODE && export PATH='$TEAM_DIR':\$PATH && $claude_bin --model $model --dangerously-skip-permissions $skills_arg $system_prompt_arg $settings_arg" Enter

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

# ── [1.6/5] 역할별 스킬 제한 ─────────────────────────────────
# gstack setup은 스킬 56개를 ~/.claude/skills/ 아래 전부 깔고, 그 frontmatter
# (약 22.8KB ≈ 5.7K 토큰)는 파인이 뜰 때마다 시스템 프롬프트로 들어간다.
# 파인 6개 × 매 턴이므로 고정비가 크다. 실제로는 researcher가 /ios-qa를,
# reviewer가 /design-shotgun을 쓸 일이 없다.
#
# ~/.claude/skills는 유저 전역이라 파인별로 다르게 만들 수 없다. 그래서
#   1) 파인마다 $PROJECT_DIR/.team/{역할}/.claude/skills 를 만들어 필요한 스킬만 넣고
#   2) 그 디렉터리를 cwd로 claude를 띄우되 --setting-sources project 로
#      유저 전역 스킬 56개와 플러그인 스킬을 차단한다
# claude에 빌트인된 스킬(dataviz, init, security-review 등 약 15개)은 설정 소스와
# 무관하게 항상 로드되므로 이 방식으로 제거되지 않는다.
# 프로젝트 스킬 탐색은 상위 디렉터리로 거슬러 올라가므로, cwd가 프로젝트 안이면
# $PROJECT_DIR/.claude/skills 의 공용 스킬은 모든 파인이 그대로 상속한다.
# cwd가 프로젝트 밖이 아니라 안이라서 git·상대경로도 평소대로 동작한다.
# 스킬은 gstack 원본 SKILL.md를 심볼릭 링크하므로 중복 사본이 생기지 않는다.
#
# 주의: --setting-sources project는 유저 settings.json(훅)도 함께 끄므로,
# 아래 start_claude_in_pane이 PreToolUse(rtk 재작성)를 --settings로 명시
# 주입한다. lead도 마찬가지지만 Stop 훅만은 제외한다(자기 자신에게 종료 신호를
# 보내 무한 루프가 되기 때문).
#
# 반면 ~/.claude/rules/ 와 ~/.claude/CLAUDE.md 는 이 플래그로 꺼지지 않는다 —
# cwd가 홈 디렉터리 아래이면 그대로 로드된다(실측). 파인 cwd는 항상
# $PROJECT_DIR/.team/{역할} 이므로 전역 규칙은 계속 들어온다.
# 즉 여기서 줄어드는 것은 gstack 스킬 frontmatter와 플러그인·에이전트 정의다.
echo -e "\n${YELLOW}[1.6/5] 역할별 스킬 제한...${NC}"

# 역할 → 허용 스킬 목록. 값이 비면 gstack 스킬을 하나도 주지 않는다는 뜻이고,
# 키 자체가 없으면 제한하지 않는다(전역 스킬 전체 유지).
#
# lead는 코드를 직접 쓰지 않고 배분·수합·git 커밋만 하므로 gstack 스킬이 필요 없다.
# 빈 값을 줘서 디렉터리는 만들되(→ --setting-sources project 적용) gstack 스킬은
# 하나도 주지 않는다(빌트인 스킬은 위 주석대로 남는다).
declare -A SKILL_SETS=(
    [lead]=""
    [architect]="spec diagram document-generate health plan-eng-review"
    [researcher]="scrape browse investigate"
    [designer]="design-consultation design-review design-html diagram"
    [developer]="investigate health codex learn"
    [reviewer]="review qa health investigate"
)

# 전역 규칙(~/.claude/rules/)과 ~/.claude/CLAUDE.md는 따로 주입하지 않는다.
# --setting-sources project가 이것들까지 끌 거라 보고 역할별로 골라 주입했었지만,
# 실측해보니 cwd가 홈 디렉터리 아래이면 그대로 로드된다(파인 cwd는 항상
# $PROJECT_DIR/.team/{역할} 이고 이 리포는 ~/ai-setup 이므로 해당된다).
# 따라서 주입은 같은 내용을 두 번 넣는 중복일 뿐이라 제거했다.
# 규칙까지 줄이려면 ~/.claude/rules/를 홈 밖으로 옮겨야 하는데, 그건 이 리포
# 밖의 다른 Claude Code 세션에도 영향을 주므로 하지 않는다.

TEAM_SKILLS_ROOT="$PROJECT_DIR/.team"
# 조립된 역할 지침(.prompt.md)과 훅 설정(.settings.json)을 두는 곳.
# 커맨드에 내용을 싣지 않고 이 경로만 넘긴다(tmux send-keys 길이 제한 회피).
RUNTIME_DIR="$TEAM_SKILLS_ROOT/_runtime"
rm -rf "$TEAM_SKILLS_ROOT"

for role in "${!SKILL_SETS[@]}"; do
    role_skills_dir="$TEAM_SKILLS_ROOT/$role/.claude/skills"
    mkdir -p "$role_skills_dir"
    granted=()
    for skill in ${SKILL_SETS[$role]}; do
        # gstack setup이 만든 래퍼(~/.claude/skills/{skill}/SKILL.md)를 그대로 링크한다.
        # 래퍼의 SKILL.md 자체가 이미 gstack 리포를 가리키는 심볼릭 링크다.
        src="$HOME/.claude/skills/$skill/SKILL.md"
        [ -e "$src" ] || { echo -e "${YELLOW}  ⚠️  $role: '$skill' 없음 (스킬명 확인)${NC}" >&2; continue; }
        mkdir -p "$role_skills_dir/$skill"
        ln -sfn "$(realpath "$src")" "$role_skills_dir/$skill/SKILL.md"
        # 일부 스킬은 런타임에 sections/ 를 읽으므로 함께 링크한다.
        if [ -d "$HOME/.claude/skills/$skill/sections" ]; then
            ln -sfn "$(realpath "$HOME/.claude/skills/$skill/sections")" "$role_skills_dir/$skill/sections"
        fi
        granted+=("$skill")
    done
    echo "  $role: ${granted[*]:-(gstack 스킬 없음)}"
done

echo -e "${GREEN}✅ 역할별 스킬 제한 완료${NC}"

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
# main-pane-width는 select-layout main-vertical이 레이아웃을 계산할 때 참조하는
# 값이라 반드시 그 호출 전에 설정해야 한다 — 순서가 바뀌면(set-option을 나중에
# 호출) 이미 그려진 레이아웃에는 반영되지 않아 55%가 무시된다.
# 절대값(컬럼 수) 대신 %로 지정 — 실제 터미널 창 폭이 좁을 때도
# lead 파인이 나머지 파인 대비 상대적으로 넓게 유지된다.
tmux set-option -t "$SESSION" main-pane-width '55%'
tmux select-layout -t "$SESSION:0" main-vertical

#  파인 이름 설정 (레이아웃 설정 후, Claude 실행 전)
# 파인 타이틀은 시각적 강조를 위해 대문자로 표시 (데이터 자체는 소문자 유지)
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    tmux select-pane -t "$SESSION:0.$pane" -T "${MEMBER_NAMES[$pane]^^}"
done

# 파인 제목 표시 설정
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
tmux set-option -t "$SESSION" allow-rename off
# 마우스 휠 스크롤·파인 클릭 전환 (tmux 기본값이 off라 켜주지 않으면 스크롤이 안 먹는다)
tmux set-option -t "$SESSION" mouse on

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
[ -t 1 ] && tmux attach -t "$SESSION"

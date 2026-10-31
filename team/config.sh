# team/config.sh — 프로젝트 전용 팀 구성 (setup-team.sh가 있으면 자동 로드)

# 인원·공급자·모델은 MEMBERS에서 설정한다.
# 새 역할의 스킬·플러그인 배분은 config.claude.sh·config.codex.sh에 추가한다.

SESSION="team1"   # tmux 세션 이름 (프로젝트별로 변경 가능)

# "role|표시이름|agent|model|effort" — 배열 순서가 곧 파인 배치 순서다.
#   - role: say 주소·파일명·디렉토리명에 쓰이는 직무 키.
#   - 표시이름: tmux pane 제목에만 반영(say 주소는 role 그대로). 비우면 role 표시.
#   - agent: claude 또는 codex. 비우면 --agent/TEAM_AGENT 기본값을 따른다.
#   - model: 비우면 CLI에 --model을 넘기지 않아 사용자 기본 모델을 따른다.
#   - effort: low/medium/high/xhigh/max. 비우면 --effort를 넘기지 않아
#     CLI 기본값(Claude는 settings.json의 effortLevel)을 따른다.
#
declare -a MEMBERS=(
    "lead|팀장|claude|claude-opus-5-5|medium"
    "architect|기획·설계|claude|claude-opus-5-5|high"
    # "researcher|리서처|claude|claude-sonnet-5-5|medium"
    # "designer|UI·프론트|codex|gpt-6-astra|low"
    "developer|백엔드|codex|gpt-6.1-sol|medium"
    "reviewer|리뷰어|claude|claude-sonnet-5-5|medium"
)

# 선언을 런처가 사용할 배열로 변환한다.
declare -a MEMBER_NAMES=()
declare -a MEMBER_DISPLAY_NAMES=()
declare -a MEMBER_AGENTS=()
declare -a SPEC_MEMBER_MODELS=()
declare -a SPEC_MEMBER_REASONING_EFFORTS=()

for spec in "${MEMBERS[@]}"; do
    IFS='|' read -r role display agent model effort <<< "$spec"
    MEMBER_NAMES+=("$role")
    MEMBER_DISPLAY_NAMES+=("${display:-$role}")
    MEMBER_AGENTS+=("$agent")
    SPEC_MEMBER_MODELS+=("$model")
    SPEC_MEMBER_REASONING_EFFORTS+=("$effort")
done

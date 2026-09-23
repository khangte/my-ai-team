# team/config.sh — 프로젝트 전용 팀 구성 (setup-team.sh가 있으면 자동 로드)

# 인원 추가·삭제·모델·추론강도 변경은 이 파일 하나만 고치면 된다. 역할마다
# 한 줄로 "role|표시이름|agent|model|effort"를 선언하면 setup-team.sh가
# MEMBER_NAMES, MEMBER_DISPLAY_NAMES, MEMBER_AGENTS, MEMBER_MODELS,
# MEMBER_REASONING_EFFORTS로 풀어 쓴다. team/config.claude.sh·config.codex.sh는
# 플러그인·스킬 배분표만 담당하며 모델은 선언하지 않는다 — 인원 증감 시 그
# 두 파일은 건드릴 필요가 없다(단, 새 역할 이름을 만들 때는 그 배분표에도
# 역할 키를 추가해야 플러그인·스킬이 배정된다).
#
# 예: 인원을 4명으로 줄이려면 MEMBERS에서 두 줄만 지우면 된다.

SESSION="team1"   # tmux 세션 이름 (프로젝트별로 변경 가능)

# "role|표시이름|agent|model|effort" — 배열 순서가 곧 파인 배치 순서다.
#   - role: say 주소·파일명·디렉토리명에 쓰이는 직무 키.
#   - 표시이름: tmux pane 제목에만 반영(say 주소는 role 그대로). 비우면 role 표시.
#   - agent: claude 또는 codex. 비우면 --agent/TEAM_AGENT 기본값을 따른다.
#   - model: 비우면 CLI에 --model을 넘기지 않아 사용자 기본 모델을 따른다.
#   - effort: low/medium/high/xhigh/max. 비우면 --effort를 넘기지 않아
#     CLI 기본값(Claude는 settings.json의 effortLevel)을 따른다.
#
# lead는 직접 작업하지 않고 배분·수합만 하지만 모든 보고가 모여 컨텍스트가
# 가장 빨리 불어나는 파인이다. 비싼 모델 × 최장 컨텍스트 조합을 피해 Sonnet을
# 쓴다. 깊은 판단이 필요한 쪽은 architect이므로 그쪽만 상위 모델을 둔다.
declare -a MEMBERS=(
    "lead|리드|claude|claude-sonnet-5|medium"
    "architect|아키텍트|claude|claude-opus-5-5|high"
    "researcher|리서쳐|claude|claude-haiku-4-5|medium"
    "designer|디자이너|codex|gpt-5.6-terra|medium"
    "developer|개발자|codex|gpt-5.6-terra|high"
    "reviewer|리뷰어|claude|claude-sonnet-5|medium"
)

# ── 아래는 위 선언을 setup-team.sh/setup-native.sh가 쓰는 배열로 풀어내는
#    어댑터다. 프로젝트에서 보통 건드릴 필요 없다.
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

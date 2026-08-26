# team/config.claude.sh — Claude 역할별 기본 설정
#
# 대상 프로젝트에 같은 파일을 두면 모델·플러그인·스킬 배분을 덮어쓸 수 있다.
# 모델 배열 길이는 team/config.sh의 MEMBER_NAMES와 같아야 한다.

declare -a MEMBER_MODELS=(
    # lead는 직접 작업하지 않고 배분·수합만 하지만 모든 보고가 모여 컨텍스트가
    # 가장 빨리 불어나는 파인이다. 비싼 모델 × 최장 컨텍스트 조합을 피해 Sonnet을 쓴다.
    # 깊은 판단이 필요한 쪽은 architect이므로 그쪽만 Opus로 둔다.
    "claude-sonnet-5"   # lead (팀장 — 판단·조율 중심)
    "claude-opus-4-8"   # architect (PM — 설계·추론 중심)
    "claude-haiku-4-5"   # researcher
    "claude-sonnet-5"   # designer
    "claude-sonnet-5"   # developer
    "claude-sonnet-5"   # reviewer
)

# 역할별 추론 강도. 값: low, medium, high, xhigh, max. 빈 문자열이면 --effort를
# 넘기지 않아 CLI 기본값(사용자 settings.json의 effortLevel)을 그대로 쓴다.
declare -a MEMBER_REASONING_EFFORTS=(
    "medium"    # lead
    "high"      # architect
    "medium"    # researcher
    "medium"    # designer
    "high"      # developer
    "high"      # reviewer
)

# 마켓플레이스 이름 → GitHub 리포. 설치할 플러그인은 PLUGIN_ROLES에서
# plugin@marketplace 형식으로 지정한다.
declare -A PLUGIN_MARKETPLACES=(
    [claude-plugins-official]="anthropics/claude-plugins-official"
    [ponytail]="DietrichGebert/ponytail"
    [caveman]="JuliusBrussee/caveman"
)

# 플러그인 → 활성화할 역할. "*"는 모든 역할, 빈 값은 설치만 한다.
declare -A PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
    ["frontend-design@claude-plugins-official"]=""
    ["serena@claude-plugins-official"]="developer reviewer designer"
    ["ponytail@ponytail"]="lead developer"
    ["caveman@caveman"]="*"
)

# 역할 → 필요한 스킬. setup-team.sh는 이 선언을 읽어 역할별 런타임 디렉터리에
# 심볼릭 링크를 만들고, 설치·오류 처리는 런처에 남긴다.
declare -A GSTACK_SKILL_SETS=(
    [lead]=""
    [architect]="spec diagram document-generate health plan-eng-review"
    [researcher]="scrape browse"
    [designer]="design-review design-html diagram"
    [developer]="health codex learn"
    [reviewer]="review qa health"
)

declare -A SUPERPOWERS_SKILL_SETS=(
    [lead]="finishing-a-development-branch"
    [architect]="brainstorming writing-plans"
    [designer]="brainstorming"
    [developer]="test-driven-development systematic-debugging receiving-code-review"
    [reviewer]="verification-before-completion"
)

declare -A FRONTEND_DESIGN_SKILL_SETS=(
    [designer]="frontend-design"
)

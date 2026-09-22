# team/config.claude.sh — Claude 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 플러그인·스킬 배분을 덮어쓸 수 있다.
# 모델·추론강도는 여기서 다루지 않는다 — team/config.sh의 MEMBERS가
# 유일한 출처다("표시이름|agent|model|effort"). 인원을 늘리거나 줄일 때 이
# 파일은 건드릴 필요 없다(단, 역할 이름 자체를 새로 만들면 아래 배분표에
# 그 역할 키를 추가해야 플러그인·스킬이 배정된다).

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

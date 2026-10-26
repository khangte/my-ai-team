# team/config.claude.sh — Claude 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 플러그인·스킬 배분을 덮어쓸 수 있다.
# 모델·추론강도는 여기서 다루지 않는다 — team/config.sh의 MEMBERS가
# 유일한 출처다("표시이름|agent|model|effort"). 인원을 늘리거나 줄일 때 이
# 파일은 건드릴 필요 없다(단, 역할 이름 자체를 새로 만들면 아래 배분표에
# 그 역할 키를 추가해야 플러그인·스킬이 배정된다).

# 마켓플레이스 이름 → GitHub 리포. 설치할 플러그인은 CLAUDE_PLUGIN_ROLES에서
# plugin@marketplace 형식으로 지정한다.
declare -A CLAUDE_PLUGIN_MARKETPLACES=(
    [claude-plugins-official]="anthropics/claude-plugins-official"
    [ponytail]="DietrichGebert/ponytail"
    [caveman]="JuliusBrussee/caveman"
)

# 플러그인 → 활성화할 역할. "*"는 모든 역할, 빈 값은 설치만 한다.
declare -A CLAUDE_PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
    ["frontend-design@claude-plugins-official"]="designer"
    ["serena@claude-plugins-official"]="*"
    ["ponytail@ponytail"]="developer"
    ["caveman@caveman"]="*"
)

# 역할 → 필요한 스킬. setup-team.sh는 이 선언을 읽어 역할별 런타임 디렉터리에
# 심볼릭 링크를 만들고, 설치·오류 처리는 런처에 남긴다.
# gstack은 제거했다. 값만 비웠고 키는 남긴다 — setup-team.sh의 역할별 스킬 디렉터리 루프가
# 이 배열의 키를 순회하며 superpowers 스킬도 함께 링크하기 때문이다. 되살리려면 주석 값을 복원한다.
declare -A CLAUDE_GSTACK_SKILL_SETS=(
    [lead]=""            # [lead]="spec plan-eng-review"
    [architect]=""       # [architect]="diagram"
    [researcher]=""      # [researcher]="scrape browse"
    [designer]=""        # [designer]="design-review design-html"
    [developer]=""       # [developer]="health"
    [reviewer]=""        # [reviewer]="review"
)

declare -A CLAUDE_SUPERPOWERS_SKILL_SETS=(
    [lead]="finishing-a-development-branch"
    [architect]="writing-plans"
    [designer]=""
    [developer]="systematic-debugging receiving-code-review"
    [reviewer]=""
)

declare -A CLAUDE_FRONTEND_DESIGN_SKILL_SETS=(
    [designer]="frontend-design"
)

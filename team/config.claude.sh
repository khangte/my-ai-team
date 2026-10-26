# team/config.claude.sh — Claude 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 이 배분을 덮어쓴다.
# 모델·추론강도는 team/config.sh의 MEMBERS가 유일한 출처다. 새 역할 이름을 만들면
# 아래 배분표에 그 역할 키를 추가해야 플러그인·스킬이 배정된다.

# 마켓플레이스 이름 → GitHub 리포. Codex와 달리 내장 카탈로그가 없어 등록이 필요하다.
declare -A CLAUDE_PLUGIN_MARKETPLACES=(
    [claude-plugins-official]="anthropics/claude-plugins-official"
    [ponytail]="DietrichGebert/ponytail"
    [caveman]="JuliusBrussee/caveman"
)

# plugin@marketplace → 활성화할 역할. "*"는 모든 역할, 빈 값은 설치만 한다.
# superpowers는 빈 값이다 — 설치해야 플러그인 캐시(~/.claude/plugins/cache)에 스킬 원본이
# 생기고, 전체를 켜면 선별이 무의미해진다. Codex는 원본이 snapshot에 있어 설치가 필요 없다.
declare -A CLAUDE_PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
    # ["frontend-design@claude-plugins-official"]="designer"
    ["serena@claude-plugins-official"]="*"
    ["ponytail@ponytail"]="developer"
    ["caveman@caveman"]="lead"
)

# 역할 → gstack 스킬. gstack은 제거해 값만 비웠다. 키는 남긴다 — setup-team.sh의 역할별
# 스킬 디렉터리 루프가 이 키를 순회한다. 되살리려면 주석 값을 복원한다.
declare -A CLAUDE_GSTACK_SKILL_SETS=(
    [lead]=""            # [lead]="spec plan-eng-review"
    [architect]=""       # [architect]="diagram"
    [researcher]=""      # [researcher]="scrape browse"
    [designer]=""        # [designer]="design-review design-html"
    [developer]=""       # [developer]="health"
    [reviewer]=""        # [reviewer]="review"
)

# 역할 → superpowers 스킬. 플러그인 캐시의 원본에서 필요한 것만 링크한다.
declare -A CLAUDE_SUPERPOWERS_SKILL_SETS=(
    [lead]="finishing-a-development-branch"
    [architect]="writing-plans"
    [designer]=""
    [developer]="systematic-debugging receiving-code-review"
    [reviewer]=""
)

# declare -A CLAUDE_FRONTEND_DESIGN_SKILL_SETS=(
#     [designer]="frontend-design"
# )

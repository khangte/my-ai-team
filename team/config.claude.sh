# team/config.claude.sh — Claude 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 이 파일 대신 그것만 쓴다(병합하지 않음).
# 모델·추론강도는 team/config.sh의 MEMBERS가 유일한 출처다. 새 역할 이름을 만들면
# 아래 배분표에 그 역할 키를 추가해야 플러그인·스킬이 배정된다.

# 마켓플레이스 이름 → GitHub 리포. Codex와 달리 내장 카탈로그가 없어 등록이 필요하다.
declare -A CLAUDE_PLUGIN_MARKETPLACES=(
    [claude-plugins-official]="anthropics/claude-plugins-official"
    [ponytail]="DietrichGebert/ponytail"
    [caveman]="JuliusBrussee/caveman"
)

# plugin@marketplace → 활성화할 역할. "*"는 모든 역할, 빈 값은 설치만 한다.
# superpowers는 빈 값이다 — 선택 스킬의 원본이라 설치만 하고(아래 SKILL_SETS가 있는 역할이
# 있을 때), 전체를 켜면 선별이 무의미해진다. 해당 Claude 역할에 필요 없고 설치도 안 된
# 플러그인은 설치하지 않으며, 이미 설치된 것은 설치 명령 없이 표시만 한다.
declare -A CLAUDE_PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
    # ["frontend-design@claude-plugins-official"]="designer"
    ["serena@claude-plugins-official"]="*"
    ["ponytail@ponytail"]="developer"
    ["caveman@caveman"]="lead"
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

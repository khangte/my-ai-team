# team/config.claude.sh — Claude 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 이 파일 대신 그것만 쓴다(병합하지 않음).
# 모델은 config.sh의 MEMBERS에서 정하고 새 역할의 스킬·플러그인은 여기 배정한다.

# 마켓플레이스 이름 → GitHub 리포. Codex와 달리 내장 카탈로그가 없어 등록이 필요하다.
declare -A CLAUDE_PLUGIN_MARKETPLACES=(
    [claude-plugins-official]="anthropics/claude-plugins-official"
    [ponytail]="DietrichGebert/ponytail"
    [caveman]="JuliusBrussee/caveman"
)

# plugin@marketplace → 활성화할 역할. "*"는 모든 역할, 빈 값은 설치만 한다.
# 선택 스킬의 원본이 필요할 때만 설치한다. 설치된 플러그인은 상태만 출력한다.
declare -A CLAUDE_PLUGIN_ROLES=(
    ["superpowers@claude-plugins-official"]=""
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

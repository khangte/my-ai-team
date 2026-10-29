# team/config.codex.sh — Codex 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 이 파일 대신 그것만 쓴다(병합하지 않음).
# 모델은 config.sh의 MEMBERS에서 정하고 새 역할의 스킬·플러그인은 여기 배정한다.

# 마켓플레이스는 선언하지 않는다 — 내장 원격 카탈로그 openai-curated-remote를 쓴다.

# plugin@marketplace → 활성화할 역할. "*"는 모든 역할, 빈 값은 선택 스킬만 노출한다.
# 역할별 CODEX_HOME에서 기본 차단 후 배정 플러그인만 켠다.
# 원격 plugin list의 enabled 값은 이 역할별 설정을 반영하지 않는다.
declare -A CODEX_PLUGIN_ROLES=(
    ["superpowers@openai-curated-remote"]=""
    ["product-design@openai-curated-remote"]="designer"
    ["engineering-suite-ponytail@openai-curated-remote"]="developer"
    ["caveman@openai-curated-remote"]="*"
)

# 역할 → standalone 스킬. .agents/skills/<name>·~/.codex/skills/<name>에서 찾아 링크한다.
declare -A CODEX_SKILL_SETS=(
    [lead]=""
    [architect]=""
    [researcher]=""
    [designer]=""
    [developer]=""
    [reviewer]=""
)

# 역할 → superpowers 스킬. snapshot의 원본에서 필요한 것만 링크한다.
declare -A CODEX_SUPERPOWERS_SKILL_SETS=(
    [lead]="finishing-a-development-branch"
    [architect]="writing-plans"
    [designer]=""
    [developer]="systematic-debugging receiving-code-review"
    [reviewer]=""
)

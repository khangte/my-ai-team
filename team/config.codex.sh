# team/config.codex.sh — Codex 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 이 파일 대신 그것만 쓴다(병합하지 않음).
# 모델·추론강도는 team/config.sh의 MEMBERS가 유일한 출처다. 새 역할 이름을 만들면
# 아래 배분표에 그 역할 키를 추가해야 플러그인·스킬이 배정된다.

# 마켓플레이스는 선언하지 않는다 — 내장 원격 카탈로그 openai-curated-remote를 쓴다.

# plugin@marketplace → 설치할 역할. "*"는 모든 역할, 빈 값은 설치하지 않는다.
# 키는 `codex plugin list --json --available`의 pluginId다. 역할마다 격리된 CODEX_HOME에 설치된다.
# 역할 홈의 plugins._default.enabled=false로 기본 차단하고 배정된 항목만 명시적으로 켠다.
# plugin list의 원격 enabled 값은 역할별 실행 설정을 반영하지 않는다.
# superpowers는 빈 값이다 — 원본이 snapshot(~/.codex/.tmp/plugins)에 이미 있고,
# `codex plugin add`는 설치와 활성화를 분리하지 못해 선별이 무의미해진다.
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

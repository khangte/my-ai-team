# team/config.codex.sh — Codex 역할별 플러그인·스킬 배분

# 대상 프로젝트에 같은 파일을 두면 플러그인·스킬 배분을 덮어쓸 수 있다.
# 모델·추론강도는 여기서 다루지 않는다 — team/config.sh의 MEMBERS가
# 유일한 출처다("표시이름|agent|model|effort"). 인원을 늘리거나 줄일 때 이
# 파일은 건드릴 필요 없다(단, 역할 이름 자체를 새로 만들면 아래 배분표에
# 그 역할 키를 추가해야 플러그인·스킬이 배정된다).
# 형식은 team/config.claude.sh와 같다. 플러그인 키는 `codex plugin list --available`에
# 나오는 실제 pluginId를 그대로 적는다(현재 카탈로그는 openai-curated-remote).

# 플러그인 → 설치할 역할. "*"는 모든 Codex 역할, 빈 값은 설치하지 않는다.
# 각 Codex 파인은 격리된 CODEX_HOME을 쓰므로 해당 역할에만 설치된다.
# superpowers는 넣지 않는다 — 여기 넣으면 전체가 설치·활성화돼 선별이 무의미해지고,
# 링크할 원본은 공식 marketplace snapshot에 이미 있다(아래 CODEX_SUPERPOWERS_SKILL_SETS).
declare -A CODEX_PLUGIN_ROLES=(
    ["product-design@openai-curated-remote"]="designer"
)

# 역할 → 필요한 스킬. setup-team.sh는 이 선언을 읽어 역할별 .agents/skills에
# 심볼릭 링크를 만든다. standalone 스킬은 .agents/skills/<name>·~/.codex/skills/<name>에서 찾는다.
# gstack은 넣지 않는다 — setup-team.sh는 gstack을 claude host로만 설치하고, codex용
# 렌더링은 이름이 gstack-<name>이라 찾지 못한다(설정해도 경고 후 건너뜀).
declare -A CODEX_SKILL_SETS=()

# superpowers 플러그인에서 역할별로 골라 링크할 스킬. 플러그인 전체를 켜면
# 역할에 불필요한 스킬까지 노출되므로 필요한 것만 고른다.
declare -A CODEX_SUPERPOWERS_SKILL_SETS=(
    [developer]="systematic-debugging receiving-code-review"
)

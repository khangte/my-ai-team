# team/config.codex.sh — Codex 역할별 스킬 배분

# 대상 프로젝트에 같은 파일을 두면 스킬 배분을 덮어쓸 수 있다. 모델·추론강도는
# 여기서 다루지 않는다 — team/config.sh의 MEMBERS가 유일한 출처다
# ("표시이름|agent|model|effort"). 인원을 늘리거나 줄일 때 이 파일은 건드릴
# 필요 없다(단, 역할 이름 자체를 새로 만들면 아래 배분표에 그 역할 키를
# 추가해야 스킬이 배정된다).

# 역할 → 역할 전용으로 추가할 standalone Codex 스킬. Claude 쪽
# config.claude.sh의 GSTACK_SKILL_SETS와 동일하게 맞춘다(스킬명은 gstack
# 접두어 없이 그대로 — find_codex_skill_source가 .agents/skills/<name>에서 찾는다).
declare -A CODEX_SKILL_SETS=(
    [designer]="design-review design-html"
    [developer]="health"
)

# 역할 → 전체를 설치할 공식 Codex 플러그인. 각 Codex 파인은 격리된 CODEX_HOME을
# 사용하므로 다른 역할이나 사용자 전역 Codex 세션에는 노출되지 않는다. connector나
# MCP·hook까지 필요한 플러그인만 여기에 넣는다.
declare -A CODEX_PLUGIN_SETS=()

# 역할 → 공식 플러그인에서 선택적으로 노출할 스킬. 형식은
# plugin@marketplace:skill 이다. 플러그인 전체를 켜면 역할에 불필요한 스킬까지
# 노출되므로 필요한 스킬만 골라 링크한다.
declare -A CODEX_PLUGIN_SKILL_SETS=()

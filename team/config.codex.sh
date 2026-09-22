# team/config.codex.sh — Codex 역할별 스킬 배분

# 대상 프로젝트에 같은 파일을 두면 스킬 배분을 덮어쓸 수 있다. 모델·추론강도는
# 여기서 다루지 않는다 — team/config.sh의 MEMBERS가 유일한 출처다
# ("표시이름|agent|model|effort"). 인원을 늘리거나 줄일 때 이 파일은 건드릴
# 필요 없다(단, 역할 이름 자체를 새로 만들면 아래 배분표에 그 역할 키를
# 추가해야 스킬이 배정된다).

# 역할 → 역할 전용으로 추가할 standalone Codex 스킬.
declare -A CODEX_SKILL_SETS=()

# 역할 → 전체를 설치할 공식 Codex 플러그인. 각 Codex 파인은 격리된 CODEX_HOME을
# 사용하므로 다른 역할이나 사용자 전역 Codex 세션에는 노출되지 않는다. connector나
# MCP·hook까지 필요한 플러그인만 여기에 넣는다.
declare -A CODEX_PLUGIN_SETS=()

# 역할 → 공식 플러그인에서 선택적으로 노출할 스킬. 형식은
# plugin@marketplace:skill 이다. Superpowers 전체에는 architect 역할 밖의 TDD·디버깅·
# 서브에이전트 흐름도 들어 있으므로 필요한 두 스킬만 링크한다.
declare -A CODEX_PLUGIN_SKILL_SETS=(
    [architect]="superpowers@openai-curated:brainstorming superpowers@openai-curated:writing-plans"
)

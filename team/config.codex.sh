# team/config.codex.sh — Codex 역할별 기본 설정
#
# 특정 모델을 역할별로 고정하려면 대상 프로젝트에
# team/config.codex.sh를 만들고 아래 배열·배분표를 선언한다.

declare -a MEMBER_MODELS=(
    "gpt-5.6-terra"     # lead
    "gpt-5.6-sol"       # architect
    "gpt-5.6-luna"      # researcher
    "gpt-5.6-terra"     # designer
    "gpt-5.6-terra"     # developer
    "gpt-5.6-sol"       # reviewer
)

declare -a MEMBER_REASONING_EFFORTS=(
    "medium"
    "high"
    "medium"
    "medium"
    "high"
    "high"
)

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

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
    "medium"
    "medium"
    "high"
    "high"
    "high"
)

# 역할 → 역할 전용으로 추가할 Codex 스킬. 기본값은 빈 배분표다. Claude용
# 플러그인/스킬을 호환성 확인 없이 재사용하지 않으며, 대상 프로젝트는 검증된
# 스킬 이름을 여기에 선언할 수 있다.
declare -A CODEX_SKILL_SETS=()

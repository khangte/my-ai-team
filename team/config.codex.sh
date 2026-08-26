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
    "high"
    "high"
    "high"
)

# 역할 → 역할 전용으로 추가할 standalone Codex 스킬. 공식 Codex 플러그인은
# 사용자 전역으로 설치·활성화되므로 여기서 자동 설치하거나 역할별 링크하지 않는다.
# architect 권장 플러그인은 README의 "Codex architect 네이티브 확장"을 참고한다.
declare -A CODEX_SKILL_SETS=()

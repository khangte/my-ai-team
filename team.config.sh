# team.config.sh — 프로젝트 전용 팀 구성 (setup-team.sh가 있으면 자동 로드)
#
# 배열 길이만 같으면 인원 수/이름/모델을 자유롭게 조정 가능.

declare -a MEMBER_NAMES=("lead" "architect" "researcher" "designer" "developer" "reviewer")
declare -a MEMBER_MODELS=(
    "claude-opus-4-8"   # lead (팀장 — 판단·조율 중심)
    "claude-opus-4-8"   # architect (PM — 설계·추론 중심)
    "claude-sonnet-5"   # researcher
    "claude-sonnet-5"   # designer
    "claude-sonnet-5"   # developer
    "claude-sonnet-5"   # reviewer
)

# team.config.sh — 프로젝트 전용 팀 구성 (setup-team.sh가 있으면 자동 로드)
#
# 배열 길이만 같으면 인원 수/이름/모델을 자유롭게 조정 가능.

declare -a MEMBER_NAMES=("쭌" "민준 아키텍트" "지훈 리서쳐" "수아 UI/UX디자이너" "서연 개발자" "태양 QA·리뷰어")
declare -a MEMBER_MODELS=(
    "claude-opus-4-8"   # 쭌 (팀장 — 판단·조율 중심)
    "claude-opus-4-8"   # 민준 (PM — 설계·추론 중심)
    "claude-sonnet-5"   # 지훈
    "claude-sonnet-5"   # 수아
    "claude-sonnet-5"   # 서연
    "claude-sonnet-5"   # 태양
)

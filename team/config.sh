# team/config.sh — 프로젝트 전용 팀 공통 구성 (setup-team.sh가 있으면 자동 로드)
#
# 인원 수·이름은 여기에서 정하고, 모델은 team/config.claude.sh 또는
# team/config.codex.sh에서 정한다. 기존 Claude 프로젝트는 이 파일에
# MEMBER_MODELS를 계속 두어도 호환되지만, 새 구성은 공급자별 파일을 권장한다.

SESSION="team1"   # tmux 세션 이름 (프로젝트별로 변경 가능)

declare -a MEMBER_NAMES=("lead" "architect" "researcher" "designer" "developer" "reviewer")

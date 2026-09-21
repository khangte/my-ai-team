# team/config.sh — 프로젝트 전용 팀 공통 구성 (setup-team.sh가 있으면 자동 로드)
#
# 인원 수·이름은 여기에서 정하고, 모델은 team/config.claude.sh 또는
# team/config.codex.sh에서 정한다. 기존 Claude 프로젝트는 이 파일에
# MEMBER_MODELS를 계속 두어도 호환되지만, 새 구성은 공급자별 파일을 권장한다.

SESSION="team1"   # tmux 세션 이름 (프로젝트별로 변경 가능)

declare -a MEMBER_NAMES=(
    "lead"
    "architect"
    "researcher"
    "designer"
    "developer"
    "reviewer"
)

# MEMBER_NAMES(직무 키)와 같은 길이·순서로 표시용 사람 이름을 정한다.
# say 주소·파일명·디렉토리명은 계속 MEMBER_NAMES(직무명)를 쓰고, 이 배열은
# tmux pane 제목에만 반영된다. 미선언 시 직무명이 그대로 표시된다.
declare -a MEMBER_DISPLAY_NAMES=(
    "민혁"   # lead
    "명준"   # architect
    "동선"   # researcher
    "하원"   # designer
    "주빈"   # developer
    "동민"   # reviewer
)

# 파인별로 다른 에이전트를 지정하려면(혼합 팀) MEMBER_AGENTS를 MEMBER_NAMES와
# 같은 길이로 선언한다. 빈 문자열은 --agent/TEAM_AGENT 기본값을 따른다.
# 예: architect와 reviewer만 codex로 띄우고 나머지는 기본값 사용
#   declare -a MEMBER_AGENTS=("" "codex" "" "" "" "codex")
# 미선언 시 전체가 빈 값과 동일하게 취급되어 기존 단일 공급자 동작이 유지된다.
declare -a MEMBER_AGENTS=(
    "claude"   # lead
    "claude"   # architect
    "claude"   # researcher
    "codex"   # designer
    "codex"    # developer
    "claude"   # reviewer
)

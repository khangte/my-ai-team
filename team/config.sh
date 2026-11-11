# team/config.sh — 프로젝트 전용 팀 구성 (setup-team.sh가 있으면 자동 로드)

# 인원·공급자·모델은 MEMBERS에서 설정한다.
# 새 역할의 스킬·플러그인 배분은 config.claude.sh·config.codex.sh에 추가한다.

SESSION="team1"   # tmux 세션 이름 (필수, 프로젝트별로 변경 가능)

# "role|표시이름|model|effort" — 배열 순서가 곧 파인 배치 순서다.
# 네 필드 모두 필수다. 비어 있거나 형식이 틀리면 경고를 출력하고 실행을 멈춘다.
#   - role: say 주소·파일명·디렉토리명에 쓰이는 직무 키.
#   - 표시이름: 현재 미사용(pane 테두리는 role 영문명을 표시한다).
#   - model: 전체 모델 ID. 공급자는 접두사로 정한다(claude-* → claude, gpt-* → codex).
#   - effort: low/medium/high/xhigh/max.
#
declare -a MEMBERS=(
    "lead|팀장|claude-sonnet-5-5|high"
    "architect|설계|gpt-6.1-sol|high"
    "uiux|UI/UX|gpt-6.1-terra|medium"
    "frontend|프론트엔드|claude-sonnet-5-5|medium"
    "backend|백엔드|claude-sonnet-5-5|medium"
    "reviewer|리뷰어|gpt-6.1-sol|medium"
)

# 선언을 런처가 사용할 배열로 변환한다.
declare -a MEMBER_NAMES=()
declare -a MEMBER_DISPLAY_NAMES=()
declare -a MEMBER_AGENTS=()
declare -a SPEC_MEMBER_MODELS=()
declare -a SPEC_MEMBER_REASONING_EFFORTS=()

for spec in "${MEMBERS[@]}"; do
    IFS='|' read -r role display model effort <<< "$spec"
    if [ "${spec//[^|]/}" != "|||" ] || [ -z "$role" ] || [ -z "$display" ]; then
        echo "❌ MEMBERS 형식 오류: '$spec' (필수 형식 role|표시이름|model|effort, team/config.sh 확인)" >&2
        exit 2
    fi
    # shortcut: 접두사 두 개만 인식, 새 모델 계열이 나오면 여기에 추가한다.
    case "$model" in
        claude-*) agent="claude" ;;
        gpt-*)    agent="codex" ;;
        *) echo "❌ MEMBERS 모델 오류: '$model' (claude-* 또는 gpt-* 전체 모델 ID 필요: $spec)" >&2; exit 2 ;;
    esac
    case "$effort" in
        low|medium|high|xhigh|max) ;;
        *) echo "❌ MEMBERS effort 오류: '$effort' (low/medium/high/xhigh/max 중 하나 필요: $spec)" >&2; exit 2 ;;
    esac
    MEMBER_NAMES+=("$role")
    MEMBER_DISPLAY_NAMES+=("$display")
    MEMBER_AGENTS+=("$agent")
    SPEC_MEMBER_MODELS+=("$model")
    SPEC_MEMBER_REASONING_EFFORTS+=("$effort")
done

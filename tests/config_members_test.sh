#!/usr/bin/env bash
# team/config.sh의 MEMBERS 4필드 파싱 계약을 검증한다.
set -u

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
failed=0

parse_lead() {
    # lead 항목을 인자로 교체한 config를 읽어 agent/model/effort를 출력한다.
    sed "s#^    \"lead|.*#    \"$1\"#" "$repo_dir/team/config.sh" > "$test_dir/config.sh"
    bash -c 'source "$1" && echo "${MEMBER_AGENTS[0]}/${SPEC_MEMBER_MODELS[0]}/${SPEC_MEMBER_REASONING_EFFORTS[0]}"' _ "$test_dir/config.sh"
}

expect() {
    # 항목의 파싱 결과가 기대값과 다르면 실패로 기록한다.
    local actual
    actual="$(parse_lead "$1" 2>/dev/null)"
    [ "$actual" = "$2" ] || { echo "FAIL: '$1' → '$actual' (기대: '$2')"; failed=1; }
}

expect_rejected() {
    # 항목이 경고 없이 넘어가거나 설정 로드를 실패시키지 않으면 실패로 기록한다.
    local err
    err="$(parse_lead "$1" 2>&1 >/dev/null)" && { echo "FAIL: '$1'이 거부되지 않음"; failed=1; }
    [ -n "$err" ] || { echo "FAIL: '$1' 경고 없음"; failed=1; }
}

expect_setup_stops() {
    # 프로젝트 config 내용으로 setup-team.sh를 돌려 기대 경고와 함께 멈추는지 검사한다.
    local project="$test_dir/project" out
    mkdir -p "$project/team"
    printf '%s\n' "$1" > "$project/team/config.sh"
    out="$(bash "$repo_dir/setup-team.sh" "$project" 2>&1)" && { echo "FAIL: setup-team이 멈추지 않음: $1"; failed=1; }
    grep -qF "$2" <<< "$out" || { echo "FAIL: 경고 '$2' 없음: $out"; failed=1; }
}

expect "lead|팀장|claude-sonnet-5-5|high" "claude/claude-sonnet-5-5/high"
expect "lead|팀장|gpt-6.1-sol|medium" "codex/gpt-6.1-sol/medium"

expect_rejected "lead|팀장|sonnet|high"
expect_rejected "lead|팀장|claude|high"                     # 모델 ID 없이 공급자만
expect_rejected "lead|팀장|codex|medium"
expect_rejected "lead|팀장||medium"
expect_rejected "lead|팀장|claude-sonnet-5-5|"
expect_rejected "lead||claude-sonnet-5-5|high"
expect_rejected "|팀장|claude-sonnet-5-5|high"
expect_rejected "lead|팀장|claude-sonnet-5-5"               # 필드 부족
expect_rejected "lead|팀장|claude-sonnet-5-5|high|"         # 필드 초과
expect_rejected "lead|팀장|claude-sonnet-5-5|fast"
expect_rejected "lead|팀장|claude|claude-sonnet-5-5|high"   # 옛 5필드
expect_rejected "lead|팀장|claude||medium"                  # 옛 5필드, 모델 비움

filled='MEMBER_NAMES=(lead) MEMBER_DISPLAY_NAMES=(팀장) MEMBER_AGENTS=(claude) SPEC_MEMBER_MODELS=(claude-sonnet-5-5) SPEC_MEMBER_REASONING_EFFORTS=(high)'
expect_setup_stops "SESSION=''"$'\n'"$filled" 'SESSION이 비어'
expect_setup_stops "$filled SPEC_MEMBER_MODELS=('')" '비어 있는 값'
expect_setup_stops "$filled SPEC_MEMBER_REASONING_EFFORTS=('')" '비어 있는 값'
expect_setup_stops "$filled MEMBER_DISPLAY_NAMES=('')" '비어 있는 값'
expect_setup_stops "$filled MEMBER_AGENTS=('')" '지원하지 않는 에이전트'
expect_setup_stops 'MEMBER_NAMES=()' '팀 구성이 없습니다'

[ "$failed" -eq 0 ] && echo "PASS: config_members_test"
exit "$failed"

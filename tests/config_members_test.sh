#!/usr/bin/env bash
# team/members.conf 3필드 파싱 계약(lib/setup-common.sh)을 검증한다.
set -u

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
failed=0

parse_lead() {
    # lead 줄을 인자로 교체한 members.conf를 읽어 agent/model/effort를 출력한다.
    awk -v r="$1" '/^lead\|/ { print r; next } { print }' "$repo_dir/team/members.conf" > "$test_dir/members.conf"
    bash -c 'source "$1/lib/setup-common.sh" && load_team_members "$2" && echo "${MEMBER_AGENTS[0]}/${SPEC_MEMBER_MODELS[0]}/${SPEC_MEMBER_REASONING_EFFORTS[0]}"' _ "$repo_dir" "$test_dir/members.conf"
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
    # 프로젝트 team/ 파일($1) 내용($2)으로 setup-team.sh를 돌려 기대 경고($3)와 함께 멈추는지 검사한다.
    local project="$test_dir/project" out
    rm -rf "$project"; mkdir -p "$project/team"
    printf '%s\n' "$2" > "$project/team/$1"
    shift
    out="$(bash "$repo_dir/setup-team.sh" "$project" 2>&1)" && { echo "FAIL: setup-team이 멈추지 않음: $1"; failed=1; }
    grep -qF "$2" <<< "$out" || { echo "FAIL: 경고 '$2' 없음: $out"; failed=1; }
}

expect "lead|claude-sonnet-5-5|high" "claude/claude-sonnet-5-5/high"
expect "lead|gpt-6.1-sol|medium" "codex/gpt-6.1-sol/medium"
expect "lead|claude-sonnet-5-5|" "claude/claude-sonnet-5-5/"   # effort 빈 값 허용

expect_rejected "lead|sonnet|high"
expect_rejected "lead|claude|high"                     # 모델 ID 없이 공급자만
expect_rejected "lead|codex|medium"
expect_rejected "lead||medium"
expect_rejected "|claude-sonnet-5-5|high"               # role 비움
expect_rejected "lead|팀장|claude-sonnet-5-5|high"       # 옛 4필드(표시이름)
expect_rejected "lead|claude-sonnet-5-5"               # 필드 부족
expect_rejected "lead|claude-sonnet-5-5|high|"         # 필드 초과
expect_rejected "lead|claude-sonnet-5-5|fast"

expect "  lead|claude-sonnet-5-5|high  "$'\r' "claude/claude-sonnet-5-5/high"   # 앞뒤 공백·CRLF

lead='lead|claude-sonnet-5-5|high'
expect_setup_stops members.conf "$lead" 'SESSION이 비어'
expect_setup_stops members.conf 'SESSION=s' '팀 구성이 없습니다'
expect_setup_stops members.conf "SESSION=s"$'\n'"$lead"$'\n'"$lead" '중복된 역할'
expect_setup_stops config.sh 'SESSION="s"' 'members.conf로 옮기세요'

[ "$failed" -eq 0 ] && echo "PASS: config_members_test"
exit "$failed"

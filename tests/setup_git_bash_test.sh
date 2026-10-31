#!/usr/bin/env bash
# Git Bash 진입점의 경로·인자·종료 코드 전달을 명령 스텁으로 검증한다.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

fail() {
    # 실패 사유를 출력하고 테스트를 종료한다.
    echo "실패: $*" >&2
    exit 1
}

stub="$test_dir/bin"
mkdir -p "$stub" "$test_dir/프로젝트 공백 ' [1]"
export CALL_LOG="$test_dir/call.log" FAKE_OS=MINGW64_NT-10.0 FAKE_EXIT=0
cat > "$stub/uname" <<'SH'
#!/bin/bash
printf '%s\n' "$FAKE_OS"
SH
cat > "$stub/cygpath" <<'SH'
#!/bin/bash
[ "$1" = -aw ] || exit 90
printf 'C:%s\n' "$2"
SH
cat > "$stub/powershell.exe" <<'SH'
#!/bin/bash
printf '%s\n' "${MSYS_NO_PATHCONV:-}" "$@" > "$CALL_LOG"
exit "$FAKE_EXIT"
SH
chmod +x "$stub"/*
export PATH="$stub:$PATH"
bash -n "$repo_dir/install/windows.sh"

project="$test_dir/프로젝트 공백 ' [1]"
bash "$repo_dir/install/windows.sh" --agent=codex "$project"
mapfile -t args < "$CALL_LOG"
[ "${#args[@]}" -eq 10 ] || fail 'PowerShell 인자 개수가 달라짐'
[ "${args[0]}" = 1 ] || fail 'MSYS 자동 경로 변환을 끄지 않음'
[ "${args[1]}" = -NoProfile ] && [ "${args[4]}" = -File ] || fail 'PowerShell 파일 호출 누락'
[ "${args[2]}" = -ExecutionPolicy ] && [ "${args[3]}" = Bypass ] || fail '프로세스 실행 정책 누락'
[ "${args[5]}" = "C:$repo_dir/install/windows.ps1" ] || fail '스크립트 경로 변환 실패'
[ "${args[6]}" = -Agent ] && [ "${args[7]}" = codex ] || fail '에이전트 전달 실패'
[ "${args[8]}" = -Project ] && [ "${args[9]}" = "C:$project" ] || fail '프로젝트 경로 보존 실패'

(
    cd "$project"
    bash "$repo_dir/install/windows.sh"
)
mapfile -t args < "$CALL_LOG"
[ "${args[7]}" = claude ] && [ "${args[9]}" = "C:$project" ] || fail '기본 에이전트·현재 폴더 전달 실패'

# 공백·한글이 있는 저장소 경로도 PowerShell의 단일 인자로 보존한다.
copy="$test_dir/저장소 사본 ' [2]"
mkdir -p "$copy/lib" "$copy/install"
cp "$repo_dir/install/windows.sh" "$repo_dir/install/windows.ps1" "$copy/install/"
cp "$repo_dir/lib/setup-common.sh" "$copy/lib/"
bash "$copy/install/windows.sh" --agent claude "$project"
mapfile -t args < "$CALL_LOG"
[ "${args[5]}" = "C:$copy/install/windows.ps1" ] || fail '저장소 경로 보존 실패'

status=0
FAKE_EXIT=37 bash "$repo_dir/install/windows.sh" "$project" || status=$?
[ "$status" -eq 37 ] || fail 'PowerShell 실패 종료 코드가 바뀜'
for os in MINGW32_NT-10.0 MINGW64_NT-10.0; do
    FAKE_OS="$os" bash "$repo_dir/install/windows.sh" "$project"
done
for os in Linux Darwin MSYS_NT-10.0 CYGWIN_NT-10.0; do
    FAKE_OS="$os" bash "$repo_dir/install/windows.sh" "$project" >/dev/null 2>&1 && fail "지원하지 않는 환경 통과: $os"
done
bash "$repo_dir/install/windows.sh" --help | grep -q install/windows.sh || fail '도움말 누락'
for option in '--agent foo' '--agent' '--unknown'; do
    # 옵션별 실패를 확인하려고 의도적으로 단어 분리를 사용한다.
    bash "$repo_dir/install/windows.sh" $option >/dev/null 2>&1 && fail "잘못된 옵션 통과: $option"
done
bash "$repo_dir/install/windows.sh" "$project" extra >/dev/null 2>&1 && fail '복수 프로젝트 통과'
bash "$repo_dir/install/windows.sh" "$test_dir/없음" >/dev/null 2>&1 && fail '없는 프로젝트 통과'
bash "$repo_dir/install/windows.sh" "$repo_dir/README.md" >/dev/null 2>&1 && fail '디렉터리가 아닌 프로젝트 통과'

# 시스템 도구에 기대지 않는 최소 PATH로 필수 명령 누락을 재현한다.
ln -s "$(command -v dirname)" "$stub/dirname"
mv "$stub/powershell.exe" "$test_dir/powershell.exe"
out="$(PATH="$stub" /bin/bash "$repo_dir/install/windows.sh" 2>&1)" && fail 'PowerShell 없이 통과'
[[ "$out" == *powershell.exe* ]] || fail 'PowerShell 누락 안내 없음'
mv "$test_dir/powershell.exe" "$stub/powershell.exe"
mv "$stub/cygpath" "$test_dir/cygpath"
out="$(PATH="$stub" /bin/bash "$repo_dir/install/windows.sh" 2>&1)" && fail 'cygpath 없이 통과'
[[ "$out" == *cygpath* ]] || fail 'cygpath 누락 안내 없음'
echo 'Git Bash 진입점 테스트 통과'

#!/bin/bash
# setup-wsl.sh·setup-mac.sh·setup-windows.ps1의 에이전트 선택, 혼합 팀 판독, 플랫폼 사전 조건 안내를 스텁으로 검증한다.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
fail() {
    # 실패 사유를 출력하고 테스트를 중단한다.
    printf '실패: %s\n' "$*" >&2; exit 1
}

real_tmux="$(command -v tmux || true)"
real_git="$(command -v git)"   # 아래 스텁이 git을 가린다

# 외부 도구 스텁: 설치돼 있는 것처럼 동작해 실제 설치가 일어나지 않게 한다.
stub="$test_dir/stub"
mkdir -p "$stub/bin"
for c in tmux git curl python3 node claude rtk codex; do
    printf '#!/bin/bash\necho "%s 0.0.0"\n' "$c" > "$stub/bin/$c"
done
printf '#!/bin/bash\necho "ko_KR.utf8"\n' > "$stub/bin/locale"
printf '#!/bin/bash\necho "%s/prefix"\n' "$stub" > "$stub/bin/npm"
printf '#!/bin/bash\necho "BREW $*" >> "%s/brew.log"\n[ "$1" = --prefix ] && echo "%s"\nexit 0\n' "$test_dir" "$stub" > "$stub/bin/brew"
printf '#!/bin/bash\nexec /bin/bash "$@"\n' > "$stub/bin/bash"
gnubin="$stub/opt/coreutils/libexec/gnubin"; mkdir -p "$gnubin"
for c in timeout realpath; do printf '#!/bin/bash\nexit 0\n' > "$gnubin/$c"; done
chmod +x "$stub"/bin/* "$gnubin"/*
export PATH="$stub/bin:$PATH"

proj="$test_dir/proj"; mkdir -p "$proj/team"

# ── 1. 이름·잔여 참조 ───────────────────────────────────────────
for f in setup-wsl.sh setup-mac.sh lib/setup-common.sh; do bash -n "$repo_dir/$f"; done
[ ! -e "$repo_dir/setup-native.sh" ] || fail 'setup-native.sh가 남아 있음'
! "$real_git" -C "$repo_dir" grep -n 'setup-native' -- . ':!tests/' >/dev/null || fail 'setup-native 참조가 남아 있음'

# ── 2. WSL: 에이전트 선택·혼합 팀 ───────────────────────────────
out="$("$repo_dir/setup-wsl.sh" "$proj")"       # 저장소 기본 config.sh는 claude+codex 혼합
grep -q '설치 대상 공급자: claude codex' <<< "$out" || fail '혼합 팀이 둘 다 설치 대상이 아님'
printf 'MEMBER_AGENTS=(codex codex)\n' > "$proj/team/config.sh"   # 프로젝트 config가 저장소 것을 덮어씀
out="$("$repo_dir/setup-wsl.sh" "$proj")"
grep -q '설치 대상 공급자: codex' <<< "$out" && ! grep -q 'claude CLI' <<< "$out" || fail '프로젝트 config(codex)가 반영되지 않음'
printf 'MEMBER_AGENTS=("" "")\n' > "$proj/team/config.sh"          # 빈 값은 --agent 기본값을 따름
out="$("$repo_dir/setup-wsl.sh" --agent codex "$proj")"
grep -q '설치 대상 공급자: codex' <<< "$out" && ! grep -q 'claude CLI' <<< "$out" || fail '--agent codex가 반영되지 않음'
out="$("$repo_dir/setup-wsl.sh" --agent=claude "$proj")"
grep -q '설치 대상 공급자: claude' <<< "$out" && ! grep -q 'codex CLI' <<< "$out" || fail '--agent=claude가 반영되지 않음'
printf 'MEMBER_AGENTS=(gemini)\n' > "$proj/team/config.sh"
"$repo_dir/setup-wsl.sh" "$proj" >/dev/null 2>&1 && fail '잘못된 MEMBER_AGENTS를 통과시킴'
"$repo_dir/setup-wsl.sh" --agent foo "$proj" >/dev/null 2>&1 && fail '잘못된 --agent를 통과시킴'
rm "$proj/team/config.sh"

# 값 없는 옵션, 재실행(멱등), 공백 경로(프로젝트·저장소 모두)
for bad in "--agent" "--agent="; do
    err="$("$repo_dir/setup-wsl.sh" $bad 2>&1)" && fail "'$bad'를 통과시킴"
    [ -n "$err" ] || fail "'$bad' 오류 메시지 없음"
done
"$repo_dir/setup-wsl.sh" --agent >/dev/null 2>&1 && fail '값 없는 --agent를 통과시킴'
"$repo_dir/setup-wsl.sh" "$proj" extra >/dev/null 2>&1 && fail '프로젝트 경로 2개를 통과시킴'
"$repo_dir/setup-wsl.sh" "$test_dir/없는 경로" >/dev/null 2>&1 && fail '없는 프로젝트 경로를 통과시킴'
sp="$test_dir/공백 프로젝트 dir"; mkdir -p "$sp/team"; printf 'MEMBER_AGENTS=(codex)\n' > "$sp/team/config.sh"
first="$("$repo_dir/setup-wsl.sh" "$sp")"; second="$("$repo_dir/setup-wsl.sh" "$sp")"
[ "$first" = "$second" ] || fail '재실행 결과가 다름'
grep -q "setup-team.sh --agent claude $sp" <<< "$first" || fail '공백 프로젝트 경로가 안내에 보존되지 않음'
grep -q '설치 대상 공급자: codex' <<< "$first" || fail '공백 경로 프로젝트의 config를 못 읽음'
cp -r "$repo_dir" "$test_dir/저장소 사본 dir"
"$test_dir/저장소 사본 dir/setup-wsl.sh" "$sp" >/dev/null || fail '공백이 있는 저장소 경로에서 실패'
# 플랫폼 가드: macOS(uname=Darwin)에서는 setup-wsl.sh가 거부하고 setup-mac.sh를 안내한다.
mkdir "$test_dir/fakeuname"; printf '#!/bin/bash\necho Darwin\n' > "$test_dir/fakeuname/uname"; chmod +x "$test_dir/fakeuname/uname"
err="$(PATH="$test_dir/fakeuname:$PATH" "$repo_dir/setup-wsl.sh" "$proj" 2>&1)" && fail 'Darwin에서 setup-wsl.sh가 통과함'
grep -q 'setup-mac.sh' <<< "$err" || fail 'Darwin 거부 시 setup-mac.sh 안내 누락'

# WSL PATH: Windows(/mnt/*) 도구를 배제하고 기존 NVM 도구를 쓰며, 이미 있으면 설치하지 않는다.
(
    source "$repo_dir/lib/setup-common.sh"
    HOME="$test_dir/nvmhome"; mkdir -p "$HOME/.nvm/versions/node/v18.0.0/bin" "$HOME/.nvm/versions/node/v20.1.0/bin"
    PATH="/mnt/c/Program Files/nodejs:/usr/bin::/mnt/c/WINDOWS:/bin"
    setup_prepare_linux_path
    case ":$PATH:" in *:/mnt/*) exit 1 ;; esac
    [ "${PATH%%:*}" = "$HOME/.nvm/versions/node/v20.1.0/bin" ] && [[ "$PATH" == *":/usr/bin:/bin" ]]
) || fail 'setup_prepare_linux_path: /mnt 제거 또는 NVM 우선 실패'
nvmhome="$test_dir/nvmhome"; nvmbin="$nvmhome/.nvm/versions/node/v20.1.0/bin"; mkdir -p "$nvmbin"
for c in node npm claude rtk codex; do
    printf '#!/bin/bash\n[ "$1" = install ] && echo "NPM-INSTALL $*" >> "%s/npm.log"\necho "nvm-%s 1.0"\n' "$test_dir" "$c" > "$nvmbin/$c"
done
chmod +x "$nvmbin"/*
lean="$test_dir/lean"; mkdir -p "$lean"
for c in tmux git curl python3 sudo; do printf '#!/bin/bash\nexit 0\n' > "$lean/$c"; done
printf '#!/bin/bash\necho ko_KR.utf8\n' > "$lean/locale"; chmod +x "$lean"/*
rm -f "$test_dir/npm.log"
out="$(HOME="$nvmhome" PATH="/mnt/c/Program Files/nodejs:$lean:/usr/bin:/bin" "$repo_dir/setup-wsl.sh" "$proj")"
grep -q 'nvm-codex' <<< "$out" && grep -q 'nvm-claude' <<< "$out" && grep -q 'nvm-node' <<< "$out" || fail 'NVM의 node/claude/codex를 쓰지 않음'
[ ! -e "$test_dir/npm.log" ] || fail '이미 NVM에 있는 CLI를 재설치함'
# 한국어 locale이 없으면 locales·CJK 글꼴을 설치하고 locale을 만든다.
printf '#!/bin/bash\necho "SUDO $*" >> "%s/sudo.log"\n' "$test_dir" > "$lean/sudo"
printf '#!/bin/bash\n' > "$lean/locale"; chmod +x "$lean/sudo" "$lean/locale"
HOME="$nvmhome" PATH="$lean:/usr/bin:/bin" "$repo_dir/setup-wsl.sh" "$proj" >/dev/null
grep -q 'SUDO apt-get install -y .*locales fonts-noto-cjk' "$test_dir/sudo.log" && grep -q 'SUDO locale-gen ko_KR.UTF-8' "$test_dir/sudo.log" \
    || fail "locale 없음 처리 누락: $(cat "$test_dir/sudo.log")"
printf '#!/bin/bash\necho ko_KR.utf8\n' > "$lean/locale"

# ── 3. macOS ────────────────────────────────────────────────────
[ "$(uname -s)" = Darwin ] || {
    "$repo_dir/setup-mac.sh" "$proj" >/dev/null 2>&1 && fail 'macOS가 아닌데 통과함'
}
export SETUP_ALLOW_NON_DARWIN=1
"$repo_dir/setup-mac.sh" --agent >/dev/null 2>&1 && fail 'mac: 값 없는 --agent를 통과시킴'
printf 'MEMBER_AGENTS=(claude codex)\n' > "$proj/team/config.sh"
out="$("$repo_dir/setup-mac.sh" "$proj")"
grep -q '설치 대상 공급자: claude codex' <<< "$out" || fail 'mac 혼합 팀 판독 실패'
grep -q "$stub/bin/bash $repo_dir/setup-team.sh --agent claude $proj" <<< "$out" || fail 'Homebrew bash 실행 안내 누락'
! grep -q 'install' "$test_dir/brew.log" || fail '이미 있는 의존성을 재설치함'
# bash 3.x만 있으면 거짓 성공 없이 실패해야 한다.
printf '#!/bin/bash\necho 3\n' > "$stub/bin/bash"
out="$("$repo_dir/setup-mac.sh" "$proj" 2>&1)" && fail 'bash 3.x에서 성공으로 끝남'
grep -q 'bash 4+ 설치에 실패' <<< "$out" || fail 'bash 3.x 실패 사유 누락'
grep -q 'BREW install bash' "$test_dir/brew.log" || fail 'bash 설치를 시도하지 않음'
printf '#!/bin/bash\nexec /bin/bash "$@"\n' > "$stub/bin/bash"
# GNU coreutils(timeout·realpath)가 없으면 설치를 시도하고, 끝내 없으면 실패한다.
mv "$gnubin" "$gnubin.off"
out="$("$repo_dir/setup-mac.sh" "$proj" 2>&1)" && fail 'coreutils 없이 성공으로 끝남'
grep -q 'GNU coreutils' <<< "$out" && grep -q 'BREW install coreutils' "$test_dir/brew.log" || fail 'coreutils 설치 시도/실패 안내 누락'
mv "$gnubin.off" "$gnubin"
# 재실행: 같은 입력이면 같은 결과
[ "$("$repo_dir/setup-mac.sh" "$proj")" = "$("$repo_dir/setup-mac.sh" "$proj")" ] || fail 'mac 재실행 결과가 다름'
# brew가 없으면 안내 후 실패한다.
rm "$stub/bin/brew"
out="$("$repo_dir/setup-mac.sh" "$proj" 2>&1)" && fail 'brew 없이 성공으로 끝남'
grep -q 'Homebrew가 없습니다' <<< "$out" || fail 'Homebrew 안내 누락'
rm -f "$proj/team/config.sh"

# ── 3b. 런타임 가드: 파인·훅이 bash 3.2로 뜨지 않게 한다 ─────────
for f in setup-team.sh bin/say; do
    [ "$(head -1 "$repo_dir/$f")" = '#!/usr/bin/env bash' ] || fail "$f 셔뱅이 env bash가 아님"
    grep -q 'bash 4+ 필요' "$repo_dir/$f" || fail "$f에 bash 4+ 가드 없음"
done
# 최종 PATH에서 Homebrew bash·GNU sort·timeout이 시스템 /usr/bin·/bin보다 먼저 잡혀야 한다.
fakebrew="$test_dir/brew prefix"; mkdir -p "$fakebrew/bin" "$fakebrew/opt/coreutils/libexec/gnubin"
ln -s /bin/bash "$fakebrew/bin/bash"
for c in sort timeout realpath; do printf '#!/bin/bash\nexit 0\n' > "$fakebrew/opt/coreutils/libexec/gnubin/$c"; done
chmod +x "$fakebrew"/opt/coreutils/libexec/gnubin/*
sed -n '/^# ── PATH 보강/,/^GREEN=/p' "$repo_dir/setup-team.sh" | sed '$d' > "$test_dir/path-block.sh"
# 우선순위 조정은 macOS(uname=Darwin)에서만 일어난다: Linux/WSL에서는 PATH 앞에 아무것도 붙지 않는다.
linux_bash="$(env -i HOME="$test_dir" HOMEBREW_PREFIX="$fakebrew" PATH=/usr/bin:/bin /bin/bash -c 'source "$1"; command -v bash' _ "$test_dir/path-block.sh")"
[ "$linux_bash" != "$fakebrew/bin/bash" ] || fail 'Linux에서 Homebrew PATH가 앞에 붙음'
mkdir -p "$test_dir/darwin-uname"; printf '#!/bin/bash\necho Darwin\n' > "$test_dir/darwin-uname/uname"; chmod +x "$test_dir/darwin-uname/uname"
resolved="$(env -i HOME="$test_dir" HOMEBREW_PREFIX="$fakebrew" PATH="$test_dir/darwin-uname:/usr/bin:/bin" /bin/bash -c \
    'source "$1"; command -v bash; command -v sort; command -v timeout; command -v realpath' _ "$test_dir/path-block.sh")"
[ "$(sed -n 1p <<< "$resolved")" = "$fakebrew/bin/bash" ] || fail "최종 PATH의 bash가 Homebrew 것이 아님: $resolved"
for i in 2 3 4; do
    [[ "$(sed -n ${i}p <<< "$resolved")" == "$fakebrew/opt/coreutils/libexec/gnubin/"* ]] || fail "최종 PATH의 GNU 도구가 시스템 것에 가려짐: $resolved"
done

# 기존 tmux 서버가 최소 PATH로 떠 있어도 팀 세션·run-shell은 런처가 준비한 PATH를 받는다. 전역 환경은 그대로다.
if [ -n "$real_tmux" ]; then
    sock="$test_dir/tmux-path.sock"
    tmux() { "$real_tmux" -S "$sock" "$@"; }
    trap 'tmux kill-server 2>/dev/null || true; rm -rf "$test_dir"' EXIT
    env -i PATH=/usr/bin:/bin HOME="$test_dir" "$real_tmux" -S "$sock" new-session -d -s pre
    global_before="$(tmux show-environment -g PATH)"
    eval "$(sed -n '/^create_team_session() {$/,/^}$/p' "$repo_dir/setup-team.sh")"
    SESSION=team TEAM_PATH="$fakebrew/bin:/usr/bin:/bin"
    create_team_session
    [ "$(tmux show-environment -t team PATH)" = "PATH=$TEAM_PATH" ] || fail '팀 세션 환경에 TEAM_PATH 누락'
    [ "$(tmux show-environment -g PATH)" = "$global_before" ] || fail 'tmux 전역 PATH를 바꿈'
    tmux run-shell -t team "printf %s \"\$PATH\" > '$test_dir/runshell.path'"
    [ "$(cat "$test_dir/runshell.path")" = "$TEAM_PATH" ] || fail 'run-shell이 팀 세션 PATH를 받지 못함'
    tmux kill-server
else
    echo '참고: tmux가 없어 tmux PATH 전파 검사를 건너뜁니다.'
fi
grep -q 'export PATH=$(shell_quote "${TEAM_PATH:-$PATH}")' "$repo_dir/setup-team.sh" || fail '파인 시작 명령이 TEAM_PATH를 export하지 않음'
! grep -qF '):\$PATH' "$repo_dir/setup-team.sh" || fail '파인 PATH가 tmux 서버 PATH에 의존함'

# ── 4. Windows: tmux 한계를 정직하게 안내하고 WSL로 위임 ─────────
ps1="$repo_dir/setup-windows.ps1"
grep -q 'wsl.exe' "$ps1" && grep -q 'setup-wsl.sh' "$ps1" || fail 'WSL 위임 누락'
grep -q 'wsl.exe -e wslpath -a' "$ps1" || fail 'wslpath는 -e로 셸 해석을 우회해야 함(UNC 역슬래시 보존)'
grep -q 'Get-Location' "$ps1" || fail '-Project 생략 시 현재 폴더 전달 누락'
grep -q -- '--cd' "$ps1" && grep -q '네이티브 CLI' "$ps1" || fail 'Windows 범위 구분 안내 누락'
grep -q 'tmux는 네이티브 Windows에서 동작하지 않' "$ps1" || fail 'tmux 요건 안내 누락'
! grep -qE 'choco|winget|scoop' "$ps1" || fail '네이티브 tmux 설치를 시도하면 안 됨'
if command -v pwsh >/dev/null; then
    # -Command 뒤 인자는 $args로 전달되지 않으므로 -File 검증 스크립트에 경로를 인자로 넘긴다.
    cat > "$test_dir/parse.ps1" <<'PS'
param([string]$Path)
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { [Console]::Error.WriteLine($_.ToString()) }; exit 1 }
PS
    pwsh -NoProfile -NonInteractive -File "$test_dir/parse.ps1" -Path "$ps1" || fail 'ps1 구문 오류'
else
    echo '참고: pwsh가 없어 setup-windows.ps1은 정적 검사만 했습니다.'
fi

echo 'setup_platforms_test 통과'

#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/busy" "$test_dir/report" "$test_dir/queue"

cat > "$test_dir/bin/tmux" <<'EOF'
#!/bin/bash
case "$1" in
    display-message)
        format="${*: -1}"
        case "$format" in
            '#{session_name}:#{window_index}.#{pane_index}') printf '%s\n' 'demo:0.1' ;;
            '#{session_id}:#{pane_id}') printf '%s\n' "${FAKE_TMUX_STATE:-\$7:%11}" ;;
        esac
        ;;
    capture-pane)
        if [ -n "${FAKE_CAPTURE_SCREEN:-}" ]; then
            printf '%s\n' "$FAKE_CAPTURE_SCREEN"
        elif [ -n "${FAKE_CAPTURE_MSG:-}" ]; then
            enter_count="$(cat "$FAKE_ENTER_COUNT_FILE" 2>/dev/null || printf '0')"
            if [ "$enter_count" -lt "${FAKE_TMUX_STICKY_UNTIL:-0}" ]; then
                printf '› %s\n' "$FAKE_CAPTURE_MSG"
            fi
        else
            printf '\n'
        fi
        ;;
    send-keys)
        printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
        if [ "${*: -1}" = "Enter" ] && [ -n "${FAKE_ENTER_COUNT_FILE:-}" ]; then
            enter_count="$(cat "$FAKE_ENTER_COUNT_FILE" 2>/dev/null || printf '0')"
            printf '%s\n' "$((enter_count + 1))" > "$FAKE_ENTER_COUNT_FILE"
        fi
        ;;
    list-panes)
        case "$*" in
            *'#{@role}'*) printf '%s\n' "${FAKE_ROLE_PANES:-1 architect}" ;;
            *) printf '%s\n' "${FAKE_TITLE_PANES:-1 ARCHITECT}" ;;
        esac
        ;;
esac
EOF
chmod +x "$test_dir/bin/tmux"

export PATH="$test_dir/bin:$PATH"
export SAY_BUSY_DIR="$test_dir/busy"
export SAY_REPORT_DIR="$test_dir/report"
export SAY_QUEUE_DIR="$test_dir/queue"
export FAKE_TMUX_LOG="$test_dir/tmux.log"
export FAKE_ENTER_COUNT_FILE="$test_dir/enter-count"

# 역할 주소는 표시용 제목보다 pane @role을 우선한다.
FAKE_ROLE_PANES='1 architect' FAKE_TITLE_PANES='1 DISPLAY_NAME' FAKE_TMUX_STATE='$7:%10' \
    "$repo_dir/bin/say" architect 'role-addressed message'
grep -q -- '-t :0.1 -l -- role-addressed message' "$test_dir/tmux.log"

# @role이 없는 기존 pane은 이전처럼 제목으로 찾아야 한다.
FAKE_ROLE_PANES='2 ' FAKE_TITLE_PANES='2 ARCHITECT' FAKE_TMUX_STATE='$7:%9' \
    "$repo_dir/bin/say" architect 'title-fallback message'
grep -q -- '-t :0.2 -l -- title-fallback message' "$test_dir/tmux.log"

# 이전 세대 marker는 현재 tmux 고유 ID와 키가 다르므로 전송을 막지 않는다.
touch "$test_dir/busy/_6__10"
FAKE_TMUX_STATE='$7:%11' "$repo_dir/bin/say" demo:0.1 'new generation message'
test -f "$test_dir/busy/_7__11"
test "$(grep -c 'new generation message' "$test_dir/tmux.log")" -eq 1

# TUI가 앞선 Enter들을 무시해도 say는 간격을 두고 다시 제출한다.
printf '0\n' > "$FAKE_ENTER_COUNT_FILE"
FAKE_CAPTURE_MSG='retry message' FAKE_TMUX_STICKY_UNTIL=2 \
    FAKE_TMUX_STATE='$7:%12' "$repo_dir/bin/say" demo:0.1 'retry message'
test "$(cat "$FAKE_ENTER_COUNT_FILE")" -eq 3

# 큐 전송의 첫 deliver가 실패해도 dequeue하지 않고 다음 루프에서 재시도한다.
rm -f "$test_dir/busy/_7__12"
printf '0\n' > "$FAKE_ENTER_COUNT_FILE"
printf '%s\n' 'queued retry message' > "$test_dir/queue/demo_0_1"
FAKE_CAPTURE_MSG='queued retry message' FAKE_TMUX_STICKY_UNTIL=5 \
    FAKE_TMUX_STATE='$7:%13' "$repo_dir/bin/say" --drain demo:0.1

for _ in $(seq 1 100); do
    [ ! -e "$test_dir/queue/demo_0_1" ] && break
    sleep 0.1
done

test ! -e "$test_dir/queue/demo_0_1"
test "$(cat "$FAKE_ENTER_COUNT_FILE")" -ge 6

# 살아 있는 owner의 lock은 오래됐더라도 회수하지 않는다.
rm -f "$test_dir/busy/_7__11"
printf '%s\n' 'must stay queued' > "$test_dir/queue/demo_0_1"
mkdir "$test_dir/queue/demo_0_1.lock"
printf '%s %s\n' "$$" "$(awk '{print $22}' "/proc/$$/stat")" > "$test_dir/queue/demo_0_1.lock/owner"
touch -d '10 seconds ago' "$test_dir/queue/demo_0_1.lock"
FAKE_TMUX_STATE='$7:%11' "$repo_dir/bin/say" --drain demo:0.1
sleep 0.2
test -s "$test_dir/queue/demo_0_1"
test -d "$test_dir/queue/demo_0_1.lock"
rm -f "$test_dir/queue/demo_0_1.lock/owner" "$test_dir/queue/demo_0_1"
rmdir "$test_dir/queue/demo_0_1.lock"

# PID owner가 없는 오래된 lock도 --drain이 회수하고 기존 큐만 전달한다.
printf '%s\n' 'queued message' > "$test_dir/queue/demo_0_1"
mkdir "$test_dir/queue/demo_0_1.lock"
touch -d '10 seconds ago' "$test_dir/queue/demo_0_1.lock"
FAKE_TMUX_STATE='$7:%11' "$repo_dir/bin/say" --drain demo:0.1

for _ in $(seq 1 50); do
    [ ! -e "$test_dir/queue/demo_0_1" ] && [ ! -e "$test_dir/queue/demo_0_1.lock" ] && break
    sleep 0.1
done

test ! -e "$test_dir/queue/demo_0_1"
test ! -e "$test_dir/queue/demo_0_1.lock"
test "$(grep -c 'queued message' "$test_dir/tmux.log")" -eq 1

# Stop 훅용 drain-one은 FIFO의 첫 메시지만 전달하고 나머지는 다음 Stop까지 보존한다.
rm -f "$test_dir/busy/_7__11"
printf '%s\n' 'first after stop' 'second after stop' > "$test_dir/queue/demo_0_1"
FAKE_TMUX_STATE='$7:%11' "$repo_dir/bin/say" --drain-one demo:0.1
test -s "$test_dir/queue/demo_0_1"
test "$(wc -l < "$test_dir/queue/demo_0_1")" -eq 1
test "$(sed -n '1p' "$test_dir/queue/demo_0_1")" = 'second after stop'
test "$(grep -c 'first after stop' "$test_dir/tmux.log")" -eq 1
test "$(grep -c 'second after stop' "$test_dir/tmux.log" || true)" -eq 0
test ! -e "$test_dir/queue/demo_0_1.lock"

# Esc 인터럽트로 Stop 훅 없이 끊긴 파인은 마커가 남아 있어도 유휴로 보고 바로 보낸다.
rm -f "$test_dir/queue/demo_0_1"
touch "$test_dir/busy/_7__14"
FAKE_CAPTURE_SCREEN=$'  ⎿  Interrupted · What should Claude do instead?\n\n> \n  ⏵⏵ bypass permissions on\n\n\n' \
    FAKE_TMUX_STATE='$7:%14' "$repo_dir/bin/say" demo:0.1 'after interrupt'
test "$(grep -c 'after interrupt' "$test_dir/tmux.log")" -eq 1
test ! -e "$test_dir/queue/demo_0_1"

# 인터럽트 문구가 남아 있어도 스피너가 돌면(새 턴 진행 중) busy로 본다.
touch "$test_dir/busy/_7__15"
printf '%s\n' 'wait for turn' > "$test_dir/queue/demo_0_1"
FAKE_CAPTURE_SCREEN=$'  ⎿  Interrupted · What should Claude do instead?\n> next task\n✻ Working… (3s · esc to interrupt)' \
    FAKE_TMUX_STATE='$7:%15' "$repo_dir/bin/say" --drain-one demo:0.1
test -f "$test_dir/busy/_7__15"
test "$(grep -c 'wait for turn' "$test_dir/tmux.log" || true)" -eq 0
rm -f "$test_dir/queue/demo_0_1"

# Codex의 작업 중 표시는 Claude와 같은 경과시간 형식이므로 마커를 유지한다.
touch "$test_dir/busy/_7__16"
printf '%s\n' 'wait for Codex turn' > "$test_dir/queue/demo_0_1"
FAKE_CAPTURE_SCREEN='• Planning work screen capture (13s • esc to interrupt)' \
    FAKE_TMUX_STATE='$7:%16' "$repo_dir/bin/say" --drain-one demo:0.1
test -f "$test_dir/busy/_7__16"
test "$(grep -c 'wait for Codex turn' "$test_dir/tmux.log" || true)" -eq 0
rm -f "$test_dir/queue/demo_0_1"

# 스피너 없는 stale 마커는 시작 유예를 넘기면 회수해 즉시 전송한다.
touch "$test_dir/busy/_7__17"
touch -d '46 seconds ago' "$test_dir/busy/_7__17"
FAKE_TMUX_STATE='$7:%17' "$repo_dir/bin/say" demo:0.1 'after stale marker'
test "$(grep -c 'after stale marker' "$test_dir/tmux.log")" -eq 1
test ! -e "$test_dir/queue/demo_0_1"

# 스피너가 아직 렌더되지 않은 시작 직후에는 마커를 유지한다.
touch "$test_dir/busy/_7__18"
printf '%s\n' 'within startup grace' > "$test_dir/queue/demo_0_1"
FAKE_TMUX_STATE='$7:%18' "$repo_dir/bin/say" --drain-one demo:0.1
test -f "$test_dir/busy/_7__18"
test -s "$test_dir/queue/demo_0_1"
rm -f "$test_dir/queue/demo_0_1"

# 짧은 probe는 입력창이나 Codex 안내 문구와 겹쳐도 재전송하지 않는다.
for short_msg in x 1234567; do
    FAKE_CAPTURE_SCREEN="› $short_msg" SAY_NOWAIT=1 \
        "$repo_dir/bin/say" demo:0.1 "$short_msg"
done
FAKE_CAPTURE_SCREEN=$'› Ask Codex to do anything\n  Codex footer' SAY_NOWAIT=1 \
    "$repo_dir/bin/say" demo:0.1 x

# 전송된 메시지와 일치하는 출력/안내 문구는 입력창 잔류로 오인하지 않는다.
FAKE_CAPTURE_SCREEN=$'› delivered footer message\n› \n  delivered footer message' SAY_NOWAIT=1 \
    "$repo_dir/bin/say" demo:0.1 'delivered footer message'

# 8자 이상 메시지가 마지막 입력 프롬프트에 남아 있으면 실패해야 한다.
for prompt in '>' '›'; do
    if FAKE_CAPTURE_SCREEN="  $prompt 12345678" SAY_NOWAIT=1 \
        "$repo_dir/bin/say" demo:0.1 '12345678'; then
        echo "입력 프롬프트 잔류를 감지하지 못했습니다: $prompt" >&2
        exit 1
    fi
    test ! -e "$test_dir/busy/_7__11"
done

# 같은 내용의 연속 항목도 각각 3회까지만 시도하고 로그를 남긴 뒤 제거한다.
printf '%s\n' 'permanent queued failure' 'permanent queued failure' > "$test_dir/queue/demo_0_1"
for expected_count in 3 6; do
    FAKE_CAPTURE_SCREEN='› permanent queued failure' FAKE_TMUX_STATE='$7:%19' \
        timeout 15s "$repo_dir/bin/say" --drain-one demo:0.1
    test "$(grep -c -- '-l -- permanent queued failure' "$test_dir/tmux.log")" -eq "$expected_count"
    test "$(grep -c 'permanent queued failure' "$test_dir/queue/dropped.log")" -eq "$((expected_count / 3))"
done
test ! -s "$test_dir/queue/demo_0_1"
test ! -e "$test_dir/queue/demo_0_1.lock"

# 백그라운드 watcher도 상한에서 종료하고 stderr와 무관하게 폐기 로그를 보존한다.
printf '%s\n' 'background queued failure' > "$test_dir/queue/demo_0_1"
FAKE_CAPTURE_SCREEN='> background queued failure' FAKE_TMUX_STATE='$7:%20' \
    "$repo_dir/bin/say" --drain demo:0.1
for _ in $(seq 1 100); do
    [ ! -e "$test_dir/queue/demo_0_1" ] && [ ! -e "$test_dir/queue/demo_0_1.lock" ] && break
    sleep 0.1
done
test ! -e "$test_dir/queue/demo_0_1"
test ! -e "$test_dir/queue/demo_0_1.lock"
test "$(grep -c -- '-l -- background queued failure' "$test_dir/tmux.log")" -eq 3
grep -q 'attempts=3 message=background queued failure' "$test_dir/queue/dropped.log"

echo 'say tests passed'

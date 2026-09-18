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
                printf '%s\n' "$FAKE_CAPTURE_MSG"
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
        printf '1 ARCHITECT\n'
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

echo 'say tests passed'

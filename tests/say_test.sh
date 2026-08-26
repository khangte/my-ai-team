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
        printf '\n'
        ;;
    send-keys)
        printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
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

# 이전 세대 marker는 현재 tmux 고유 ID와 키가 다르므로 전송을 막지 않는다.
touch "$test_dir/busy/_6__10"
FAKE_TMUX_STATE='$7:%11' "$repo_dir/bin/say" demo:0.1 'new generation message'
test -f "$test_dir/busy/_7__11"
test "$(grep -c 'new generation message' "$test_dir/tmux.log")" -eq 1

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

echo 'say tests passed'

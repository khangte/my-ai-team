#!/bin/bash
# 기본 모델·추론 설정 상속, tmux 번호 기준 정규화, 경로의 글롭 문자 처리를 검증한다.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_dir/setup-team.sh"
bash -n "$script"
test_dir="$(mktemp -d)"
trap 'for s in "$test_dir"/tmux-*.sock; do command tmux -S "$s" kill-server 2>/dev/null || true; done; rm -rf "$test_dir"' EXIT
fail() { printf '실패: %s\n' "$*" >&2; exit 1; }

load_functions() {
    local name
    for name in "$@"; do
        eval "$(sed -n "/^${name}() {\$/,/^}\$/p" "$script")"
    done
}
load_functions codex_default_model_config write_codex_role_plugins codex_plugin_cache \
    codex_shared_plugin_cache link_codex_base_assets prepare_codex_role_home \
    start_codex_in_pane shell_quote create_team_session
TEAM_PATH="$PATH"
YELLOW='' RED='' GREEN='' NC=''
sleep() { :; }

# ── 1. 기본 모델·추론 설정 상속 ─────────────────────────────────
base_codex_home="$test_dir/base"
declare -A CODEX_PLUGIN_ROLES=([sample@local]='developer')
mkdir -p "$base_codex_home"
write_base() { printf '%s' "$1" > "$base_codex_home/config.toml"; }
toml_get() { # <파일> <점 경로> : 최상위·테이블 값을 JSON으로 출력(없으면 null)
    python3 -I - "$1" "$2" <<'PY'
import json, sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
for key in sys.argv[2].split("/"):
    data = data.get(key) if isinstance(data, dict) else None
print(json.dumps(data))
PY
}

write_base $'model = "model-a"\nmodel_reasoning_effort = "low"\n\n[projects."/x"]\nmodel = "should-not-copy"\ntrust_level = "trusted"\n'
role_home="$test_dir/team/developer/.codex-home"
write_codex_role_plugins developer "$role_home"
[ "$(toml_get "$role_home/config.toml" model)" = '"model-a"' ] || fail '기본 모델이 상속되지 않음'
[ "$(toml_get "$role_home/config.toml" model_reasoning_effort)" = '"low"' ] || fail '기본 추론 강도가 상속되지 않음'
[ "$(toml_get "$role_home/config.toml" projects)" = 'null' ] || fail '사용자 설정 전체가 복사됨'
[ "$(toml_get "$role_home/config.toml" plugins/_default/enabled)" = 'false' ] || fail '플러그인 기본 차단 누락'
[ "$(toml_get "$role_home/config.toml" plugins/sample@local/enabled)" = 'true' ] || fail '역할 플러그인 활성화 누락'
grep -qF 'should-not-copy' "$role_home/config.toml" && fail '테이블 안의 model이 복사됨'

# 기존 .team 재사용: 사용자 기본 설정이 바뀌면 재실행 후 따라간다(이전 값에 고정되지 않는다).
write_base $'model = "model-b"\nmodel_reasoning_effort = "high"\n'
write_codex_role_plugins developer "$role_home"
[ "$(toml_get "$role_home/config.toml" model)" = '"model-b"' ] || fail '바뀐 기본 모델이 반영되지 않음'
[ "$(toml_get "$role_home/config.toml" model_reasoning_effort)" = '"high"' ] || fail '바뀐 기본 추론 강도가 반영되지 않음'
# 사용자 설정에 키가 없거나 파일이 없어도 정상이고, 이전 값이 남지 않는다.
write_base $'[projects."/x"]\ntrust_level = "trusted"\n'
write_codex_role_plugins developer "$role_home"
[ "$(toml_get "$role_home/config.toml" model)" = 'null' ] && [ "$(toml_get "$role_home/config.toml" model_reasoning_effort)" = 'null' ] || fail '키가 없는데 이전 값이 남음'
rm "$base_codex_home/config.toml"
write_codex_role_plugins developer "$role_home"
[ "$(toml_get "$role_home/config.toml" plugins/sample@local/enabled)" = 'true' ] || fail '기본 설정 파일 없음에서 실패'
# 기본 홈은 읽기만 한다.
write_base $'model = "model-a"\n'
before="$(sha256sum < "$base_codex_home/config.toml")"
write_codex_role_plugins developer "$role_home"
[ "$(sha256sum < "$base_codex_home/config.toml")" = "$before" ] || fail '기본 홈 config가 수정됨'

# MEMBERS의 명시 값은 실행 인자로 전달되고, 비우면 인자가 없어 상속값이 쓰인다(재실행 A→B, 명시→빈칸).
PROJECT_DIR="$test_dir/project" TEAM_SKILLS_ROOT="$test_dir/team" BIN_DIR="$test_dir/bin"
write_codex_role_agents() { :; }
pane_state_key() { printf 'key'; }
wait_for_pane() { return 0; }
tmux() {
    [[ "${1:-}" != send-keys || "${4:-}" != "cd "* ]] || printf '%s' "$4" > "$test_dir/sent_cmd"
    [[ "${1:-}" != capture-pane ]] || printf 'Ask Codex to do anything\n'
}
mkdir -p "$test_dir/bin" "$test_dir/fakebin"; printf '#!/bin/bash\n' > "$test_dir/fakebin/codex"; chmod +x "$test_dir/fakebin/codex"
PATH="$test_dir/fakebin:$PATH"
sent() { start_codex_in_pane s:0.1 "$1" developer "$2"; cat "$test_dir/sent_cmd"; }
cmd="$(sent model-a high)"
[[ "$cmd" == *"--model 'model-a'"* && "$cmd" == *'model_reasoning_effort="high"'* ]] || fail '명시 값이 인자로 전달되지 않음'
cmd="$(sent model-b medium)"
[[ "$cmd" == *"--model 'model-b'"* && "$cmd" != *"model-a"* && "$cmd" == *'model_reasoning_effort="medium"'* ]] || fail '재실행 모델 A→B 변경 미반영'
cmd="$(sent '' '')"
[[ "$cmd" != *"--model"* && "$cmd" != *"model_reasoning_effort"* ]] || fail '명시→빈칸인데 이전 인자가 남음'
write_base $'model = "user-default"\nmodel_reasoning_effort = "low"\n'
write_codex_role_plugins developer "$role_home"
[ "$(toml_get "$role_home/config.toml" model)" = '"user-default"' ] || fail '빈칸일 때 사용자 기본 모델이 쓰이지 않음'

# ── 2. tmux 창·파인 번호: 사용자 설정이 1부터여도 팀 세션은 0부터 ──────
unset -f tmux
tmux() { command tmux -S "$sock" -f "$test_dir/tmux.conf" "$@"; }
SESSION=team1
for mode in 0 1; do
    sock="$test_dir/tmux-$mode.sock"   # 모드마다 별도 서버를 써서 종료 경합을 피한다
    printf 'set -g base-index %s\nset -g pane-base-index %s\n' "$mode" "$mode" > "$test_dir/tmux.conf"
    tmux new-session -d -s other -x 100 -y 30
    create_team_session
    for ((i = 0; i < 2; i++)); do tmux split-window -t "$SESSION:0.$i" -h; done
    panes="$(tmux list-panes -t "$SESSION:0" -F '#{session_name}:#{window_index}.#{pane_index}' | tr '\n' ' ')"
    [ "$panes" = 'team1:0.0 team1:0.1 team1:0.2 ' ] || fail "base-index=$mode: 파인 주소 불일치: $panes"
    [ "$(tmux list-windows -t "$SESSION" -F '#{window_index}' | tr '\n' ' ')" = '0 ' ] || fail "base-index=$mode: 창 번호 불일치"
    # 다른 세션과 전역 설정은 그대로다.
    [ "$(tmux show-options -gv pane-base-index)" = "$mode" ] && [ "$(tmux show-options -gv base-index)" = "$mode" ] || fail "base-index=$mode: 전역 설정이 바뀜"
    [ "$(tmux list-panes -t other -F '#{pane_index}')" = "$mode" ] || fail "base-index=$mode: 다른 세션 파인 번호가 바뀜"
    tmux set-option -p -t "$SESSION:0.2" @role dev
    [ "$(tmux list-panes -t "$SESSION:0" -F '#{pane_index} #{@role}' | grep ' dev$' | cut -d' ' -f1)" = 2 ] || fail "base-index=$mode: @role 주소 불일치"
    tmux kill-server
done

# ── 3. 경로의 [ ] * ? 는 글롭이 아니라 글자로 취급한다 ──────────────
make_cache() { # <홈> <plugin@mp> <버전>
    local dir="$1/plugins/cache/${2##*@}/${2%@*}/$3"
    mkdir -p "$dir/.codex-plugin"; : > "$dir/.codex-plugin/plugin.json"
}
for weird in 'project[1]' 'pro*ject' 'pro?ject' 'pro[a-z]ject'; do
    home="$test_dir/$weird/.team/developer/.codex-home"
    make_cache "$home" sample@local 1.0
    # 글롭이 살아 있으면 잡힐 수 있는 형제 경로: 비교용으로 매칭 후보를 만든다.
    mkdir -p "$test_dir/projectX/.team/developer/.codex-home/plugins/cache/local/sample/9.9/.codex-plugin"
    : > "$test_dir/projectX/.team/developer/.codex-home/plugins/cache/local/sample/9.9/.codex-plugin/plugin.json"
    found="$(codex_plugin_cache "$home" sample@local)" || fail "$weird: 설치본을 못 찾음"
    [ "$found" = "$home/plugins/cache/local/sample/1.0" ] || fail "$weird: 다른 경로를 잡음: $found"
    # 재사용: 이 홈의 설치본을 다른 역할이 연결해서 쓴다.
    base_codex_home="$test_dir/emptybase" codex_assets_home="$test_dir/noassets" TEAM_SKILLS_ROOT="$test_dir/$weird/.team"
    other="$TEAM_SKILLS_ROOT/reviewer/.codex-home"
    codex() { printf 'codex %s\n' "$*" >> "$test_dir/calls"; }
    : > "$test_dir/calls"
    CODEX_PLUGIN_ROLES=([sample@local]='reviewer')
    out="$(prepare_codex_role_home reviewer "$other")"
    [[ "$out" == *"sample@local 로컬에 이미 설치됨(다른 홈 설치본 재사용) → reviewer"* ]] || fail "$weird: 재사용 실패: $out"
    ! grep -q 'plugin add' "$test_dir/calls" || fail "$weird: 재사용 대신 재설치"
    rm -rf "$test_dir/$weird" "$test_dir/projectX"
done

# 기존 동작 보존: 다른 마켓플레이스의 동명 플러그인·빈 캐시는 설치본이 아니고, 여러 버전 중 최신을 고른다.
home="$test_dir/home"
make_cache "$home" sample@other 1.0
mkdir -p "$home/plugins/cache/local/sample/empty"
! codex_plugin_cache "$home" sample@local >/dev/null || fail '다른 마켓플레이스/빈 캐시를 설치본으로 오인'
make_cache "$home" sample@local 1.2; make_cache "$home" sample@local 1.10; make_cache "$home" sample@local 1.9
[ "$(codex_plugin_cache "$home" sample@local)" = "$home/plugins/cache/local/sample/1.10" ] || fail '최신 버전 선택 불일치'

printf 'setup-team round3 테스트 통과\n'

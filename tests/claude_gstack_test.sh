#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/tests/lib.sh"
load_functions install_claude_gstack link_plugin_skills link_owned_skill team_owned_record
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
GSTACK_DIR="$test_dir/home/.claude/skills/gstack"
TEAM_SKILLS_ROOT="$test_dir/team dir"
YELLOW='' GREEN='' NC=''
MEMBER_NAMES=(lead backend reviewer)
MEMBER_AGENTS=(claude claude codex)
PANE_COUNT=3
declare -A CLAUDE_GSTACK_SKILL_SETS=([lead]='spec' [backend]='health' [reviewer]='review')
export TEST_GSTACK_LOG="$test_dir/setup.log"
bun() { :; }

git() {
    [ "$*" = "clone --single-branch --depth 1 https://github.com/garrytan/gstack.git $GSTACK_DIR -q" ]
    mkdir -p "$GSTACK_DIR/health"
    printf '# Health\n' > "$GSTACK_DIR/health/SKILL.md"
    cat > "$GSTACK_DIR/setup" <<'SETUP'
#!/usr/bin/env bash
set -eu
[ "$*" = '--host claude' ]
printf 'setup\n' >> "$TEST_GSTACK_LOG"
SETUP
    chmod +x "$GSTACK_DIR/setup"
}

# 처음에는 공식 setup을 한 번 실행하고, 설치본이 있으면 다시 실행하지 않는다.
install_claude_gstack >/dev/null
install_claude_gstack >/dev/null
test "$(cat "$TEST_GSTACK_LOG")" = setup

# Claude 역할에 배정이 없으면 설치하지 않는다(Codex 역할 배정은 무시).
rm -rf "$GSTACK_DIR" "$TEST_GSTACK_LOG"
MEMBER_AGENTS=(codex codex codex)
install_claude_gstack
test ! -e "$GSTACK_DIR"

# 배정한 스킬 디렉터리만 역할 스킬 디렉터리에 링크한다.
MEMBER_AGENTS=(claude claude codex)
install_claude_gstack >/dev/null
role=backend
role_skills_dir="$TEAM_SKILLS_ROOT/$role/.claude/skills"
granted=()
link_plugin_skills gstack "$GSTACK_DIR" ${CLAUDE_GSTACK_SKILL_SETS[$role]}
test -f "$role_skills_dir/health/SKILL.md"
test "${granted[*]}" = gstack:health
test ! -e "$TEAM_SKILLS_ROOT/lead/.claude/skills/spec"

echo "claude_gstack_test: ok"

#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/tests/lib.sh"
load_functions codex_gstack_skills prepare_codex_gstack link_plugin_skills link_owned_skill team_owned_record
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
TEAM_SKILLS_ROOT="$test_dir/team dir"
TEAM_PATH="$PATH"
YELLOW='' NC=''
MEMBER_NAMES=(lead backend reviewer)
MEMBER_AGENTS=(claude claude codex)
PANE_COUNT=3
declare -A CODEX_GSTACK_SKILL_SETS=([lead]='spec' [backend]='health' [reviewer]='review')
export TEST_GSTACK_LOG="$test_dir/setup.log"

git() {
    [ "$*" = "clone --single-branch --depth 1 https://github.com/garrytan/gstack.git $TEAM_SKILLS_ROOT/_assets/gstack/source" ]
    mkdir -p "${@: -1}"
    cat > "${@: -1}/setup" <<'SETUP'
#!/usr/bin/env bash
set -eu
[ "$*" = '--host codex' ]
printf '%s\n' "$CODEX_HOME|$GSTACK_STATE_ROOT" >> "$TEST_GSTACK_LOG"
mkdir -p "$CODEX_HOME/skills/gstack-review"
printf '# Review\n' > "$CODEX_HOME/skills/gstack-review/SKILL.md"
printf '{}\n' > "$CODEX_HOME/hooks.json"
SETUP
    chmod +x "${@: -1}/setup"
}

prepare_codex_gstack
prepare_codex_gstack
root="$TEAM_SKILLS_ROOT/_assets/gstack"
test "$(cat "$TEST_GSTACK_LOG")" = "$root/codex-home|$root/state"
role=reviewer
role_skills_dir="$TEAM_SKILLS_ROOT/$role/.agents/skills"
granted=()
link_plugin_skills gstack "$root/codex-home/skills" $(codex_gstack_skills "$role")
test -f "$role_skills_dir/gstack-review/SKILL.md"
test ! -e "$TEAM_SKILLS_ROOT/$role/.codex-home/hooks.json"
test ! -e "$TEAM_SKILLS_ROOT/lead/.agents/skills/gstack-spec"

MEMBER_AGENTS=(claude claude claude)
prepare_codex_gstack
test "$(wc -l < "$TEST_GSTACK_LOG")" -eq 1

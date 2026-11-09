#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 현재 팀 구성에서 backend는 Claude다. 배열 위치가 아니라 역할로 찾으므로
# config.sh에서 인원을 증감해도 이 계약은 유지된다.
source "$repo_dir/team/config.sh"
backend_index=""
for ((member_index = 0; member_index < ${#MEMBER_NAMES[@]}; member_index++)); do
    if [ "${MEMBER_NAMES[$member_index]}" = "backend" ]; then
        backend_index="$member_index"
        break
    fi
done
test -n "$backend_index"
test "${MEMBER_AGENTS[$backend_index]}" = "claude"

# 모델·추론강도는 team/config.sh의 MEMBERS가 유일한 출처다.
test -n "${SPEC_MEMBER_MODELS[$backend_index]}"
test -n "${SPEC_MEMBER_REASONING_EFFORTS[$backend_index]}"

# config.codex.sh는 스킬·플러그인 배분표만 담당한다(모델은 선언하지 않는다).
source "$repo_dir/team/config.codex.sh"

# standalone 스킬은 어느 역할에도 배정하지 않는다.
for role in "${!CODEX_SKILL_SETS[@]}"; do
    test -z "${CODEX_SKILL_SETS[$role]}"
done
test ! -d "$repo_dir/skills/codex"

# backend에는 공식 Superpowers 플러그인의 디버깅·리뷰 수용 스킬만 선택 노출한다.
test "${CODEX_SUPERPOWERS_SKILL_SETS[backend]}" = "systematic-debugging receiving-code-review"
test "${CODEX_PLUGIN_ROLES[product-design@openai-curated-remote]}" = "uiux"
test "${CODEX_SUPERPOWERS_SKILL_SETS[lead]}" = "finishing-a-development-branch"
test "${CODEX_SUPERPOWERS_SKILL_SETS[architect]}" = "writing-plans"
test "${CODEX_PLUGIN_ROLES[engineering-suite-ponytail@openai-curated-remote]}" = "architect backend frontend"
test "${CODEX_PLUGIN_ROLES[caveman@openai-curated-remote]}" = "*"

# 역할 분리 후 디자인 도구는 uiux, 구현 스킬은 frontend에 배정한다.
test "${CODEX_PLUGIN_ROLES[open-design@openai-curated-remote]}" = "uiux"
test -z "${CODEX_SUPERPOWERS_SKILL_SETS[uiux]}"
test "${CODEX_SUPERPOWERS_SKILL_SETS[frontend]}" = "systematic-debugging receiving-code-review"
source "$repo_dir/team/config.claude.sh"
test "${CLAUDE_SUPERPOWERS_SKILL_SETS[frontend]}" = "systematic-debugging receiving-code-review"
test "${CLAUDE_PLUGIN_ROLES[ponytail@ponytail]}" = "architect backend frontend"
for role in "${MEMBER_NAMES[@]}"; do
    test "$role" != "researcher"
    test -s "$repo_dir/team/$role.md"
done
test -s "$repo_dir/team/uiux.md"

# 런처가 파인별 CODEX_HOME과 세션 시작 정리 훅을 사용해야 한다.
grep -qF 'export CODEX_HOME=$(shell_quote "$role_codex_home")' "$repo_dir/setup-team.sh"
grep -qF 'CODEX_HOME="$role_home" codex login status' "$repo_dir/setup-team.sh"
grep -qF '\"SessionStart\"' "$repo_dir/setup-team.sh"
grep -qF 'CODEX_HOME="$role_home" codex plugin add' "$repo_dir/setup-team.sh"

# pane의 역할 주소와 표시 제목은 분리한다. @role은 say 주소이고, 제목은 표시이름이다.
grep -qF 'tmux set-option -p -t "$SESSION:0.$pane" @role "${MEMBER_NAMES[$pane]}"' "$repo_dir/setup-team.sh"
grep -qF 'tmux set-option -p -t "$SESSION:0.$pane" @display_name "${display_name^^}"' "$repo_dir/setup-team.sh"
grep -qF 'tmux set-option -t "$SESSION" pane-border-format " #{@display_name} "' "$repo_dir/setup-team.sh"
! grep -qF 'tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "' "$repo_dir/setup-team.sh"
grep -qF 'tmux set-option -t "$SESSION" set-titles on' "$repo_dir/setup-team.sh"
grep -qF 'tmux set-option -t "$SESSION" set-titles-string "#{@display_name}"' "$repo_dir/setup-team.sh"
grep -qF '| say ${MEMBER_NAMES[$m]} \"...\" |' "$repo_dir/setup-team.sh"
# 매초 파인 제목을 조회하는 타이틀 워처는 두지 않는다.
! grep -qF '파인 타이틀 워처' "$repo_dir/setup-team.sh"
! grep -qF 'SESSION_ID' "$repo_dir/setup-team.sh"

# 무인 Codex 파인은 .git을 쓸 수 있게 full access가 기본이고,
# 필요할 때만 명시적으로 workspace-write로 낮춘다.
grep -qF 'local permission_args="--dangerously-bypass-approvals-and-sandbox"' "$repo_dir/setup-team.sh"
grep -qF 'if [ "${CODEX_FULL_ACCESS:-1}" = "0" ]; then' "$repo_dir/setup-team.sh"
grep -qF 'permission_args="--ask-for-approval never --sandbox workspace-write"' "$repo_dir/setup-team.sh"

# 스킬 배분 가이드가 현재 Codex 플러그인 배분을 설명한다.
grep -qF 'engineering-suite-ponytail@openai-curated-remote' "$repo_dir/docs/guides/skill-allocation.md"
grep -qF 'product-design@openai-curated-remote' "$repo_dir/docs/guides/skill-allocation.md"

echo 'architect Codex tests passed'

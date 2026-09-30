#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 현재 팀 구성에서 developer는 Codex다. 배열 위치가 아니라 역할로 찾으므로
# config.sh에서 인원을 증감해도 이 계약은 유지된다.
source "$repo_dir/team/config.sh"
developer_index=""
for ((member_index = 0; member_index < ${#MEMBER_NAMES[@]}; member_index++)); do
    if [ "${MEMBER_NAMES[$member_index]}" = "developer" ]; then
        developer_index="$member_index"
        break
    fi
done
test -n "$developer_index"
test "${MEMBER_AGENTS[$developer_index]}" = "codex"

# 모델·추론강도는 team/config.sh의 MEMBERS가 유일한 출처다.
test -n "${SPEC_MEMBER_MODELS[$developer_index]}"
test -n "${SPEC_MEMBER_REASONING_EFFORTS[$developer_index]}"

# config.codex.sh는 스킬·플러그인 배분표만 담당한다(모델은 선언하지 않는다).
source "$repo_dir/team/config.codex.sh"

# gstack의 codex 렌더링은 설치되지 않으므로 standalone 스킬은 배정하지 않는다.
test "${#CODEX_SKILL_SETS[@]}" -eq 0
test ! -d "$repo_dir/skills/codex"

# developer에는 공식 Superpowers 플러그인의 디버깅·리뷰 수용 스킬만 선택 노출한다.
test "${CODEX_SUPERPOWERS_SKILL_SETS[developer]}" = "systematic-debugging receiving-code-review"
test "${CODEX_PLUGIN_ROLES[product-design@openai-curated-remote]}" = "designer"

# 런처가 파인별 CODEX_HOME과 세션 시작 정리 훅을 사용해야 한다.
grep -qF "export CODEX_HOME='\$role_codex_home'" "$repo_dir/setup-team.sh"
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
grep -qF 'want="${MEMBER_DISPLAY_NAMES[$pane]:-${MEMBER_NAMES[$pane]}}"' "$repo_dir/setup-team.sh"
grep -qF 'say_name="${MEMBER_NAMES[$m]}"' "$repo_dir/setup-team.sh"
grep -qF 'state_key="$(pane_state_key "$SESSION_ID:0.$pane")"' "$repo_dir/setup-team.sh"
grep -qF '[ -f "/tmp/team-busy/$state_key" ] && continue' "$repo_dir/setup-team.sh"

# 무인 Codex 파인은 .git을 쓸 수 있게 full access가 기본이고,
# 필요할 때만 명시적으로 workspace-write로 낮춘다.
grep -qF 'local permission_args="--dangerously-bypass-approvals-and-sandbox"' "$repo_dir/setup-team.sh"
grep -qF 'if [ "${CODEX_FULL_ACCESS:-1}" = "0" ]; then' "$repo_dir/setup-team.sh"
grep -qF 'permission_args="--ask-for-approval never --sandbox workspace-write"' "$repo_dir/setup-team.sh"

# README가 공식 카탈로그의 실제 대체재와 선택 적용 범위를 설명한다.
grep -qF 'CODEX_SUPERPOWERS_SKILL_SETS' "$repo_dir/README.md"
grep -qF 'figma@openai-curated-remote' "$repo_dir/README.md"
grep -qF 'notion@openai-curated-remote' "$repo_dir/README.md"

echo 'architect Codex tests passed'

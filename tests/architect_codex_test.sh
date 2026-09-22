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

# developer는 flagship 모델과 깊은 추론을 사용한다. 모델·추론강도는
# team/config.sh의 MEMBERS가 유일한 출처다.
test "${SPEC_MEMBER_MODELS[$developer_index]}" = "gpt-5.6-terra"
test "${SPEC_MEMBER_REASONING_EFFORTS[$developer_index]}" = "high"

# config.codex.sh는 스킬·플러그인 배분표만 담당한다(모델은 선언하지 않는다).
source "$repo_dir/team/config.codex.sh"

# 자체 제작 standalone 스킬은 배정하지 않는다.
test "${#CODEX_SKILL_SETS[@]}" -eq 0
test ! -d "$repo_dir/skills/codex"

# architect에는 공식 Superpowers 플러그인의 설계 스킬만 선택적으로 노출한다.
expected_plugin_skills="superpowers@openai-curated:brainstorming superpowers@openai-curated:writing-plans"
test "${CODEX_PLUGIN_SKILL_SETS[architect]}" = "$expected_plugin_skills"
test "${#CODEX_PLUGIN_SETS[@]}" -eq 0

# marketplace 이름이 인증 방식에 따라 달라도 공식 플러그인을 해석한다.
fixture="$repo_dir/tests/fixtures/codex-plugin-catalog.json"
resolved_id="$("$repo_dir/bin/resolve-codex-plugin" "$fixture" superpowers@openai-curated id)"
resolved_source="$("$repo_dir/bin/resolve-codex-plugin" "$fixture" superpowers@openai-curated source)"
test "$resolved_id" = "superpowers@openai-api-curated"
test "$resolved_source" = "/catalog/plugins/superpowers"

# 런처가 파인별 CODEX_HOME과 세션 시작 정리 훅을 사용해야 한다.
grep -qF "export CODEX_HOME='\$role_codex_home'" "$repo_dir/setup-team.sh"
grep -qF 'CODEX_HOME="$role_home" codex login status' "$repo_dir/setup-team.sh"
grep -qF '\"SessionStart\"' "$repo_dir/setup-team.sh"
grep -qF 'CODEX_HOME="$role_home" codex plugin add' "$repo_dir/setup-team.sh"

# 무인 Codex 파인은 .git을 쓸 수 있게 full access가 기본이고,
# 필요할 때만 명시적으로 workspace-write로 낮춘다.
grep -qF 'local permission_args="--dangerously-bypass-approvals-and-sandbox"' "$repo_dir/setup-team.sh"
grep -qF 'if [ "${CODEX_FULL_ACCESS:-1}" = "0" ]; then' "$repo_dir/setup-team.sh"
grep -qF 'permission_args="--ask-for-approval never --sandbox workspace-write"' "$repo_dir/setup-team.sh"

# README가 공식 카탈로그의 실제 대체재와 선택 적용 범위를 설명한다.
grep -qF 'superpowers@openai-curated' "$repo_dir/README.md"
grep -qF 'figma@openai-curated' "$repo_dir/README.md"
grep -qF 'notion@openai-curated' "$repo_dir/README.md"

echo 'architect Codex tests passed'

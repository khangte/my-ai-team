#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 기본 혼합 팀은 architect와 reviewer만 Codex다.
source "$repo_dir/team/config.sh"
test "${MEMBER_AGENTS[1]}" = "codex"
test "${MEMBER_AGENTS[5]}" = "codex"

# architect는 flagship 모델과 깊은 추론을 사용한다.
source "$repo_dir/team/config.codex.sh"
test "${MEMBER_MODELS[1]}" = "gpt-5.6-sol"
test "${MEMBER_REASONING_EFFORTS[1]}" = "high"

# 공식 Codex 플러그인은 사용자 전역 상태라 런처가 standalone 스킬처럼 복제하지 않는다.
test "${#CODEX_SKILL_SETS[@]}" -eq 0
test ! -d "$repo_dir/skills/codex"

# 런처가 세션 시작 정리 훅을 포함하고 공식 플러그인을 자동 설치하지 않아야 한다.
grep -qF '\"SessionStart\"' "$repo_dir/setup-team.sh"
! grep -qF 'codex plugin add' "$repo_dir/setup-team.sh"

# README가 공식 카탈로그의 실제 대체재와 선택 적용 범위를 설명한다.
grep -qF 'superpowers@openai-curated' "$repo_dir/README.md"
grep -qF 'figma@openai-curated' "$repo_dir/README.md"
grep -qF 'notion@openai-curated' "$repo_dir/README.md"

echo 'architect Codex tests passed'

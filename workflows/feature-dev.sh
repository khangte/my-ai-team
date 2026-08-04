#!/bin/bash
# workflows/feature-dev.sh
FEATURE_NAME=$1

# 파인 밖(호스트 셸)에서 실행되므로 PATH에 say가 없다. 리포 기준 경로로 호출한다.
SAY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../team" && pwd)/say"

"$SAY" team:0.2 "[$FEATURE_NAME] 기술 조사 시작해줘"
"$SAY" team:0.3 "[$FEATURE_NAME] UI 설계 시작해줘"

echo "Phase 1 시작: 조사 + 디자인 병렬 진행"

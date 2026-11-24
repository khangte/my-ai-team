#!/bin/bash
# 테스트 공용 헬퍼. 호출 측에서 repo_dir를 먼저 정한 뒤 source 한다.

load_functions() {
    # 사용법: load_functions <함수명>...
    # setup-team.sh에서 함수 본문만 꺼내 현재 셸에 정의한다(스크립트 전체를 실행하지 않는다).
    local name
    for name in "$@"; do
        eval "$(sed -n "/^${name}() {\$/,/^}\$/p" "$repo_dir/setup-team.sh")"
    done
}

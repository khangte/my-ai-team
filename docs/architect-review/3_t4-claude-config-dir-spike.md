# T4 스파이크 결과 — `CLAUDE_CONFIG_DIR`로 파인 룰 체인 격리 가능한가

- 근거: `docs/architect-review/2_token-optimization-tasks.md` T4
- 결론: **불가 (현재 형태로는).** 확인 항목 1은 통과, 2는 실패. 코드 변경 없음.

## 검증 방법

격리된 스크래치 프로젝트(`/tmp/.../t4-project`)에서 `CLAUDE_CONFIG_DIR`를 새 빈 디렉터리로
지정해 `claude -p --dangerously-skip-permissions --settings <테스트 settings.json>`을 직접
실행. team1 tmux 세션은 건드리지 않음(파인 실기동 restart는 setup-team.sh가 세션을
kill-session 후 재생성해 팀 전체를 끊기 때문에, 이 스파이크에는 별도 격리 인스턴스를 썼다).

## 확인 결과

### 1. `~/.claude/CLAUDE.md` · `rules/`를 안 읽는가 → **통과**

`CLAUDE_CONFIG_DIR`를 새 디렉터리로 주면 `~/.claude/CLAUDE.md`·`rules/ecc/common/*.md`·RTK 규칙을
전혀 로드하지 않는다. 단, 이 결과를 얻기까지 인증이 먼저 깨졌다: `~/.claude/.credentials.json`도
`CLAUDE_CONFIG_DIR` 아래에서 찾으므로, 새 디렉터리에 로그인 정보가 없으면 `Not logged in`으로
바로 죽는다. 새 config 디렉터리에 `.credentials.json`을 복사해 넣은 뒤에야 정상 응답했고, 그때
프롬프트로 직접 물어봐도 "rules/ecc/common/*.md, RTK 관련해서 로드한 커스텀 지침 없음"이라고
답했다.

### 2. `--settings`의 `enabledPlugins`(caveman 등)가 그대로 뜨는가 → **실패**

같은 세션에서 `--settings`로 `caveman@caveman:true`를 명시했지만 caveman 모드가 활성화되지
않았다("그런 모드 자체가 제 시스템에 존재하지 않습니다"). 원인은 플러그인 캐시·마켓플레이스
정보가 `~/.claude/plugins/{cache,data,marketplaces}`에 있는데, `CLAUDE_CONFIG_DIR`를 바꾸면
그 아래 별도의(비어 있는) `plugins/` 디렉터리를 보기 때문이다(`ls`로 실측 확인: 새 config 디렉터리
아래 `plugins/`는 생성되지만 내용이 없음). 문서가 미리 예측한 실패 지점("플러그인 캐시가
`~/.claude/plugins/`에 있으므로 여기서 깨질 가능성이 가장 높다")이 그대로 재현됐다.

### 3. `.claude-logs/` 로깅·busy 마커 훅이 그대로 도는가 → **통과 (참고용)**

2에서 이미 깨졌으므로 원칙대로면 여기서 멈춰야 하지만, 비용이 낮아 추가 확인함: `--settings`로
넣은 PreToolUse 훅은 `CLAUDE_CONFIG_DIR`와 무관하게 정상 실행됐다. 훅은 `--settings` JSON에
커맨드 경로가 고정 문자열로 박혀 있어 config 디렉터리 위치와 무관하기 때문으로 보인다.

## 결론

확인 항목 2가 깨졌으므로 "파인용 슬림 룰 + 사용자 세션은 그대로" 목표를 `CLAUDE_CONFIG_DIR` 단독으로는
이룰 수 없다. `.credentials.json`과 `plugins/{cache,data,marketplaces}`를 새 config 디렉터리로
심링크하면 우회는 가능해 보이나, 이는 스파이크 범위를 넘는 별도 구현 작업이고 사용자 개인 설정
디렉터리 구조에 손대는 방식이라 원칙("사용자 전역 설정은 건드리지 않는다")과 충돌 소지가 있다.
T4는 여기서 종료. 룰 체인 격리는 이 방식으로는 보류하고, 필요하면 별도 검토 항목으로 재작성해야
한다(T7처럼 사용자 확인이 필요한 접근으로 재분류하는 편이 나아 보인다 — 최종 판단은 architect 몫).

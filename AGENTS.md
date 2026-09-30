# AGENTS.md

Always write Korean (and other non-ASCII) strings in tool-call parameters as literal UTF-8; never as `\uXXXX` unicode escapes.

## Multi-Agent Team

- 파인끼리는 `say`로만 소통한다
- 상대가 작업 중이면 큐에 쌓였다가 유휴가 되면 자동 전송된다 (발신 파인은 대기하지 않음)
  - 진행 중인 작업을 중단시켜야 하면 `SAY_NOWAIT=1`로 즉시 전송
- 프롬프트·툴 로그는 `$PROJECT_DIR/.claude-logs/{역할}.jsonl`. 원인 추적이 필요할 때 읽어라.
- `docs/`에 커밋하는 건 `docs/architect-review/`의 architect 판정 문서뿐이다.

### 파일 읽기 규칙

- 같은 세션에서 이미 읽은 파일은 다시 읽지 않는다.
- 파일을 수정한 직후 확인만을 위해 다시 읽지 않는다. 수정 실패는 도구 오류로 확인한다.
- 300줄이 넘는 파일은 먼저 `rg -n`으로 관련 줄을 찾고 필요한 구간만 읽는다.

### 보고 규칙

- **`say`를 실행해야 보고다.** 근거·상세는 `say`와 산출물에 담고, 응답은 실행한 `say` 한 줄로 끝낸다.
- **다음 담당자에게 직접 전달한 건은 lead에 사본을 보내지 않는다**
  - lead는 그 사안이 **종결될 때** 최종 결과만 받는다
  - 예외: 사용자 승인이 필요하거나, 일정·범위·우선순위가 바뀌는 경우
- **작업 단위가 끝날 때 lead에 한 번만 보고한다** — 한 턴에 lead로 `say`는 한 번이다
  - "기록 완료", "갱신 확인", "재확인 완료" 같은 중간 상태는 다음 보고에 합쳐 보낸다
  - 같은 사안을 여러 역할이 각자 lead에 보고하지 않는다 — 마지막 판정자만 보고한다

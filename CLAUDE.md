# CLAUDE.md

## General

- Always write Korean (and other non-ASCII) strings in tool-call parameters as literal UTF-8; never as `\uXXXX` unicode escapes.

## Code Style

- Add a brief docstring directly below every class or function declaration.
- Write the docstring in Korean unless the content specifically requires English, such as code, queries, identifiers, commands, or technical syntax.

## Language

- `say` 메시지 본문은 항상 영어로, 핵심만 간결하게 쓴다 (인사·불필요한 설명 생략). 파일 경로·식별자는 원문 그대로 둔다.
- 사용자에게 보이는 모든 텍스트(보고·질문·진행 알림)는 한국어로 쓴다.
- 사람이 읽는 산출물(`docs/architect-review/` 판정 문서 등)은 한국어로 쓴다.

## Multi-Agent Team

- pane끼리는 `say`로만 소통한다
- 상대가 작업 중이면 큐에 쌓였다가 유휴가 되면 자동 전송된다 (발신 pane은 대기하지 않음)
  - 진행 중인 작업을 중단시켜야 하면 `SAY_NOWAIT=1`로 즉시 전송
- 프롬프트·툴 로그는 `$PROJECT_DIR/.team-logs/{역할}.jsonl`. 원인 추적이 필요할 때 읽어라.

### 보고 규칙 (모든 역할 공통)

- **`say`를 실행해야 보고다.** 근거·상세는 `say`와 산출물에 담고, 응답은 실행한 `say` 한 줄로 끝낸다.
- **다음 담당자에게 직접 전달한 건은 lead에 사본을 보내지 않는다**
  - lead는 그 사안이 **종결될 때** 최종 결과만 받는다
  - 예외: 사용자 승인이 필요하거나, 일정·범위·우선순위가 바뀌는 경우
- **작업 단위가 끝날 때 lead에 한 번만 보고한다**
  - "기록 완료", "갱신 확인", "재확인 완료" 같은 중간 상태는 다음 보고에 합쳐 보낸다
  - 같은 사안을 여러 역할이 각자 lead에 보고하지 않는다 — 마지막 판정자만 보고한다

### 파일 읽기 규칙

- 같은 세션에서 이미 읽은 파일은 다시 읽지 않는다.
- 300줄이 넘는 파일은 먼저 `rg -n`으로 관련 줄을 찾고 필요한 구간만 읽는다.

## Commit

- 커밋 메시지는 caveman-commit 스킬로 작성한다.
- `type(scope):` 키워드만 영어로 쓰고, 요약·본문은 한글로 쓴다.

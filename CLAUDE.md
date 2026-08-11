# CLAUDE.md

## 팀 구성

- `setup-team.sh`가 tmux 세션 하나에 파인 6개를 띄우고 각각 다른 모델로 `claude` 실행
- 각 파인의 지침 = `team/{역할}.md` + "작업 경로" 안내 + (lead 한정) 팀원 배분 표
  - `--append-system-prompt-file`로 주입되며, 조립 결과는 `.team/_runtime/{역할}.prompt.md`에 남음
  - 자기 지침이 의심스러우면 그 파일을 읽는다
- **각 파인의 cwd는 프로젝트 루트가 아니라 역할별 스킬 격리 디렉터리(`.team/{역할}/`)**
  - 파일·git 작업은 시스템 프롬프트 "작업 경로" 절이 알려주는 실제 프로젝트 루트 기준
- 기본 6인: lead(:0.0)·architect(:0.1)·researcher(:0.2)·designer(:0.3)·developer(:0.4)·reviewer(:0.5)
  - 인원·파인 번호는 `team/config.sh`로 프로젝트마다 달라짐
  - **실제 배분 기준은 lead가 런타임에 받는 "팀원 배분(자동 생성)" 표**
  - 역할 지침은 프로젝트 루트의 `team/{역할}.md`가 있으면 그쪽 우선

## 파인 간 통신

- 파인끼리는 `say :0.{N} "메시지"`로만 소통 (파인 번호 대신 `say developer "..."`도 가능)
- **응답 텍스트에 "완료했습니다"라고 쓰는 것은 보고가 아니다**
  - 그 텍스트는 파인 밖으로 나가지 않으므로 반드시 `say`를 실행
- `tmux send-keys`는 쓰지 않는다 — Enter 인자가 누락되면 메시지가 상대 입력창에 남음
- 상대가 작업 중이면 `say`가 큐에 쌓아두고 유휴 시 자동 전송 (발신 파인은 대기하지 않음)
- 긴급 중단 지시처럼 즉시 전달이 필요하면 `SAY_NOWAIT=1`

보고 경로:

| 상황                          | 경로                                    |
| ----------------------------- | --------------------------------------- |
| 일반 완료                     | 각 파인 → lead(:0.0)                    |
| 설계 이탈(developer/designer) | 파인 → architect(:0.1) → lead           |
| 리뷰 승인                     | reviewer(:0.5) → lead                   |
| 리뷰 코드 품질 수정요청       | reviewer(:0.5) → developer(:0.4) 직행   |
| 리뷰 설계 판단 필요           | reviewer(:0.5) → architect(:0.1) → lead |

- 보고 누락 대비: lead 외 각 파인은 응답을 마칠 때 "응답 종료" 신호를 lead에 자동 전달(Stop 훅)
- lead는 폴링하지 않고 신호가 온 파인만 확인 (`team/lead.md`)

### 팀 밖 세션과의 통신

- 파인 간 통신은 위의 `say`가 전부
- 각 파인은 Claude Code의 cross-session messaging도 켜둔 채 뜸 (`crossSessionInbound: accept`)
  - 팀 밖 일반 세션이 `/list-agents`로 파인을 찾아 `SendMessage`로 지시 가능
  - 파인 쪽에서 이 경로가 필요한 경우는 서브에이전트와의 통신뿐
- 파인끼리는 여전히 `say`를 쓴다 — `say`에만 있는 유휴 대기 큐·전송 검증·`SAY_NOWAIT` 인터럽트가 팀 운영의 전제
- 컨테이너로 띄운 경우(`setup-docker.sh`) 이 경로는 컨테이너 안에서만 유효 (호스트 세션과 상호 비가시)

## 스킬

- [gstack](https://github.com/garrytan/gstack)·[superpowers](https://github.com/obra/superpowers) 스킬은 역할별로 필요한 것만 배정
- 내가 실제로 쓸 수 있는 것과 사용 시점은 자기 역할 문서의 "## 스킬" 절에 있음
- 이 스킬들은 단독 실행 전제로 쓰여 팀 구조와 어긋나는 지시가 섞여 있음
  - 예: 사용자 직접 승인 요청, 서브에이전트 dispatch, 워크트리 생성
  - 충돌하면 **역할 문서가 우선한다**
- 전역 규칙의 서브에이전트 위임(planner·code-reviewer 등)은 파인 역할이 대체한다

## 프롬프트·툴 로깅

- 훅이 `$PROJECT_DIR/.claude-logs/{역할}.jsonl`에 자동 기록
- 원인 추적이 필요하면 읽으면 된다
- 커밋 대상이 아니다 (상세는 README)

## rtk

- `git status`·`ls`·`cat` 등은 훅이 `rtk git status` 형태로 재작성 → 직접 `rtk`를 붙이지 않는다
- 메타 커맨드(`rtk gain` 등)는 전역 RTK.md 참조

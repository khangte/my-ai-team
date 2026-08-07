# CLAUDE.md

## 팀 구성

`setup-team.sh`는 tmux 세션 하나에 파인 6개를 띄우고 각각 다른 모델로 `claude`를 실행한다.
각 파인은 자기 역할 문서(`team/{역할}.md`)를 기반으로 조립된 지침만 갖는다
— 스크립트가 여기에 아래 "작업 경로" 안내와 (lead에 한해) 팀원 배분 표를 덧붙여 `--append-system-prompt-file`로 주입한다.
조립된 최종 지침은 `.team/_runtime/{역할}.prompt.md`에 그대로 남으므로, 자기 지침이 의심스러우면 읽어보면 된다.

**각 파인의 cwd는 프로젝트 루트가 아니라 역할별 스킬 격리 디렉터리(`.team/{역할}/`)다.**
파일·git 작업은 시스템 프롬프트의 "작업 경로" 절이 알려주는 실제 프로젝트 루트를 기준으로 한다.

기본 구성은 lead(:0.0)·architect(:0.1)·researcher(:0.2)·designer(:0.3)·developer(:0.4)·reviewer(:0.5) 6인이지만,
인원과 파인 번호는 `team/config.sh`로 프로젝트마다 달라진다.
**실제 배분은 lead가 런타임에 받는 "팀원 배분(자동 생성)" 표가 기준이다.**
역할 지침도 프로젝트 루트의 `team/{역할}.md`가 있으면 그쪽이 우선한다.

## 파인 간 통신

파인끼리는 `say :0.{N} "메시지"`로만 소통한다(파인 번호 대신 `say developer "..."`도 된다).
**응답 텍스트에 "완료했습니다"라고 쓰는 것은 보고가 아니다** — 그 텍스트는 파인 밖으로 나가지 않으므로 반드시 `say`를 실행해야 한다.

`tmux send-keys`는 쓰지 않는다. Enter 인자가 누락되면 메시지가 상대 입력창에 남는다.

상대가 작업 중이면 `say`는 큐에 쌓아두고 유휴가 되면 자동 전송한다(발신 파인은 대기하지 않는다).
즉시 전달이 필요한 긴급 중단 지시는 `SAY_NOWAIT=1`을 붙인다.

보고 경로:

- 일반 완료: 각 파인 → lead(:0.0)
- 설계 이탈(developer/designer): 파인 → architect(:0.1) → lead
- 리뷰 승인: reviewer(:0.5) → lead
- 리뷰 코드 품질 수정요청: reviewer(:0.5) → developer(:0.4) 직행
- 리뷰 설계 판단 필요: reviewer(:0.5) → architect(:0.1) → lead

보고 누락에 대비해 lead 외 각 파인은 응답을 마칠 때 "응답 종료" 신호를 lead에 자동 전달한다(Stop 훅).
lead는 폴링하지 않고 신호가 온 파인만 확인한다(`team/lead.md`).

## 스킬

[gstack](https://github.com/garrytan/gstack)과 [superpowers](https://github.com/obra/superpowers)
스킬은 역할별로 필요한 것만 배정된다. 내가 실제로 쓸 수 있는 것과 언제 쓰는지는 자기 역할 문서의 "## 스킬" 절에 있다.

이 스킬들은 단독 실행을 전제로 쓰여 팀 구조와 어긋나는 지시(사용자 직접 승인 요청, 서브에이전트 dispatch, 워크트리 생성 등)가 섞여 있다.
충돌하면 **역할 문서가 우선한다**.

## 프롬프트·툴 로깅

훅이 `$PROJECT_DIR/.claude-logs/{역할}.jsonl`에 자동 기록한다.
원인 추적이 필요하면 읽으면 된다. 커밋 대상이 아니다(상세는 README).

## rtk

`git status`·`ls`·`cat` 등은 훅이 `rtk git status` 형태로 재작성하므로 직접 `rtk`를 붙이지 않는다.
아래 메타 커맨드만 직접 실행한다.

```bash
rtk gain              # 누적 토큰 절약량
rtk gain --history    # 명령별 절약 내역
rtk discover          # 놓친 절약 기회 분석
rtk proxy <cmd>       # 재작성 없이 원본 명령 실행(디버깅용)
```

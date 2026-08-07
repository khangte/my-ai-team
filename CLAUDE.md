# CLAUDE.md

## 팀 구성

`setup-team.sh`는 tmux 세션 하나에 파인 6개를 띄우고 각각 다른 모델로 `claude`를 실행한다.
파인별 역할 지침(`team/{역할}.md`)은 `--append-system-prompt`로 주입되므로, 각 파인은
자기 역할 문서만 갖는다.

| 파인 | 역할       | 담당                                   |
| ---- | ---------- | -------------------------------------- |
| :0.0 | lead       | 지시 수령·작업 배분·결과 통합·git 커밋 |
| :0.1 | architect  | 설계·기술 문서·설계 이탈 판단          |
| :0.2 | researcher | 기술 조사·비교 분석                    |
| :0.3 | designer   | UI/UX 설계·스펙                        |
| :0.4 | developer  | 구현·테스트·버그 수정                  |
| :0.5 | reviewer   | 코드 리뷰·보안·설계 정합성 검증        |

팀 구성은 `team/config.sh`로, 역할 지침은 프로젝트 루트의 `team/{역할}.md`로 재정의된다.

## 파인 간 통신

파인끼리는 `say :0.{N} "메시지"`로만 소통한다(파인 번호 대신 `say developer "..."`도 된다).
**응답 텍스트에 "완료했습니다"라고 쓰는 것은 보고가 아니다** — 그 텍스트는 파인 밖으로
나가지 않으므로 반드시 `say`를 실행해야 한다.

`tmux send-keys`는 쓰지 않는다. Enter 인자가 누락되면 메시지가 상대 입력창에 남는다.

보고 경로:

- 일반 완료: 각 파인 → lead(:0.0)
- 설계 이탈(developer/designer): 파인 → architect(:0.1) → lead
- 리뷰 승인: reviewer(:0.5) → lead
- 리뷰 코드 품질 수정요청: reviewer(:0.5) → developer(:0.4) 직행
- 리뷰 설계 판단 필요: reviewer(:0.5) → architect(:0.1) → lead

보고 누락에 대비해 lead 외 각 파인은 응답을 마칠 때 "응답 종료" 신호를 lead에 자동
전달한다(Stop 훅). lead는 폴링하지 않고 신호가 온 파인만 확인한다(`team/lead.md`).

## 스킬

[gstack](https://github.com/garrytan/gstack)은 `~/.claude/skills/gstack`에 전역 설치되어
모든 파인에서 쓸 수 있다. [superpowers](https://github.com/obra/superpowers) 프로세스
스킬은 역할별로 배정되며, 무엇을 언제 쓰는지는 자기 역할 문서의 "## 스킬" 절에 있다.

이 스킬들은 단독 실행을 전제로 쓰여 팀 구조와 어긋나는 지시(사용자 직접 승인 요청,
서브에이전트 dispatch, 워크트리 생성 등)가 섞여 있다. 충돌하면 **역할 문서가 우선한다**.

## 프롬프트·툴 로깅

훅이 `$PROJECT_DIR/.claude-logs/{역할}.jsonl`에 자동 기록한다. 원인 추적이 필요하면
읽으면 된다. 커밋 대상이 아니다(상세는 README).

## rtk

`git status`·`ls`·`cat` 등은 훅이 `rtk git status` 형태로 재작성하므로 직접 `rtk`를
붙이지 않는다. 아래 메타 커맨드만 직접 실행한다.

```bash
rtk gain              # 누적 토큰 절약량
rtk gain --history    # 명령별 절약 내역
rtk discover          # 놓친 절약 기회 분석
rtk proxy <cmd>       # 재작성 없이 원본 명령 실행(디버깅용)
```

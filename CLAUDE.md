# CLAUDE.md

## 팀 구성

`setup-team.sh`는 tmux 세션 하나에 파인 6개를 띄우고, 각 파인에서 서로 다른 모델로
`claude`를 실행한다. 파인별 역할 지침(`team/{역할}.md`)은 `--append-system-prompt`로
주입되므로, 각 파인은 자기 역할 문서만 시스템 프롬프트로 갖는다.

| 파인 | 역할       | 담당                                   |
| ---- | ---------- | -------------------------------------- |
| :0.0 | lead       | 지시 수령·작업 배분·결과 통합·git 커밋 |
| :0.1 | architect  | 설계·기술 문서·설계 이탈 판단          |
| :0.2 | researcher | 기술 조사·비교 분석                    |
| :0.3 | designer   | UI/UX 설계·스펙                        |
| :0.4 | developer  | 구현·테스트·버그 수정                  |
| :0.5 | reviewer   | 코드 리뷰·보안·설계 정합성 검증        |

팀 구성(인원·이름·모델·세션명)은 `team/config.sh`로 프로젝트마다 재정의할 수 있고,
역할 지침도 프로젝트 루트의 `team/{역할}.md`가 있으면 그쪽이 우선한다.

## 파인 간 통신

파인끼리는 `say :0.{N} "메시지"`로만 소통한다(`team/say`, `setup-team.sh`가 PATH에 넣어준다).
파인 번호 대신 역할 이름도 쓸 수 있다 — `say developer "..."`.
**응답 텍스트에 "완료했습니다"라고 쓰는 것은 보고가 아니다** — 그 텍스트는 자기 파인 밖으로
나가지 않으므로, 보고하려면 반드시 위 명령을 실제로 실행해야 한다.

`tmux send-keys`를 직접 쓰지 않는다. Enter가 별개 인자라 누락되기 쉽고, 그러면 메시지가
상대 파인 입력창에 남은 채 전송되지 않는다. `say`는 Enter를 항상 붙인다.

보고 경로는 평상시 1홉(각 파인 → lead), 설계 판단이 필요한 건만 architect를 경유한다.

- 일반 완료 보고: 각 파인 → lead(:0.0)
- 설계 이탈(developer/designer): 파인 → architect(:0.1) 판단 → lead
- 리뷰 결과(승인): reviewer(:0.5) → lead
- 리뷰 결과(코드 품질 수정요청): reviewer(:0.5) → developer(:0.4) 직행
- 리뷰 결과(설계 판단 필요·설계이탈): reviewer(:0.5) → architect(:0.1) 판정 → lead

보고를 잊는 경우에 대비해, lead를 제외한 각 파인은 응답을 마칠 때 "응답 종료" 신호를
lead에 자동 전달한다(Stop 훅). lead는 폴링 없이 신호가 온 파인만 확인하면 된다
(자세한 규칙은 `team/lead.md`).

## 스킬

[gstack](https://github.com/garrytan/gstack) 스킬이 `~/.claude/skills/gstack`에
설치되어 있다. 유저 전역 경로라 프로젝트와 무관하게 모든 파인에서 쓸 수 있다.

[superpowers](https://github.com/obra/superpowers) 플러그인의 프로세스 스킬(TDD·근본원인
디버깅·완료 전 검증 등)도 역할별로 배정되어 있다. 각 파인이 실제로 받는 것은
`setup-team.sh`가 링크한 것뿐이고, 무엇을 언제 쓰는지는 자기 역할 문서(`team/{역할}.md`)의
"## 스킬" 절에 적혀 있다.

이 스킬들은 단독 실행을 전제로 쓰여 있어 팀 구조와 어긋나는 지시가 섞여 있다
(사용자에게 직접 승인 요청, 서브에이전트 dispatch, 워크트리 생성 등).
역할 문서의 "## 스킬" 절이 그런 지점을 어떻게 바꿔 읽을지 명시하므로,
충돌하면 **역할 문서가 우선한다**.

## 프롬프트·툴 로깅

프롬프트와 툴 사용은 훅이 `$PROJECT_DIR/.claude-logs/{역할}.jsonl`에 자동 기록한다.
재현·원인 추적이 필요하면 이 파일을 읽으면 된다. 커밋 대상이 아니고, 시크릿은
마스킹된다(상세는 README 참조).

## rtk

[rtk](https://github.com/rtk-ai/rtk)는 개발 명령 출력을 압축해 토큰을 절약하는 CLI 프록시다.
`git status`·`ls`·`cat` 등은 훅이 알아서 `rtk git status` 형태로 재작성하므로,
명령 앞에 `rtk`를 직접 붙일 필요는 없다.

다만 아래 메타 커맨드는 재작성 대상이 아니라 직접 실행해야 한다.

```bash
rtk gain              # 누적 토큰 절약량
rtk gain --history    # 명령별 절약 내역
rtk discover          # 놓친 절약 기회 분석
rtk proxy <cmd>       # 재작성 없이 원본 명령 실행(디버깅용)
```

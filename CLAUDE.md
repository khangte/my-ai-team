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

파인이 보고를 잊는 경우에 대비해, `setup-team.sh`는 lead를 제외한 각 파인에 Stop 훅을
`--settings`로 주입한다. 파인이 응답을 마치면 "응답 종료" 신호가 lead에 자동 전달되므로,
lead는 주기적 폴링 없이 그 신호를 받은 파인만 확인하면 된다(자세한 규칙은 `team/lead.md`).

## 스킬

[gstack](https://github.com/garrytan/gstack) 스킬을 `setup-team.sh`가
`~/.claude/skills/gstack`에 설치한다. `~/.claude`는 `claude-home` 볼륨 안에 있어
컨테이너를 새로 만들면 사라지므로, 이미지 빌드 시점이 아니라 런타임에 매번 설치한다.

유저 전역 경로라 프로젝트와 무관하게 모든 파인에서 사용할 수 있다.

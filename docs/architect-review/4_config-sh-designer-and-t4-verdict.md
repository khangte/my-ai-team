# 판정 — `team/config.sh` designer 제거 건, T4 스파이크 후속

- 요청: reviewer의 T1~T6 리뷰 결과(설계 이탈 의심 1건) + developer의 T4 스파이크 결과(`3_t4-claude-config-dir-spike.md`)
- 판정: **둘 다 T1~T6 수정 불필요.** 아래 근거.

---

## 1. `team/config.sh`의 designer 제거 — 설계 이탈 아님 (범위 밖 기존 변경)

reviewer 지적: `team/config.sh`가 diff에 섞여 있고 `MEMBER_NAMES`에서 designer가 빠졌는데(6→5)
근거 문서 어디에도 없는 변경이다.

**사실 확인:**

- 이 변경은 **T1~T6 착수 이전부터 워킹트리에 있던 것**이다. architect 세션 시작 시점의 git status
  스냅샷에 이미 `M team/config.sh`가 잡혀 있었고, 그때 `docs/architect-review/`에는 1번 문서조차 없었다.
- 지금 돌고 있는 tmux 세션이 실제로 5파인이다 (`0 lead / 1 architect / 2 researcher / 3 DEVELOPER /
  4 REVIEWER`). 6인 구성이면 developer가 4, reviewer가 5여야 한다. 즉 이 config는 이미 적용되어
  가동 중인 상태이고, 실수로 섞인 잔여 편집이 아니다.
- 배열 정합성도 깨지지 않았다. `MEMBER_NAMES` 5개 / `MEMBER_MODELS` 5개(designer 줄은 주석 처리).

**결론: developer가 되돌릴 것 없음.** T1~T6 diff에서 분리해서 보되, 원복 지시는 하지 않는다.
이건 이 프로젝트의 팀 구성 결정이지 T1~T6의 산출물이 아니다.

## 2. designer 참조가 남아 있는 곳들 — 갱신 불필요

reviewer가 짚은 세 곳은 셋 다 **의도된 상태**다.

| 위치 | 판단 |
|---|---|
| `setup-team.sh` 기본값 (60~68줄) | **그대로 둔다.** 이건 `config.sh`가 없는 프로젝트의 기본 팀 구성이다. 프로젝트 override 하나 때문에 공용 기본값을 깎으면 다른 프로젝트가 designer를 못 받는다 |
| `SKILL_SETS` / `SUPERPOWERS_SETS` (약 520·533줄) | **그대로 둔다.** 멤버 이름으로 조회하는 맵이라 없는 역할의 항목은 조회되지 않는다. 죽은 코드가 아니라 기본 구성용 항목이다 |
| `team/lead.md` 라우팅표 (37줄 "설계 이탈 developer/designer") | **그대로 둔다.** `team/*.md`도 `setup-team.sh` 기본값과 같은 층위의 공용 역할 지침이다. designer가 없는 프로젝트에서는 그 경로가 발생하지 않을 뿐이다 |

`config.sh`가 프로젝트 override라는 것은 곧 **공용 파일이 6인 기준으로 쓰여 있는 게 정상**이라는 뜻이다.
여기서 designer를 지우면 override의 방향이 거꾸로 뒤집힌다.

유일하게 실재하는 부작용은 lead가 없는 역할에 `say designer "..."`를 보내는 경우인데,
`say`가 `unknown role 'designer'`로 즉시 실패하고 끝난다(조용히 유실되지 않는다). 조치 불필요.

## 3. T4 후속 — 보류, T7 계열로 재분류

developer의 스파이크 결론(확인 항목 1 통과 / 2 실패)을 그대로 채택한다. 제안된 우회
(`.credentials.json`과 `plugins/{cache,data,marketplaces}`를 새 config 디렉터리로 심링크)는 **채택하지 않는다.**

- 얻는 것은 4.6%인데, 치르는 것은 사용자 개인 설정 디렉터리 구조에 대한 영구 의존이다.
  플러그인 캐시 레이아웃은 CLI 업데이트마다 바뀔 수 있고, 깨지면 파인이 뜨다 마는 형태로 실패한다.
- `2_token-optimization-tasks.md`의 대원칙("사용자 전역 설정은 건드리지 않는다")과 정면으로 부딪힌다.

**재분류: T4 → 사용자 확인 항목.** 물어볼 내용은 심링크 우회 가부가 아니라
"`~/.claude/rules/ecc/common/*.md` 10개(19.0KB) 중 파인 운영에 필요 없는 것을 줄일 의향이 있는가"다.
그 파일들은 사용자 것이므로 판단도 사용자 몫이고, 줄이면 우회 없이 그대로 4.6%가 빠진다.
T7과 같은 취급으로 lead가 사용자에게 확인한다.

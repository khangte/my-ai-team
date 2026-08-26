# 역할별 에이전트 혼합 실행 계획

## 목적

현재 `--agent claude|codex`는 팀 전체에 하나의 CLI를 강제한다. 이 문서는 **파인별로 서로
다른 에이전트를 띄우는** 구조를 설계한다. 첫 대상은 reviewer다.

reviewer만 Codex로 돌리면 코드를 쓴 모델과 리뷰하는 모델이 달라져, 같은 모델끼리 공유하는
맹점을 구조적으로 줄일 수 있다. `team/config.codex.sh`는 이미 reviewer에 `gpt-5.6-sol` /
추론 수준 `high`를 선언하고 있어 의도 자체는 존재하지만, 현재 런처는 그 조합을 만들 수 없다.

Codex 백엔드 자체의 도입 계획은 [codex-support-plan.md](codex-support-plan.md)가 다룬다.
이 문서는 그 위에서 **혼합 실행**만 다룬다.

## 목표

- 파인마다 독립적으로 에이전트를 선택할 수 있게 한다.
- reviewer를 Codex로 띄워도 `say` 큐·유휴 판정이 지금과 동일하게 동작한다.
- 기존 `--agent` 플래그와 단일 공급자 팀 동작을 깨뜨리지 않는다.
- 혼합 팀에서 각 파인이 무엇으로 떴는지 실행 로그에 드러난다.

## 비목표

- Codex 파인에 rtk 토큰 절감 훅을 재현하지 않는다 (현재 rtk에 Codex 프로세서가 없다).
- Claude 플러그인을 Codex 스킬로 자동 변환하지 않는다.
- reviewer 외 역할의 기본 공급자를 바꾸지 않는다.

## 현재 구조의 제약

### 1. 공급자 선택이 팀 단위다

`setup-team.sh`의 실행 루프는 전역 `$TEAM_AGENT` 하나로 모든 파인을 분기한다.

```bash
for ((pane = 0; pane < PANE_COUNT; pane++)); do
    if [ "$TEAM_AGENT" = "claude" ]; then
        start_claude_in_pane "$SESSION:0.$pane" "${MEMBER_MODELS[$pane]}" "${MEMBER_NAMES[$pane]}"
    else
        start_codex_in_pane "$SESSION:0.$pane" "${MEMBER_MODELS[$pane]}" "${MEMBER_NAMES[$pane]}" "${MEMBER_REASONING_EFFORTS[$pane]}"
    fi
done
```

모델 배열(`MEMBER_MODELS`)도 `config.{agent}.sh` 한 파일에서만 읽으므로, 한 팀 안에
Claude 모델명과 Codex 모델명이 공존할 자리가 없다.

### 2. 유휴 판정이 Claude 훅에 종속돼 있다

`bin/say`의 `is_busy()`는 `/tmp/team-busy/{pane_id}` 마커로 파인의 작업 여부를 판정한다.
이 마커의 생명주기는 전적으로 Claude harness 훅이 만든다.

| 시점 | 훅 | 동작 |
| --- | --- | --- |
| 턴 시작 | `UserPromptSubmit` | 마커 생성 |
| 턴 종료 | `Stop` | 마커 삭제 |
| `/clear`·`/compact`·재시작 | `SessionStart` | stale 마커 삭제 |

Codex CLI(0.149.1)에서 확인한 결과, 턴 종료에 대응하는 `agent-turn-complete` 이벤트는
존재하지만 **턴 시작에 대응하는 이벤트가 없다.** 즉 Codex 파인은 마커를 켤 방법이 없다.

이때 `bin/say`는 폴백으로 내려가는데, 폴백 조건이 문제다.

```bash
if [ -d "/tmp/team-busy" ]; then
    return 1   # 디렉터리가 있으면 마커 없는 파인은 무조건 '유휴'
fi
```

다른 Claude 파인이 이미 `/tmp/team-busy`를 만들어 두므로, **Codex reviewer는 리뷰 도중에도
항상 유휴로 판정된다.** lead의 다음 지시가 큐에 쌓이지 않고 곧바로 꽂혀 진행 중인 리뷰를
끊는다. 이것이 혼합 실행의 최대 차단 요인이다.

### 3. Codex 파인이 잃는 부가 기능

| 기능 | 근거 | 대응 |
| --- | --- | --- |
| busy 마커 | turn-start 훅 없음 | 아래 A안으로 해결 |
| 자동 종료 신호 | `Stop` 훅 없음 | `notify` = `agent-turn-complete`로 대체 |
| `say` 중복 보고 가드 | 같은 `Stop` 훅에 얹혀 있음 | 위와 함께 이식 |
| rtk 토큰 절감 | `PreToolUse` matcher, Codex 프로세서 부재 | 포기, 문서화 |
| 툴 로그 JSONL | 같은 `PreToolUse` | 후속 과제 |

## 설계

### A. busy 마커를 harness 훅에서 독립시킨다 (선행 필수)

마커를 **누가 켜는가**를 바꾼다. 지금은 수신 파인의 harness가 켜지만, 앞으로는 **발신자인
`bin/say`가 전달 직후 켠다.**

```text
현재:  say → 파인에 전달 → 파인 harness의 UserPromptSubmit이 마커 생성
변경:  say → 파인에 전달 → say가 직접 마커 생성
```

근거:

- `say`는 메시지를 실제로 꽂은 시점을 정확히 안다. 그 순간이 곧 턴 시작이다.
- 어떤 CLI가 그 파인에 떠 있든 무관하게 동작한다. 공급자 중립이다.
- Claude 파인에서는 harness 훅의 `touch`와 중복될 뿐 무해하다 (같은 파일).
- 마커를 **지우는** 쪽은 공급자별 훅에 남긴다. Claude는 `Stop`, Codex는 `notify`.

이 변경만으로 유휴 판정이 CLI 종류에서 분리되므로, 이후 어떤 에이전트를 어느 파인에 꽂아도
큐가 깨지지 않는다. 혼합 실행의 토대다.

사람이 파인에 직접 입력한 경우는 여전히 마커가 켜지지 않는다. 이는 현 구조에서도
Codex 파인에 동일하게 존재하는 한계이며, 폴백 화면 판정이 그 자리를 메운다.

### B. 파인별 에이전트 선택

`team/config.sh`에 공급자 중립 배열을 추가한다.

```bash
declare -a MEMBER_AGENTS=("" "" "" "" "" "codex")
```

- 빈 문자열은 `$TEAM_AGENT`(전역 기본값)를 따른다. 기존 프로젝트는 배열을 선언하지 않으면
  전부 빈 값과 동일하게 취급되어 동작이 바뀌지 않는다.
- 배열을 선언했다면 길이를 `MEMBER_NAMES`와 함께 검증한다.

실행 루프는 전역 플래그 대신 파인별 값으로 분기한다.

```bash
agent="${MEMBER_AGENTS[$pane]:-$TEAM_AGENT}"
```

### C. 공급자별 모델 배열의 동시 로딩

혼합 팀에서는 `config.claude.sh`와 `config.codex.sh`를 **둘 다** 읽어야 한다. 현재는 선택된
공급자 하나만 읽는다.

배열을 공급자별 이름으로 분리해 담는다.

```bash
CLAUDE_MEMBER_MODELS=(...)   # config.claude.sh 해석 결과
CODEX_MEMBER_MODELS=(...)    # config.codex.sh 해석 결과
CODEX_MEMBER_REASONING_EFFORTS=(...)
```

파인 실행 시 그 파인의 에이전트에 맞는 배열에서 인덱스로 꺼낸다. 기존
`MEMBER_MODELS` 호환 경로(과거 Claude 프로젝트의 `config.sh`)는 그대로 유지한다.

혼합 팀이 아닐 때는 필요 없는 공급자 설정 파일이 없어도 무해해야 하므로, 파일 부재는
오류가 아니라 빈 배열로 처리한다.

### D. Codex 파인의 종료 신호

Codex `notify` 설정에 `agent-turn-complete`를 걸어 Claude의 `Stop` 훅과 같은 일을 시킨다.

```text
1. rm -f /tmp/team-busy/{pane_id}
2. /tmp/team-say/{pane_id} 마커가 있으면 소비하고 종료 (본 보고 있음)
   없으면 lead에 자동 종료 신호를 say로 전송
```

Claude 쪽 `hook_cmd`와 동일한 로직이므로, 두 곳에 같은 문자열을 복제하지 말고 셸 함수
하나로 조립해 양쪽이 쓰게 한다.

### E. 인증 검사 범위

현재는 `$TEAM_AGENT` 하나만 검사한다. 혼합 팀에서는 **실제로 사용되는 공급자 전부**를
검사해야 한다. `MEMBER_AGENTS`에서 사용 중인 공급자 집합을 구해 각각
`claude auth status` / `codex login status`를 돌린다.

## 구현 단계

### 1단계 — busy 마커 독립 (선행) — 완료

- [x] `bin/say`의 `deliver` 성공 직후 대상 파인 마커를 `touch`
- [x] Claude 파인 회귀 확인: 중복 `touch`가 기존 큐 동작을 바꾸지 않는지
- [x] `SAY_NOWAIT=1` 경로에서도 마커가 켜지는지 확인 (`deliver` 공용 경로라 자동 커버)

완료 조건: Claude 전용 팀의 큐잉·전달 동작이 변경 전과 동일하다.

### 2단계 — 파인별 에이전트 분기

- [ ] `team/config.sh`에 `MEMBER_AGENTS` 도입, 미선언 시 전역값 폴백
- [ ] 배열 길이 검증을 기존 검증부에 추가
- [ ] 공급자별 모델 배열을 동시에 로딩하도록 설정 해석부 수정
- [ ] 실행 루프를 파인별 분기로 교체
- [ ] 사용되는 공급자 전부에 대해 인증 검사
- [ ] `[7/7]` 출력에 파인별 에이전트명 표시

완료 조건:

- `MEMBER_AGENTS` 미선언 프로젝트가 이전과 동일하게 뜬다.
- reviewer만 Codex인 팀이 6개 파인으로 정상 기동한다.
- 각 파인이 자기 역할과 프로젝트 루트를 정확히 설명한다.

### 3단계 — Codex 파인 관측성

- [ ] `notify` = `agent-turn-complete` 훅 생성 및 주입
- [ ] Claude `Stop`과 종료 신호 로직을 공용 함수로 통합
- [ ] 중복 보고 가드(`/tmp/team-say`) 동작 확인
- [ ] rtk·툴 로그 미지원을 README의 공급자 차이 표에 기재

완료 조건:

- Codex reviewer가 리뷰 중일 때 lead의 `say`가 큐에 쌓인다.
- 리뷰 종료 후 큐 메시지가 자동 전달된다.
- 본 보고가 있으면 종료 신호가 중복 전달되지 않는다.
- 본 보고 없이 끝나면 lead가 자동 신호를 받는다.

### 4단계 — 문서화

- [ ] README에 혼합 팀 설정 예시 추가
- [ ] 공급자별 기능 차이 표에 파인 단위 관점 추가
- [ ] `team/config.sh` 주석에 `MEMBER_AGENTS` 사용법 기재

## 검증 계획

### 정적 검증

```bash
bash -n setup-team.sh
bash -n bin/say
```

- `MEMBER_AGENTS` 길이 불일치가 비정상 종료하는지 확인한다.
- 알 수 없는 에이전트명이 오류로 종료하는지 확인한다.
- 생성된 Codex 설정을 `--strict-config`로 검증한다.

### 큐 동작 테스트 (핵심)

혼합 실행의 실패 모드가 전부 여기에 몰려 있다.

1. Codex reviewer에 긴 작업을 지시한다.
2. 작업 중 lead에서 두 번째 `say`를 보낸다.
3. 큐 파일에 쌓이고 즉시 전달되지 **않는지** 확인한다.
4. 리뷰 종료 후 자동 전달되는지 확인한다.
5. `SAY_NOWAIT=1`이 큐를 무시하고 즉시 꽂는지 확인한다.
6. 파인을 강제 종료해 stale 마커가 30분 만료로 회수되는지 확인한다.

### 혼합 팀 통합 테스트

- Claude 5 + Codex reviewer 6파인 기동
- developer → reviewer 리뷰 요청 경로
- reviewer → lead 본 보고
- reviewer 미보고 종료 시 자동 신호
- 전원 Claude 팀 회귀
- 전원 Codex 팀 회귀

## 위험과 대응

### 마커 소유권 이전의 회귀 위험

`say`가 마커를 켜면 Claude 파인에서는 harness 훅과 이중으로 켜진다. 지우는 쪽은 여전히
훅 하나뿐이므로 삭제 경합은 없지만, 사람이 파인에 직접 입력한 턴에서는 `say`가 개입하지
않아 마커가 켜지지 않는다. 이는 변경 전 Codex 파인과 같은 수준이며, 화면 기반 폴백 판정이
남아 있다. 1단계를 단독 커밋해 회귀를 격리한다.

### 공급자별 설정 파일 부재

혼합 팀은 두 설정 파일을 모두 읽지만, 프로젝트가 하나만 둘 수 있다. 부재는 오류가 아니라
빈 배열로 처리하고, 실제로 그 공급자를 쓰는 파인이 있는데 모델이 비면 CLI 기본 모델로
진행한다.

### Codex `notify` 계약 미검증

`agent-turn-complete`는 바이너리 문자열로만 확인했다. 실제 페이로드 형식과 호출 시점은
스모크 테스트로 실측해야 한다. 실측 전에는 3단계를 완료로 표시하지 않는다.

### reviewer 품질 변동

모델을 바꾸면 리뷰 문체와 지적 밀도가 달라진다. `team/reviewer.md`가 요구하는 출력 형식이
Codex에서도 지켜지는지 실제 리뷰 몇 건으로 확인하고, 필요하면 지침을 공급자 중립적으로
다듬는다. 지침을 Codex에 맞춰 특화하지는 않는다.

## 최종 완료 기준

- `MEMBER_AGENTS`로 파인별 에이전트를 지정할 수 있다.
- reviewer만 Codex인 팀에서 `say` 큐와 유휴 판정이 단일 공급자 팀과 동일하게 동작한다.
- 미선언 프로젝트와 단일 공급자 팀의 기존 동작이 유지된다.
- Codex 파인에서 지원되지 않는 기능이 README에 명시된다.
- 큐 동작 테스트 6항목이 모두 통과한다.

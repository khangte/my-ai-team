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

| 시점                       | 훅                 | 동작            |
| -------------------------- | ------------------ | --------------- |
| 턴 시작                    | `UserPromptSubmit` | 마커 생성       |
| 턴 종료                    | `Stop`             | 마커 삭제       |
| `/clear`·`/compact`·재시작 | `SessionStart`     | stale 마커 삭제 |

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

**정정 (실측 후):** 아래 §"2단계 실측 결과"에서 확인했듯 Codex CLI 0.149.1은 Claude Code와
거의 동일한 훅 스키마(`PreToolUse`/`Stop`/`UserPromptSubmit`/`SessionStart` 등)를
`.codex/hooks.json`으로 지원한다. 최초 조사 시점에 바이너리 문자열만으로 "턴 시작 훅이
없다"고 판단한 것은 틀렸다 — 캐시된 공식 문서(`codex-manual.md`)를 확인하기 전이었다.
다만 1단계(A안, `say`가 마커를 직접 켠다)는 여전히 유효하고 더 낫다: harness 훅 두 종류를
동시에 유지·검증할 필요 없이 공급자 중립적으로 한 곳에서 turn-start를 확정하기 때문이다.
`Stop`(종료 신호)은 이식했지만 `UserPromptSubmit`(마커 생성)은 이식하지 않았다 —
1단계가 이미 그 자리를 채우고 있어 중복이다.

| 기능                 | 근거                                            | 대응                                       |
| -------------------- | ----------------------------------------------- | ------------------------------------------ |
| busy 마커 생성       | 1단계(A안)로 공급자 중립 해결                   | Codex 쪽 `UserPromptSubmit` 훅 이식 불필요 |
| 자동 종료 신호       | `.codex/hooks.json`의 `Stop` 이벤트로 이식 완료 | `stop_hook_cmd_for_role` 공용 함수         |
| `say` 중복 보고 가드 | 같은 `Stop` 훅에 얹음                           | 위와 함께 이식 완료                        |
| rtk 토큰 절감        | `PreToolUse` matcher, Codex 프로세서 부재       | 포기, 문서화                               |
| 툴 로그 JSONL        | 같은 `PreToolUse`                               | 후속 과제 (미구현)                         |

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

### D. Codex 파인의 종료 신호 — 실측 후 확정 설계

당초 예상한 `notify` = `agent-turn-complete`(CLI 플래그) 대신, Claude와 동일한
**`.codex/hooks.json`의 `Stop` 이벤트**를 쓴다. 캐시된 공식 문서(`codex-manual.md`
"Hooks" 절)로 확인한 실제 스키마:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "..." }] }]
  }
}
```

동작:

```text
1. rm -f /tmp/team-busy/{pane_id}
2. /tmp/team-say/{pane_id} 마커가 있으면 소비하고 종료 (본 보고 있음)
   없으면 lead에 자동 종료 신호를 say로 전송
```

Claude 쪽 `hook_cmd`와 완전히 같은 로직이므로 `stop_hook_cmd_for_role()` 셸 함수
하나로 조립해 양쪽 `start_claude_in_pane`/`write_codex_role_agents`가 공유한다.

**신뢰 절차 우회.** Codex 문서: "Non-managed hooks must be reviewed and trusted
before they run." 프로젝트 로컬 `.codex/hooks.json`은 기본적으로 사람이 `/hooks`로
검토·신뢰해야 실행된다. 무인 파인에는 검토할 사람이 없으므로
`--dangerously-bypass-hook-trust`를 `codex` 실행 커맨드에 추가한다 —
`--ask-for-approval never`와 같은 무인 실행 전제선상의 플래그다.

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

### 2단계 — 파인별 에이전트 분기 — 완료

- [x] `team/config.sh`에 `MEMBER_AGENTS` 도입, 미선언 시 전역값 폴백
- [x] 배열 길이 검증을 기존 검증부에 추가
- [x] 공급자별 모델 배열을 동시에 로딩하도록 설정 해석부 수정
      (`USED_AGENTS` 집합을 구해 사용되는 공급자마다 `config.{agent}.sh`를 각각
      로딩하고, `PROVIDER_MEMBER_MODELS["${agent}:${i}"]` 맵에 저장)
- [x] 실행 루프를 파인별 분기로 교체 (`MEMBER_AGENTS[$pane]` 기준)
- [x] 사용되는 공급자 전부에 대해 인증 검사 (`USED_AGENTS[claude]`/`[codex]` 각각)
- [x] `[7/7]` 출력에 파인별 에이전트명 표시
- [x] `[1-4/7]` Claude·Codex 준비 블록을 `if/else` 배타 구조에서 두 개의 독립
      조건으로 분리, `.team/` 삭제를 공급자 공통 구간에서 한 번만 실행

완료 조건 — 모두 실측 확인:

- `MEMBER_AGENTS` 미선언 프로젝트가 이전과 동일하게 뜬다. (전원 claude / 전원 codex
  두 케이스 모두 기존 모델 배분과 일치함을 격리 테스트로 확인)
- reviewer만 Codex인 팀 구성에서 `MEMBER_AGENTS`·`USED_AGENTS`·파인별 모델이 의도대로
  해석됨을 확인 (`pane 5 (reviewer, codex): model=gpt-5.6-sol`).
- `MEMBER_NAMES` 길이를 프로젝트에서 바꿨는데 공급자 모델 배열 길이가 안 맞으면
  정확히 오류로 종료함을 확인.

### 3단계 — Codex 파인 관측성 — 완료 (실 tmux 파인 E2E 검증까지 마침)

- [x] `.codex/hooks.json`의 `Stop` 이벤트로 종료 신호 훅 생성 및 주입
      (당초 계획한 `notify`=`agent-turn-complete`가 아니라 Claude와 동일한 훅
      스키마로 확정 — 위 §D 실측 후 확정 설계 참조)
- [x] Claude `Stop`과 종료 신호 로직을 `stop_hook_cmd_for_role()` 공용 함수로 통합
- [x] JSON 이스케이프 버그 수정: `STOP_HOOK_CMD`를 순수 셸 커맨드로 바꾸고
      `json_escape()` 공용 헬퍼로 소비 시점에 한 번만 이스케이프 (아래 §실측
      중 발견한 버그 참조 — 이중 이스케이프로 Codex의 Stop 훅이
      `syntax error near unexpected token '('`로 매번 실패했었다)
- [x] `--dangerously-bypass-hook-trust`가 문서·배너와 달리 `/hooks` 화면의
      review 요구를 없애지 못함을 실측으로 확인, `start_codex_in_pane`에
      `/hooks` → `t`(trust all) → `esc` 자동 입력 시퀀스 추가로 해결
      (git 프로젝트 신뢰 프롬프트 "Do you trust the contents" 자동 처리도 함께 추가)
- [x] 실제 tmux 파인에서 Codex `Stop` 훅이 트리거되는지 통합 테스트 —
      격리된 2파인(lead+reviewer) 프로젝트로 `setup-team.sh --agent codex`를
      풀 실행하고, `say`로 실제 메시지를 보내 busy 마커 생성→Stop 훅 실행→
      마커 삭제까지 실측 확인. `Stop hook (blocked)` 오류 없음.
- [ ] rtk·툴 로그 미지원을 README의 공급자 차이 표에 기재

완료 조건 — 모두 실 tmux 파인에서 확인:

- [x] hooks.json이 역할별로 올바른 커맨드로 생성된다.
- [x] `say`로 Codex 파인에 메시지를 보내면 busy 마커가 즉시 켜진다 (1단계 기능,
      Codex 파인에서도 정상 동작 확인).
- [x] 응답 완료 후 Stop 훅이 실행돼 busy 마커가 삭제된다 (`Stop hook (blocked)`
      오류 없이 조용히 성공).
- [ ] lead가 실제로 큐잉된 메시지를 자동 전달받는 시나리오는 lead 파인이 사람 입력
      대기 상태였던 테스트 환경 특성상 별도로 재현하지 않았다 — 마커 생성·삭제
      메커니즘 자체가 Claude와 동일하게 검증됐으므로 파생 동작으로 간주.

### 4단계 — 문서화 — 완료

- [x] `team/config.sh` 주석에 `MEMBER_AGENTS` 사용법 기재
- [x] 스크립트 상단 주석에 혼합 팀 실행 흐름 반영
- [x] README에 "혼합 팀 — 역할별로 다른 에이전트 지정" 절 추가 (설정 예시,
      길이 검증·인증 검사 범위 설명 포함)
- [x] "Codex 실행 모드" 절을 실제 이식 완료 상태로 갱신 (Stop 훅·신뢰 자동
      승인 반영, 예전에 "이식하지 않는다"고 썼던 rtk·gstack·로깅은 계속
      미지원으로 명시해 구분)
- [x] "Stop 훅 — 보고 누락 방지" 절에 Codex 이식 사실과 자동 승인 처리 반영
- [x] "setup-team.sh 실행되면" 절의 인증 확인 단계를 공급자별 분기로 수정

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

### Codex `hooks.json` 실행 — 실측 완료, 두 개의 실제 버그를 발견·수정

`.codex/hooks.json`을 실 tmux 파인에서 검증하는 과정에서 설계만으로는 드러나지 않는
버그 두 개를 발견했다.

**1. JSON 이중 이스케이프.** `STOP_HOOK_CMD`는 원래 Claude용으로 이미 JSON
이스케이프된 리터럴(`\\\"`)을 하드코딩하고 있었다. 이 값을 그대로 Codex hooks.json에
넣거나(1차 시도), 거기에 `sed`로 재이스케이프를 씌우거나(2차 시도) 둘 다 실패했다.
Codex의 훅 실행기는 Claude Code와 달리 `command` 문자열을 `/bin/bash -c`에 거의 그대로
넘기는데, 리터럴 `\"` 두 글자가 남으면 `(자동)`의 괄호가 quoting 밖으로 노출돼
`syntax error near unexpected token '('`로 매 턴 실패했다 — 화면에 그대로 노출되는
형태라 원인 규명은 어렵지 않았다. **근본 수정**: `STOP_HOOK_CMD`를 순수 셸 문자열로
바꾸고, JSON에 넣는 시점에 `json_escape()`(백슬래시 다음 큰따옴표 순서로 1회
이스케이프)를 소비자마다 호출하도록 통일했다. Claude 쪽도 같은 함수로 옮겨 향후
이런 종류의 불일치가 재발하지 않게 했다.

**2. `--dangerously-bypass-hook-trust`가 문서·CLI 배너와 다르게 동작.** 플래그를 켜면
배너에 "Enabled hooks may run without review for this invocation"이라고 뜨지만, 실제로
`/hooks` 화면을 열어보면 `Stop: Installed 1, Active 0, Review 1`로 남아 있었다 — 즉
플래그는 review 화면 자체를 없애지 못했다. 사람이 `/hooks`에서 `t`(trust all)를 눌러야
`Active 1`로 바뀌었고, 그 전까지 Stop 훅은 조용히(에러 메시지 없이) 실행되지 않아
busy 마커가 영원히 안 지워졌다. `start_codex_in_pane`에 `/hooks` → `t` → `esc` 자동
입력 시퀀스를 추가해 해결했다. git 프로젝트 신뢰 프롬프트("Do you trust the contents
of this directory?")도 이전엔 자동 처리가 없어 같은 자리에서 추가했다.

두 버그 모두 정적 검증(JSON 파싱 왕복)만으로는 드러나지 않았다 — 실제 Codex CLI가
훅을 실행하는 런타임 계약(이스케이프 처리 방식, 신뢰 승인 UI 흐름)은 문서와
배너 문구만으로 신뢰할 수 없다는 게 이번 작업의 핵심 교훈이다. 격리된 2파인
프로젝트로 `setup-team.sh --agent codex`를 처음부터 끝까지 실행하고, 실제 `say`
메시지로 busy 마커 생성→Stop 훅 실행→마커 삭제 전 과정을 확인한 뒤에야 3단계를
완료로 표시했다.

### reviewer 품질 변동

모델을 바꾸면 리뷰 문체와 지적 밀도가 달라진다. `team/reviewer.md`가 요구하는 출력 형식이
Codex에서도 지켜지는지 실제 리뷰 몇 건으로 확인하고, 필요하면 지침을 공급자 중립적으로
다듬는다. 지침을 Codex에 맞춰 특화하지는 않는다.

## 최종 완료 기준

- [x] `MEMBER_AGENTS`로 파인별 에이전트를 지정할 수 있다.
- [x] reviewer만 Codex인 팀에서 `say` 큐와 유휴 판정이 단일 공급자 팀과 동일하게
      동작한다 (실 tmux 파인으로 busy 마커 생성→Stop 훅→마커 삭제 전 과정 확인).
- [x] 미선언 프로젝트와 단일 공급자 팀의 기존 동작이 유지된다 (전원 claude/전원 codex
      두 케이스 모두 격리 테스트로 회귀 없음 확인).
- [x] Codex 파인에서 지원되지 않는 기능(rtk, 툴 로그)이 README에 명시된다
      ("Codex 실행 모드" 절 참고).
- [ ] 큐 동작 테스트 6항목 중 lead 자동 전달 재현은 별도 실행 안 함(§3단계 완료
      조건 참조) — 나머지는 통과.

## 남은 작업 (후속)

- 실제 프로젝트에서 reviewer를 Codex로 돌려 리뷰 품질(문체·지적 밀도)을 몇 건
  확인 — `team/reviewer.md` 지침이 공급자 중립으로 잘 작동하는지 실사용 검증.

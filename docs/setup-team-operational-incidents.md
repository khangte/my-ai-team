# setup-team.sh 운영 이력과 구현 근거

- 작성일: 2026-09-23

이 문서는 `setup-team.sh`에서 축약·제거한 인라인 주석을 원문 근거로 옮긴 운영 기록이다.
스크립트 주석을 구현을 이해하는 데 필요한 수준으로 유지하기 위해, 과거 증상·재현 과정·
수치 기반 배분 근거는 여기 보관한다. 아래는 스크립트가 처리하는 시간 순서, 즉 구성 결정 →
런타임 준비 → 파인 기동 → 턴 처리 → 종료·압축 순서다.

## `CLAUDE_CONFIG_DIR` 격리안을 채택하지 않은 이유

파인별 `CLAUDE_CONFIG_DIR`로 사용자 전역 규칙을 차단하는 스파이크를 수행했다.
새 빈 디렉터리를 지정하면 `~/.claude/CLAUDE.md`, `rules/`, RTK 규칙을 읽지 않는 것은
확인됐다. 그러나 인증 정보도 새 디렉터리에서 찾으므로 `.credentials.json`이 없으면 로그인 실패가 발생한다.

더 중요한 실패 지점은 플러그인이다. `--settings`로 Caveman을 활성화해도 새 config
디렉터리에는 `plugins/{cache,data,marketplaces}`가 없어서 모드가 활성화되지 않았다.
인증 파일과 플러그인 디렉터리를 심볼릭 링크하는 우회는 가능해 보이지만, 사용자 전역
설정 구조를 건드리며 별도 설계·승인이 필요한 작업이다. 따라서 현재는 이 방식으로 파인별 격리를 시도하지 않는다.

## Claude 플러그인 역할 배분의 비용 근거

파인 5개 이상에서 플러그인을 전부 켜면 스킬 frontmatter·SessionStart 주입·MCP 도구 정의가 매 턴 고정비로 누적된다.

| 구성 요소 |  관측 고정비 | 주요 원인                                                        |
| --------- | -----------: | ---------------------------------------------------------------- |
| ponytail  | 약 2.2K 토큰 | 스킬 frontmatter 약 0.9K + SessionStart 주입 약 1.3K             |
| caveman   | 약 3.9K 토큰 | 스킬 frontmatter 약 2.8K + SessionStart 주입 약 1.0K             |
| serena    |   약 6K 토큰 | MCP 도구 정의 30개; 스킬이 없어 plugin details에는 나타나지 않음 |

### 역할별 판단

- caveman은 모든 파인에 준다. 켠 파인이 아니라 lead가 보고를 입력으로 받아 이득을 회수하는 구조이며, 팀 전체 출력 문체 통일의 가치가 고정비보다 크다는 판단이다.
- ponytail은 최종적으로 developer에만 준다. 기존 헬퍼 재사용부터 한 줄 구현까지의 사다리 중 코드 대상인 2~7단을 실제로 사용하는 역할이 developer이기 때문이다. lead·architect·reviewer의 YAGNI 판단은 역할 지침의 한 문장으로 보완하는 편이 고정비보다 훨씬 싸다.
- serena는 고정비가 가장 크므로 현재는 developer·reviewer에만 준다. frontend를 실제로 구현하는 designer 역할을 다시 활성화하면 Serena의 LSP 백엔드가 ts/tsx·vue·svelte·html·scss와 심볼 참조 탐색을 지원한다는 점을 고려해 별도로 배정 여부를 판단한다.

`PLUGIN_ROLES`와 역할별 스킬 집합은 `team/config.claude.sh`가 원본이다. 배분을 바꿀 때에는 역할별 사용 빈도뿐 아니라 lead에 집계되는 보고의 비용도 함께 검토한다.

### 상충하는 과거 권고의 우선순위

`docs/architect-review/6_caveman-ponytail-role-scoping.md`는 비용 관점에서 caveman 전면 제외를 권고했지만, 이후 사용자 최종 결정은 **caveman 전 역할 유지, ponytail developer만 유지**였다. 현재 설정을 바꿀 때에는 6번 문서의 권고가 아니라 이 최종 결정을 기준으로 삼는다.

## Caveman SessionStart와 Node 경로

Caveman 플러그인은 자체 `SessionStart` 훅을 갖고 있으며 matcher가 없다. 따라서 `startup`, `resume`, `/clear`, `/compact` 모든 소스에서 발화한다. 별도의 Caveman SessionStart 훅을 추가할 필요는 없다.

다만 실제 위험은 훅의 부재가 아니라 Node를 찾지 못해 훅이 조용히 실패하는 경우다. 플러그인 훅은 `node`라는 이름만 실행하므로 Node가 nvm 버전 디렉터리 아래에 있고 tmux 서버의 PATH가 이를 물려받지 못하면 Caveman·Ponytail 훅이 활성화되지 않는다.

`setup-team.sh`는 가장 최신 nvm Node의 `bin` 경로를 `NVM_BIN`으로 구한 뒤 각 파인을 기동하는 `export PATH`에 명시적으로 넣는다. 이 경로를 제거하거나 tmux 서버 환경에만 의존하지 않는다.

`CAVEMAN_DEFAULT_MODE=full`은 startup 때 기본 모드를 고정한다. 단 `/clear`와 `/compact`에서는 `~/.claude/.caveman-active`의 기존 모드가 우선할 수 있다. 이 파일은 모든 파인 및 사용자 개인 세션이 공유하므로, 한 세션의 lite 설정이 이후 compact를 거친 다른 파인에 전파될 수 있다는 한계가 있다.

## Codex 프로젝트 로컬 훅 신뢰

Codex 역할별 `.codex/hooks.json`은 프로젝트 로컬 훅이므로 기본적으로 신뢰 검토가 필요하다. 무인 파인에서 승인 대기를 피하려고 `--dangerously-bypass-hook-trust`를 사용한다.

다만 이 플래그만으로는 충분하지 않은 TUI 실행이 관측됐다. CLI 배너에는 review 없이 실행될 수 있다고 표시됐지만 `/hooks` 화면의 review 배지가 남았고, Stop 훅은 Active 0인 채로 남았다. 이때 문법 오류 없이 busy 마커 정리와 자동 종료 신호가 조용히 실행되지 않았다.

`/hooks` 화면에서 사람이 `t`(trust all)를 누르면 Active 1로 바뀌어 훅이 동작한다. 팀 파인에는 사람이 붙어 있지 않으므로 `start_codex_in_pane`은 다음 절차를 자동화한다.

1. Codex 프롬프트가 입력을 받을 때까지 기다린다.
2. `/hooks`를 열고 `t`로 전체 훅을 신뢰한다.
3. Escape로 화면을 닫는다.

이 입력은 TUI가 준비되기 전에 보내면 무시될 수 있으므로, 프롬프트 문구를 기다린 뒤 전송해야 한다.

## busy·보고 마커의 턴 경계

`say`가 화면의 `esc to interrupt` 문구로 유휴 여부를 판정하던 때에는, `--dangerously-skip-permissions` 모드의 하단 힌트줄에 그 문구가 상시 남아 유휴 파인을 busy로 오판했다. 본문 노출과 다른 원인이라 캡처 범위를 줄여도 해결되지 않았고, 메시지가 최대 30분 동안 큐에 쌓일 수 있었다.

그래서 현재는 화면 상태 대신 harness가 실행하는 실제 턴 경계를 쓴다.

- `UserPromptSubmit`에서 `/tmp/team-busy/<state_key>`를 만들고 보고 마커를 지운다.
- `Stop`에서 busy 마커를 지우고, 본 보고 마커가 없을 때만 자동 종료 신호를 보낸다.
- `/clear`·`/compact`는 진행 중인 턴을 Stop 훅 없이 끊을 수 있으므로, `SessionStart`에서 잔존 busy 마커를 지운다.

보고 마커는 “이번 턴에 보고했는가”를 나타내는 1비트다. 턴 시작에서 초기화하지 않으면 한 턴에 여러 번 보고했을 때 Stop 훅이 한 번만 소비한 마커가 다음 턴의 종료 신호를 잘못 억제할 수 있다. 과거에는 reviewer가 14:02에 보고한 뒤 14:04에 미보고 종료 신호가 오탐으로 발생한 사례도 있었다.

마커 키는 논리적 파인 번호가 아니라 tmux의 세션·파인 고유 ID로 만든다. 같은 세션 이름으로 팀을 다시 만들어도 이전 실행의 marker와 충돌하지 않게 하기 위해서다.

## Stop 훅 명령의 이중 이스케이프

Stop 훅 종료 신호는 Claude와 Codex 양쪽에서 `command` 타입으로 셸 명령을 실행한다. 이 공통 동작을 이용해 종료 신호 로직은 한 곳에서 조립한다.

이때 공용 함수가 이미 JSON 이스케이프된 값(`\\\"` 리터럴)을 만들면 안 된다. 과거에는 그 값을 Claude JSON에 그대로 넣었으나, Codex 훅 실행기는 남아 있는 백슬래시를 그대로 셸에 넘겼고 `syntax error near unexpected token '('` 오류가 발생했다.

현재 계약은 다음과 같다.

- `stop_hook_cmd_for_role`는 순수 셸 명령 문자열을 `STOP_HOOK_CMD`에 넣는다.
- Claude·Codex 설정을 만드는 소비자가 JSON의 `command` 필드에 넣기 직전에 `json_escape`를 적용한다.
- lead는 수신처가 자기 자신(`:0.0`)이므로 종료 신호를 보내지 않고 busy 마커만 지운다.
- 그 외 역할은 본 보고 마커가 있으면 이를 소비하고 조용히 끝내며, 없을 때만 lead에 자동 종료 신호를 보낸다.

## 컨텍스트 축소 시 `/clear`를 강제하지 않는 이유

`/clear`는 세션을 새로 시작하여 시스템 프롬프트, 규칙 체인, 스킬 목록의 프롬프트 캐시를 무효화한다. 관측 당시 세션 첫 턴의 `cache_creation_input_tokens` 중앙값은 27,547이었고, cache_create 단가는 cache_read보다 12.5배였다.

`/compact`는 세션과 프리픽스 캐시를 유지한 채 대화 본문만 요약한다. 따라서 수동 압축은 기능 구현 완료, 리뷰 반영 완료, 커밋 직후 같은 자연 경계에서만 사용한다. 기본적으로는 `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`이 1M 컨텍스트 모델을 200K에서 자동 compact하도록 설정하므로, `/clear`를 주기적으로 지시하지 않는다.

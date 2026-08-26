# Codex 지원 추가 계획

## 목적

현재 하네스는 Claude Code 인스턴스 여러 개를 tmux 파인에 띄우고, 역할별 지침·스킬·훅을
주입해 하나의 팀으로 동작시킨다. 이 구조를 Claude 전용 구현에서 `claude | codex` 중 하나를
선택할 수 있는 이중 백엔드 구조로 확장한다.

이번 작업의 핵심은 Claude 설정을 Codex 형식으로 일괄 변환하는 것이 아니다. tmux 파인,
`bin/say`, 역할 문서와 보고 체계처럼 모델 공급자와 무관한 부분은 공유하고, CLI 실행·지침 발견·
스킬 위치·설정·인증처럼 공급자에 종속된 부분만 어댑터로 분리한다.

## 목표

- 기존 Claude 실행 방식과 프로젝트별 오버라이드를 깨뜨리지 않는다.
- 같은 역할 구성으로 Claude 팀과 Codex 팀을 선택해 실행할 수 있게 한다.
- Codex 파인도 공통 지침과 자기 역할 지침만 읽게 한다.
- 기존 `say` 큐, busy 마커, 종료 신호와 로깅 구조를 Codex에서도 유지한다.
- 네이티브 실행에서는 Codex 샌드박스를 기본 안전 경계로 사용한다.
- Docker 실행에서는 컨테이너를 외부 격리 경계로 사용하는 선택지를 제공한다.

## 비목표

- Claude 플러그인을 전부 Codex 플러그인으로 자동 변환하지 않는다.
- 1차 구현에서 tmux 팀을 Codex 네이티브 서브에이전트 구조로 교체하지 않는다.
- 사용자 전역 `~/.claude`, `~/.codex`, `~/.agents` 설정을 수정하지 않는다.
- 특정 Codex 모델을 모든 사용자에게 강제하지 않는다. 계정·워크스페이스별 모델 가용성이
  다를 수 있으므로 프로젝트 설정이나 Codex 기본값으로 선택할 수 있게 한다.

## 현재 구조에서 분리해야 할 지점

현재 `setup-team.sh`에는 다음 Claude 전용 동작이 함께 들어 있다.

- `claude auth status`를 이용한 인증 확인
- `claude` CLI 실행과 `--append-system-prompt-file`, `--settings` 인자 조립
- 프로젝트 `CLAUDE.md`에 공통 규칙 병합
- `.team/{역할}/.claude/skills`를 이용한 역할별 스킬 제한
- `rtk hook claude` PreToolUse 훅
- Claude 마켓플레이스 플러그인 설치와 역할별 활성화
- Claude 모델명을 담은 `MEMBER_MODELS`
- `CLAUDE_CODE_*` 환경변수와 cross-session messaging 설정

반면 아래 요소는 Codex에서도 그대로 공유할 수 있다.

- tmux 세션과 파인 분할
- `MEMBER_NAMES` 역할 목록
- `team/{역할}.md` 역할 지침 원문
- `bin/say`의 대상 해석, 큐, 유휴 대기와 전송 검증
- `/tmp/team-busy`, `/tmp/team-say` 마커 규약
- 역할별 런타임 디렉터리 `.team/{역할}`
- lead 중심 보고 경로

## Claude와 Codex 설정 대응

| 관심사 | Claude | Codex | 구현 방침 |
| --- | --- | --- | --- |
| 저장소 공통 지침 | `CLAUDE.md` | `AGENTS.md` | 각각 별도 마커 블록으로 대상 프로젝트에 병합 |
| 역할별 지침 | `--append-system-prompt-file` | `.team/{역할}/AGENTS.md` | `team/{역할}.md` 원문은 공유하고 공급자별 래퍼만 생성 |
| 역할별 스킬 | `.claude/skills` | `.agents/skills` | 같은 런타임 디렉터리 아래에 공급자별 경로 생성 |
| 프로젝트 설정 | `settings.json` | `.codex/config.toml`, `.codex/hooks.json` | 정적 설정과 훅을 분리해 생성 |
| 승인·격리 | `--dangerously-skip-permissions` | sandbox + approval policy | 네이티브와 Docker 기본값을 구분 |
| 인증 | `claude auth status` | `codex login status` | 선택된 백엔드만 검사 |
| 모델 | Claude 모델명 | Codex 모델명 | 공급자별 모델 배열 또는 기본 모델 사용 |
| 훅 | Claude hooks | Codex hooks | 공통 이벤트는 재사용하되 입력 스키마 실측 후 로거 보정 |
| 플러그인 | Claude marketplace | Codex skills/plugins | 1:1 대응을 가정하지 않고 개별 이식 |

Codex는 Git 루트부터 현재 작업 디렉터리까지 `AGENTS.md`를 계층적으로 읽는다. 따라서
대상 프로젝트 루트의 `AGENTS.md`에는 팀 공통 규칙을 넣고, `.team/{역할}/AGENTS.md`에는
역할 지침을 넣으면 기존의 공통 지침 + 역할별 지침 구조를 자연스럽게 재현할 수 있다.

참고 문서:

- [Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex config basics](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [Import from another agent](https://learn.chatgpt.com/docs/import)

## 목표 실행 인터페이스

기본값은 기존 호환성을 위해 Claude로 둔다.

```bash
./setup-team.sh --agent claude /path/to/project
./setup-team.sh --agent codex /path/to/project

# 자동화나 프로젝트 래퍼에서 사용
TEAM_AGENT=codex ./setup-team.sh /path/to/project
```

우선순위는 명시적 CLI 인자, 환경변수, 기본값 순으로 한다.

```text
--agent 값 > TEAM_AGENT > claude
```

알 수 없는 값은 Claude로 조용히 폴백하지 않고 즉시 오류로 종료한다.

## 제안 디렉터리 구조

소스 저장소:

```text
CLAUDE.md                         Claude 공통 규칙
AGENTS.md                         Codex 공통 규칙
team/
  config.sh                       역할·세션 등 공급자 중립 설정
  config.claude.sh                Claude 모델·플러그인·역할별 스킬 배분
  config.codex.sh                 Codex 모델·추론 수준·역할별 스킬 배분
  {역할}.md                       공급자 중립 역할 지침
```

대상 프로젝트에 실행 시 생성되는 구조:

```text
.team/
  _runtime/
    {역할}.prompt.md              기존 Claude용 조립 지침
    {역할}.settings.json          기존 Claude용 런타임 설정
  {역할}/
    AGENTS.md                     Codex 역할 지침
    .agents/skills/               Codex 역할별 스킬
    .codex/config.toml            Codex 역할별 설정
    .codex/hooks.json             Codex 역할별 훅
```

별도의 `team/providers/` 계층은 지금 만들지 않는다. 현재는 공급자별 선언을 기존
`config.claude.sh`, `config.codex.sh`에 모으고, 인증·설치·링크·파인 실행처럼 상태를 변경하는
절차는 `setup-team.sh`에 유지하는 편이 파일 수와 추상화 비용을 함께 억제한다. 공급자별 실행
코드가 독립적으로 테스트할 만큼 커지거나 동일한 조건문이 반복될 때만 `lib/providers/` 같은
실행 모듈 분리를 다시 검토한다.

### 구성 배치 원칙

`setup-team.sh`에 Claude와 Codex의 모든 내용을 몰아넣지는 않는다. 현재 스크립트는 이미 역할별
플러그인과 스킬 배분 선언, 설치·링크 절차, 훅 설정 생성, tmux 실행을 함께 담당하고 있다.
Codex 배분표까지 같은 위치에 추가하면 역할 정책을 바꾸는 작업이 런처 동작 변경과 섞이게 된다.

다음 기준으로 선언과 절차를 구분한다.

| 내용 | 배치 위치 | 이유 |
| --- | --- | --- |
| 세션 이름과 역할 목록 | `team/config.sh` | 공급자와 무관한 팀 구성 |
| 역할별 모델과 추론 수준 | `team/config.{agent}.sh` | 공급자마다 값과 지원 범위가 다름 |
| 역할별 스킬·플러그인 배분표 | `team/config.{agent}.sh` | “누가 무엇을 받는가”라는 선언적 정책 |
| 역할의 책임과 행동 지침 | `team/{역할}.md` | 긴 자연어 지침을 셸 문자열과 분리하고 양쪽에서 공유 |
| 인증·설치·심볼릭 링크·설정 파일 생성 | `setup-team.sh` | 실행 시점의 상태 변경과 오류 처리가 필요한 절차 |
| Codex/Claude CLI 인자 조립과 tmux 기동 | `setup-team.sh` | 런처의 핵심 실행 책임 |

즉, `setup-team.sh`는 설정을 **해석하고 적용**하되 역할별 정책의 원본은 소유하지 않는다.
공급자별 설정 파일은 신뢰된 Bash 파일로 `source`하므로 데이터 선언만 두고 설치나 파일 변경 같은
부수 효과는 넣지 않는다.

## 설정 설계

### 공통 팀 설정

`team/config.sh`에는 공급자와 무관한 값만 남긴다.

```bash
SESSION="team1"
declare -a MEMBER_NAMES=("lead" "architect" "researcher" "designer" "developer" "reviewer")
```

### 공급자별 역할 설정

`team/config.claude.sh`와 `team/config.codex.sh`에서 동일한 인덱스의 역할에 대응하는 모델을
정한다. Codex 모델 값이 비어 있으면 `--model`을 넘기지 않아 사용자의 Codex 기본 모델을
따르게 한다. Codex는 같은 인덱스의 추론 수준도 선언하고 파인 실행 시 실제 CLI 설정으로
전달한다.

```bash
# team/config.codex.sh
declare -a MEMBER_MODELS=("" "" "" "" "" "")
declare -a MEMBER_REASONING_EFFORTS=("medium" "high" "medium" "high" "high" "high")

declare -A CODEX_SKILL_SETS=(
    [architect]="..."
    [developer]="..."
    [reviewer]="..."
)
```

Claude 설정에는 기존 `PLUGIN_MARKETPLACES`, `PLUGIN_ROLES`, `GSTACK_SKILL_SETS`,
`SUPERPOWERS_SKILL_SETS`, `FRONTEND_DESIGN_SKILL_SETS` 선언을 이동한다. 해당 배열을 순회하며
설치하고 역할별 런타임 디렉터리에 연결하는 코드는 `setup-team.sh`에 남긴다.

공통 구성과 공급자 구성은 서로 독립된 두 단계로 해석한다. 각 단계에서는 저장소 기본값을 먼저
읽고 대상 프로젝트 값을 나중에 적용한다.

```text
공통 구성: 이 저장소/team/config.sh
        → 대상 프로젝트/team/config.sh

공급자 구성: 이 저장소/team/config.{agent}.sh
          → 대상 프로젝트/team/config.{agent}.sh
```

공통 설정과 공급자별 설정을 각각 독립적으로 폴백시켜, 프로젝트가 역할 구성만 바꾸거나
모델만 바꾸는 경우 모두 지원한다. 과거 프로젝트의 `team/config.sh`에 들어 있는
`MEMBER_MODELS`는 Claude 모드에서만 호환 값으로 취급하고 Codex 기본값과 섞지 않는다.

### 보정한 설정 문제

이전 구현은 저장소의 `team/config.codex.sh`를 읽은 뒤 Codex 분기에서 `MEMBER_MODELS=()`로
다시 초기화했다. 그 결과 프로젝트에 별도 `team/config.codex.sh`가 없으면 저장소에 선언한
역할별 Codex 기본 모델이 사라지고 모든 파인이 사용자 기본 모델로 실행됐다.

또한 `MEMBER_REASONING_EFFORTS`는 선언되어 있지만 파인 시작 함수로 전달되지 않아 실제 실행에
반영되지 않았다. 구성 분리 작업과 함께 다음을 보정했다.

- [x] 공통 역할 설정과 공급자 기본 설정의 로딩 순서를 명확히 한다.
- [x] 저장소의 Codex 기본 모델을 프로젝트 공통 설정과 구분해 보존한다.
- [x] 프로젝트 `team/config.{agent}.sh`가 공급자 기본값을 마지막에 덮어쓰게 한다.
- [x] 모델 배열과 추론 수준 배열의 길이를 `MEMBER_NAMES`와 함께 검증한다.
- [x] `MEMBER_REASONING_EFFORTS`를 Codex 파인 실행 시 실제 설정으로 전달한다.
- [x] 프로젝트가 특정 값을 빈 문자열로 지정해 기본 모델 또는 기본 추론 수준을 사용하려는 경우를
  명시적으로 지원한다.

### Codex 실행 정책

네이티브 기본 실행은 다음 수준을 목표로 한다.

```bash
codex \
  --ask-for-approval never \
  --sandbox workspace-write
```

- 파인이 사람 승인을 기다리며 멈추지 않는다.
- 쓰기는 작업 저장소 범위로 제한한다.
- 네트워크나 저장소 밖 작업이 필요한 명령은 자동으로 승인되지 않으므로 실패가 파인에
  반환된다.
- 훅 신뢰 우회 같은 추가 권한 옵션은 기본 실행 명령에 넣지 않고, 훅 이식 단계에서 별도로
  검증한다.

Docker에서는 컨테이너가 외부 격리 경계일 때만 `--yolo`를 선택할 수 있게 한다. 기본값으로
강제하지 않고 다음과 같은 명시적 옵션이나 환경변수를 요구한다.

```bash
CODEX_FULL_ACCESS=1 ./setup-docker.sh /path/to/project
```

## 역할 지침 로딩

### 공통 규칙

Claude와 동일하게 이 저장소의 Codex 공통 규칙을 대상 프로젝트의 `AGENTS.md`에 마커
블록으로 병합한다.

```md
<!-- BEGIN AI-TEAM CODEX -->
...
<!-- END AI-TEAM CODEX -->
```

병합 규칙은 기존 `CLAUDE.md`와 동일하게 한다.

- 파일이 없으면 생성한다.
- 기존 마커가 있으면 마커 내부만 교체한다.
- 마커가 없으면 파일 끝에 추가한다.
- 사용자가 쓴 마커 밖 내용은 보존한다.
- 대상 프로젝트가 이 저장소 자신이면 별도 병합을 하지 않는다.

### 역할 규칙

Codex 파인은 `.team/{역할}`을 cwd로 사용한다. 해당 디렉터리에 생성한 `AGENTS.md`에는
다음 내용을 넣는다.

1. `team/{역할}.md` 원문
2. 실제 프로젝트 루트 안내
3. lead에만 동적으로 생성되는 팀원 배분 표
4. Codex 파인 간에는 네이티브 서브에이전트 메시징 대신 `say`를 사용한다는 규칙

루트 `AGENTS.md`는 공통 규칙을, 역할 디렉터리의 `AGENTS.md`는 역할 규칙을 담당하므로
한 파일에 공통 내용을 중복 삽입하지 않는다.

## 스킬과 플러그인

Codex는 저장소 루트와 현재 디렉터리까지의 `.agents/skills`를 읽는다. 역할별 스킬 제한이
필요한 경우 `.team/{역할}/.agents/skills`에 필요한 스킬만 연결한다.

Claude의 스킬 디렉터리를 무조건 Codex에 심볼릭 링크하지 않는다. 먼저 각 스킬을 다음 기준으로
분류한다.

| 분류 | 처리 |
| --- | --- |
| 순수 Markdown 지침과 범용 스크립트 | Codex 호환 여부 확인 후 공유 |
| Claude 전용 툴명·훅·경로 사용 | Codex 변형을 별도로 작성 |
| Claude marketplace 전용 플러그인 | Codex 플러그인 또는 대체 스킬을 조사 |
| 대응물이 없고 필수가 아님 | Codex 모드에서 제외하고 문서화 |

`/import`는 사용자 개인 Claude 설정을 Codex로 가져오는 초기 부트스트랩에는 사용할 수 있지만,
이 하네스의 설정 소스로 사용하지 않는다. 생성형 `.team/` 구조와 프로젝트별 오버라이드는
저장소 스크립트가 재현 가능하게 관리해야 한다.

## 훅과 로깅 이식

Codex도 `UserPromptSubmit`, `PreToolUse`, `Stop`, `SessionStart` 이벤트를 지원하므로 기존
busy 마커와 종료 신호 구조를 유지한다.

### 유지할 동작

- `UserPromptSubmit`: `/tmp/team-busy/{pane_id}` 생성
- `Stop`: busy 마커 제거, 본 보고가 없으면 lead에 자동 종료 신호 전송
- `SessionStart`: stale busy 마커 제거
- `UserPromptSubmit`, `PreToolUse`: 역할별 JSONL 로그 기록

### 변경할 동작

- `rtk hook claude`는 Codex 모드에서 실행하지 않는다. 현재 RTK 훅 인터페이스에는 Codex
  프로세서가 없으므로 지원되지 않는 연결을 추측해 추가하지 않는다.
- `bin/log-hook`의 Codex 훅 입력을 샘플 세션에서 캡처해 Claude 입력과 필드 차이를 확인한다.
- 로그 경로는 장기적으로 `.agent-logs/{provider}/{role}.jsonl`로 일반화한다.
- 기존 `.claude-logs`를 읽는 문서와 분석 스크립트가 있다면 마이그레이션 기간 동안 양쪽을
  지원하거나 명시적으로 함께 변경한다.
- Codex의 훅 출력 계약을 확인한 뒤 현재 로거의 stdin 재출력이 필요한지 결정한다.

## 설치와 인증

### WSL 네이티브

`setup-native.sh`에서 선택된 백엔드 또는 두 CLI를 설치할 수 있게 한다. 기존 사용자가
Claude만 쓸 때 불필요한 Codex 설치를 강제하지 않도록 `--agent` 값을 전달받는 방식이
우선이다.

Codex 설치 명령:

```bash
npm install -g @openai/codex
```

### Docker

Docker 이미지는 Claude와 Codex를 모두 포함시켜 이미지 하나로 어느 팀이든 실행할 수 있게 한다.
Codex 인증 상태도 `/home/user` 볼륨에 보존되므로 기존 볼륨 이름 `claude-home`은 공급자 중립
이름으로 변경하는 안을 검토한다.

볼륨 이름 변경은 기존 로그인 데이터를 잃은 것처럼 보이게 만들 수 있으므로 1차 구현에서는
기존 이름을 유지하고, 추후 마이그레이션 절차와 함께 변경한다.

### 인증 흐름

- Claude 선택 시 현재 `claude auth status` 흐름을 유지한다.
- Codex 선택 시 `codex login status`를 검사한다.
- 미인증이면 해당 CLI의 로그인 안내를 표시하고 사용자가 완료할 때까지 대기한다.
- 한 공급자로 실행할 때 다른 공급자의 인증 여부는 검사하지 않는다.

## 구현 단계

### 1단계 — 최소 실행 경로

- [x] `--agent claude|codex` 파싱과 `TEAM_AGENT` 환경변수 지원
- [x] 기본값을 `claude`로 두어 기존 명령 호환 유지
- [x] Codex CLI 설치 확인과 인증 확인 추가
- [x] 공급자별 모델 설정 로딩
- [x] 대상 프로젝트 `AGENTS.md` 마커 병합
- [x] `.team/{역할}/AGENTS.md` 생성
- [x] Codex 파인 실행 함수 추가
- [x] Codex 역할별 `.agents/skills` 생성
- [x] Codex 기본 모델이 설정 로딩 중 초기화되는 문제 수정
- [x] 역할별 추론 수준을 Codex 실행에 연결하고 배열 길이 검증
- [ ] Claude 모드 회귀 테스트

완료 조건:

- 기존 인자 없는 `setup-team.sh`가 이전과 동일하게 Claude 팀을 띄운다.
- `--agent codex`로 동일한 역할 수의 Codex 파인이 뜬다.
- 각 Codex 파인이 프로젝트 루트와 자기 역할을 정확히 설명한다.
- 한 Codex 파인에서 `say lead "..."` 메시지를 전달할 수 있다.

### 2단계 — 훅과 관측성 동등성

- [ ] Codex 훅 입력 샘플 캡처와 `bin/log-hook` 호환성 확인
- [ ] 역할별 `.codex/hooks.json` 생성
- [ ] busy 마커 생성·정리 연결
- [ ] Stop 자동 보고와 중복 보고 가드 연결
- [ ] Codex 로그 경로 일반화
- [ ] `/clear` 또는 세션 재시작에 대응하는 stale 마커 정리 검증

완료 조건:

- 작업 중인 Codex 파인에는 `say` 메시지가 큐에 쌓인다.
- 파인이 유휴 상태가 되면 큐 메시지가 자동 전달된다.
- 본 보고가 있으면 Stop 종료 신호가 중복 전달되지 않는다.
- 본 보고 없이 종료하면 lead가 자동 신호를 받는다.
- 프롬프트와 툴 로그에 시크릿 본문이 그대로 기록되지 않는다.

### 3단계 — 스킬·플러그인 이식

- [x] Claude 플러그인·역할별 스킬 배분 선언을 `team/config.claude.sh`로 이동
- [x] Codex 역할별 스킬 배분 선언을 `team/config.codex.sh`에 추가
- [x] `setup-team.sh`에는 선언을 소비하는 설치·링크 절차만 유지
- [x] 현재 역할별 Claude 스킬 목록 작성
- [x] architect 스킬을 Codex 공식 카탈로그 기준으로 분류
- [x] 공식 `superpowers@openai-curated`의 `brainstorming`·`writing-plans` 대응 확인
- [x] Figma·Notion·GitHub 플러그인의 architect 선택 적용 범위 확인
- [x] 파인별 `CODEX_HOME`으로 전체 플러그인 config·cache 격리
- [x] Superpowers는 전체 설치 대신 architect에 공식 스킬 2개만 선택 노출
- [ ] 역할별 실제 로딩 스킬 목록 검증
- [x] README에 Codex architect 모델·네이티브 플러그인·훅 차이 추가

완료 조건:

- Codex 파인이 자기 역할에 허용된 스킬만 발견한다.
- 사용할 수 없는 Claude 전용 기능이 조용히 누락되지 않고 문서에 표시된다.
- Claude의 역할별 스킬 제한은 기존대로 유지된다.

### 4단계 — 문서와 배포 정리

- [ ] README 구조도와 실행 예시를 이중 백엔드 기준으로 수정
- [ ] WSL/Docker 설치 절차 수정
- [ ] 모델 설정과 프로젝트별 오버라이드 예시 추가
- [ ] 권한 모드별 위험 설명 추가
- [ ] Docker 볼륨 이름 변경 여부 결정 및 필요 시 마이그레이션 안내 작성
- [ ] Claude 전용 명칭이 남은 런타임 파일과 주석 정리

## 검증 계획

### 정적 검증

```bash
bash -n setup-team.sh
bash -n setup-native.sh
bash -n setup-docker.sh
```

- 설정 배열 길이가 `MEMBER_NAMES`와 일치하는지 검사한다.
- `--agent`의 잘못된 값이 비정상 종료하는지 확인한다.
- 생성된 JSON은 JSON 파서로, TOML은 Codex `--strict-config`로 검증한다.
- 대상 프로젝트의 기존 `CLAUDE.md`와 `AGENTS.md` 마커 밖 내용이 유지되는지 확인한다.

### 격리된 스모크 테스트

실제 작업 프로젝트 대신 `/tmp` 아래에 테스트용 Git 저장소를 만들어 확인한다.

1. `CLAUDE.md`, `AGENTS.md`가 없는 프로젝트
2. 두 파일에 사용자 내용만 있고 마커가 없는 프로젝트
3. 기존 마커 블록이 있는 프로젝트
4. 프로젝트별 `team/config.sh`만 있는 프로젝트
5. 프로젝트별 `team/config.codex.sh`만 있는 프로젝트

각 경우에 setup을 두 번 실행해 결과가 중복되지 않는 멱등성도 확인한다.

### 파인 통합 테스트

- Claude 6개 파인 기동과 역할 확인
- Codex 6개 파인 기동과 역할 확인
- developer → lead 본 보고
- designer 작업 중 메시지 큐잉 후 전달
- reviewer 미보고 종료 시 Stop 신호
- 파인 재시작 후 stale busy 마커 제거
- 세션 종료 후 백그라운드 큐 워처 잔류 여부 확인

## 위험과 대응

### `AGENTS.md` 발견 범위 오류

Codex를 프로젝트 루트에서 실행하면 역할 디렉터리의 `AGENTS.md`를 읽지 않는다. 반드시
`.team/{역할}`을 cwd로 실행하고, Codex가 표시하는 workspace root와 활성 지침을 스모크
테스트에서 확인한다.

### 프로젝트 설정 신뢰

Codex는 신뢰되지 않은 프로젝트의 `.codex` 설정과 훅을 읽지 않는다. 최초 실행의 trust
절차를 감지하고 처리하되, 사용자의 의사 없이 임의로 신뢰 상태를 변경하지 않는다.

### 네이티브 무인 실행의 권한 실패

`approval_policy=never`는 승인을 자동 허용한다는 뜻이 아니라 승인 요청 없이 현재 경계 안에서만
진행한다는 뜻이다. 네트워크나 프로젝트 밖 쓰기가 필요한 작업은 실패할 수 있다. 이를
`--yolo`로 자동 우회하지 말고, 실패를 보고하게 하거나 사용자가 명시적으로 full access를
선택하게 한다.

### 동일 워킹트리 충돌

Codex 네이티브 서브에이전트든 tmux 파인이든 여러 작업자가 같은 파일을 수정하면 충돌할 수 있다.
현재 lead의 배분 규칙과 reviewer 흐름을 유지하고, Codex를 추가한다는 이유로 동시 수정 범위를
넓히지 않는다.

### 플러그인 기능 차이

Claude marketplace 플러그인의 이름이 같거나 비슷하더라도 Codex에서 동일하게 동작한다고
가정하지 않는다. 기능별 검증 전까지는 Codex 모드의 알려진 차이로 표시한다.

### 로그 호환성

Codex 훅 이벤트의 필드가 Claude와 다르면 로그가 조용히 비거나 잘못 분류될 수 있다. 로거가
예외를 삼키는 현재 정책은 유지하되, 스모크 테스트에서 최소 한 개의 프롬프트·툴 이벤트가 실제로
기록됐는지 별도로 검사한다.

## 향후 선택지 — Codex 네이티브 팀 모드

Codex는 프로젝트의 `.codex/agents/*.toml`에 `name`, `description`,
`developer_instructions`, 모델과 sandbox를 정의하는 커스텀 에이전트를 지원한다. 장기적으로는
lead 한 세션이 architect·researcher·designer·developer·reviewer를 서브에이전트로 생성하는
모드를 추가할 수 있다.

이 모드는 파인별 독립 TUI, 장기 세션, `say` 큐를 사용하는 현재 하네스와 관찰·통신 방식이
다르다. 따라서 기존 tmux 방식을 대체하지 않고 별도 모드로 실험한다.

```bash
./setup-team.sh --agent codex --team-mode tmux
./setup-team.sh --agent codex --team-mode native
```

네이티브 모드는 tmux Codex 지원이 안정화되고 역할 지침과 완료 조건을 재사용할 수 있게 된 뒤
별도 설계 문서로 다룬다.

## 최종 완료 기준

- Claude와 Codex가 같은 저장소에서 서로의 사용자 설정을 덮어쓰지 않고 실행된다.
- 기존 Claude 사용자는 명령이나 프로젝트 설정을 바꾸지 않아도 이전 동작을 유지한다.
- Codex 사용자는 `--agent codex` 한 옵션으로 역할별 tmux 팀을 시작할 수 있다.
- 양쪽 모두 공통 규칙, 역할 규칙, `say` 보고 체계와 최소 관측성을 제공한다.
- 공급자별로 지원하지 않는 스킬·플러그인·권한 차이가 README에 명시된다.
- 최소 실행, 훅 동등성, 스킬 이식과 문서화 단계의 완료 조건이 모두 검증된다.

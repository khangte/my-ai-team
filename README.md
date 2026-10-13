# My AI team

- Claude Code 또는 Codex 인스턴스 여러 개를 tmux 파인에 띄우는 오케스트레이션 셋업
- 구성: `team/config.sh`의 `MEMBERS`에 선언한 역할로 만드는 멀티에이전트 팀
  (기본값은 lead·architect·researcher·designer·developer·reviewer 6인, 불필요한 역할은 `MEMBERS`에서 뺀다)

## 구조

![팀 구조: lead가 배분하고 architect·researcher·designer·developer·reviewer 5개 역할이 병렬로 붙는다](images/team-architecture.svg)

| 역할       | 담당                                                      |
| ---------- | --------------------------------------------------------- |
| lead       | 배분·수합·git 커밋 (직접 작업하지 않음)                   |
| architect  | 설계·기술 판단, 설계 이탈 승인                            |
| researcher | 웹 조사                                                   |
| designer   | UI/UX 설계 + **프론트엔드 구현** (마크업·스타일·컴포넌트) |
| developer  | **백엔드 구현** (API·DB·테스트·빌드)                      |
| reviewer   | 코드 리뷰·QA·커버리지 판정                                |

designer와 developer는 프론트/백엔드로 갈린다 — designer가 화면을 설계하고 그대로 구현하며,
필요한 API는 `say developer`로 요청한다. 상세는 각 `team/{역할}.md` 참조.

```
CLAUDE.md               Claude 파인 공통 규칙
AGENTS.md               Codex 파인 공통 규칙
team/                   프로젝트별 오버라이드 대상만 (역할 지침·공급자별 설정)
  ├ config.sh           팀 공통 구성 템플릿 (역할·표시명·공급자·모델·추론 수준)
  ├ config.claude.sh    Claude 역할별 플러그인·스킬 배분표
  ├ config.codex.sh     Codex 역할별 플러그인·스킬 배분표
  └ {역할}.md             역할별 지침 (lead/architect/researcher/designer/developer/reviewer)
bin/                    항상 이 저장소 기준으로 고정 실행되는 스크립트 (오버라이드 대상 아님)
  ├ say                 파인 간 메시지 전송 래퍼 (setup-team.sh가 각 파인 PATH에 등록)
  └ log-hook            프롬프트·툴 사용을 .claude-logs/{역할}.jsonl에 기록하는 훅
docs/                   설계 배경·실측 분석 문서
  └ architect-review/   architect의 리뷰 판정 문서 ({순번}_{주제}.md)
Dockerfile              팀 환경용 컨테이너 이미지 정의 (격리 실행할 때)
setup-docker.sh         Docker로 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행
setup-native.sh         WSL 등 호스트에 직접 의존성 설치 (Docker 없이 실행할 때)
setup-team.sh           tmux 세션 구성 + 선택한 에이전트 CLI 실행 (핵심 스크립트)
```

### 런타임 산출물

- `setup-team.sh`는 실행할 때마다 **대상 프로젝트 루트**에 `.team/`을 새로 생성
  - 내용: 역할별 스킬 심볼릭 링크 + `_runtime/`의 조립된 역할 지침·훅 설정
  - 매 실행마다 지워지고 다시 만들어짐 → 대상 프로젝트 `.gitignore`에 `.team/` 추가 권장
- 프롬프트·툴 로그(`.claude-logs/`)는 내부 `.gitignore`로 스스로 제외되므로 별도 설정 불필요 (아래 "프롬프트·툴 로깅" 참고)

### 이 저장소의 위치

- 이 저장소 자체는 개발 대상이 아니라 **팀 오케스트레이션 엔진**
- 실제 개발할 프로젝트는 별도 폴더에 존재
- `setup-team.sh`가 그 폴더를 인자로 받아 그 안에서 claude 인스턴스를 실행

## 실행 방식 및 사용법

|               | WSL 네이티브                        | Docker                                            |
| ------------- | ----------------------------------- | ------------------------------------------------- |
| 격리          | 없음 (호스트에 직접 설치)           | 컨테이너로 격리                                   |
| 적합한 경우   | 혼자 개발, 빠른 반복                | 팀 배포, 환경 재현성 필요                         |
| 진입 스크립트 | `setup-native.sh` → `setup-team.sh` | `setup-docker.sh` (내부에서 `setup-team.sh` 실행) |

### 진입

먼저 이 저장소를 clone(아래 예시는 `~/ai-setup` 기준).

```bash
git clone https://github.com/khangte/my-ai-team.git ~/ai-setup
```

#### WSL 네이티브

```bash
# ai-setup/ 안에서 실행
./setup-native.sh /path/to/project     # 최초 1회: 팀에 쓰이는 공급자 의존성을 모두 설치
./setup-team.sh /path/to/project        # 지정한 프로젝트로 팀 세션 실행

# Codex 팀
./setup-native.sh --agent codex          # 최초 1회: tmux/codex 의존성 설치
./setup-team.sh --agent codex /path/to/project

# 작업 디렉터리(프로젝트 루트)에서 실행
~/ai-setup/setup-native.sh              # 최초 1회
~/ai-setup/setup-team.sh .              # 현재 디렉터리를 프로젝트로 지정

# Codex 팀
~/ai-setup/setup-native.sh --agent codex
~/ai-setup/setup-team.sh --agent codex .
```

#### Docker

```bash
# ai-setup/ 안에서 실행
./setup-docker.sh /path/to/project      # 이미지 빌드 + 컨테이너 기동 + setup-team.sh 실행

# 작업 디렉터리(프로젝트 루트)에서 실행
~/ai-setup/setup-docker.sh .            # 현재 디렉터리를 프로젝트로 지정
```

> `setup-team.sh` 인자 규칙
>
> - 인자 생략 시 환경변수 `$PROJECT_DIR`, 그것도 없으면 **현재 디렉터리** 사용
> - 상대·절대 경로 모두 허용
> - 세션 이름 기본값은 `team1`, `team/config.sh`의 `SESSION=` 값으로 변경 가능
>   (아래 "프로젝트별 팀 구성 커스터마이징" 참고)

Docker 환경의 특이점:

- `Dockerfile`은 npm/rtk/bun을 `/opt` 하위에 설치
  - 이유: 컨테이너 재생성 시 `/home/user`가 named volume(`claude-home`)으로 덮어써짐
  - WSL 네이티브는 이 제약이 없어 기본 경로 사용
- 컨테이너 이름은 `claude-env`로 고정, `sleep infinity`로 상주 — 재접속 때 `setup-docker.sh` 재실행 불필요

### setup-team.sh 실행되면

0. 의존성·인증 확인 `[0/7]`
   - tmux 설치 여부는 항상 확인
   - 실제로 팀에 쓰이는 공급자마다 필요한 도구·인증을 확인 (혼합 팀이면 둘 다)
     - Claude: claude/rtk/bun 설치, `claude auth status` 로그인 확인 (미로그인 시 `/login` 안내 후 대기)
     - Codex: codex 설치, `codex login status` 로그인 확인 (미로그인 시 `codex login` 안내 후 대기)
   - 확인 직후 기존 tmux 세션을 정리 (`.team/` 삭제와의 경합 방지)
1. rtk 훅 초기화 `[1/7]` (Claude)
2. gstack 스킬(`/office-hours`, `/review` 등 슬래시 커맨드) 설치 `[2/7]` (Claude)
3. 필수 마켓플레이스 플러그인(superpowers/frontend-design/serena/ponytail/caveman) 설치 `[3/7]` (Claude) — 역할별 활성화는 7번이 담당
4. 팀 공통 지침을 `CLAUDE.md`에 병합 + 역할별 스킬 제한 `[4/7]` (Claude) — `.team/{역할}/.claude/skills`에 그 역할이 쓸 스킬만 링크
5. `AGENTS.md` 병합, 역할별 스킬·플러그인·lifecycle 훅 준비 `[5/7]` (Codex)
6. tmux 세션 구성 `[6/7]`
   - 팀 인원 수만큼 파인 분할
   - 파인 타이틀은 대문자로 표시 (예: `LEAD`, `ARCHITECT`)
7. 각 파인에서 선택한 CLI 실행 `[7/7]` — 실행 로그에 파인별 model·effort 표시
   - Claude: 지정 모델, 역할 지침·훅 설정·플러그인 활성화를 주입한 `claude --dangerously-skip-permissions`
   - Codex: 역할별 `AGENTS.md`를 읽고 Git 메타데이터까지 쓸 수 있는
     `codex --dangerously-bypass-approvals-and-sandbox`
     - 읽기·코드 수정만 허용하려면 `CODEX_FULL_ACCESS=0`으로 실행
       (`workspace-write`는 `.git`을 항상 read-only로 보호하므로 `git add/commit`은 불가)
8. 완료 후 `tmux attach -t [세션명]` 접속 안내

### 세션 확인 및 종료

```bash
# team1: 세션명 예시
tmux attach -t team1                          # 접속 (WSL 네이티브)
docker exec -it claude-env bash -lc "tmux attach -t team1"   # 접속 (Docker — 컨테이너 재진입 후 attach)
tmux capture-pane -t team1:0.N -p | tail -5   # N번 파인 진행 상황만 확인
tmux kill-session -t team1                    # 세션 종료
```

### `--dangerously-skip-permissions`를 쓰는 이유

- 각 파인이 이 플래그로 실행됨 — 툴 사용마다 사람 승인이 필요하면 멀티에이전트 자동 진행이 불가능해서
- 대가: 파인이 확인 없이 파일을 수정·삭제 → **git으로 관리되는 프로젝트**에서 쓰거나 Docker로 격리 권장
- 파급효과: 권한 우회 세션은 cross-session messaging도 기본 승인 대기로 보류되는데, 사람이 안 붙어 있어
  `dialogExpiry`(기본 5분) 후 그대로 폐기됨 → `setup-team.sh`가 각 파인에 `crossSessionInbound: accept`를
  함께 주입 (아래 "팀 밖 세션에서 파인 호출" 참고)

### Codex 실행 모드

`setup-team.sh --agent codex` 또는 `TEAM_AGENT=codex`로 Codex 파인을 띄운다.

- 대상 프로젝트의 `AGENTS.md`에는 이 저장소의 Codex 공통 규칙이 마커 블록으로 병합된다.
- 각 파인은 `.team/{역할}/`에서 실행되며, 같은 위치의 역할별 `AGENTS.md`를 추가로 읽는다.
- 첫 실행에서 Codex가 프로젝트 신뢰를 확인하는 대화상자와, `.codex/hooks.json`의
  훅 신뢰 승인(`/hooks` 화면)은 `setup-team.sh`가 자동으로 처리한다 — 사람이 개입할
  필요 없다.
- 세션 시작 시 남은 busy 마커를 정리하고, 응답 종료 시 미보고 종료 신호를 보낸다.
  `say` 통신, 역할 지침, `.codex/hooks.json`의 `SessionStart`·`Stop` 이벤트로 이식했다.
- Claude 전용 rtk 토큰 절감 훅과 gstack 플러그인, 프롬프트·툴 JSONL 로깅
  (`.claude-logs/`)은 Codex에 이식하지 않는다. Codex 공식 플러그인은 아래 설명처럼
  파인별로 격리한다.
- Codex 모델과 추론 수준은 `team/config.sh`의 `MEMBERS`에서 역할별로 정한다. 각 항목의 모델·추론 수준을 비워 두면 Codex 사용자 기본값을 사용한다. `config.codex.sh`는 모델이 아니라 플러그인·스킬 배분만 담당한다.

### 혼합 팀 — 역할별로 다른 에이전트 지정

역할별로 다른 공급자를 쓰려면 `team/config.sh`의 각 `MEMBERS` 항목에 공급자를 지정한다.
저장소 기본값은 designer·developer만 Codex이고, 나머지(lead·architect·researcher·reviewer)는 Claude다.

```bash
# <프로젝트_경로>/team/config.sh
SESSION="team1"
declare -a MEMBERS=(
    "lead|리드|claude|claude-opus-5-5|medium"
    "architect|아키텍트|codex|gpt-6-sol|high"
    "developer|개발자|codex|gpt-6-sol|medium"
    "reviewer|리뷰어|claude|claude-opus-5-5|medium"
)
```

어느 역할을 Codex로 돌릴지는 프로젝트마다 다르다. 핵심은 **코드를 쓰는 모델과 판단하는
모델을 분리**하는 것 — 같은 모델끼리는 맹점도 공유하기 때문이다.

- 항목 형식과 기본값 규칙은 아래 "프로젝트별 팀 구성 커스터마이징" 참고.
- 일부 역할만 Codex를 써도 `[0/7]`이 Codex 로그인까지 함께 확인한다.
- **Codex 파인은 `.claude-logs/`에 기록을 남기지 않는다.** 로깅 훅이 Claude 전용이라,
  혼합 팀의 로그를 분석하면 Codex 파인 구간만 통째로 빈다. 보고 경로나 토큰 비용을
  실측할 계획이라면 그 역할을 Claude에 두는 편이 낫다.

## Claude/Codex 지침과 team/ — 지침이 파인에 로딩되는 방식

파인 지침은 두 층으로 구성된다.

1. **공통 규칙 — 대상 프로젝트의 `CLAUDE.md`**
   - `setup-team.sh`가 연 프로젝트 폴더(`$PROJECT_DIR`)의 `CLAUDE.md`
   - Claude Code가 세션 시작 시 자동으로 읽고, 모든 파인에 동일 적용
   - **파인이 읽는 것은 `$PROJECT_DIR`의 `CLAUDE.md`이지 이 저장소의 것이 아니다.**
     그래서 `setup-team.sh`가 실행할 때마다 이 저장소의 `CLAUDE.md` 내용을
     대상 프로젝트의 `CLAUDE.md`에 마커 블록으로 병합한다
   - 병합 규칙 — 사용자가 쓴 내용은 건드리지 않는다
     - 파일이 없으면 블록만 담아 새로 생성
     - 마커가 있으면 그 사이만 교체 (블록 앞뒤 내용 보존)
     - 마커가 없으면 파일 끝에 블록 추가
     - `$PROJECT_DIR`가 이 저장소 자신이면 아무것도 하지 않음
   - 따라서 팀 공통 규칙은 이 저장소의 `CLAUDE.md`만 고치면 다음 실행부터 전 프로젝트에 반영됨
     - 단 **README 등 이 저장소 파일을 참조하는 문장은 쓰지 않는다** — 대상 프로젝트에는 그 파일이 없다
   - 역할별 지시(팀원 배분, "하지 말 것" 등)는 여기에 넣지 않음
     — architect·developer 등 다른 파인도 같은 내용을 받아버리기 때문

2. **역할별 지침 — `team/{역할}.md`**
   - 각 파인에서 `claude` 실행 시, `MEMBER_NAMES`의 이름에 대응하는
     `team/{이름}.md`를 읽어 `--append-system-prompt`로 주입
     - 예: lead 파인 → `team/lead.md`, architect 파인 → `team/architect.md`
   - 대응 파일이 없으면 시스템 프롬프트 추가 없이 그냥 실행
   - 오버라이드 규칙은 `team/config.sh`와 동일
     - **대상 프로젝트 루트**(`$PROJECT_DIR/team/{이름}.md`)에 파일이 있으면 우선 사용
     - 없으면 **이 저장소**(`team/{이름}.md`)의 기본값으로 폴백

## 프로젝트별 팀 구성 커스터마이징

- 기본 팀 구성은 이 저장소의 `team/config.sh`에 있다 — 현재 lead/architect/researcher/designer/developer/reviewer 6인
- 인원 수·세션 이름·역할별 공급자·모델·추론 수준을 바꾸려면 **대상 프로젝트 루트**에 `team/config.sh` 배치
- `config.claude.sh`와 `config.codex.sh`에는 공급자별 플러그인·스킬 배분만 둔다
- 공통 구성과 선택한 공급자 전용 구성은 차례로 자동 로드되어 기본값을 덮어쓴다
- 항목 형식은 `role|표시이름|agent|model|effort`이고 배열 순서가 tmux 파인 배치 순서다. 인원은 `MEMBERS` 항목 증감으로 조절한다(예시는 위 "혼합 팀").
- `agent`를 비우면 `--agent`/`TEAM_AGENT` 기본값을, `model`·`effort`를 비우면 각 CLI 기본값(Claude는 `settings.json`, Codex는 사용자 기본값)을 따른다.
- `effort`에는 `low`/`medium`/`high`/`xhigh`/`max`를 쓴다.
- 이 저장소의 `team/config.sh`는 복사해서 수정할 템플릿이다.
- 이름을 바꾸면 대응하는 `team/{이름}.md`도 필요(없으면 역할 지침 없이 실행 — 위 "Claude/Codex 지침과 team/" 참고)

## 파인 간 통신 — `bin/say`

- 파인끼리는 `say`로만 메시지를 주고받음
- `setup-team.sh`가 `bin/`을 각 파인 PATH에 등록 → 경로 없이 바로 호출

```bash
say :0.0 "[developer] 로그인 기능 구현 완료"   # 파인 번호로 지정
say lead  "[developer] 로그인 기능 구현 완료"   # 파인 타이틀(역할 이름)로도 가능
```

`tmux send-keys`를 직접 쓰지 않는 이유: `Enter`가 별개 인자라 누락되기 쉽고, 누락 시 메시지가
상대 입력창에 텍스트로만 남고 전송되지 않음. `say`는 Enter를 항상 부착해 이를 방지.

유휴 판정은 화면 문구가 아니라 훅 기반 busy 마커(`/tmp/team-busy/`)로 한다. 상세는 [docs/pane-messaging.md](docs/pane-messaging.md) "유휴 판정" 참조.

파인 밖(호스트 셸)에서 호출:

- PATH에 없으므로 경로와 세션명을 함께 지정 — `./bin/say team1:0.4 "..."`

### 팀 밖 세션에서 파인 호출 — `SendMessage`

Claude Code의 cross-session messaging이 파인마다 켜져 있어, 팀 밖 Claude 세션이 파인 하나를 직접 지시할 수 있다.
대부분은 lead에 `tmux attach`로 붙어 명령하므로, lead를 거치지 않고 특정 파인을 바로 찔러야 할 때만 쓴다.

- 각 파인이 `/list-agents`에 보이고 이름은 cwd 기반(`lead-1f`, `developer-a7`)이다. 자연어로 지시하면 된다.
- 이름이 겹치면 `to`에 `lead-1f [bba91f]`처럼 ref를 붙인다.
- Docker 실행 시 호스트에서는 파인이 보이지 않는다. 네이티브 실행에서만 유효하다.
- 파인끼리는 `say`를 쓴다. `SendMessage`는 Stop 훅에서 호출할 수 없고, `SAY_NOWAIT` 같은 인터럽트 구분이 없으며,
  토큰 이득이 없고(실측), Codex 파인은 지원하지 않는다. 비교와 실측은 [docs/token-cost.md](docs/token-cost.md) 참조.

### 보고 경로

- 평상시 1홉 — 각 파인 → lead
- 설계 판단이 필요한 건만 architect 경유

| 상황                           | 경로                                                          |
| ------------------------------ | ------------------------------------------------------------- |
| 일반 완료 보고                 | 각 파인 → lead                                                |
| 설계 이탈 (developer/designer) | 파인 → architect → lead                                       |
| 리뷰 승인                      | reviewer → lead                                               |
| 리뷰 — 코드 품질 수정요청      | reviewer → 작성자 (직행, lead 사본 없음)                      |
| 리뷰 — 설계 판단 필요          | reviewer → architect (lead 사본 없음) → architect 판정만 lead |
| 화면에 필요한 API 요청         | designer → developer                                          |

코드 품질 수정요청의 "작성자"는 백엔드면 developer, 프론트엔드면 designer다.

**중간 경유는 lead에 보고하지 않는다.** 다음 담당자에게 넘긴 사실("developer에
전달했다", "architect 경유함")은 lead가 할 일이 없는 턴을 만든다. lead는 그 사안이
**종결될 때** 최종 결과 하나만 받는다. architect처럼 지시를 내리는 역할도 지시 시점이
아니라 그 결과를 검수한 뒤에 보고한다.

실측 근거: lead 56턴 중 19턴이 툴 호출 0건이었고, 그중 16건이 보고 수신뿐이었다.
프로토콜 수정 후 같은 규모 작업에서 사본 0건. 상세는
[docs/pane-messaging.md](docs/pane-messaging.md) 10단계.

### Stop 훅 — 보고 누락 방지

- 파인이 `say` 실행을 잊어도 lead가 완료를 알 수 있도록, `setup-team.sh`가 lead를 뺀 각 파인에 Stop 훅을 주입해 응답 종료 시 완료 신호를 자동 전달 (폴링 불필요)
- 예외: 방금 `say`로 보고했으면 생략 / lead 자신은 대상 제외 (무한루프 방지)
- Claude·Codex 양쪽에서 동일하게 동작 — Codex는 `.codex/hooks.json`의 `Stop` 이벤트로 이식했다.

"방금 보고했는가"는 `/tmp/team-say/` 마커로 판정하며, 턴 경계마다 비운다. 이유와 오탐 실측은
[docs/pane-messaging.md](docs/pane-messaging.md) 10단계 참조.

## 프롬프트·툴 로깅 — 재현성과 추적

배경:

- 입력한 질문 / 실행한 명령 / 참조한 파일이 남아 있어야 결과 재현과 원인 추적이 가능

구현:

- `setup-team.sh`가 모든 파인에 `UserPromptSubmit`·`PreToolUse` 훅(`bin/log-hook`)을 주입해 자동 기록

```
$PROJECT_DIR/.claude-logs/
├── .gitignore        내용은 "*" — 디렉터리가 스스로를 커밋에서 제외
├── lead.jsonl
├── developer.jsonl
└── ...               역할당 하나씩 (그 파인이 처음 동작할 때 생성)
```

형식:

- 한 줄이 JSON 하나인 JSONL
- 프롬프트·툴 두 종류가 시간순으로 섞여 기록

```json
{"ts":"...","role":"developer","event":"UserPromptSubmit","session":"s1","prompt":"로그인 기능 구현해줘"}
{"ts":"...","role":"developer","event":"PreToolUse","session":"s1","tool":"Write","input":{"file_path":"/a/b.py","content_len":500}}
```

### 설계상의 선택

- **역할별 파일** — 여러 파인이 병렬로 도는 구조라 한 파일에 쓰면 경합·귀속 불명이 생긴다.
- **`.team/` 바깥** — `.team/`은 매 실행 `rm -rf` 대상이라 거기 두면 재시작 시 소실된다.
- **대상 리포 `.gitignore` 불변** — 로그 디렉터리 안에 `.gitignore`(`*`)를 둬서 스스로를 제외한다.
- **본문은 길이만 기록** — Write/Edit 전문은 로그를 비대하게 하고 시크릿 노출 표면을 키운다.
- **시크릿 마스킹** — 알려진 패턴(`sk-`, `ghp_`, `AKIA`, `xox*-`, `API_KEY=` 등)과 `.env` 명령은 가리고 Read는 경로만 남긴다.
  임의 형식의 키는 못 걸러내므로 로그 파일을 `600`으로 만든다. 훅이 실패해도 파인 작업은 막지 않는다.

### 단독 실행에서는 쌓이지 않는다

- 로깅 훅은 `setup-team.sh`가 `--settings`로 주입하는데, `--settings`는 전역 `~/.claude/settings.json`을
  병합이 아니라 **대체**함 → 그 스크립트를 거치지 않고 `claude`를 단독 실행하면 **로그가 남지 않음**

| 실행 방식            | 훅 소스                        | 로깅    |
| -------------------- | ------------------------------ | ------- |
| `setup-team.sh` (팀) | `--settings`로 주입            | 쌓임    |
| `claude` 단독 실행   | 전역 `~/.claude/settings.json` | 안 쌓임 |

단독 실행에도 로그를 남기려면:

- `~/.claude/settings.json`에 같은 훅 추가 — `bin/log-hook <역할> "$CLAUDE_PROJECT_DIR"`
- 단, 어떤 프로젝트에서 claude를 띄우든 전부 로그가 쌓인다는 점 감안

## 역할별 스킬 제한

- 문제: gstack setup은 스킬 수십 개를 `~/.claude/skills/`에 전부 설치하고, 그 frontmatter가 파인이 뜰 때마다
  시스템 프롬프트에 포함됨 → 구성한 모든 파인 × 매 턴이라 고정비가 큰데, 대부분은 역할과 무관한 스킬
- 해결: `~/.claude/skills`는 유저 전역이라 파인별 구성이 불가하므로, `setup-team.sh`가 파인마다
  `.team/{역할}/.claude/skills`에 **필요한 스킬만 심볼릭 링크**하고 그 디렉터리를 cwd로 실행,
  `--setting-sources project`로 유저 전역·플러그인 스킬은 차단

| 역할       | 허용 스킬                   |
| ---------- | --------------------------- |
| lead       | `spec` `plan-eng-review`    |
| architect  | `diagram`                   |
| researcher | `scrape` `browse`           |
| designer   | `design-review` `design-html` |
| developer  | `health`                    |
| reviewer   | `review`                    |

- `spec`·`plan-eng-review`는 사용자에게 직접 묻는 대화형 스킬이라, 사용자와 대화하는 유일한 파인인 lead에 둔다
  (모호한 요청 → lead `spec` → architect `writing-plans` → lead `plan-eng-review` → developer)
- 실측(commerce-data-platform, 11일) 결과 역할 지침의 `## 스킬`에 사용 조건이 없는 스킬은 한 번도 호출되지 않았다.
  그래서 배정한 스킬은 `team/{역할}.md`에 언제 쓰는지 함께 적고, 호출 0회였던 `document-generate`·`qa`·`learn`은 뺐다

gstack `investigate`는 superpowers `systematic-debugging`과 교리·4단계 구성이
문구까지 거의 같은 순수 중복이라 어느 역할에도 주지 않는다. 크기는 6.6배
(62.6KB 대 9.5KB)인데 디버깅 실체는 뒤쪽 ~250줄뿐이고, 본문의 gstack 경로 참조
92곳과 frontmatter의 훅·gbrain 쿼리는 파인에서 동작하지 않는다.
근거: `docs/architect-review/8_ecc-skill-overlap-review.md` §5

designer의 `design-consultation`도 같은 이유로 뺐다 — 아래 `frontend-design`과
"팔레트·타이포·레이아웃을 정한다"는 역할이 겹치는데, 71KB(1,258줄) 중 앞 861줄이
gstack 보일러플레이트라 실제 디자인 지침은 32%뿐이다. 웹 리서치 절차가 빠지지만
그건 researcher 파인이 이미 담당한다.

### superpowers 스킬

[superpowers](https://github.com/obra/superpowers)는 gstack과 달리 **플러그인**이라
`--setting-sources project`에 통째로 차단된다. 그래서 gstack과 같은 방식으로
역할별 필요한 것만 `.team/{역할}/.claude/skills`에 링크해 되살린다
(`team/config.claude.sh`의 `CLAUDE_SUPERPOWERS_SKILL_SETS`).

| 역할      | 배정 스킬                                        |
| --------- | ------------------------------------------------ |
| lead      | `finishing-a-development-branch`                 |
| architect | `writing-plans`                                  |
| developer | `systematic-debugging` `receiving-code-review`   |

- researcher·designer·reviewer는 배정 없음
- gstack은 래퍼의 `SKILL.md`만 링크하지만, superpowers는 `references/` 등 하위 파일을
  런타임에 읽으므로 **스킬 디렉터리를 통째로** 링크한다
- 플러그인 설치 경로에 버전 디렉터리가 끼므로(`.../superpowers/6.2.0/skills`)
  경로를 고정하지 않고 최신 버전을 골라 쓴다. 미설치면 경고만 내고 넘어간다

배정에서 뺀 것과 그 이유:

| 스킬                                                        | 제외 이유                                                           |
| ----------------------------------------------------------- | ------------------------------------------------------------------- |
| `dispatching-parallel-agents` `subagent-driven-development` | 구성한 파인이 이미 병렬 실행 단위 — 파인 대신 서브에이전트를 띄운다 |
| `requesting-code-review`                                    | 리뷰어 서브에이전트를 띄우게 되어 reviewer 파인이 논다              |
| `using-git-worktrees`                                       | 구성한 파인이 같은 워킹트리를 공유하는 구조와 충돌                  |
| `using-superpowers`                                         | "1%라도 해당되면 무조건 스킬 호출" — 전 파인 고정비만 늘어남        |
| `executing-plans` `writing-skills`                          | 각각 별도 세션 실행 전제 / 팀 업무 아님                             |
| `brainstorming`                                             | 사용자와 대화하는 스킬이라 `say`로만 소통하는 파인과 맞지 않음. 모호한 요청 정리는 lead의 gstack `spec`이 맡는다 |
| `test-driven-development`                                   | `writing-plans` 계획서에 테스트 우선 단계가 이미 들어 있음. 규칙은 `team/developer.md`의 "테스트 원칙"에 문장으로 남김 |
| `verification-before-completion`                            | 핵심 규칙이 `team/reviewer.md`의 "승인 전 검증"과 같아 스킬 없이 지켜짐(실측 호출 0회, 직접 실행 검증 138회) |

이 스킬들은 단독 실행을 전제로 쓰여 있어(사용자에게 직접 승인 요청, 서브에이전트 dispatch 등)
그대로 두면 팀 구조와 어긋난다. 그래서 각 `team/{역할}.md`의 "## 스킬" 절에서 팀 규칙으로
바꿔 읽도록 명시했다 — 예로 `writing-plans`의 서브에이전트·worktree 실행 선택지 대신 lead에게 계획을 보고한다.

역할 경계: **테스트 우선 사이클(red→구현→green)까지 developer**,
**커버리지·품질 최종 판정은 reviewer**.

### Codex 파인 스킬

Codex 파인(기본 구성에서 designer·developer)은 위 Claude용 스킬·플러그인을 읽지 못한다.
`team/config.claude.sh`의 designer·developer 항목은 그 역할을 Claude로 돌릴 때만 적용되고,
Codex 파인의 플러그인·스킬은 `team/config.codex.sh`가 따로 정한다. 형식은 `config.claude.sh`와 같다
(`CODEX_PLUGIN_ROLES`는 플러그인 → 역할, `CODEX_SKILL_SETS`·`CODEX_SUPERPOWERS_SKILL_SETS`는 역할 → 스킬).

| 역할      | Codex에서 받는 것                                                              |
| --------- | ------------------------------------------------------------------------------ |
| developer | `superpowers`의 `systematic-debugging` `receiving-code-review` (스킬 링크) |
| designer  | `product-design@openai-curated-remote` (플러그인 전체 설치)                     |

`CODEX_PLUGIN_ROLES`의 키는 `codex plugin list --available`에 나오는 실제 pluginId를 그대로 적는다
(현재 카탈로그는 `openai-curated-remote`). superpowers 스킬 링크는 공식 marketplace snapshot
(`~/.codex/.tmp/plugins`)에서 가져온다.

gstack 스킬(`CODEX_SKILL_SETS`)은 비워 둔다. `setup-team.sh`는 gstack을 claude host로만
설치하고(`./setup`), gstack의 codex 렌더링은 이름이 `gstack-<name>`이라
`find_codex_skill_source`가 찾지 못한다 — 설정해도 경고만 내고 건너뛴다.

Codex 공식 카탈로그를 기준으로 Claude 기능의 대체재를 다음처럼 사용한다.

| 기존 기능                                   | Codex 네이티브 대체재                                     | 적용 방침                                        |
| ------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------ |
| Superpowers `brainstorming`·`writing-plans` | `superpowers`의 동명 스킬                                 | architect를 Codex로 돌릴 때 `CODEX_SUPERPOWERS_SKILL_SETS`에 선언(기본 배정 없음) |
| gstack `diagram`                            | `figma@openai-curated-remote`의 `figma-generate-diagram`         | FigJam을 쓰는 프로젝트에서만 역할별 전체 설치    |
| 문서 기반 spec → plan/task                  | `notion@openai-curated-remote`의 `notion-spec-to-implementation` | Notion이 source of truth일 때만 역할별 전체 설치 |
| GitHub issue/PR 문맥                        | `github@openai-curated-remote`                                 | 로컬 저장소만 쓰면 불필요                        |
| lifecycle hook                              | Codex 네이티브 hooks                                      | 이 저장소가 `SessionStart`·`Stop`을 자동 생성    |
| Serena·gstack `health`·독립 plan review     | 정확한 공식 대체재 없음                                   | Codex 기본 저장소 도구와 architect 지침으로 수행 |

`CODEX_SUPERPOWERS_SKILL_SETS`에 선언하면 `setup-team.sh`가 superpowers에서 그 스킬만 찾아
`.team/{역할}/.agents/skills`에 링크한다. 전체 플러그인에 포함된 나머지 스킬은 그 역할에 보이지 않는다.
역할 지침(`team/{역할}.md`)의 팀 규칙이 스킬의 단독 세션 지침보다 우선한다.

각 Codex 파인은 `.team/{역할}/.codex-home`을 `CODEX_HOME`으로 사용한다. 인증, Codex 시스템
스킬, 공식 marketplace 카탈로그만 공유하고 plugin 활성화 config·설치 cache는 역할마다
분리하므로, 사용자 전역에 설치된 플러그인이나 다른 파인의 플러그인이 들어오지 않는다.
connector·MCP·hook까지 필요한 전체 플러그인은 프로젝트의 `team/config.codex.sh`에서
역할별로 선언한다.

```bash
# <프로젝트>/team/config.codex.sh
declare -A CODEX_PLUGIN_ROLES=(
    ["figma@openai-curated-remote"]="architect"
    ["notion@openai-curated-remote"]="architect"
)
declare -A CODEX_SUPERPOWERS_SKILL_SETS=(
    [architect]="brainstorming writing-plans"
)
```

전체 플러그인 설치도 해당 역할의 격리된 홈에만 적용된다. 외부 connector를 쓰는 플러그인은
서비스 인증이 별도로 필요할 수 있으며, 미인증·설치 실패는 경고하고 나머지 팀 준비를 계속한다.

### frontend-design 스킬

[frontend-design](https://github.com/anthropics/claude-plugins-official)(공식 마켓플레이스)도
플러그인이라 superpowers와 같은 방식으로 링크한다(`team/config.claude.sh`의
`CLAUDE_FRONTEND_DESIGN_SKILL_SETS`).
스킬이 1개뿐이지만 배열로 둬서 배분 규칙을 나머지와 맞췄다.

| 역할     | 배정 스킬         |
| -------- | ----------------- |
| designer | `frontend-design` |

`design-consultation`을 대체한다. 8.3KB 전량이 지침이라 호출당 **2.1K 토큰**으로
`design-consultation`(17.8K)보다 **8.5배 싸다**. 더 중요한 건 gstack에 없는
**AI 슬롭 캘리브레이션** — 지금 AI 디자인이 수렴하는 세 가지 룩(크림 배경+세리프+테라코타,
니어블랙+애시드그린, 헤어라인 브로드시트)을 명시하고, 브리프가 자유롭게 둔 축을
거기에 쓰지 말라고 못박는다.

`design-review`(브라우저 QA)·`design-html`(코드 생성)은 역할이 달라 유지한다.
단 `design-html`은 Pretext(`@chenglou/pretext`) 참조가 38곳이라 그 스택에 묶인다.

> 버전 디렉터리가 semver가 아니라 `unknown`이지만, 설치본이 하나뿐이라
> superpowers와 같은 `*/skills` glob + `tail -1`로 잡힌다.

제한 대상이 아닌 것:

- claude 빌트인 스킬
- `$PROJECT_DIR/.claude/skills`의 공용 스킬
- 위 둘은 모든 파인이 그대로 사용, 자세한 근거와 예외는 `setup-team.sh`의 `[4/7]` 섹션 주석 참조
- 전역 규칙(`~/.claude/rules/`, `~/.claude/CLAUDE.md`)도 **대상 프로젝트가 홈 아래에 있으면** 차단되지 않고 그대로 로드됨
  — `--setting-sources project`의 규칙 차단은 cwd가 홈 밖일 때만 성립(실측). 즉 `/mnt/c/...` 같은 홈 밖 프로젝트로 팀을
  띄우면 파인이 전역 규칙 없이 뜨므로, 그쪽에 의존하는 지침이 있으면 프로젝트 `CLAUDE.md`로 옮겨야 함

스킬 제한 절감량은 [docs/token-cost.md](docs/token-cost.md) 참조.

## 역할별 플러그인 활성화

- 문제: caveman·ponytail·serena는 유저 전역 `~/.claude/settings.json`의 `enabledPlugins`로 켜지는데,
  파인은 `--setting-sources project`로 뜨는 탓에 이 전역 설정을 못 읽음 → 방치하면 **세 플러그인이
  파인에서 전혀 걸리지 않음**(실측 확인)
- 해결: `setup-team.sh`의 `[3/7]`이 플러그인을 설치하고, 파인 실행 시 `--settings`에
  `enabledPlugins`·`extraKnownMarketplaces`를 역할별로 명시 주입(`team/config.claude.sh`의
  `CLAUDE_PLUGIN_ROLES` 배열이 배분을 결정)

실측 파인당 고정비 — `ponytail` ~2.2K tok / `caveman` ~3.9K tok / `serena` ~6K tok.
활성 파인 수만큼 매 턴 반복되는 비용이므로, 쓰지 않을 역할에는 주지 않는다.

| 플러그인        | 배분                          | 이유                                                                                                                                                        |
| --------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| caveman         | 전 파인                       | 켠 파인이 아니라 lead가 이득을 회수하는 구조(파인들의 보고가 전부 lead 입력). 출력 문체를 팀 전체에서 통일하는 값이 고정비보다 크다는 사용자 결정           |
| ponytail        | developer만                   | 사다리 7단 중 2~7단이 전부 코드 대상이라 코드를 안 쓰는 역할에는 1단 YAGNI만 남음. 그 한 줄은 역할 지침에 문장으로 넣는 편이 100배 쌈(2.2K 대 ~20토큰)      |
| serena          | 전 파인                       | 심볼 탐색을 전 역할에서 쓰도록 확대. 고정비가 가장 큼(MCP 툴 정의 30개)이라 줄일 때 첫 후보 |
| superpowers     | 없음(`enabledPlugins` 미주입) | 위 "superpowers 스킬" 절대로 `[4/7]`이 스킬 디렉터리를 역할별로 직접 링크하므로 이미 걸려 있음. 여기서 또 켜면 스킬 14개가 통째로 들어와 선별이 무의미해짐  |
| frontend-design | designer                      | `[4/7]`이 designer에 직접 링크하고 `enabledPlugins`로도 켬 — 스킬이 1개뿐이라 선별 손실이 없음                                                             |

배분 근거 실측은 [docs/architect-review/6_caveman-ponytail-role-scoping.md](docs/architect-review/6_caveman-ponytail-role-scoping.md) 참조.

designer에게 serena를 주는 이유: serena의 LSP 백엔드가 프론트엔드를 1급으로 지원한다 —
typescript(`.ts/.tsx/.js/.jsx`), vue(`.vue` SFC), svelte(`.svelte` SFC), angular, html,
some-sass(`.scss/.sass/.css`). 값이 나오는 지점은 `find_referencing_symbols`로,
"이 컴포넌트를 고치면 어디가 깨지나"를 grep으로 찾으면 `<Button`, `Button(`,
`import Button`, 재export를 놓치지만 심볼 탐색은 잡는다.

> UI가 없는 프로젝트(이 리포처럼 bash + 문서)에 팀을 띄우면 designer 파인 자체가
> 불필요하다. serena만 빼는 게 아니라 `team/config.sh`의 `MEMBERS`에서
> designer를 빼는 것이 옳은 대응이다.

`claude plugin enable`은 부르지 않는다 — 유저 전역 `settings.json`을 고쳐 팀 밖 세션까지 건드리는데,
파인 활성화는 `--settings`가 이미 담당하므로 불필요하다.

실측 고정비, PATH 관련 함정(활성화가 조용히 실패하는 경우)은 [docs/token-cost.md](docs/token-cost.md) 참조.
